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
%% - All standard operations work normally
%% - When the actor is enabled or disabled, and event will be fired (useful for links)
%% - The behaviour will be dependant for each implementation

-module(nkservice_actor_srv).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([start/2, sync_op/2, sync_op/3, async_op/2]).
-export([actor_is_deleted/1, conflict_detected/2]).
-export([init/1, terminate/2, code_change/3, handle_call/3,  handle_cast/2, handle_info/2]).
-export([add_link/3, remove_link/2]).
-export([get_all/0, unload_all/0, get_state/1]).
-export([do_stop/2]).
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
        atom() => term()                                %% User config
    }.


-type event() ::
    created |
    loaded |
    saved |
    {updated, nkservice_actor:actor()} |
    deleted |
    {enabled, boolean()} |
    {info, binary(), Meta::map()} |
    {stopped, Code::binary(), Txt::binary()} |
    {link_added, Type::binary()} |
    {link_removed, Type::binary()} |
    {link_down, Type::binary()} |
    {unloaded, nkservice:msg()}.


-type start_opts() ::
    #{
        %is_enabled => boolean(),        % Mark as disabled on load
        is_new => boolean(),
        config => config()              % Overrides config
    }.


-type link_opts() ::
    #{
        type => atom()|binary(),        % If used, will generate events
        get_events => boolean(),        % calls to actor_link_event for each event
        avoid_unload => boolean(),      % do not unload until is unlinked
        atom() => term()                % user config
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
    term().

-type async_op() ::
    {unlink, nklib:link()} |
    {send_info, atom()|binary(), map()} |
    {send_event, event()} |
    save |
    {unload, Reason::nkservice:msg()} |
    term().

-type state() :: #actor_st{}.

-type save_reason() ::
    creation | user_op | user_order | pre_delete | unloaded | update | timer.



%% ===================================================================
%% Public
%% ===================================================================


%% @private
%% Call SrvId:actor_activate/2 instead calling this directly!
-spec start(nkservice_actor:actor(), start_opts()) ->
    {ok, pid()} | {error, term()}.

