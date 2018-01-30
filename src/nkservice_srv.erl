
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

-module(nkservice_srv).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([find_name/1, get_status/1]).
-export([get/3, put/3, put_new/3, del/2]).
-export([call/2, call/3, cast/2]).
-export([start_link/1, stop_all/1]).
-export([pending_msgs/0]).
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2,
         handle_info/2]).

-include("nkservice.hrl").
%%-include_lib("nkapi/include/nkapi.hrl").

-define(SRV_CHECK_TIME, 5000).

-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE '~s' "++Txt, [State#state.id | Args])).


%% ===================================================================
%% Public
%% ===================================================================

%% @private Finds a service's id from its name
-spec find_name(nkservice:name()) ->
    {ok, nkservice:id()} | not_found.

find_name(Name) ->
    case nklib_proc:values({?MODULE, Name}) of
        [] -> not_found;
        [{Id, _Pid}|_] -> {ok, Id}
    end.

%% @doc
get_status(Id) ->
    call(Id, {?MODULE, get_status}).


%% @doc Gets a value from service's store
-spec get(nkservice:id(), term(), term()) ->
    term().

get(SrvId, Key, Default) ->
    case ets:lookup(SrvId, Key) of
        [{_, Value}] -> Value;
        [] -> Default
    end.


%% @doc Inserts a value in service's store
-spec put(nkservice:id(), term(), term()) ->
    ok.

put(SrvId, Key, Value) ->
    ets:insert(SrvId, {Key, Value}).


%% @doc Inserts a value in service's store
-spec put_new(nkservice:id(), term(), term()) ->
    true | false.

put_new(SrvId, Key, Value) ->
    ets:insert_new(SrvId, {Key, Value}).


%% @doc Deletes a value from service's store
-spec del(nkservice:id(), term()) ->
    ok.

del(SrvId, Key) ->
    ets:delete(SrvId, Key).


%% @doc Synchronous call to the service's gen_server process
-spec call(nkservice:id(), term()) ->
    term().

call(Id, Term) ->
    call(Id, Term, 5000).


%% @doc Synchronous call to the service's gen_server process with a timeout
-spec call(nkservice:id(), term(), pos_integer()|infinity|default) ->
    term().

call(Id, Term, Time) ->
    nklib_util:call(Id, Term, Time).


%% @doc Asynchronous call to the service's gen_server process
-spec cast(nkservice:id(), term()) ->
    term().

cast(Id, Term) ->
    gen_server:cast(Id, Term).




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


%% @private
pending_msgs() ->
    lists:map(
        fun({_Id, Name, _Class, Pid}) ->
            {_, Len} = erlang:process_info(Pid, message_queue_len),
            {Name, Len}
        end,
        nkservice:get_all()).



%% ===================================================================
%% gen_server
%% ===================================================================

-type plugin_status() :: starting | started | failed.

-record(state, {
        id :: nkservice:id(),
        service :: nkservice:service(),
        plugins :: #{atom() => #{pid=>pid(), status=>plugin_status()}},
        events :: queue:queue(),
        user :: map()
    }).

