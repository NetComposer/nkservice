
%% -------------------------------------------------------------------
%%
%% Copyright (c) 2018 Carlos Gonzalez Florido.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------


%% Package management
%% -----------------
%%
%% When the service starts, packages_status is empty
%% - All defined packages will be launched in check_packages, low first
%% - Packages can return running or failed
%% - Periodically we re-launch start for failed ones
%% - If the package supervisor fails, it is marked as failed
%%
%% When the service is updated
%% - Packages no longer available are removed, and called stop_package
%% - Packages that stay are marked as upgrading, called update_package
%% - When response is received, they are marked as running or failed
%%
%% Service stop
%% - Services are stopped sequentially (high to low)


-module(nkservice_srv).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([start/1, stop/1, replace/2, update/2, do_update/1, get_status/1]).
-export([get_events/1, send_event/2, launch_check_status/1]).
-export([get_all/0, get_all/1]).
-export([call_module/4]).
-export([call/2, call/3, cast/2]).
-export([start_link/1, stop_all/1, do_event/2]).
-export([print_packages/1, print_childs/2]).
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2,
         handle_info/2]).
-export_type([event/0]).

-include("nkservice.hrl").
-include("nkservice_srv.hrl").

-define(SRV_CHECK_TIME, 5000).
-define(MAX_EVENT_QUEUE_SIZE, 1000).

-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE '~s' "++Txt, [State#state.id | Args])).


%% ===================================================================
%% Types
%% ===================================================================


-type id() :: nkservice:id().

-type service_status() ::
    #{
        class => nkservice:class(),
        name => nkservice:name(),
        hash => integer(),
        node => node(),
        modules => #{nkservice:module_id() => module_status()},
        packages => #{nkservice:package_id() => package_status()}
    }.

-type status() :: starting | running | updating | failed.

-type package_status() ::
    #{
        status => status(),
        last_status_time => nklib_util:m_timestamp(),
        error => term(),
        last_error_time => nklib_util:m_timestamp()
    }.


-type module_status() ::
    #{
        status => status(),
        last_status_time => nklib_util:m_timestamp(),
        error => term(),
        last_error_time => nklib_util:m_timestamp()
    }.