start(#{srv:=_, class:=_, type:=_}=Actor, StartOpts) ->
    gen_server:start(?MODULE, {Actor, StartOpts}, []).


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


%% @private Called when the object has been deleted on database
actor_is_deleted(Pid) ->
    gen_server:cast(Pid, nkservice_deleted).


%% @private
get_state(Id) ->
    sync_op(Id, get_state).


%% @private
%% Called from nkdomain_domain_obj after detecting OldPid is in conflict (and will win)
conflict_detected(Pid, WinnerPid) ->
    gen_server:cast(Pid, {nkservice_conflict_detected, WinnerPid}).


%% @doc
-spec get_all() ->
    [#actor_id{}].

get_all() ->
    [ActorId || {#actor_id{pid=Pid}=ActorId, Pid} <- nklib_proc:values(?MODULE)].


%% @private
unload_all() ->
    lists:foreach(
        fun(#actor_id{pid=Pid}) -> async_op(Pid, {unload, normal}) end,
        get_all()).


% ===================================================================
%% gen_server behaviour
%% ===================================================================


-record(link_opts, {
    type :: binary(),
    get_events :: boolean(),
    avoid_unload :: boolean(),
    opts :: link_opts()
}).


%% @private
-spec init(term()) ->
    {ok, state()} | {stop, term()}.

init({Actor, StartOpts}) ->
    State1 = do_init(Actor, StartOpts),
    case register_with_leader(State1) of
        {ok, State2} ->
            set_debug(State2),
            State3 = set_unload_policy(State2),
            case handle(actor_init, [], State3) of
                {ok, State4} ->
                    ?DEBUG("started (~p)", [self()], State4),
                    State5 = case maps:get(is_new, StartOpts, false) of
                        true ->
                            do_event(created, State4);
                        false ->
                            State4
                    end,
                    State6 = do_event(loaded, State5),
                    State7 = do_check_alarms(State6),
                    % If it is a creation, is_dirty = true
                    case do_save(creation, State7) of
                        {ok, State8} ->
                            self() ! nkservice_heartbeat,
                            {ok, do_refresh_ttl(State8)};
                        {{error, Error}, State8} ->
                            ?LLOG(warning, "error creating object: ~p", [Error], State8),
                            {stop, Error}
                    end;
                {error, Error} ->
                    {stop, Error}
            end;
        {error, Error} ->
            {stop, Error}
    end.



%% @private
-spec handle_call(term(), {pid(), term()}, state()) ->
    {noreply, state()} | {reply, term(), state()} |
    {stop, Reason::term(), state()} | {stop, Reason::term(), Reply::term(), state()}.

handle_call({nkservice_sync_op, Op}, From, State) ->
    case handle(actor_sync_op, [Op, From], State) of
        {reply, Reply, #actor_st{}=State2} ->
            reply(Reply, do_refresh_ttl(State2));
        {reply_and_save, Reply, #actor_st{}=State2} ->
            {_, State3} = do_save(user_op, State2#actor_st{is_dirty=true}),
            reply(Reply, do_refresh_ttl(State3));
        {noreply, #actor_st{}=State2} ->
            noreply(do_refresh_ttl(State2));
        {noreply_and_save, #actor_st{}=State2} ->
            {_, State3} = do_save(user_op, State2#actor_st{is_dirty=true}),
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
    safe_handle(actor_handle_call, [Msg, From], State).


%% @private
-spec handle_cast(term(), state()) ->
    {noreply, state()} | {stop, term(), state()}.

handle_cast({nkservice_async_op, Op}, State) ->
    case handle(actor_async_op, [Op], State) of
        {noreply, #actor_st{}=State2} ->
            noreply(do_refresh_ttl(State2));
        {noreply_and_save, #actor_st{}=State2} ->
            {_, State3} = do_save(user_op, State2#actor_st{is_dirty=true}),
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

handle_cast(nkservice_deleted, State) ->
    do_stop(actor_deleted, State#actor_st{is_dirty=false});

handle_cast({nkservice_conflict_detected, WinnerPid}, State) ->
    #actor_st{actor_id =ActorId} = State,
    {ok, State2} = handle(actor_conflict_detected, [ActorId, WinnerPid], State),
    noreply(State2);

handle_cast(Msg, State) ->
    safe_handle(actor_handle_cast, [Msg], State).


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

handle_info(nkservice_next_status_timer, State) ->
    State2 = State#actor_st{status_timer=undefined},
    {ok, State3} = handle(actor_next_status_timer, [], State2),
    noreply(State3);

handle_info(nkservice_heartbeat, State) ->
    erlang:send_after(?HEARTBEAT_TIME, self(), nkservice_heartbeat),
    do_heartbeat(State);

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #actor_st{leader_pid=Pid}=State) ->
    ?LLOG(notice, "service leader is down, stopping", [], State),
    do_stop(leader_down, State);

handle_info({'DOWN', Ref, process, _Pid, _Reason}=Info, State) ->
    case link_down(Ref, State) of
        {ok, Link, LinkOpts, State2} ->
            ?DEBUG("link ~p down (~p)", [Link, LinkOpts], State),
            {ok, State3} = handle(actor_link_down, [Link], State2),
            noreply(State3);
        not_found ->
            safe_handle(actor_handle_info, [Info], State)
    end;

handle_info(Msg, State) ->
    safe_handle(actor_handle_info, [Msg], State).


%% @private
-spec code_change(term(), state(), term()) ->
    {ok, state()}.

code_change(OldVsn, #actor_st{actor_id=#actor_id{srv=SrvId}}=State, Extra) ->
    ?CALL_SRV(SrvId, actor_code_change, [OldVsn, State, Extra]).


%% @private
-spec terminate(term(), state()) ->
    ok.

%%terminate(_Reason, #actor{moved_to=Pid}) when is_pid(Pid) ->
%%    ok;

terminate(Reason, State) ->
    State2 = do_stop2({terminate, Reason}, State),
    {ok, _State3} = handle(actor_terminate, [Reason], State2),
    ok.


%% ===================================================================
%% Operations
%% ===================================================================

%% @private
do_sync_op(get_actor_id, _From, #actor_st{actor_id =ActorId}=State) ->
    reply({ok, ActorId}, do_refresh_ttl(State));

do_sync_op(get_actor, _From, State) ->
    #actor_st{
        actor_id = #actor_id{srv=SrvId, uid=UID, class=Class, type=Type, name=Name},
        spec = Spec,
        meta = Meta,
        vsn = Vsn
    } = State,
    Actor = #{
        srv => SrvId,
        uid => UID,
        class => Class,
        type => Type,
        name => Name,
        vsn => Vsn,
        spec => Spec,
        metadata => Meta
    },
    {ok, UserActor, State2} = handle(actor_get, [Actor], State),
    reply({ok, UserActor}, do_refresh_ttl(State2));

do_sync_op(get_state, _From, State) ->
    reply({ok, State}, State);

do_sync_op(get_links, _From, #actor_st{links=Links}=State) ->
    Data = nklib_links:fold_values(
        fun(Link, #link_opts{opts=Opts}, Acc) -> [{Link, Opts}|Acc] end,
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
            case Reply of
                ok ->
                    do_stop(actor_deleted, State2);
                _ ->
                    noreply(State)
            end
    end;

do_sync_op({enable, Enable}, _From, State) ->
    case do_update(#{metadata=>#{<<"isEnabled">>:=Enable}}, State) of
        {ok, State2} ->
            reply(ok, do_refresh_ttl(State2));
        {error, Error, State2} ->
            reply({error, Error}, State2)
    end;

do_sync_op(is_enabled, _From, #actor_st{is_enabled=IsEnabled}=State) ->
    reply({ok, IsEnabled}, State);

do_sync_op({link, Link, Opts}, _From, State) ->
    LinkOpts = #link_opts{
        type = nklib_util:to_binary(maps:get(disable_actor, Opts, <<>>)),
        get_events = maps:get(get_events, Opts, false),
        avoid_unload = maps:get(avoid_unload, Opts, false),
        opts = Opts
    },
    ?DEBUG("link ~p added (~p)", [Link, LinkOpts], State),
    {reply, ok, add_link(Link, LinkOpts, do_refresh_ttl(State))};

do_sync_op({update, Actor}, _From, #actor_st{is_enabled=IsEnabled, config=Config}=State) ->
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

do_sync_op(get_alarms, _From, #actor_st{meta=Meta}=State) ->
    Alarms = case Meta of
        #{<<"isInAlarm">>:=true, <<"alarms">>:=AlarmList} ->
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

do_async_op({set_dirty, IsDirty}, State) ->
    noreply(do_refresh_ttl(State#actor_st{is_dirty=IsDirty}));

do_async_op(save, State) ->
    {_Reply, State2} = do_save(user_order, State),
    noreply(do_refresh_ttl(State2));

do_async_op({unload, Reason}, State) ->
    ?DEBUG("received unload: ~p", [Reason], State),
    do_stop(Reason, State);

do_async_op(Op, State) ->
    ?LLOG(notice, "unknown async op: ~p", [Op], State),
    noreply(State).




%% ===================================================================
%% Internals
%% ===================================================================

do_init(Actor, StartOpts) ->
    #{srv:=SrvId, uid:=UID, class:=Class, type:=Type, name:=Name} = Actor,
    Meta = maps:get(metadata, Actor, #{}),
    Spec = maps:get(spec, Actor, #{}),
    ActorVsn = maps:get(vsn, Actor, <<"0">>),
    ActorId = #actor_id{
        srv = SrvId,
        uid = UID,
        class = Class,
        type = Type,
        name = Name,
        pid = self()
    },
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
    IsNew = maps:get(is_new, StartOpts, false),
    Config1 = ?CALL_SRV(SrvId, actor_config, [ActorId]),
    Config2 = case StartOpts of
        #{config:=StartConfig} ->
            maps:merge(Config1, StartConfig);
        _ ->
            Config1
    end,
    #actor_st{
        actor_id = ActorId,
        config = Config2,
        spec = Spec,
        meta = Meta,
        vsn = ActorVsn,
        status = #{},
        links = nklib_links:new(),
        is_dirty = IsNew,
        is_enabled = maps:get(<<"isEnabled">>, Meta, true),
        saved_time = 0,
        loaded_time = Now,
        status_timer = NextStatusTimer,
        unload_policy = permanent           % Updated later
    }.


%% @private
set_unload_policy(#actor_st{config=Config, meta=Meta}=State) ->
    Policy = case maps:get(permanent, Config, false) of
        true ->
            permanent;
        false ->
            case maps:get(<<"expiresTime">>, Meta, 0) of
                0 ->
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
set_debug(#actor_st{actor_id =#actor_id{srv=SrvId, type=Type}}=State) ->
    Debug = case nkservice_util:get_debug(SrvId, nkservice_actor, <<"all">>, debug) of
        true ->
            true;
        _ ->
            case nkservice_util:get_debug(SrvId, nkservice_actor, Type, debug) of
                true ->
                    true;
                _ ->
                    false
            end
    end,
    put(nkservice_actor_debug, Debug),
    ?DEBUG("debug activated", [], State).


%% @private
%% The service leader registers the UID and the set {Srv, Class, Type, Name} with
%% this pid.
%% If the service master dies, the process will stop immediately
register_with_leader(#actor_st{actor_id=ActorId}=State) ->
    case nkservice_master:register_actor(ActorId) of
        {ok, Pid} ->
            ?DEBUG("registered with master service (~p)", [Pid], State),
            monitor(process, Pid),
            {ok, State#actor_st{leader_pid=Pid}};
        {error, Error} ->
            {error, Error}
    end.


%% @private
do_check_alarms(#actor_st{meta=#{<<"isInAlarm">>:=true}}=State) ->
    {ok, State2} = handle(actor_alarms, [], State),
    State2;

do_check_alarms(State) ->
    State.


%% @private
do_save(_Reason, #actor_st{is_dirty=false}=State) ->
    {ok, State};

do_save(Reason, State) ->
    case handle(actor_save, [Reason], State) of
        {ok, Meta, State2} ->
            ?DEBUG("save (~p) (~p)", [Reason, Meta], State2),
            State3 = State2#actor_st{
                is_dirty = false,
                saved_time = nklib_date:epoch(msecs)
            },
            {ok, do_event(saved, State3)};
        {error, not_implemented, State2} ->
            {{error, not_implemented}, State2};
        {error, Error, State2} ->
            ?LLOG(warning, "save error: ~p", [Error], State),
            {{error, Error}, State2}
    end.


%% @private
do_delete(#actor_st{meta=Meta}=State) ->
    {_, State2} = do_save(pre_delete, State),
    case handle(actor_delete, [], State2) of
        {ok, State3} ->
            ?DEBUG("object deleted", [], State3),
            {ok, do_event(deleted, State3)};
        {error, Error, State3} ->
            ?LLOG(warning, "object could not be deleted: ~p", [Error], State3),
            {{error, Error}, State3#actor_st{meta=Meta}}
    end.


%% @private Reset TTL
do_refresh_ttl(#actor_st{unload_policy={ttl, Time}, ttl_timer=Timer}=State) when is_integer(Time) ->
    nklib_util:cancel_timer(Timer),
    Ref = erlang:send_after(Time, self(), nkservice_ttl_timeout),
    State#actor_st{ttl_timer=Ref};

do_refresh_ttl(State) ->
    State.


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
do_stop2(Reason, #actor_st{actor_id=#actor_id{srv=SrvId}, stop_reason=false, config=Config}=State) ->
    {ok, State2} = handle(actor_stop, [Reason], State#actor_st{stop_reason=Reason}),
    {Code, Txt} = nkservice_msg:msg(SrvId, Reason),
    State3 = do_event({stopped, Code, Txt}, State2),
    {_, State4} = do_save(unloaded, State3),
    State5 = do_event({unloaded, Reason}, State4),
    case Config of
        #{remove_after_stop:=true} ->
            {_, State6} = do_delete(State5),
            State6;
        _ ->
            State5
    end;

do_stop2(_Reason, State) ->
    State.


%% @private
do_update(Actor, #actor_st{actor_id =Id, spec=Spec, meta=Meta}=State) ->
    #actor_id{srv=SrvId, uid=UID, class=Class, type=Type, name=Name} = Id,
    try
        case maps:get(srv, Actor, SrvId) of
            SrvId -> ok;
            _ -> throw({updated_invalid_field, srv})
        end,
        case maps:get(uid, Actor, UID) of
            UID -> ok;
            _ -> throw({updated_invalid_field, uid})
        end,
        case maps:get(class, Actor, Class) of
            Class -> ok;
            _ -> throw({updated_invalid_field, class})
        end,
        case maps:get(type, Actor, Type) of
            Type -> ok;
            _ -> throw({updated_invalid_field, type})
        end,
        case maps:get(name, Actor, Name) of
            Name -> ok;
            _ -> throw({updated_invalid_field, name})
        end,
        Spec2 = maps:get(spec, Actor, Spec),
        SpecUpdated = Spec /= Spec2,
        Links = maps:get(<<"links">>, Meta, #{}),
        ActorMeta1 = maps:get(metadata, Actor, #{}),
        ForbiddenFields = [
            <<"resourceVersion">>,
            <<"generation">>,
            <<"creationTime">>,
            <<"expiresTime">>
        ],
        case maps:with(ForbiddenFields, ActorMeta1) of
            M when map_size(M)==0 ->
                ok;
            M ->
                throw({updated_invalid_field, hd(maps:keys(M))})
        end,
        ActorLinks = maps:get(<<"links">>, ActorMeta1, Links),
        ActorMeta2 = case Links /= ActorLinks of
            true ->
                case nkservice_actor_util:check_links(ActorMeta1) of
                    {ok, ActorMetaLinks} ->
                        ActorMetaLinks;
                    {error, Error} ->
                        throw(Error)
                end;
            false ->
                ActorMeta1
        end,
        Meta2 = maps:merge(Meta, ActorMeta2),
        MetaUpdated = Meta /= Meta2,
        case SpecUpdated orelse MetaUpdated of
            true ->
                State2 = State#actor_st{spec=Spec2, meta=Meta2, is_dirty=true},
                State3 = do_update_version(State2),
                Enabled = maps:get(<<"isEnabled">>, Meta2, true),
                State4 = do_enabled(Enabled, State3),
                case do_save(update, State4) of
                    {ok, State5} ->
                        {ok, do_event({updated, Actor}, State5)};
                    {{error, SaveError}, State5} ->
                        {error, SaveError, State5}
                end;
            false ->
                {ok, State}
        end
    catch
        throw:Throw ->
            {error, Throw, State}
    end.


%% @private
do_update_name(Name, #actor_st{actor_id=#actor_id{name=OldName}=Id}=State) ->
    lager:error("NKLOG UPDATE NAME ~p", [Name]),
    case nkservice_actor_util:normalized_name(Name) of
        OldName ->
            {ok, State};
        NewName ->
            Id2 = Id#actor_id{name=NewName},
            case register_with_leader(State#actor_st{actor_id=Id2}) of
                {ok, State2} ->
                    State3 = State2#actor_st{is_dirty=true},
                    State4 = do_update_version(State3),
                    case do_save(update, State4) of
                        {ok, State5} ->
                            {ok, do_event({updated, #{name=>NewName}}, State5)};
                        {{error, SaveError}, State5} ->
                            {error, SaveError, State5}
                    end;
                {error, RegError} ->
                    {error, RegError, State}
            end
    end.



%% @private
do_update_version(#actor_st{actor_id =#actor_id{name=Name}, spec=Spec, meta=Meta}=State) ->
    {ok, Time} = nklib_date:to_3339(nklib_date:epoch(msecs)),
    Meta2 = nkservice_actor_util:update_meta(Name, Spec, Meta, Time),
    State#actor_st{meta=Meta2}.


%% @private
do_enabled(Enabled, #actor_st{is_enabled=Enabled}=State) ->
    State;

do_enabled(Enabled, State) ->
    State2 = State#actor_st{is_enabled = Enabled},
    {ok, State3} = handle(actor_enabled, [Enabled], State2),
    do_event({enabled, Enabled}, State3).


%% @private
do_heartbeat(State) ->
    do_check_save(State).

%% @private
do_check_save(#actor_st{is_dirty=true, saved_time=Time, config=Config}=State) ->
    ConfigTime = maps:get(save_time, Config, ?DEFAULT_SAVE_TIME),
    case nklib_date:epoch(msecs) - Time > ConfigTime of
        true ->
            {_, State2} = do_save(timer, State),
            do_heartbeat_user(State2);
        false ->
            do_heartbeat_user(State)
    end;

do_check_save(State) ->
    do_heartbeat_user(State).


%% @private
do_heartbeat_user(#actor_st{}=State) ->
    {ok, State2} = handle(actor_heartbeat, [], State),
    noreply(State2).


%% @private
do_event(Event, #actor_st{links=Links}=State) ->
    ?DEBUG("sending 'event': ~p", [Event], State),
    State2 = nklib_links:fold_values(
        fun
            (Link, #link_opts{get_events=true, opts=Opts}, Acc) ->
                {ok, Acc2} = handle(actor_link_event,[Link, Opts, Event], Acc),
                Acc2;
            (_Link, _LinkOpts, Acc) ->
                Acc
        end,
        State,
        Links),
    {ok, State3} = handle(actor_event, [Event], State2),
    State3.


%% @private
do_ttl_timeout(#actor_st{unload_policy={ttl, _}, links=Links, status_timer=undefined}=State) ->
    Avoid = nklib_links:fold_values(
        fun
            (_Link, #link_opts{avoid_unload=true}, _Acc) -> true;
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
handle(Fun, Args, #actor_st{actor_id=#actor_id{srv=SrvId}}=State) ->
    ?CALL_SRV(SrvId, Fun, Args++[State]).


%% @private
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
add_link(Link, #link_opts{}=LinkOpts, #actor_st{links=Links}=State) ->
    State2 = case LinkOpts of
        #link_opts{type=Type} when Type /= <<>> ->
            do_event({link_added, Type}, State);
        _ ->
            State
    end,
    State2#actor_st{links=nklib_links:add(Link, LinkOpts, Links)}.


%% @private
remove_link(Link, #actor_st{links=Links}=State) ->
    State2 = case nklib_links:get_value(Link, Links) of
        {ok, #link_opts{type=Type}} when Type /= <<>> ->
            do_event({link_removed, Type}, State);
        _ ->
            State
    end,
    State2#actor_st{links=nklib_links:remove(Link, Links)}.


%% @private
link_down(Mon, #actor_st{links=Links}=State) ->
    case nklib_links:down(Mon, Links) of
        {ok, Link, LinkOpts, Links2} ->
            case LinkOpts of
                #link_opts{type=Type} when Type /= <<>> ->
                    State2 = do_event({link_down, Type}, State),
                    {ok, Link, LinkOpts, State2#actor_st{links=Links2}};
                _ ->
                    {ok, Link, LinkOpts, State#actor_st{links=Links2}}
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
