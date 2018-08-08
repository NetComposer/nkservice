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

%% @doc Basic Actor behaviour
%%
%% When the actor starts, it must register with its service's leader or it won't start
%% If the leader fails, the actor will save and unload immediately
%% (the leader keeps the registration for the actor, so it cannot be found any more)
%%
%% Unload policy
%%
%% - Permanent mode
%%      if object has permanent => true in config(), it is not unloaded
%% - Expires mode
%%      if object has expires property, the object expires after that time no matter what
%% - TTL mode
%%      otherwise, property default_ttl in object_info() is used for ttl, default is ?DEFAULT_TTL
%%      once expired, the object is unloaded if no childs or usages
%%      some functions restart de count calling do_refresh()
%%
%% Enabled policy
%%
%% - An actor starts disabled if property "isEnabled" is set to false
%% - All standard operations work normally (but see dont_update_on_disabled and dont_delete_on_disabled)
%% - When the actor is enabled or disabled, and event will be fired (useful for links)
%% - The behaviour will be dependant for each implementation
%%
%% Save policy
%%
%% - It will saved on 'save' operations (sync and async) and returning
%%   reply_and_save and noreply_and_save on operations
%% - Also before deletion, on unload, on update (if is_dirty:true)
%% - Periodically, at each heartbeat (5secs) save_time parameter if check and it will
%%   be saved if dirty and save_time has passed
%% - Also, at each check_ttl (for example after each sync or async operation)
%%   if is_dirty:true, a timer will be started (save_time in config)
%%   if it is saved, the timers is removed. If it fires, it is saved


-module(nkservice_actor_srv).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([create/2, start/2, sync_op/2, sync_op/3, async_op/2]).
-export([init/1, terminate/2, code_change/3, handle_call/3,  handle_cast/2, handle_info/2]).
-export([add_link/3, remove_link/2]).
-export([get_all/0, unload_all/0, get_state/1, raw_stop/2]).
-export([do_stop/2, do_event_link/2]).
-export_type([event/0, save_reason/0]).


-include("nkservice.hrl").
-include("nkservice_actor.hrl").
-include("nkservice_actor_debug.hrl").


-define(DEFAULT_TTL, 10000).
-define(DEF_SYNC_CALL, 5000).
-define(HEARTBEAT_TIME, 5000).
-define(DEFAULT_SAVE_TIME, 5000).



%% ===================================================================
%% Types
%% ===================================================================


-type config() ::
    #{
        permanent => boolean(),
        save_time => integer(),                         %% msecs for auto-save
        ttl => integer(),                               %% msecs
        stop_after_disabled => boolean(),               %% Default false
        dont_update_on_disabled => boolean(),           %% Default false
        dont_delete_on_disabled => boolean(),           %% Default false
        activable => boolean(),                         %% Default true
        atom() => term()                                %% User config
    }.


-type event() ::
    created |
    activated |
    saved |
    {updated, nkservice_actor:actor()} |
    deleted |
    {enabled, boolean()} |
    {info, binary(), Meta::map()} |
    {link_added, Type::binary()} |
    {link_removed, Type::binary()} |
    {link_down, Type::binary()} |
    {stopped, nkservice:msg()}.


-type start_opts() ::
    #{
        %is_enabled => boolean(),        % Mark as disabled on load
        config => config()              % Overrides config
    }.


-type link_opts() ::
    #{
        get_events => boolean(),        % calls to actor_srv_link_event for each event (false)
        gen_events => boolean(),        % generate events {link_XXX} (true)
        avoid_unload => boolean(),      % do not unload until is unlinked (false)
        data => term()                  % user config
    }.


-type sync_op() ::
    get_actor |
    get_actor_id |
    get_links |
    save |
    delete |
    {enable, boolean()} |
    is_enabled |
    {link, nklib:link(), link_opts()} |
    {update, nkservice_actor:actor()} |
    {update_name, binary()} |
    get_alarms |
    {apply, Mod::module(), Fun::atom(), Args::list()} |
    actor_deleted |
    term().

-type async_op() ::
    {unlink, nklib:link()} |
    {send_info, atom()|binary(), map()} |
    {send_event, event()} |
    save |
    {stop, Reason::nkservice:msg()} |
    term().

-type state() :: #actor_st{}.

-type save_reason() ::
    creation | user_op | user_order | unloaded | update | timer.



%% ===================================================================
%% Public
%% ===================================================================

%% @private
%% Call SrvId:actor_create/2 instead calling this directly!
-spec create(nkservice_actor:actor(), start_opts()) ->
    {ok, pid()} | {error, term()}.