-type event() ::
    service_started |
    service_updated |
    service_stopping |
    {service_updated, #{
        packages_to_stop => [nkservice:module_id()],
        packages_to_start => [nkservice:module_id()],
        packages_to_update => [nkservice:module_id()],
        modules_to_stop => [nkservice:module_id()],
        modules_to_start => [nkservice:module_id()],
        modules_to_update => [nkservice:module_id()]
    }} |
    {package_supervisor_down, #{package_id=>nkservice:module_id()}} |
    {package_supervisor_stopped, #{package_id=>nkservice:module_id()}} |
    {module_supervisor_down, #{module_id=>nkservice:module_id()}} |
    {module_supervisor_stopped, #{module_id=>nkservice:module_id()}} |
    {package_status, #{package_id=>nkservice:module_id(), status=>status()}} |
    {module_status, #{module_id=>nkservice:module_id(), status=>status()}}.



%% ===================================================================
%% Public
%% ===================================================================

%% @doc
start(Service) ->
    nkservice_srv_sup:start_service(Service).


%% @doc Stops a service, only in local node
-spec stop(id()) ->
    ok | {error, not_running|term()}.

stop(SrvId) ->
    Reply = nkservice_srv_sup:stop_service(SrvId),
    code:purge(SrvId),
    Reply.


%% @doc Replaces a service configuration with a new full set of parameters
%% Should be performed only on master node, or master will overwrite it
-spec replace(id(), nkservice:spec()) ->
    ok | {error, term()}.

replace(SrvId, Spec) ->
    Service1 = nkservice_config_cache:get_full_service(SrvId),
    Service2 = nkservice_config:negated_service(Service1),
    case nkservice_config:config_service(SrvId, Spec, Service2) of
        {ok, Service3} ->
            do_update(Service3);
        {error, Error} ->
            {error, Error}
    end.


%% @doc Updates a service configuration in local node
%% Should be performed only on master node
%% Fields class, name, global, plugins, uuid, meta, if used, overwrite previous settings
%% Packages and modules are merged. Use remove => true to remove an old one
%% Fields cache, debug, secret are merged. Use remove => true to remove an old one
-spec update(id(), nkservice:spec()) ->
    ok | {error, term()}.

update(SrvId, Spec) ->
    Service1 = nkservice_config_cache:get_full_service(SrvId),
    case nkservice_config:config_service(SrvId, Spec, Service1) of
        {ok, Service2} ->
            do_update(Service2);
        {error, Error} ->
            {error, Error}
    end.


%% @private
do_update(#{id:=SrvId}=Service) ->
    call(SrvId, {nkservice_update, Service}, 30000).



%% @doc
-spec get_status(id()) ->
    {ok, service_status()} | {error, term()}.

get_status(SrvId) ->
    call(SrvId, nkservice_get_status).


%% @doc
-spec get_events(id()) ->
    {ok, list()}.

get_events(SrvId) ->
    call(SrvId, nkservice_get_events).

%% @doc
-spec send_event(id(), nkservice:event()) ->
    ok.

send_event(SrvId, Event) ->
    cast(SrvId, {nkservice_send_event, Event}).


%% @doc Call module and updates state
call_module(SrvId, ModuleSrvId, Fun, Args) ->
    call(SrvId, {nkservice_call_module, to_bin(ModuleSrvId), Fun, Args}).


%% @doc
launch_check_status(SrvId) ->
    cast(SrvId, nkservice_check_status).


%% @doc Synchronous call to the service's gen_server process
-spec call(nkservice:id(), term()) ->
    term().

call(SrvId, Term) ->
    call(SrvId, Term, 5000).


%% @doc Synchronous call to the service's gen_server process with a timeout
-spec call(nkservice:id()|pid(), term(), pos_integer()|infinity|default) ->
    term().

call(SrvId, Term, Time) ->
    nklib_util:call(SrvId, Term, Time).


%% @doc Asynchronous call to the service's gen_server process
-spec cast(nkservice:id()|pid(), term()) ->
    term().

cast(SrvId, Term) ->
    gen_server:cast(SrvId, Term).


%% @doc Gets all started services
-spec get_all() ->
    [{id(), nkservice:name(), nkservice:class(), integer(), pid()}].

get_all() ->
    [{SrvId, ?CALL_SRV(SrvId, name), Class, Hash, Pid} ||
        {{SrvId, Class, Hash}, Pid} <- nklib_proc:values(nkservice_srv)].


%% @doc Gets all started services
-spec get_all(nkservice:class()) ->
    [{id(), nkservice:name(), pid()}].

get_all(Class) ->
    Class2 = nklib_util:to_binary(Class),
    [{SrvId, Name, Pid} || {SrvId, Name, C, _H, Pid} <- get_all(), C==Class2].


%% @private
print_packages(SrvId) ->
    nkservice_packages_sup:get_packages(SrvId).

print_childs(SrvId, PackageId) ->
    nkservice_packages_sup:get_childs(SrvId, nklib_util:to_binary(PackageId)).



%% ===================================================================
%% Private
%% ===================================================================


%% @private
-spec start_link(nkservice:spec()) ->
    {ok, pid()} | {error, term()}.

start_link(#{id:=Id}=Spec) ->
    gen_server:start_link({local, Id}, ?MODULE, Spec, []).



%% @private
-spec stop_all(pid()) ->
    ok.

stop_all(Pid) ->
    nklib_util:call(Pid, nkservice_stop_all, 30000).


%%%% @private
%%pending_msgs() ->
%%    lists:map(
%%        fun({_Id, Name, _Class, Pid}) ->
%%            {_, Len} = erlang:process_info(Pid, message_queue_len),
%%            {Name, Len}
%%        end,
%%        nkservice:get_all()).



%% ===================================================================
%% gen_server
%% ===================================================================


%% @private
init(#{id:=SrvId, hash:=Hash}=Service) ->
    process_flag(trap_exit, true),          % Allow receiving terminate/2
    Class = maps:get(class, Service, <<>>),
    Name = maps:get(name, Service, <<>>),
    nklib_proc:put(?MODULE, {SrvId, Class, Hash}),
    nklib_proc:put({?MODULE, Name}, {SrvId, Hash}),
    nklib_proc:put({?MODULE, SrvId}, {Class, Name, Hash}),
    nkservice_config_cache:make_cache(Service),
    % Someone could be listening (like events)
    nkservice_util:notify_updated_service(SrvId),
    {ok, UserState} = SrvId:service_init(Service, #{}),
    State = #state{
        id = SrvId,
        service = Service,
        package_status= #{},
        package_sup_pids = [],
        module_status= #{},
        module_sup_pids = [],
        events = {0, queue:new()},
        user = UserState
    },
    self() ! nkservice_timed_check_status,
    {ok, do_event(service_started, State)}.



%% @private
handle_call(nkservice_get_status, _From, State) ->
    {reply, {ok, do_get_status(State)}, State};

handle_call(nkservice_get_events, _From, #state{events={_, Queue}}=State) ->
    {_, Events} = lists:foldl(
        fun({Time, Event}, {LastTime, Acc}) ->
            {Time, [{Time-LastTime, Time, Event}|Acc]}
        end,
        {0, []},
        queue:to_list(Queue)),
    {reply, {ok, Events}, State};

handle_call({nkservice_update, NewService}, _From, State) ->
    State2 = do_update(NewService, State),
    State3 = do_event(update_received, State2),
    {reply, ok, State3};

handle_call({nkservice_call_module, _ModuleId, _Fun, _Args}, _From, State) ->
    {reply, {error, unknown_module}, State};

handle_call(nkservice_state, _From, State) ->
    {reply, State, State};

handle_call(Msg, From, State) ->
    handle(service_handle_call, [Msg, From], State).


%% @private
handle_cast({nkservice_send_event, Event}, State)->
    {noreply, do_event(Event, State)};

handle_cast(nkservice_check_status, State)->
    {noreply, check_sup_state(State)};

handle_cast({nkservice_package_status, PackageId, Status}, State)->
    State2 = nkservice_srv_packages:update_status(PackageId, Status, State),
    {noreply, State2};

handle_cast({nkservice_module_status, ModuleId, Status}, State)->
    State2 = nkservice_srv_modules:update_status(ModuleId, Status, State),
    {noreply, State2};

handle_cast(nkservice_stop, State)->
    % Will restart everything
    {stop, normal, State};

handle_cast(Msg, State) ->
    handle(service_handle_cast, [Msg], State).


%% @private
handle_info(nkservice_timed_check_status, State) ->
    State2 = check_sup_state(State),
    erlang:send_after(?SRV_CHECK_TIME, self(), nkservice_timed_check_status),
    {noreply, State2};

handle_info({'DOWN', _Ref, process, Pid, _Reason}=Msg, State) ->
    #state{
        package_status= PackagesStatus,
        package_sup_pids = PackagePids,
        module_status= ModuleStatus,
        module_sup_pids = ModulePids
    } = State,
    case lists:keytake(Pid, 2, PackagePids) of
        {value, {ignore, Pid}, PackagePids2} ->
            State2 = State#state{package_sup_pids=PackagePids2},
            {noreply, State2};
        {value, {PackageId, Pid}, PackagePids2} ->
            State2 = case maps:is_key(PackageId, PackagesStatus) of
                true ->
                    nkservice_srv_packages:update_status(PackageId, {error, supervisor_down}, State);
                false ->
                    State
            end,
            State3 = State2#state{package_sup_pids=PackagePids2},
            {noreply, State3};
        false ->
            case lists:keytake(Pid, 2, ModulePids) of
                {value, {ignore, Pid}, ModulePids2} ->
                    State2 = State#state{module_sup_pids=ModulePids2},
                    {noreply, State2};
                {value, {ModuleId, Pid}, ModulePids2} ->
                    State2 = case maps:is_key(ModuleId, ModuleStatus) of
                        true ->
                            nkservice_srv_modules:update_status(ModuleId, {error, supervisor_down}, State);
                        false ->
                            State
                    end,
                    State3 = State2#state{module_sup_pids=ModulePids2},
                    {noreply, State3};
                false ->
                    handle(service_handle_info, [Msg], State)
            end
    end;

handle_info(Msg, State) ->
    handle(service_handle_info, [Msg], State).


%% @private
code_change(OldVsn, #state{id=SrvId, user=UserState}=State, Extra) ->
    case apply(SrvId, service_code_change, [OldVsn, UserState, Extra]) of
        {ok, UserState2} ->
            {ok, State#state{user=UserState2}};
        {error, Error} ->
            {error, Error}
    end.



%% @private
terminate(Reason, #state{id=SrvId, service=Service}=State) ->
    State2 = do_event(service_stopping, State),
    ?LLOG(debug, "is stopping (~p)", [Reason], State2),
    lists:foreach(
        fun(Module) -> nkservice_srv_modules:do_stop(Module, State2) end,
        maps:keys(?CALL_SRV(SrvId, modules))),
    lists:foreach(
        fun(Package) -> nkservice_srv_packages:do_stop(Package, self(), Service, State2) end,
        maps:keys(?CALL_SRV(SrvId, packages))),
    % We could launch all in parallel and wait for the casts here
    ?LLOG(info, "is stopped", [], State2),
    catch handle(nkservice_terminate, [Reason], State2).



%% ===================================================================
%% Internal
%% ===================================================================


%% @private Packages will be checked from low to high
check_sup_state(#state{id=SrvId}=State) ->
    State2 = nkservice_srv_modules:start(maps:keys(?CALL_SRV(SrvId, modules)), State),
    State3 = nkservice_srv_packages:start(maps:keys(?CALL_SRV(SrvId, packages)), State2),
    nkservice_master:updated_service_status(SrvId, do_get_status(State3)),
    State3.


%% @private
do_update(NewService, #state{id=SrvId, service=OldService}=State) ->
    State2 = do_update_core(NewService, State),
    {Event1, State3} = do_update_modules(NewService, OldService, State2),
    {Event2, State4} = do_update_packages(NewService, OldService, State3),
    nkservice_config_cache:make_cache(NewService),
    nkservice_util:notify_updated_service(SrvId),
    Event3 = {service_updated, maps:merge(Event1, Event2)},
    State5 = State4#state{service = NewService},
    State6 = do_event(Event3, State5),
    check_sup_state(State6).


%% @private
do_update_core(#{hash:=Hash}=NewService, #state{id=SrvId}=State) ->
    Name = maps:get(name, NewService),
    Class = maps:get(class, NewService),
    nklib_proc:put(?MODULE, {SrvId, Class, Hash}),
    nklib_proc:put({?MODULE, Name}, {SrvId, Hash}),
    nklib_proc:put({?MODULE, SrvId}, {Class, Name, Hash}),
    State.


%% @private
do_update_modules(NewService, OldService, State) ->
    NewModules = maps:get(modules, NewService, #{}),
    NewModuleIds = maps:keys(NewModules),
    OldModules = maps:get(modules, OldService, #{}),
    OldModuleIds = maps:keys(OldModules),
    ToStop = lists:sort(OldModuleIds -- NewModuleIds),
    State2 = nkservice_srv_modules:stop(ToStop, State),
    ToStart = lists:sort(NewModuleIds -- OldModuleIds),
    ToUpdate1 = (OldModuleIds -- ToStart) -- ToStop,
    ToUpdate2 = lists:sort(lists:filter(
        fun(ModuleId) ->
            #{hash:=Old} = maps:get(ModuleId, OldModules, #{}),
            #{hash:=New} = NewSpec = maps:get(ModuleId, NewModules, #{}),
            Old /= New orelse maps:get(reload, NewSpec, false)
        end,
        ToUpdate1)),
    Unchanged = lists:sort((OldModuleIds -- ToUpdate2) -- ToStop),
    % To update a module, we stop it
    % It will be restarted by check_sup_state
    State3 = nkservice_srv_modules:stop(ToUpdate2, State2),
    ?LLOG(notice, "updated modules (to stop: ~p, to start: ~p, to update: ~p, unchanged: ~p)",
        [ToStop, ToStart, ToUpdate2, Unchanged], State2),
    Event = #{
        modules_to_stop => ToStop,
        modules_to_start => ToStart,
        modules_to_update => ToUpdate2,
        modules_unchanged => Unchanged
    },
    {Event, State3}.


%% @private
do_update_packages(NewService, OldService, State) ->
    NewPackages = maps:get(packages, NewService, #{}),
    NewPackageIds = maps:keys(NewPackages),
    OldPackages = maps:get(packages, OldService, #{}),
    OldPackageIds = maps:keys(OldPackages),
    ToStop = lists:sort(OldPackageIds -- NewPackageIds),
    State2 = nkservice_srv_packages:stop(ToStop, OldService, State),
    ToStart = lists:sort(NewPackageIds -- OldPackageIds),
    ToUpdate1 = (OldPackageIds -- ToStart) -- ToStop,
    ToUpdate2 = lists:sort(lists:filter(
        fun(PackageId) ->
            #{hash:=Old} = maps:get(PackageId, OldPackages, #{}),
            #{hash:=New} = maps:get(PackageId, NewPackages, #{}),
            Old /= New
        end,
        ToUpdate1)),
    Unchanged = lists:sort(ToUpdate1 -- ToUpdate2),
    % Update is managed by package theirselves, we only signal them
    State3 = nkservice_srv_packages:update(ToUpdate2, NewService, OldService, State2),
    ?LLOG(notice, "updated packages (to stop: ~p, to start: ~p, to update: ~p, unchanged: ~p)",
        [ToStop, ToStart, ToUpdate2, Unchanged], State2),
    Event = #{
        packages_to_stop => ToStop,
        packages_to_start => ToStart,
        packages_to_update => ToUpdate2,
        packages_unchanged => Unchanged},
    {Event, State3}.


%% @private
do_get_status(State) ->
    #state{
        service = Service,
        package_status = PackagesStatus,
        module_status = ModuleStatus
    } = State,
    #{name:=Name, class:=Class, hash:=Hash} = Service,
    #{
        name => Name,
        class => Class,
        node => node(),
        packages => PackagesStatus,
        modules => ModuleStatus,
        hash => Hash
    }.


%% @private
%% Will call the service's functions
handle(Fun, Args, #state{id=SrvId, service=Service, user=UserState}=State) ->
    case apply(SrvId, Fun, Args++[Service, UserState]) of
        {reply, Reply, UserState2} ->
            {reply, Reply, State#state{user=UserState2}};
        {reply, Reply, UserState2, Time} ->
            {reply, Reply, State#state{user=UserState2}, Time};
        {noreply, UserState2} ->
            {noreply, State#state{user=UserState2}};
        {noreply, UserState2, Time} ->
            {noreply, State#state{user=UserState2}, Time};
        {stop, Reason, Reply, UserState2} ->
            {stop, Reason, Reply, State#state{user=UserState2}};
        {stop, Reason, UserState2} ->
            {stop, Reason, State#state{user=UserState2}};
        {ok, UserState2} ->
            {ok, State#state{user=UserState2}};
        Other ->
            ?LLOG(warning, "invalid response for ~p(~p): ~p", [Fun, Args, Other], State),
            error(invalid_handle_response)
    end.


%% @private
do_event(Event, #state{events={Size, Queue}}=State) ->
    {ok, State2} = handle(service_event, [Event], State),
    {Size2, Queue2} = case Size >= ?MAX_EVENT_QUEUE_SIZE of
        true ->
            {Size-1, queue:drop(Queue)};
        false ->
            {Size, Queue}
    end,
    Now = nklib_util:m_timestamp(),
    {Size3, Queue3} = {Size2+1, queue:in({Now, Event}, Queue2)},
    State2#state{events={Size3, Queue3}}.



%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).
