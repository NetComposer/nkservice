
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


%% Plugin management
%% -----------------
%%
%% When the service starts, plugins_status is empty
%% - All defined plugins will be launched in check_plugins, low first
%% - Plugins can return running or failed
%% - Periodically we re-launch start for failed ones
%% - If the plugin supervisor fails, it is marked as failed
%%
%% When the service is updated
%% - Plugins no longer available are removed, and called stop_plugin
%% - Plugins that stay are marked as upgrading, called update_plugin
%% - When response is received, they are marked as running or failed
%%
%% Service stop
%% - Services are stopped sequentially (high to low)



-module(nkservice_srv).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([get_status/1, get_events/1, send_event/2, force_check_plugins/1]).
-export([get/3, put/3, put_new/3, del/2]).
-export([call/2, call/3, cast/2]).
-export([start_link/1, stop_all/1]).
-export([pending_msgs/0]).
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2,
         handle_info/2]).

-include("nkservice.hrl").
%%-include_lib("nkapi/include/nkapi.hrl").

-define(SRV_CHECK_TIME, 5000).
-define(MAX_EVENT_QUEUE_SIZE, 1000).

-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE '~s' "++Txt, [State#state.id | Args])).


%% ===================================================================
%% Types
%% ===================================================================

-type id() :: nkservice:id().

-type plugin_status() ::
    #{
        status => starting | running | updating | failed,
        last_status_time => nklib_util:m_timestamp(),
        error => term(),
        last_error_time => nklib_util:m_timestamp()
    }.



%% ===================================================================
%% Public
%% ===================================================================


%% @doc
-spec get_status(id()) ->
    #{Plugin::atom() => plugin_status()}.

get_status(Id) ->
    call(Id, {?MODULE, get_status}).


%% @doc
-spec get_events(id()) ->
    {ok, list()}.

get_events(Id) ->
    call(Id, {?MODULE, get_events}).


%% @doc
send_event(Id, Event) ->
    cast(Id, {?MODULE, send_event, Event}).


%% @doc
force_check_plugins(Id) ->
    cast(Id, {?MODULE, force_check_plugins}).


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

-record(state, {
        id :: nkservice:id(),
        service :: nkservice:service(),
        plugins_status :: #{atom() => plugin_status()},
        plugins_sup :: [{atom(), pid()}],
        events :: {Size::integer(), queue:queue()},
        user :: map(),
        updating :: boolean()
    }).