-define(P1, #state.id).
-define(P2, #state.user).


%% @private
init(#{id:=Id}=Service) ->
    lager:error("NKLOG SRV ~p", [Id]),
    process_flag(trap_exit, true),          % Allow receiving terminate/2
    Class = maps:get(class, Service, <<>>),
    Name = maps:get(name, Service, <<>>),
    nklib_proc:put(?MODULE, {Id, Class}),
    nklib_proc:put({?MODULE, Name}, Id),
    nkservice_config:make_cache(Service),
    % Someone could be listening (like events)
    nkservice_util:notify_updated_service(Id),
    {ok, UserState} = Id:service_init(Service, #{}),
    State = #state{
        id = Id,
        service = Service,
        plugins = #{},
        events = queue:new(),
        user = UserState
    },
    self() ! {?MODULE, check_plugins},
    {ok, State}.



%% @private
-spec handle_call(term(), {pid(), term()}, nkservice:service()) ->
    term().

handle_call({?MODULE, get_status}, _From, #state{plugins=Plugins}=State) ->
    {reply, {ok, Plugins}, State};

handle_call({?MODULE, update, Spec}, From, #state{id=Id, service=Service}=State) ->
    case nkservice_config:config_service(Spec, Service) of
        {ok, Service2} ->
            Class = maps:get(class, Service2, <<>>),
            Name = maps:get(name, Service2, <<>>),
            nklib_proc:put(?MODULE, {Id, Class}),
            nklib_proc:put({?MODULE, Name}, Id),
            nkservice_config:make_cache(Service2),
            nkservice_util:notify_updated_service(Id),
            gen_server:reply(From, ok),
            State2 = State#state{
                service = Service2
            },
            State3 = check_plugins(?CALL_SRV(Id, plugins), State2),
            {noreply, State3};
        {error, Error} ->
            {reply, {error, Error}, State}
    end;

%%handle_call({nkservice_update, UserSpec}, _From, #state{service=Service}=State) ->
%%    #{id:=Id, name:=Name} = Service,
%%    case nkservice_config:config_service(UserSpec, Service) of
%%        {ok, Service2} ->
%%            case nkservice_srv_listen_sup:start_transports(Service2) of
%%                {ok, Service3} ->
%%                    nkservice_config:make_cache(Service3),
%%                    {Added, Removed} = get_diffs(Service3, Service),
%%                    Added2 = case maps:is_key(lua_state, Added) of
%%                        true -> Added#{lua_state:=<<"...">>};
%%                        false -> Added
%%                    end,
%%                    Removed2 = case maps:is_key(lua_state, Removed) of
%%                        true -> Removed#{lua_state:=<<"...">>};
%%                        false -> Removed
%%                    end,
%%                    lager:info("Service '~s' added config: ~p", [Name, Added2]),
%%                    lager:info("Service '~s' removed config: ~p", [Name, Removed2]),
%%                    nkservice_util:notify_updated_service(Id),
%%                    {reply, ok, State#state{service=Service3}};
%%                {error, Error} ->
%%                    {reply, {error, Error}, State}
%%            end;
%%        {error, Error} ->
%%            {reply, {error, Error}, State}
%%    end;
%%
%%handle_call(nkservice_stop_all, _From, #state{service=Service}=State) ->
%%    #{plugins:=Plugins} = Service,
%%    Service2 = nkservice_config:stop_plugins(Plugins, Service),
%%    {reply, ok, State#state{service=Service2}};

handle_call(nkservice_state, _From, State) ->
    {reply, State, State};

handle_call(Msg, From, State) ->
    nklib_gen_server:handle_call(service_handle_call, Msg, From, State, ?P1, ?P2).


%% @private
-spec handle_cast(term(), nkservice:service()) ->
    term().

handle_cast({?MODULE, plugin_started, Plugin, Pid}, State)->
    #state{id=Id, plugins=Plugins} = State,
    Status2 = case maps:get(Plugin, Plugins) of
        {ok, #{pid:=Pid}=Status} ->
            Status#{status=>running};
        {ok, Status} ->
            monitor(process, Pid),
            Status#{status=>running, pid=>Pid}
    end,
    Plugins2 = Plugins#{Plugin => Status2},
    State2 = State#state{plugins=Plugins2},
    State3 = check_plugins(?CALL_SRV(Id, plugins), State2),
    {noreply, State3};

handle_cast({?MODULE, plugin_start_error, Plugin, Error}, #state{plugins=Plugins}=State)->
    Status1 = maps:get(Plugin, Plugins),
    Status2 = Status1#{status=>failed, error=>Error},
    Plugins2 = Plugins#{Plugin => Status2},
    State2 = State#state{plugins=Plugins2},
    {noreply, State2};

handle_cast(nkservice_stop, State)->
    % Will restart everything
    {stop, normal, State};

handle_cast(Msg, State) ->
    nklib_gen_server:handle_cast(service_handle_cast, Msg, State, ?P1, ?P2).

%% @private
-spec handle_info(term(), nkservice:service()) ->
    nklib_util:gen_server_info(nkservice:service()).

handle_info({?MODULE, check_plugins}, #state{id=Id}=State) ->
    State2 = check_plugins(?CALL_SRV(Id, plugins), State),
    % erlang:send_after(?SRV_CHECK_TIME, self(), {?MODULE, check_plugins}),
    {noreply, State2};

handle_info({'DOWN', _Ref, process, Pid, Reason}=Msg, State) ->
    #state{plugins=Plugins} = State,
    Pids = [{Plugin, PluginPid} || {Plugin, #{pid:=PluginPid}} <- maps:to_list(Plugins)],
    case lists:keyfind(Pid, 2, Pids) of
        {Plugin, Pid} ->
            ?LLOG(warning, "plugin ~s failed", [Plugin], State),
            Status1 = maps:get(Plugin, Plugins),
            Status2 = Status1#{status=>failed, error=>Reason},
            Plugins2 = Plugins#{Plugin => Status2},
            State2 = State#state{plugins=Plugins2},
            {noreply, State2};
        error ->
            nklib_gen_server:handle_info(service_handle_info, Msg, State, ?P1, ?P2)
    end;

handle_info(Msg, State) ->
    nklib_gen_server:handle_info(service_handle_info, Msg, State, ?P1, ?P2).


%% @private
-spec code_change(term(), nkservice:service(), term()) ->
    {ok, nkservice:service()} | {error, term()}.

code_change(OldVsn, State, Extra) ->
    nklib_gen_server:code_change(service_code_change, OldVsn, State, Extra, ?P1, ?P2).


%% @private
-spec terminate(term(), nkservice:service()) ->
    ok.

terminate(Reason, #state{id=Id, service=_Service}=State) ->
    catch nklib_gen_server:terminate(nkservice_terminate, Reason, State, ?P1, ?P2),
    %#{plugins:=Plugins} = Service,
    %_Service2 = nkservice_config:stop_plugins(Plugins, Service),
    lager:notice("Service '~s' has terminated (~p)", [Id, Reason]).
    


%% ===================================================================
%% Internal
%% ===================================================================


%% @private Plugins will be checked from low to high
check_plugins([Plugin|Rest], State) ->
    #state{id=Id, plugins=Plugins} = State,
    {ok, Pid} = nkservice_srv_plugins_sup:start_plugin(Id, Plugin),
    case maps:get(Plugin, Plugins, #{}) of
        #{status:=running, pid:=Pid} ->
            % Plugin is ok, let's go next
            check_plugins(Rest, State);
        PluginStatus ->
            % Plugin is not ok, let's spawn a process to try
            % to start it, and abort the operation
            % it will call us later
            spawn_start_plugin(Plugin, Pid, State),
            PluginStatus2 = PluginStatus#{status=>starting},
            Plugins2 = Plugins#{Plugin => PluginStatus2},
            State#state{plugins=Plugins2}
    end.


%% @private
spawn_start_plugin(Plugin, Pid, #state{service=Service}) ->
    Self = self(),
    spawn_link(
        fun() ->
            case nkservice_config:start_plugin(Plugin, Pid, Service) of
                ok ->
                    gen_server:cast(Self, {?MODULE, plugin_started, Plugin, Pid});
                {error, Error} ->
                    gen_server:cast(Self, {?MODULE, plugin_start_error, Plugin, Error})
            end
        end).



%%%% private
%%get_diffs(Map1, Map2) ->
%%    Add = get_diffs(nklib_util:to_list(Map1), Map2, []),
%%    Rem = get_diffs(nklib_util:to_list(Map2), Map1, []),
%%    {maps:from_list(Add), maps:from_list(Rem)}.
%%
%%
%%%% private
%%get_diffs([], _, Acc) ->
%%    Acc;
%%
%%get_diffs([{cache, _}|Rest], Map, Acc) ->
%%    get_diffs(Rest, Map, Acc);
%%
%%get_diffs([{Key, Val}|Rest], Map, Acc) ->
%%    Acc1 = case maps:find(Key, Map) of
%%        {ok, Val} -> Acc;
%%        _ -> [{Key, Val}|Acc]
%%    end,
%%    get_diffs(Rest, Map, Acc1).