create(_Actor, #{config:=#{activable:=false}}) ->
    {error, actor_is_not_activable};

create(#actor{id=#actor_id{srv=Srv}}=Actor, StartOpts) ->
    case is_pid(whereis(Srv)) of
        true ->
            gen_server:start(?MODULE, {create, Actor, StartOpts}, []);
        false ->
            {error, {service_not_available, Srv}}
    end.


%% @private
%% Call SrvId:actor_activate/2 instead calling this directly!
-spec start(nkservice_actor:actor(), start_opts()) ->
    {ok, pid()} | {error, term()}.

start(_Actor, #{config:=#{activable:=false}}) ->
    {error, actor_is_not_activable};

start(#actor{id=#actor_id{srv=Srv}}=Actor, StartOpts) ->
    case is_pid(whereis(Srv)) of
        true ->
            gen_server:start(?MODULE, {start, Actor, StartOpts}, []);
        false ->
            {error, {service_not_available, Srv}}
    end.


%% @doc
-spec sync_op(nkservice_actor:id()|pid(), sync_op()) ->
    term() | {error, timeout|process_not_found|object_not_found|term()}.

sync_op(Id, Op) ->
    sync_op(Id, Op, ?DEF_SYNC_CALL).


%% @doc
-spec sync_op(nkservice_actor:id()|pid(), sync_op(), timeout()) ->
    term() | {error, timeout|process_not_found|object_not_found|term()}.

sync_op(Pid, Op, Timeout) when is_pid(Pid) ->
    nklib_util:call2(Pid, {nkservice_sync_op, Op}, Timeout);

sync_op(Id, Op, Timeout) ->
    sync_op(Id, Op, Timeout, 5).


%% @private
sync_op(_Id, _Op, _Timeout, 0) ->
    {error, process_not_found};

sync_op(Id, Op, Timeout, Tries) ->
    case nkservice_actor_db:activate(Id) of
        {ok, #actor_id{pid=Pid}, _} when is_pid(Pid) ->
            case sync_op(Pid, Op, Timeout) of
                {error, process_not_found} ->
                    lager:notice("NkSERVICE SynOP failed (~p), retrying...", [Id]),
                    timer:sleep(250),
                    sync_op(Id, Op, Timeout, Tries-1);
                Other ->
                    Other
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc
-spec async_op(pid(), async_op()) ->
    ok | {error, process_not_found|object_not_found|term()}.

async_op(Pid, Op) when is_pid(Pid) ->
    gen_server:cast(Pid, {nkservice_async_op, Op});

async_op(Id, Op) ->
    case nkservice_actor_db:activate(Id) of
        {ok, #actor_id{pid=Pid}, _} when is_pid(Pid) ->
            async_op(Pid, Op);
        {error, Error} ->
            {error, Error}
    end.


%% @private
%% If the object is activated, it will be unloaded without saving
%% before launching the deletion
raw_stop(Id, Reason) ->
    case nkservice_actor_db:is_activated(Id) of
        {true, #actor_id{pid=Pid}} ->
            async_op(Pid, {raw_stop, Reason});
        false ->
            ok
    end.


%% @private
get_state(Id) ->
    sync_op(Id, get_state).


%% @doc
-spec get_all() ->
    [#actor_id{}].

get_all() ->
    [ActorId || {#actor_id{pid=Pid}=ActorId, Pid} <- nklib_proc:values(?MODULE)].


%% @private
unload_all() ->
    lists:foreach(
        fun(#actor_id{pid=Pid}) -> async_op(Pid, {stop, normal}) end,
        get_all()).


% ===================================================================
%% gen_server behaviour
%% ===================================================================


-record(link_info, {
    get_events :: boolean(),
    gen_events :: boolean(),
    avoid_unload :: boolean(),
    data :: term()
}).


%% @private
-spec init(term()) ->
    {ok, state()} | {stop, term()}.

init({create, Actor, StartOpts}) ->
    #actor{id=#actor_id{srv=SrvId}=ActorId} = Actor,
    Actor2 = Actor#actor{id=ActorId#actor_id{pid=self()}},
    case register_with_leader(Actor2) of
        {ok, LeaderPid} ->
            case ?CALL_SRV(SrvId, actor_db_create, [SrvId, Actor2]) of
                {ok, _Meta} ->
                    State = do_pre_init(Actor2, StartOpts, LeaderPid),
                    ?DEBUG("created (~p)", [self()], State),
                    State2 = do_event(created, State),
                    do_post_init(State2);
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {stop, Error}
    end;

init({start, Actor, StartOpts}) ->
    #actor{id=ActorId} = Actor,
    Actor2 = Actor#actor{id=ActorId#actor_id{pid=self()}},
    case register_with_leader(Actor2) of
        {ok, LeaderPid} ->
            State = do_pre_init(Actor2, StartOpts, LeaderPid),
            do_post_init(State);
        {error, Error} ->
            {stop, Error}
    end.


%% @private
-spec handle_call(term(), {pid(), term()}, state()) ->
    {noreply, state()} | {reply, term(), state()} |
    {stop, Reason::term(), state()} | {stop, Reason::term(), Reply::term(), state()}.

handle_call({nkservice_sync_op, Op}, From, State) ->
    case handle(actor_srv_sync_op, [Op, From], State) of
        {reply, Reply, #actor_st{}=State2} ->
            reply(Reply, do_refresh_ttl(State2));
        {reply_and_save, Reply, #actor_st{}=State2} ->
            {_, State3} = do_save(user_op, State2#actor_st{is_dirty2=true}),
            reply(Reply, do_refresh_ttl(State3));
        {noreply, #actor_st{}=State2} ->
            noreply(do_refresh_ttl(State2));
        {noreply_and_save, #actor_st{}=State2} ->
            {_, State3} = do_save(user_op, State2#actor_st{is_dirty2=true}),
            noreply(do_refresh_ttl(State3));
        {stop, Reason, Reply, #actor_st{}=State2} ->
            gen_server:reply(From, Reply),
            do_stop(Reason, State2);
        {stop, Reason, #actor_st{}=State2} ->
            do_stop(Reason, State2);
        continue ->
            do_sync_op(Op, From, State);
        {continue, [Op2, _From2, #actor_st{}=State2]} ->
            do_sync_op(Op2, From, State2);
        Other ->
            ?LLOG(error, "invalid response for sync op ~p: ~p", [Op, Other], State),
            error(invalid_sync_response)
    end;

handle_call(Msg, From, State) ->
    safe_handle(actor_srv_handle_call, [Msg, From], State).


%% @private
-spec handle_cast(term(), state()) ->
    {noreply, state()} | {stop, term(), state()}.

handle_cast({nkservice_async_op, Op}, State) ->
    case handle(actor_srv_async_op, [Op], State) of
        {noreply, #actor_st{}=State2} ->
            noreply(do_refresh_ttl(State2));
        {noreply_and_save, #actor_st{}=State2} ->
            {_, State3} = do_save(user_op, State2#actor_st{is_dirty2=true}),
            noreply(do_refresh_ttl(State3));
        {stop, Reason, #actor_st{}=State2} ->
            do_stop(Reason, State2);
        continue ->
            do_async_op(Op, State);
        {continue, [Op2, #actor_st{}=State2]} ->
            do_async_op(Op2, State2);
        Other ->
            ?LLOG(error, "invalid response for async op ~p: ~p", [Op, Other], State),
            error(invalid_async_response)
    end;

handle_cast(Msg, State) ->
    safe_handle(actor_srv_handle_cast, [Msg], State).


%% @private
-spec handle_info(term(), state()) ->
    {noreply, state()} | {stop, term(), state()}.

handle_info({nkservice_updated, _SrvId}, State) ->
    set_debug(State),
    noreply(State);

handle_info(nkservice_check_expire, State) ->
    case do_check_expired(State) of
        true ->
            do_stop(actor_expired, State);
        {false, State2} ->
            noreply(State2)
    end;

handle_info(nkservice_ttl_timeout, State) ->
    do_ttl_timeout(State);

handle_info(nkservice_timer_save, State) ->
    do_async_op({save, timer}, State);

handle_info(nkservice_next_status_timer, State) ->
    State2 = State#actor_st{status_timer=undefined},
    {ok, State3} = handle(actor_srv_next_status_timer, [], State2),
    noreply(State3);

handle_info(nkservice_heartbeat, State) ->
    erlang:send_after(?HEARTBEAT_TIME, self(), nkservice_heartbeat),
    do_heartbeat(State);

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #actor_st{leader_pid=Pid}=State) ->
    ?LLOG(notice, "service leader is down, stopping", [], State),
    do_stop(leader_is_down, State);

handle_info({'DOWN', Ref, process, _Pid, _Reason}=Info, State) ->
    case link_down(Ref, State) of
        {ok, Link, LinkOpts, State2} ->
            ?DEBUG("link ~p down (~p)", [Link, LinkOpts], State),
            {ok, State3} = handle(actor_srv_link_down, [Link], State2),
            noreply(State3);
        not_found ->
            safe_handle(actor_srv_handle_info, [Info], State)
    end;

handle_info(Msg, State) ->
    safe_handle(actor_srv_handle_info, [Msg], State).


%% @private
-spec code_change(term(), state(), term()) ->
    {ok, state()}.

code_change(OldVsn, #actor_st{actor=#actor{id=#actor_id{srv=SrvId}}}=State, Extra) ->
    ?CALL_SRV(SrvId, actor_code_change, [OldVsn, State, Extra]).


%% @private
-spec terminate(term(), state()) ->
    ok.

%%terminate(_Reason, #actor{moved_to=Pid}) when is_pid(Pid) ->
%%    ok;

terminate(Reason, State) ->
    State2 = do_stop2({terminate, Reason}, State),
    {ok, _State3} = handle(actor_srv_terminate, [Reason], State2),
    ok.


%% ===================================================================
%% Operations
%% ===================================================================

%% @private
do_sync_op(get_actor_id, _From, #actor_st{actor=#actor{id=ActorId}}=State) ->
    reply({ok, ActorId}, do_refresh_ttl(State));

do_sync_op(get_actor, _From, #actor_st{actor=Actor}=State) ->
    {ok, UserActor, State2} = handle(actor_srv_get, [Actor], State),
    reply({ok, UserActor}, do_refresh_ttl(State2));

do_sync_op(get_state, _From, State) ->
    reply({ok, State}, State);

do_sync_op(get_links, _From, #actor_st{links=Links}=State) ->
    Data = nklib_links:fold_values(
        fun(Link, #link_info{data=Data}, Acc) -> [{Link, Data}|Acc] end,
        [],
        Links),
    reply({ok, Data}, State);

do_sync_op(save, _From, State) ->
    {Reply, State2} = do_save(user_order, State),
    reply(Reply, do_refresh_ttl(State2));

do_sync_op(delete, From, #actor_st{is_enabled=IsEnabled, config=Config}=State) ->
    case {IsEnabled, Config} of
        {false, #{dont_delete_on_disabled:=true}} ->
            reply({error, actor_is_disabled}, State);
        _ ->
            {Reply, State2} = do_delete(State),
            gen_server:reply(From, Reply),
            do_stop(actor_deleted, State2)
    end;

do_sync_op({enable, Enable}, _From, State) when is_boolean(Enable)->
    #actor_st{actor = Actor} = State,
    #actor{metadata = Meta} = Actor,
    case maps:get(<<"isEnabled">>, Meta, true) of
        Enable ->
            reply(ok, do_refresh_ttl(State));
        _ ->
            Meta2 = Meta#{<<"isEnabled">> => Enable},
            UpdActor = Actor#actor{metadata = Meta2},
            case do_update(UpdActor, State) of
                {ok, State2} ->
                    reply(ok, do_refresh_ttl(State2));
                {error, Error, State2} ->
                    reply({error, Error}, State2)
            end
    end;

do_sync_op(is_enabled, _From, #actor_st{is_enabled=IsEnabled}=State) ->
    reply({ok, IsEnabled}, State);

do_sync_op({link, Link, Opts}, _From, State) ->
    LinkData = #link_info{
        get_events = maps:get(get_events, Opts, false),
        gen_events = maps:get(gen_events, Opts, true),
        avoid_unload = maps:get(avoid_unload, Opts, false),
        data = maps:get(data, Opts, undefined)
    },
    ?DEBUG("link ~p added (~p)", [Link, LinkData], State),
    {reply, ok, add_link(Link, LinkData, do_refresh_ttl(State))};

do_sync_op({update, #actor{}=Actor}, _From, #actor_st{is_enabled=IsEnabled, config=Config}=State) ->
    case {IsEnabled, Config} of
        {false, #{dont_update_on_disabled:=true}} ->
            reply({error, object_is_disabled}, State);
        _ ->
            case do_update(Actor, State) of
                {ok, State2} ->
                    reply(ok, do_refresh_ttl(State2));
                {error, Error, State2} ->
                    reply({error, Error}, State2)
            end
    end;

do_sync_op({update_name, Name}, _From, #actor_st{is_enabled=IsEnabled, config=Config}=State) ->
    case {IsEnabled, Config} of
        {false, #{dont_update_on_disabled:=true}} ->
            reply({error, object_is_disabled}, State);
        _ ->
            case do_update_name(Name, State) of
                {ok, State2} ->
                    reply(ok, do_refresh_ttl(State2));
                {error, Error, State2} ->
                    reply({error, Error}, State2)
            end
    end;

do_sync_op(get_alarms, _From, #actor_st{actor=Actor}=State) ->
    Alarms = case Actor of
        #actor{metadata = #{<<"isInAlarm">>:=true, <<"alarms">>:=AlarmList}} ->
            AlarmList;
        _ ->
            []
    end,
    {reply, {ok, Alarms}, State};

do_sync_op({apply, Mod, Fun, Args}, From, State) ->
    apply(Mod, Fun, Args++[From, do_refresh_ttl(State)]);

do_sync_op(Op, _From, State) ->
    ?LLOG(notice, "unknown sync op: ~p", [Op], State),
    reply({error, unknown_op}, State).


%% @private
do_async_op({unlink, Link}, State) ->
    {ok, remove_link(Link, State)};

do_async_op({send_info, Info, Meta}, State) ->
    noreply(do_event({info, nklib_util:to_binary(Info), Meta}, do_refresh_ttl(State)));

do_async_op({send_event, Event}, State) ->
    noreply(do_event(Event, do_refresh_ttl(State)));

do_async_op({set_dirty, IsDirty}, State) when is_boolean(IsDirty)->
    noreply(do_refresh_ttl(State#actor_st{is_dirty2=IsDirty}));

do_async_op(save, State) ->
    do_async_op({save, user_order}, State);

do_async_op({save, Reason}, State) ->
    {_Reply, State2} = do_save(Reason, State),
    noreply(do_refresh_ttl(State2));

do_async_op({stop, Reason}, State) ->
    ?DEBUG("received stop: ~p", [Reason], State),
    do_stop(Reason, State);

do_async_op({raw_stop, Reason}, State) ->
    % We don't send the deleted event here, since we may not be active at all
    ?LLOG(warning, "received raw_stop: ~p", [Reason], State),
    {ok, State2} = handle(actor_srv_stop, [Reason], State),
    State3 = do_event({stopped, Reason}, State2),
    {stop, normal, State3#actor_st{stop_reason=raw_stop}};

do_async_op(Op, State) ->
    ?LLOG(notice, "unknown async op: ~p", [Op], State),
    noreply(State).




%% ===================================================================
%% Internals
%% ===================================================================


%% @private
do_pre_init(Actor, StartOpts, LeaderPid) ->
    #actor{id=#actor_id{srv=SrvId, uid=UID}=ActorId, metadata=Meta} = Actor,
    true = is_binary(UID) andalso UID /= <<>>,
    nklib_proc:put(?MODULE, ActorId),
    Now = nklib_date:epoch(msecs),
    NextStatusTimer = case Meta of
        #{<<"nextStatusTime">>:=NextStatusTime} ->
            case NextStatusTime - Now of
                Step when Step=<0 ->
                    self() ! nkservice_next_status_timer,
                    undefined;
                Step ->
                    erlang:send_after(Step, self(), nkservice_next_status_timer)
            end;
        _ ->
            undefined
    end,
    Config1 = ?CALL_SRV(SrvId, actor_config, [ActorId]),
    Config2 = case StartOpts of
        #{config:=StartConfig} ->
            maps:merge(Config1, StartConfig);
        _ ->
            Config1
    end,
    State = #actor_st{
        config = Config2,
        actor = Actor#actor{status=#{is_activated=>true}},
        links = nklib_links:new(),
        is_dirty2 = false,
        is_enabled = maps:get(<<"isEnabled">>, Meta, true),
        save_timer = undefined,
        activated_time = Now,
        status_timer = NextStatusTimer,
        unload_policy = permanent,           % Updated later
        leader_pid = LeaderPid
    },
    set_debug(State),
    set_unload_policy(State).


%% @private
do_post_init(State) ->
    case handle(actor_srv_init, [], State) of
        {ok, State2} ->
            ?DEBUG("started (~p)", [self()], State2),
            State3 = do_event(activated, State2),
            State4 = do_check_alarms(State3),
            self() ! nkservice_heartbeat,
            {ok, do_refresh_ttl(State4)};
        {error, Error} ->
            {stop, Error}
    end.


%% @private
set_debug(State) ->
    #actor_st{actor=#actor{id=#actor_id{srv=SrvId, class=Class, type=Type}}} = State,
    Debug = case nkservice_util:get_debug(SrvId, nkservice_actor, <<"all">>, debug) of
        true ->
            true;
        _ ->
            case nkservice_util:get_debug(SrvId, nkservice_actor, {Class, <<"all">>}, debug) of
                true ->
                    true;
                _ ->
                    case nkservice_util:get_debug(SrvId, nkservice_actor, {Class, Type}, debug) of
                        true ->
                            true;
                        _ ->
                            false
                    end
            end
    end,
    put(nkservice_actor_debug, Debug),
    ?DEBUG("debug activated", [], State).


%% @private
set_unload_policy(#actor_st{config=Config}=State) ->
    Policy = case maps:get(permanent, Config, false) of
        true ->
            permanent;
        false ->
            #actor_st{actor=#actor{metadata=Meta}} = State,
            case maps:get(<<"expiresTime">>, Meta, <<>>) of
                <<>> ->
                    % A TTL reseated after each operation
                    TTL = maps:get(ttl, Config, ?DEFAULT_TTL),
                    ?DEBUG("TTL is ~p", [TTL], State),
                    {ttl, TTL};
                Expires ->
                    self() ! nkservice_check_expire,
                    {expires, Expires}
            end
    end,
    ?DEBUG("unload policy is ~p", [Policy], State),
    State#actor_st{unload_policy=Policy}.


%% @private
%% The service leader registers the UID and the set {Srv, Class, Type, Name} with
%% this pid.
%% If the service master dies, the process will stop immediately
register_with_leader(#actor{id=#actor_id{srv=SrvId}=ActorId}) ->
    case nkservice_master:register_actor(ActorId) of
        {ok, Pid} ->
            ?DEBUG("registered with master service (~p)", [Pid]),
            monitor(process, Pid),
            % Maybe the master didn't start the service yet at our node
            case wait_start_srv(SrvId, 10) of
                ok ->
                    {ok, Pid};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @private
wait_start_srv(SrvId, Tries) when Tries > 0 ->
    case whereis(SrvId) of
        Pid when is_pid(Pid) ->
            ok;
        undefined ->
            timer:sleep(1000),
            ?LLOG(notice, "waiting for service '~s' (~p tries left)", [SrvId, Tries]),
            wait_start_srv(SrvId, Tries-1)
    end;

wait_start_srv(SrvId, _Tries) ->
    ?LLOG(warning, "Cannot start service '~s': timeout", [SrvId]),
    {error, service_wait_timeout}.


%% @private
do_check_alarms(#actor_st{actor=#actor{metadata=Meta}}=State) ->
    case Meta of
        #{<<"isInAlarm">>:=true} ->
            {ok, State2} = handle(actor_srv_alarms, [], State),
            State2;
        _ ->
            State
    end.


%% @private
do_save(Reason, #actor_st{is_dirty2=true, actor=Actor, save_timer=Timer}=State) ->
    nklib_util:cancel_timer(Timer),
    #actor{id=#actor_id{srv=SrvId}} = Actor,
    State2 = State#actor_st{save_timer=undefined},
    case ?CALL_SRV(SrvId, actor_db_update, [SrvId, Actor]) of
        {ok, DbMeta} ->
            ?DEBUG("save (~p) (~p)", [Reason, DbMeta], State2),
            State3 = State2#actor_st{is_dirty2=false},
            {ok, do_event(saved, State3)};
        {error, not_implemented, State2} ->
            {{error, not_implemented}, State2};
        {error, Error, State2} ->
            ?LLOG(warning, "save error: ~p", [Error], State),
            {{error, Error}, State2}
    end;

do_save(_Reason, State) ->
    {ok, State}.


%% @private Reset TTL
do_refresh_ttl(#actor_st{unload_policy={ttl, Time}, ttl_timer=Timer}=State) when is_integer(Time) ->
    nklib_util:cancel_timer(Timer),
    Ref = erlang:send_after(Time, self(), nkservice_ttl_timeout),
    do_check_save(State#actor_st{ttl_timer=Ref});

do_refresh_ttl(State) ->
    do_check_save(State).


%% @private
do_check_expired(#actor_st{unload_policy={expires, Expires}, ttl_timer=Timer}=State) ->
    nklib_util:cancel_timer(Timer),
    case nklib_date:epoch(msecs) of
        Now when Now >= Expires ->
            true;
        Now ->
            Remind = min(3600000, Expires - Now),
            Ref = erlang:send_after(Remind, self(), nkservice_check_expire),
            {false, State#actor_st{ttl_timer=Ref}}
    end;

do_check_expired(State) ->
    {false, State}.


%% @private
do_stop(Reason, State) ->
    {stop, normal, do_stop2(Reason, State)}.


%% @private
do_stop2(Reason, #actor_st{stop_reason=false, config=Config}=State) ->
    {_, State2} = case Config of
        #{remove_after_stop:=true} ->
            do_delete(State);
        _ ->
            {ok, State}
    end,
    State3 = State2#actor_st{stop_reason=Reason},
    {ok, State4} = handle(actor_srv_stop, [Reason], State3),
    State5 = do_event({stopped, Reason}, State4),
    {_, State6} = do_save(unloaded, State5),
    State6;

do_stop2(_Reason, State) ->
    State.


%% @private
do_delete(#actor_st{is_dirty2=deleted}=State) ->
    {ok, State};

do_delete(#actor_st{actor=Actor}=State) ->
    #actor{id=#actor_id{uid=UID, srv=SrvId}} = Actor,
    case ?CALL_SRV(SrvId, actor_db_delete, [SrvId, UID, #{}]) of
        {ok, _ActorIds, DbMeta} ->
            ?DEBUG("object deleted: ~p", [DbMeta], State),
            {ok, do_event(deleted, State#actor_st{is_dirty2=deleted})};
        {error, Error} ->
            ?LLOG(warning, "object could not be deleted: ~p", [Error], State),
            {{error, Error}, State#actor_st{actor=Actor}}
    end.


%% @private
do_update(UpdActor, #actor_st{actor=#actor{id=Id}=Actor}=State) ->
    #actor_id{srv=SrvId, uid=UID, class=Class, type=Type, name=Name} = Id,
    try
        case UpdActor#actor.id#actor_id.srv of
            SrvId -> ok;
            _ -> throw({updated_invalid_field, srv})
        end,
        case UpdActor#actor.id#actor_id.uid of
            undefined -> ok;
            UID -> ok;
            _ -> throw({updated_invalid_field, uid})
        end,
        case UpdActor#actor.id#actor_id.class of
            Class -> ok;
            _ -> throw({updated_invalid_field, class})
        end,
        case UpdActor#actor.id#actor_id.type of
            Type -> ok;
            _ -> throw({updated_invalid_field, type})
        end,
        case UpdActor#actor.id#actor_id.name of
            Name -> ok;
            _ -> throw({updated_invalid_field, name})
        end,
        #actor{data=Data, metadata=Meta} = Actor,
        UpdData = UpdActor#actor.data,
        IsDataUpdated = UpdData /= Data,
        UpdMeta = UpdActor#actor.metadata,
        CT = maps:get(<<"creationTime">>, Meta),
        case maps:get(<<"creationTime">>, UpdMeta, CT) of
            CT -> ok;
            _ -> throw({updated_invalid_field, metadata})
        end,
        Links = maps:get(<<"links">>, Meta, #{}),
        UpdLinks = maps:get(<<"links">>, UpdMeta, Links),
        UpdMeta2 = case UpdLinks == Links of
            true ->
                UpdMeta;
            false ->
                case nkservice_actor_util:check_links(UpdMeta) of
                    {ok, UpdMetaLinks} ->
                        UpdMetaLinks;
                    {error, Error} ->
                        throw(Error)
                end
        end,
        Enabled = maps:get(<<"isEnabled">>, Meta, true),
        UpdEnabled = maps:get(<<"isEnabled">>, UpdMeta2, true),
        UpdMeta3 = case maps:get(<<"isEnabled">>, UpdMeta2, true) of
            true ->
                maps:remove(<<"isEnabled">>, UpdMeta2);
            false ->
                UpdMeta2
        end,
        NewMeta = maps:merge(Meta, UpdMeta3),
        IsMetaUpdated = (Meta /= NewMeta) orelse (Enabled /= UpdEnabled),
        case IsDataUpdated orelse IsMetaUpdated of
            true ->
                %lager:error("NKLOG UPDATE Data:~p, Meta:~p", [IsDataUpdated, IsMetaUpdated]),
                NewMeta2 = case UpdEnabled of
                    true ->
                        maps:remove(<<"isEnabled">>, NewMeta);
                    false ->
                        NewMeta#{<<"isEnabled">>=>false}
                end,
                NewActor = Actor#actor{data=UpdData, metadata=NewMeta2},
                State2 = State#actor_st{actor=NewActor, is_dirty2=true},
                State3 = do_update_version(State2),
                State4 = do_enabled(UpdEnabled, State3),
                State5 = set_unload_policy(State4),
                case do_save(update, State5) of
                    {ok, State6} ->
                        {ok, do_event({updated, UpdActor}, State6)};
                    {{error, SaveError}, State5} ->
                        {error, SaveError, State5}
                end;
            false ->
                % lager:error("NKLOG NO UPDATE"),
                {ok, State}
        end
    catch
        throw:Throw ->
            {error, Throw, State}
    end.


%% @private
do_update_name(Name, #actor_st{actor=Actor}=State) ->
    #actor{id=#actor_id{name=OldName}=Id} = Actor,
    lager:error("NKLOG UPDATE NAME ~p", [Name]),
    case nkservice_actor_util:normalized_name(Name) of
        OldName ->
            {ok, State};
        NewName ->
            Id2 = Id#actor_id{name=NewName},
            Actor2 = Actor#actor{id=Id2},
            case register_with_leader(State#actor_st{actor=Actor2}) of
                {ok, State2} ->
                    State3 = State2#actor_st{is_dirty2=true},
                    State4 = do_update_version(State3),
                    case do_save(update, State4) of
                        {ok, #actor_st{actor=Actor}=State5} ->
                            {ok, do_event({updated, Actor}, State5)};
                        {{error, SaveError}, State5} ->
                            {error, SaveError, State5}
                    end;
                {error, RegError} ->
                    {error, RegError, State}
            end
    end.


%% @private
do_update_version(#actor_st{actor=Actor}=State) ->
    #actor{id=#actor_id{name=Name}, data=Data, metadata=Meta} = Actor,
    {ok, Time} = nklib_date:to_3339(nklib_date:epoch(msecs)),
    Meta2 = nkservice_actor_util:update_meta(Name, Data, Meta, Time),
    State#actor_st{actor=Actor#actor{metadata=Meta2}}.


%% @private
do_enabled(Enabled, #actor_st{is_enabled=Enabled}=State) ->
    State;

do_enabled(Enabled, State) ->
    State2 = State#actor_st{is_enabled = Enabled},
    {ok, State3} = handle(actor_srv_enabled, [Enabled], State2),
    do_event({enabled, Enabled}, State3).


%% @private
do_heartbeat(State) ->
    case handle(actor_srv_heartbeat, [], State) of
        {ok, State2} ->
            noreply(State2);
        {error, Error} ->
            do_stop(Error, State)
    end.


%% @private
do_check_save(#actor_st{is_dirty2=true, save_timer=undefined, config=Config}=State) ->
    SaveTime = maps:get(save_time, Config, ?DEFAULT_SAVE_TIME),
    Timer = erlang:send_after(SaveTime, self(), nkservice_timer_save),
    State#actor_st{save_timer=Timer};

do_check_save(State) ->
    State.


%% @private
do_event(Event, State) ->
    ?DEBUG("sending 'event': ~p", [Event], State),
    State2 = do_event_link(Event, State),
    {ok, State3} = handle(actor_srv_event, [Event], State2),
    State3.


%% @private
do_event_link(Event, #actor_st{links=Links}=State) ->
    nklib_links:fold_values(
        fun
            (Link, #link_info{get_events=true, data=Data}, Acc) ->
                {ok, Acc2} = handle(actor_srv_link_event, [Link, Data, Event], Acc),
                Acc2;
            (_Link, _LinkOpts, Acc) ->
                Acc
        end,
        State,
        Links).



%% @private
do_ttl_timeout(#actor_st{unload_policy={ttl, _}, links=Links, status_timer=undefined}=State) ->
    Avoid = nklib_links:fold_values(
        fun
            (_Link, #link_info{avoid_unload=true}, _Acc) -> true;
            (_Link, _LinkOpts, Acc) -> Acc
        end,
        false,
        Links),
    case Avoid of
        true ->
            noreply(do_refresh_ttl(State));
        false ->
            do_stop(ttl_timeout, State)
    end;

do_ttl_timeout(#actor_st{unload_policy={ttl, _}}=State) ->
    noreply(do_refresh_ttl(State)).


%% ===================================================================
%% Util
%% ===================================================================


% @private
reply(Reply, #actor_st{}=State) ->
    {reply, Reply, State}.


%% @private
noreply(#actor_st{}=State) ->
    {noreply, State}.


%% @private
%% Will call the service's functions
handle(Fun, Args, State) ->
    #actor_st{actor=#actor{id=#actor_id{srv=SrvId}}} = State,
    %lager:error("NKLOG CALL ~p:~p:~p", [SrvId, Fun, Args]),
    ?CALL_SRV(SrvId, Fun, Args++[State]).


%% @privateF
safe_handle(Fun, Args, State) ->
    Reply = handle(Fun, Args, State),
    case Reply of
        {reply, _, #actor_st{}} ->
            Reply;
        {reply, _, #actor_st{}, _} ->
            Reply;
        {noreply, #actor_st{}} ->
            Reply;
        {noreply, #actor_st{}, _} ->
            Reply;
        {stop, _, _, #actor_st{}} ->
            Reply;
        {stop, _, #actor_st{}} ->
            Reply;
        Other ->
            ?LLOG(error, "invalid response for ~p(~p): ~p", [Fun, Args, Other], State),
            error(invalid_handle_response)
    end.


%% @private
add_link(Link, LinkInfo, #actor_st{links=Links}=State) ->
    #link_info{gen_events=GenEvents, data=Data} = LinkInfo,
    State2 = case GenEvents of
        true ->
            do_event({link_added, Data}, State);
        _ ->
            State
    end,
    State2#actor_st{links=nklib_links:add(Link, LinkInfo, Links)}.


%% @private
remove_link(Link, #actor_st{links=Links}=State) ->
    State2 = case nklib_links:get_value(Link, Links) of
        {ok, #link_info{gen_events=true, data=Data}} ->
            do_event({link_removed, Data}, State);
        _ ->
            State
    end,
    State2#actor_st{links=nklib_links:remove(Link, Links)}.


%% @private
link_down(Mon, #actor_st{links=Links}=State) ->
    case nklib_links:down(Mon, Links) of
        {ok, Link, LinkInfo, Links2} ->
            case LinkInfo of
                #link_info{gen_events=true, data=Data} ->
                    State2 = do_event({link_down, Data}, State),
                    {ok, Link, LinkInfo, State2#actor_st{links=Links2}};
                _ ->
                    {ok, Link, LinkInfo, State#actor_st{links=Links2}}
            end;
        not_found ->
            not_found
    end.


%%%% @private
%%links_iter(Fun, Acc, #actor_st{links=Links}) ->
%%    nklib_links:fold_values(Fun, Acc, Links).

%%%% @private
%%to_bin(Term) when is_binary(Term) -> Term;
%%to_bin(Term) -> nklib_util:to_binary(Term).