-define(P1, #state.id).
-define(P2, #state.user).


%% @private
init(#{id:=Id}=Service) ->
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
        plugins_status = #{},
        plugins_sup = [],
        events = {0, queue:new()},
        user = UserState,
        updating = false
    },
    self() ! {?MODULE, check_plugins},
    event(service_started),
    {ok, State}.



%% @private
-spec handle_call(term(), {pid(), term()}, nkservice:service()) ->
    term().

handle_call({?MODULE, get_status}, _From, #state{plugins_status=Plugins}=State) ->
    {reply, {ok, Plugins}, State};

handle_call({?MODULE, get_events}, _From, #state{events={_, Queue}}=State) ->
    {_, Events} = lists:foldl(
        fun({Time, Event}, {LastTime, Acc}) ->
            {Time, [{Time-LastTime, Time, Event}|Acc]}
        end,
        {0, []},
        queue:to_list(Queue)),
    {reply, {ok, Events}, State};


handle_call({?MODULE, update, Spec}, _From, #state{service=Service}=State) ->
    event(received_service_update),
    case nkservice_config:config_service(Spec, Service) of
        {ok, NewService} ->
            State2 = do_upgrade(NewService, State),
            {reply, ok, State2};
        {error, Error} ->
            {reply, {error, Error}, State}
    end;

handle_call({?MODULE, replace, Spec}, _From, #state{service=Service}=State) ->
    event(received_service_replace),
    RawService = maps:with([id, uuid], Service),
    case nkservice_config:config_service(Spec, RawService) of
        {ok, NewService} ->
            State2 = do_upgrade(NewService, State),
            {reply, ok, State2};
        {error, Error} ->
            {reply, {error, Error}, State}
    end;

handle_call(nkservice_state, _From, State) ->
    {reply, State, State};

handle_call(Msg, From, State) ->
    nklib_gen_server:handle_call(service_handle_call, Msg, From, State, ?P1, ?P2).


%% @private
-spec handle_cast(term(), nkservice:service()) ->
    term().

handle_cast({?MODULE, send_event, Event}, State)->
    {noreply, insert_event(Event, State)};

handle_cast({?MODULE, force_check_plugins}, State)->
    {noreply, check_plugins(State)};

handle_cast({?MODULE, plugin_status, Plugin, Status}, State)->
    State2 = update_plugin_status(Plugin, Status, State),
    {noreply, State2};

handle_cast(nkservice_stop, State)->
    % Will restart everything
    {stop, normal, State};

handle_cast(Msg, State) ->
    nklib_gen_server:handle_cast(service_handle_cast, Msg, State, ?P1, ?P2).

%% @private
-spec handle_info(term(), nkservice:service()) ->
    nklib_util:gen_server_info(nkservice:service()).

handle_info({?MODULE, check_plugins}, State) ->
    State2 = check_plugins(State),
    erlang:send_after(?SRV_CHECK_TIME, self(), {?MODULE, check_plugins}),
    {noreply, State2};

handle_info({'DOWN', _Ref, process, Pid, _Reason}=Msg, State) ->
    #state{plugins_status=PluginsStatus, plugins_sup=Sups} = State,
    case lists:keytake(Pid, 2, Sups) of
        {value, {Plugin, Pid}, Sups2} ->
            State2 = case maps:is_key(Plugin, PluginsStatus) of
                true ->
                    event({supervisor_down, Plugin}),
                    update_plugin_status(Plugin, {error, supervisor_down}, State);
                false ->
                    event({supervisor_stopped, Plugin}),
                    State
            end,
            State3 = State2#state{plugins_sup=Sups2},
            {noreply, State3};
        false ->
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

terminate(Reason, #state{id=Id}=State) ->
    event(service_stopping),
    ?LLOG(notice, "is stopping (~p)", [Reason], State),
    lists:foreach(
        fun(Plugin) -> do_stop_plugin(Plugin, self(), State) end,
        lists:reverse(?CALL_SRV(Id, plugin_list))),
    % We could launch all in parallel and wait for the casts here
    ?LLOG(info, "is stopped", [], State),
    catch nklib_gen_server:terminate(nkservice_terminate, Reason, State, ?P1, ?P2).



%% ===================================================================
%% Internal
%% ===================================================================

%% @private
do_upgrade(NewService, #state{id=Id}=State) ->
    OldName = ?CALL_SRV(Id, name),
    NewName = maps:get(name, NewService),
    case OldName == NewName of
        true ->
            ok;
        false ->
            nklib_proc:del({?MODULE, OldName}),
            nklib_proc:put({?MODULE, NewName}, Id)
    end,
    OldClass = ?CALL_SRV(Id, class),
    NewClass = maps:get(class, NewService),
    case OldClass == NewClass of
        true ->
            ok;
        false ->
            nklib_proc:del(?MODULE),
            nklib_proc:put(?MODULE, {Id, NewClass})
    end,
    OldPluginList = ?CALL_SRV(Id, plugin_list),
    NewPluginList = maps:get(plugin_list, NewService),
    ToStop = OldPluginList -- NewPluginList,
    % Plugins to stop are removed from 'plugins_status'
    State2 = do_stop_plugins(ToStop, State),
    NewPlugins1 = maps:get(plugins, NewService, #{}),
    % Remove config for stopped plugins
    NewPlugins2 = maps:without(ToStop, NewPlugins1),
    NewService2 = NewService#{plugins=>NewPlugins2},
    State3 = State2#state{service = NewService2},
    nkservice_config:make_cache(NewService2),
    ToStart = NewPluginList -- OldPluginList,
    ToUpdate = (OldPluginList -- ToStart) -- ToStop,
    % All not-new plugins will receive a restart
    State4 = do_update_plugins(ToUpdate, State3),
    nkservice_util:notify_updated_service(Id),
    ?LLOG(notice, "service updated (to stop: ~p, to start: ~p, to update: ~p)",
          [ToStop, ToStart, ToUpdate], State4),
    event({service_update, ToStop, ToStart, ToUpdate}),
    % New plugins will be started now
    check_plugins(State4).


%% @private Plugins will be checked from low to high
check_plugins(#state{id=Id}=State) ->
    check_plugins(?CALL_SRV(Id, plugin_list), State).


%% @private
check_plugins([], State) ->
    State;

check_plugins([nkservice|Rest], State) ->
    check_plugins(Rest, State);

check_plugins([Plugin|Rest], #state{plugins_status=PluginsStatus}=State) ->
    %lager:error("NKLOG CHECK ~p ~p", [Plugin, PluginsStatus]),
    Status = maps:get(Plugin, PluginsStatus, #{}),
    State2 = case maps:get(status, Status, failed) of
        failed ->
            do_start_plugin(Plugin, State);
        _ ->
            % for 'starting', 'running', 'updating', do nothing
            State
    end,
    check_plugins(Rest, State2).


%% @private
do_start_plugin(Plugin, #state{service=Service}=State) ->
    Self = self(),
    case start_plugin_sup(Plugin, State) of
        {ok, Pid, State2} ->
            cast_plugin_status(Self, Plugin, starting),
            spawn_link(
                fun() ->
                    Res = try nkservice_config:start_plugin(Plugin, Pid, Service) of
                        ok ->
                            running;
                        {error, Error} ->
                            {error, Error}
                    catch
                        Class:Error ->
                            {error, {Class, {Error, erlang:get_stacktrace()}}}
                    end,
                    cast_plugin_status(Self, Plugin, Res)
                end),
            State2;
        error ->
            cast_plugin_status(Self, Plugin, {error, supervisor_down}),
            State
    end.


%% @private
do_stop_plugins([], State) ->
    State;

do_stop_plugins([Plugin|Rest], #state{plugins_status=PluginsStatus}=State) ->
    Self = self(),
    PluginsStatus2 = maps:remove(Plugin, PluginsStatus),
    State2 = State#state{plugins_status=PluginsStatus2},
    spawn_link(fun() -> do_stop_plugin(Plugin, Self, State) end),
    do_stop_plugins(Rest, State2).


%% @private
do_stop_plugin(Plugin, Self, #state{id=Id, service=Service}=State) ->
    send_event(Self, {plugin_stopping, Plugin}),
    case find_plugin_sup_pid(Plugin, State) of
        {ok, Pid} ->
            try nkservice_config:stop_plugin(Plugin, Pid, Service) of
                ok ->
                    ok;
                {error, Error} ->
                    {error, Error}
            catch
                Class:Error ->
                    {error, {Class, {Error, erlang:get_stacktrace()}}}
            end,
            nkservice_srv_plugins_sup:stop_plugin_sup(Id, Plugin);
        undefined ->
            ok
    end,
    send_event(Self, {plugin_stopped, Plugin}).


%% @private
do_update_plugins([], State) ->
    State;

do_update_plugins([Plugin|Rest], #state{service=Service}=State) ->
    Self = self(),
    State2 = case start_plugin_sup(Plugin, State) of
        {ok, Pid, State3} ->
            cast_plugin_status(Self, Plugin, updating),
            spawn_link(
                fun() ->
                    Res = try nkservice_config:update_plugin(Plugin, Pid, Service) of
                        ok ->
                            running;
                        {error, Error} ->
                            {error, Error}
                    catch
                        Class:Error ->
                            {error, {Class, {Error, erlang:get_stacktrace()}}}
                    end,
                    cast_plugin_status(Self, Plugin, Res)
                end),
            State3;
        error ->
            cast_plugin_status(Self, Plugin, {error, supervisor_down}),
            State
    end,
    do_update_plugins(Rest, State2).


%% @private
update_plugin_status(Plugin, Status, #state{plugins_status=PluginsStatus}=State) ->
    event({plugin_status, Plugin, Status}),
    Now = nklib_util:m_timestamp(),
    PluginStatus1 = maps:get(Plugin, PluginsStatus, #{}),
    PluginStatus2 = case Status of
        {error, Error} ->
            ?LLOG(warning, "updated plugin '~s' error: ~p", [Plugin, Error], State),
            PluginStatus1#{
                status => failed,
                last_error => Error,
                last_error_time => Now,
                last_status_time => Now
            };
        _ ->
            case maps:get(status, PluginStatus1, undefined) of
                Status ->
                    ok;
                Old ->
                    ?LLOG(notice, "updated plugin '~s' status ~p -> ~p",
                          [Plugin, Old, Status], State)
            end,
            PluginStatus1#{
                status => Status,
                last_status_time => Now
            }
    end,
    PluginsStatus2 = PluginsStatus#{Plugin => PluginStatus2},
    State#state{plugins_status=PluginsStatus2}.


%% @private
start_plugin_sup(Plugin, #state{id=Id, plugins_sup=Sups}=State) ->
    case find_plugin_sup_pid(Plugin, State) of
        {ok, Pid} ->
            {ok, Pid, State};
        undefined ->
            case nkservice_srv_plugins_sup:start_plugin_sup(Id, Plugin) of
                {ok, Pid} ->
                    monitor(process, Pid),
                    Sups2 = lists:keystore(Plugin, 1, Sups, {Plugin, Pid}),
                    {ok, Pid, State#state{plugins_sup=Sups2}};
                {error, Error} ->
                    ?LLOG(warning, "could not start plugin '~s' supervisor: ~p",
                        [Plugin, Error], State),
                    error
            end
    end.


%% @private
find_plugin_sup_pid(Plugin, #state{plugins_sup=Sups}) ->
    case lists:keyfind(Plugin, 1, Sups) of
        {Plugin, Pid} when is_pid(Pid) ->
            {ok, Pid};
        _ ->
            undefined
    end.


%% @private
insert_event(Event, #state{events={Size, Queue}}=State) ->
    ?LLOG(info, "EVENT: ~p", [Event], State),
    {Size2, Queue2} = case Size >= ?MAX_EVENT_QUEUE_SIZE of
        true ->
            {Size-1, queue:drop(Queue)};
        false ->
            {Size, Queue}
    end,
    Now = nklib_util:m_timestamp(),
    {Size3, Queue3} = {Size2+1, queue:in({Now, Event}, Queue2)},
    State#state{events={Size3, Queue3}}.


%% @private
cast_plugin_status(Pid, Plugin, Status) ->
    gen_server:cast(Pid, {?MODULE, plugin_status, Plugin, Status}).


%% @private
event(Event) ->
    send_event(self(), Event).





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



