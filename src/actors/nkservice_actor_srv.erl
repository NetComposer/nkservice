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

-export([create/3, start/3, sync_op/2, sync_op/3, async_op/2, live_async_op/2, delayed_async_op/3]).
-export([init/1, terminate/2, code_change/3, handle_call/3,  handle_cast/2, handle_info/2]).
-export([get_all/0, unload_all/0, get_state/1, raw_stop/2]).
-export([do_event/2, do_event_link/2, do_update/3, do_delete/1, do_set_next_status_time/2,
         do_get_links/1, do_add_link/3, do_remove_link/2]).
-export_type([event/0, save_reason/0]).


-include("nkservice.hrl").
-include("nkservice_actor.hrl").
-include("nkservice_actor_debug.hrl").


-define(DEFAULT_TTL, 10000).
-define(DEF_SYNC_CALL, 5000).
-define(HEARTBEAT_TIME, 5000).
-define(DEFAULT_SAVE_TIME, 5000).
-define(MAX_STATUS_TIME, 24*60*60*1000).


%% ===================================================================
%% Types
%% ===================================================================


-type event() ::
    created |
    activated |
    saved |
    {updated, nkservice_actor:actor()} |
    deleted |
    {enabled, boolean()} |
    {info, binary(), Meta::map()} |
    {link_added, nklib_links:link()} |
    {link_removed, nklib_links:link()} |
    {link_down, Type::binary()} |
    {alarm_fired, nkservice_actor:alarm_class(), nkservice_actor:alarm_body()} |
    alarms_all_cleared |
    {stopped, nkservice:msg()}.


-type link_opts() ::
    #{
        get_events => boolean(),        % calls to actor_srv_link_event for each event (false)
        gen_events => boolean(),        % generate events {link_XXX} (true)
        avoid_unload => boolean(),      % do not unload until is unlinked (false)
        data => term()                  % user config
    }.


-type sync_op() ::
    get_actor |
    consume_actor |
    get_actor_id |
    get_links |
    save |
    delete |
    {enable, boolean()} |
    is_enabled |
    {link, nklib:link(), link_opts()} |
    {update, nkservice_actor:actor(), nkservice_actor:update_opts()} |
    {update_name, binary()} |
    get_alarms |
    {set_alarm, nkservice_actor:alarm_class(), nkservice_actor:alarm_body()} |
    {apply, Mod::module(), Fun::atom(), Args::list()} |
    actor_deleted |
    term().

-type async_op() ::
    {unlink, nklib:link()} |
    {send_info, atom()|binary(), map()} |
    {send_event, event()} |
    {set_next_status_time, binary()|integer()} |
    {set_alarm, nkservice_actor:alarm_class(), nkservice_actor:alarm_body()} |
    clear_all_alarms |
    save |
    delete |
    {stop, Reason::nkservice:msg()} |
    term().


-type state() :: #actor_st{}.


-type save_reason() ::
    creation | user_op | user_order | unloaded | update | timer.


-record(link_info, {
    get_events :: boolean(),
    gen_events :: boolean(),
    avoid_unload :: boolean(),
    data :: term()
}).



%% ===================================================================
%% Public
%% ===================================================================

%% @private
%% Call SrvId:actor_create/2 instead calling this directly!
-spec create(nkservice:id(), nkservice_actor:actor(), nkservice_actor:config()) ->
    {ok, #actor_id{}} | {error, term()}.

create(SrvId, Actor, Config) ->
    do_start(SrvId, create, Actor, Config).


%% @private
%% Call SrvId:actor_activate/2 instead calling this directly!
-spec start(nkservice:id(), nkservice_actor:actor(), nkservice_actor:config()) ->
    {ok, #actor_id{}} | {error, term()}.

start(SrvId, Actor, Config) ->
    do_start(SrvId, start, Actor, Config).


%% @private
do_start(SrvId, Op, #actor{id=ActorId}=Actor, Config) ->
    case ?CALL_SRV(SrvId, actor_get_config, [SrvId, ActorId, Config]) of
        {ok, _Module, #{activable:=false}} ->
            {error, actor_is_not_activable};
        {ok, Module, Config2} ->
            Ref = make_ref(),
            Opts = {SrvId, Op, Module, Actor, Config2, self(), Ref},
            case gen_server:start(?MODULE, Opts, []) of
                {ok, Pid} ->
                    {ok, ActorId#actor_id{pid = Pid}};
                ignore ->
                    receive
                        {do_start_ignore, Ref, Result} ->
                            Result
                    after 5000 ->
                        error(do_start_ignore)
                    end;
                {error, Error} ->
                    {error, Error}
            end
    end.



%% @doc
-spec sync_op(nkservice_actor:id()|pid(), sync_op()) ->
    term() | {error, timeout|process_not_found|object_not_found|term()}.

sync_op(Id, Op) ->
    sync_op(Id, Op, ?DEF_SYNC_CALL).


%% @doc
-spec sync_op(nkservice_actor:id()|pid(), sync_op(), timeout()) ->
    term() | {error, timeout|process_not_found|object_not_found|term()}.

sync_op(Pid, Op, Timeout) when erlang:is_pid(Pid) ->
    nklib_util:call2(Pid, {nkservice_sync_op, Op}, Timeout);

sync_op(Id, Op, Timeout) ->
    sync_op(Id, Op, Timeout, 5).


%% @private
sync_op(_Id, _Op, _Timeout, 0) ->
    {error, process_not_found};

sync_op(Id, Op, Timeout, Tries) ->
    case nkservice_actor_util:id_to_actor_id(Id) of
        {ok, SrvId, #actor_id{pid=Pid}=ActorId} when is_pid(Pid) ->
            case sync_op(Pid, Op, Timeout) of
                {error, process_not_found} ->
                    ActorId2 = ActorId#actor_id{pid=undefined},
                    timer:sleep(250),
                    lager:warning("NkSERVICE SynOP failed (~p), retrying...", [ActorId2]),
                    sync_op({SrvId, ActorId2}, Op, Timeout, Tries-1);
                Other ->
                    Other
            end;
        {ok, SrvId, ActorId} ->
            case nkservice_actor:activate({SrvId, ActorId}) of
                {ok, #actor_id{pid=Pid}=ActorId2, _} when is_pid(Pid) ->
                    sync_op({SrvId, ActorId2}, Op, Timeout, Tries);
                Other ->
                    Other
            end;
        {error, Error} ->
            {error, Error}
    end.



%% @doc
-spec async_op(nkservice_actor:id()|pid(), async_op()) ->
    ok | {error, process_not_found|object_not_found|term()}.

async_op(Pid, Op) when is_pid(Pid) ->
    gen_server:cast(Pid, {nkservice_async_op, Op});

async_op(Id, Op) ->
    case nkservice_actor:activate(Id) of
        {ok, #actor_id{pid=Pid}, _} when is_pid(Pid) ->
            async_op(Pid, Op);
        {error, Error} ->
            {error, Error}
    end.


%% @doc
-spec live_async_op(nkservice_actor:id()|pid(), async_op()) ->
    ok | {error, term()}.

live_async_op(Pid, Op) when is_pid(Pid) ->
    async_op(Pid, {nkservice_async_op, Op});

live_async_op(Id, Op) ->
    case nkservice_actor:find(Id) of
        {ok, #actor_id{pid=Pid}, _} when is_pid(Pid) ->
            async_op(Pid, Op);
        _ ->
            ok
    end.


%% @doc
-spec delayed_async_op(nkservice_actor:id()|pid(), async_op(), pos_integer()) ->
    ok | {error, process_not_found|object_not_found|term()}.

delayed_async_op(Pid, Op, Time) when is_pid(Pid), Time > 0 ->
    _ = spawn(
        fun() ->
            timer:sleep(Time),
            async_op(Pid, Op)
        end),
    ok;

delayed_async_op(Id, Op, Time) ->
    case nkservice_actor:activate(Id) of
        {ok, #actor_id{pid=Pid}, _} when is_pid(Pid) ->
            delayed_async_op(Pid, Op, Time);
        {error, Error} ->
            {error, Error}
    end.



%%%% @private Disabled the actor, only if it is activated
%%%% used before external deletion
%%raw_disable(SrvId, Id) ->
%%    case nkservice_actor_db:is_activated(SrvId, Id) of
%%        {true, #actor_id{pid=Pid}} ->
%%            sync_op(none, Pid, {enable, false});
%%        false ->
%%            ok
%%    end.


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



%% ===================================================================
%% In-process API
%% ===================================================================

%% @private
do_event(Event, State) ->
    ?ACTOR_DEBUG("sending 'event': ~p", [Event], State),
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
do_set_next_status_time(NextTime, State) ->
    #actor_st{status_timer = Timer1} = State,
    nklib_util:cancel_timer(Timer1),
    Now = nklib_date:epoch(secs),
    NextTime2 = nklib_date:to_epoch(NextTime, secs),
    Timer2 = case NextTime2 - Now of
        Step when Step=<0 ->
            self() ! nkservice_next_status_timer,
            undefined;
        Step ->
            Step2 = min(Step, ?MAX_STATUS_TIME),
            erlang:send_after(Step2, self(), nkservice_next_status_timer)
    end,
    State#actor_st{status_timer = Timer2}.


%% @private
do_get_links(#actor_st{links=Links}) ->
    nklib_links:fold_values(
        fun(Link, #link_info{data=Data}, Acc) -> [{Link, Data}|Acc] end,
        [],
        Links).


%% @private
do_add_link(Link, Opts, #actor_st{links=Links}=State) ->
    LinkInfo = #link_info{
        get_events = maps:get(get_events, Opts, false),
        gen_events = maps:get(gen_events, Opts, true),
        avoid_unload = maps:get(avoid_unload, Opts, false),
        data = maps:get(data, Opts, undefined)
    },
    State2 = case LinkInfo#link_info.gen_events of
        true ->
            do_event({link_added, Link}, State);
        _ ->
            State
    end,
    State2#actor_st{links=nklib_links:add(Link, LinkInfo, Links)}.


%% @private
do_remove_link(Link, #actor_st{links=Links}=State) ->
    case nklib_links:get_value(Link, Links) of
        {ok, #link_info{gen_events=true}} ->
            State2 = do_event({link_removed, Link}, State),
            State3 = State2#actor_st{links=nklib_links:remove(Link, Links)},
            {true, State3};
        not_found ->
            false
    end.


%% @private
do_update(UpdActor, Opts, #actor_st{srv=SrvId, actor=#actor{id=Id}=Actor}=State) ->
    #actor_id{uid=UID, domain=Domain, group=Class, vsn=Vsn, resource=Res, name=Name} = Id,
    try
        case UpdActor#actor.id#actor_id.domain of
            Domain -> ok;
            _ -> throw({updated_invalid_field, domain})
        end,
        case UpdActor#actor.id#actor_id.uid of
            undefined -> ok;
            UID -> ok;
            _ -> throw({updated_invalid_field, uid})
        end,
        case UpdActor#actor.id#actor_id.group of
            Class -> ok;
            _ -> throw({updated_invalid_field, group})
        end,
        case UpdActor#actor.id#actor_id.vsn of
            Vsn -> ok;
            _ -> throw({updated_invalid_field, vsn})
        end,
        case UpdActor#actor.id#actor_id.resource of
            Res -> ok;
            _ -> throw({updated_invalid_field, resource})
        end,
        case UpdActor#actor.id#actor_id.name of
            Name -> ok;
            _ -> throw({updated_invalid_field, name})
        end,
        DataFieldsList = maps:get(data_fields, Opts, all),
        #actor{data=Data, metadata=Meta} = Actor,
        DataFields = case DataFieldsList of
            all ->
                Data;
            _ ->
                maps:with(DataFieldsList, Data)
        end,
        UpdData = UpdActor#actor.data,
        UpdDataFields = case DataFieldsList of
            all ->
                UpdData;
            _ ->
                maps:with(DataFieldsList, UpdData)
        end,
        IsDataUpdated = UpdDataFields /= DataFields,
        UpdMeta = UpdActor#actor.metadata,
        CT = maps:get(<<"creationTime">>, Meta),
        case maps:get(<<"creationTime">>, UpdMeta, CT) of
            CT -> ok;
            _ -> throw({updated_invalid_field, metadata})
        end,
        SubType = maps:get(<<"subtype">>, Meta, <<>>),
        case maps:get(<<"subtype">>, UpdMeta, <<>>) of
            SubType -> ok;
            _ -> throw({updated_invalid_field, subtype})
        end,
        Links = maps:get(<<"links">>, Meta, #{}),
        UpdLinks = maps:get(<<"links">>, UpdMeta, Links),
        UpdMeta2 = case UpdLinks == Links of
            true ->
                UpdMeta;
            false ->
                case nkservice_actor_util:do_check_links(SrvId, UpdMeta) of
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
                Data2 = maps:merge(Data, UpdDataFields),
                NewActor = Actor#actor{data=Data2, metadata=NewMeta2},
                case nkservice_actor_util:update_check_fields(NewActor, State) of
                    ok ->
                        case handle(actor_srv_update, [NewActor], State) of
                            {ok, NewActor2, State2} ->
                                State3 = State2#actor_st{actor=NewActor2, is_dirty=true},
                                State4 = do_update_version(State3),
                                State5 = do_enabled(UpdEnabled, State4),
                                State6 = set_unload_policy(State5),
                                case do_save(update, State6) of
                                    {ok, State7} ->
                                        {ok, do_event({updated, UpdActor}, State7)};
                                    {{error, SaveError}, State6} ->
                                        {error, SaveError, State6}
                                end;
                            {error, UpdError, State2} ->
                                {error, UpdError, State2}
                        end;
                    {error, StaticFieldError} ->
                        {error, StaticFieldError, State}
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
do_delete(#actor_st{is_dirty=deleted}=State) ->
    {ok, State};

do_delete(#actor_st{srv=SrvId, actor=Actor}=State) ->
    #actor{id=#actor_id{uid=UID}} = Actor,
    case handle(actor_srv_delete, [], State) of
        {ok, State2} ->
            case ?CALL_SRV(SrvId, actor_db_delete, [SrvId, UID, #{}]) of
                {ok, _ActorIds, DbMeta} ->
                    ?ACTOR_DEBUG("object deleted: ~p", [DbMeta], State),
                    {ok, do_event(deleted, State2#actor_st{is_dirty=deleted})};
                {error, Error} ->
                    ?ACTOR_LOG(warning, "object could not be deleted: ~p", [Error], State),
                    {{error, Error}, State2#actor_st{actor=Actor}}
            end;
        {error, Error, State2} ->
            {{error, Error}, State2}
    end.


% ===================================================================
%% gen_server behaviour
%% ===================================================================



%% @private
-spec init(term()) ->
    {ok, state()} | {stop, term()}.

init({SrvId, Op, Module, Actor, Config, Caller, Ref}) ->
    State = do_pre_init(SrvId, Module, Actor, Config),
    case do_check_expired(State) of
        {false, State2} ->
            case do_register(1, State2) of
                {ok, State3} ->
                    ?ACTOR_DEBUG("registered", [], State3),
                    case handle(actor_srv_init, [Op], State3) of
                        {ok, State4} ->
                            do_init(Op, State4);
                        {error, Error} ->
                            do_init_stop(Error, Caller, Ref);
                        {delete, Error} ->
                            _ = do_delete(State),
                            do_init_stop(Error, Caller, Ref)
                    end;
                {error, Error} ->
                    do_init_stop(Error, Caller, Ref)
            end;
        true ->
            ?ACTOR_LOG(warning, "actor is expired on load", [], State),
            % Call stop functions, probably will delete the actor
            _ = do_stop(actor_expired, State),
            do_init_stop(actor_not_found, Caller, Ref)
    end.


%% @private
do_init(create, State) ->
    #actor_st{srv=SrvId, actor=Actor} = State,
    case ?CALL_SRV(SrvId, actor_db_create, [SrvId, Actor]) of
        {ok, _Meta} ->
            ?ACTOR_DEBUG("created (~p)", [self()], State),
            State2 = do_event(created, State),
            do_post_init(State2);
        {error, actor_db_not_implemented} ->
            ?ACTOR_LOG(notice, "actor will not be persisted!", State),
            State2 = do_event(created, State),
            do_post_init(State2);
        {error, Error} ->
            {stop, Error}
    end;

do_init(start, State) ->
    do_post_init(State).


%% @private
do_init_stop(Error, Caller, Ref) ->
    Caller ! {do_start_ignore, Ref, {error, Error}},
    ignore.



%% @private
-spec handle_call(term(), {pid(), term()}, state()) ->
    {noreply, state()} | {reply, term(), state()} |
    {stop, Reason::term(), state()} | {stop, Reason::term(), Reply::term(), state()}.

handle_call({nkservice_sync_op, Op}, From, State) ->
    case handle(actor_srv_sync_op, [Op, From], State) of
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
            ?ACTOR_LOG(error, "invalid response for sync op ~p: ~p", [Op, Other], State),
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
            {_, State3} = do_save(user_op, State2#actor_st{is_dirty=true}),
            noreply(do_refresh_ttl(State3));
        {stop, Reason, #actor_st{}=State2} ->
            do_stop(Reason, State2);
        continue ->
            do_async_op(Op, State);
        {continue, [Op2, #actor_st{}=State2]} ->
            do_async_op(Op2, State2);
        Other ->
            ?ACTOR_LOG(error, "invalid response for async op ~p: ~p", [Op, Other], State),
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
    case handle(actor_srv_next_status_timer, [], State2) of
        {ok, State3} ->
            noreply(State3);
        {stop, Reason, State3} ->
            do_stop(Reason, State3);
        {delete, Reason, State3} ->
            {_, State4} = do_delete(State3),
            do_stop(Reason, State4)
    end;

handle_info(nkservice_heartbeat, State) ->
    erlang:send_after(?HEARTBEAT_TIME, self(), nkservice_heartbeat),
    do_heartbeat(State);

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #actor_st{father_pid=Pid}=State) ->
    ?ACTOR_LOG(notice, "service leader is down", [], State),
    case do_register(1, State#actor_st{father_pid=undefined}) of
        {ok, State2} ->
            ?ACTOR_LOG(notice, "re-registered with service leader", [], State),
            noreply(State2);
        {error, _Error} ->
            do_stop(leader_is_down, State)
    end;

handle_info({'DOWN', Ref, process, _Pid, Reason}=Info, State) ->
    case link_down(Ref, State) of
        {ok, Link, #link_info{data=Data}=LinkInfo, State2} ->
            ?ACTOR_LOG(warning, "link ~p down (~p) (~p)", [Link, LinkInfo, Reason], State),
            ?ACTOR_DEBUG("link ~p down (~p) (~p)", [Link, LinkInfo, Reason], State),
            {ok, State3} = handle(actor_srv_link_down, [Link, Data], State2),
            noreply(State3);
        not_found ->
            safe_handle(actor_srv_handle_info, [Info], State)
    end;

handle_info(Msg, State) ->
    safe_handle(actor_srv_handle_info, [Msg], State).


%% @private
-spec code_change(term(), state(), term()) ->
    {ok, state()}.

code_change(OldVsn, #actor_st{srv=SrvId}=State, Extra) ->
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

do_sync_op(get_srv_uid, _From, #actor_st{srv=SrvId, actor=#actor{id=ActorId}}=State) ->
    #actor_id{uid=UID} = ActorId,
    reply({ok, SrvId, UID}, do_refresh_ttl(State));

do_sync_op(get_actor, _From, #actor_st{actor=Actor, run_state=RunState}=State) ->
    Actor2 = Actor#actor{run_state = RunState},
    {ok, UserActor, State2} = handle(actor_srv_get, [Actor2], State),
    reply({ok, UserActor}, do_refresh_ttl(State2));

do_sync_op(consume_actor, From, #actor_st{actor=Actor, run_state=RunState}=State) ->
    Actor2 = Actor#actor{run_state = RunState},
    {ok, UserActor, State2} = handle(actor_srv_get, [Actor2], State),
    gen_server:reply(From, {ok, UserActor}),
    do_stop(actor_consumed, State2);

do_sync_op(get_state, _From, State) ->
    reply({ok, State}, State);

do_sync_op(get_links, _From, State) ->
    Data = do_get_links(State),
    reply({ok, Data}, State);

do_sync_op(save, _From, State) ->
    {Reply, State2} = do_save(user_order, State),
    reply(Reply, do_refresh_ttl(State2));

do_sync_op(force_save, _From, State) ->
    {Reply, State2} = do_save(user_order, State#actor_st{is_dirty=true}),
    reply(Reply, do_refresh_ttl(State2));

do_sync_op(get_unload_policy, _From, #actor_st{unload_policy=Policy}=State) ->
    reply({ok, Policy}, State);

do_sync_op(get_save_time, _From, #actor_st{save_timer=Timer}=State) ->
    Reply = case is_reference(Timer) of
        true ->
            erlang:read_timer(Timer);
        false ->
            undefined
    end,
    reply({ok, Reply}, State);

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
            case do_update(UpdActor, #{}, State) of
                {ok, State2} ->
                    reply(ok, do_refresh_ttl(State2));
                {error, Error, State2} ->
                    reply({error, Error}, State2)
            end
    end;

do_sync_op(is_enabled, _From, #actor_st{is_enabled=IsEnabled}=State) ->
    reply({ok, IsEnabled}, State);

do_sync_op({link, Link, Opts}, _From, State) ->
    State2 = do_add_link(Link, Opts, State),
    {reply, ok, do_refresh_ttl(State2)};

do_sync_op({update, #actor{}=Actor, Opts}, _From, #actor_st{is_enabled=IsEnabled, config=Config}=State) ->
    case {IsEnabled, Config} of
        {false, #{dont_update_on_disabled:=true}} ->
            reply({error, object_is_disabled}, State);
        _ ->
            case do_update(Actor, Opts, State) of
                {ok, State2} ->
                    reply(ok, do_refresh_ttl(State2));
                {error, Error, State2} ->
                    reply({error, Error}, State2)
            end
    end;

%%do_sync_op({update_name, Name}, _From, #actor_st{is_enabled=IsEnabled, config=Config}=State) ->
%%    case {IsEnabled, Config} of
%%        {false, #{dont_update_on_disabled:=true}} ->
%%            reply({error, object_is_disabled}, State);
%%        _ ->
%%            case do_update_name(Name, State) of
%%                {ok, State2} ->
%%                    reply(ok, do_refresh_ttl(State2));
%%                {error, Error, State2} ->
%%                    reply({error, Error}, State2)
%%            end
%%    end;

do_sync_op(get_alarms, _From, #actor_st{actor=Actor}=State) ->
    Alarms = case Actor of
        #actor{metadata = #{<<"isInAlarm">>:=true, <<"alarms">>:=AlarmList}} ->
            AlarmList;
        _ ->
            []
    end,
    {reply, {ok, Alarms}, State};

do_sync_op({set_alarm, Class, Body}, _From, State) ->
    reply(ok, do_add_alarm(Class, Body, State));

do_sync_op({apply, Mod, Fun, Args}, From, State) ->
    apply(Mod, Fun, Args++[From, do_refresh_ttl(State)]);

do_sync_op(Op, _From, State) ->
    ?ACTOR_LOG(notice, "unknown sync op: ~p", [Op], State),
    reply({error, unknown_op}, State).


%% @private
do_async_op({unlink, Link}, State) ->
    case do_remove_link(Link, State) of
        {true, State2} ->
            {ok, State2};
        false ->
            {ok, State}
    end;

do_async_op({send_info, Info, Meta}, State) ->
    noreply(do_event({info, nklib_util:to_binary(Info), Meta}, do_refresh_ttl(State)));

do_async_op({send_event, Event}, State) ->
    noreply(do_event(Event, do_refresh_ttl(State)));

do_async_op({set_next_status_time, Time}, State) ->
    noreply(do_set_next_status_time(Time, State));

do_async_op({set_dirty, IsDirty}, State) when is_boolean(IsDirty)->
    noreply(do_refresh_ttl(State#actor_st{is_dirty=IsDirty}));

do_async_op(save, State) ->
    do_async_op({save, user_order}, State);

do_async_op({save, Reason}, State) ->
    {_Reply, State2} = do_save(Reason, State),
    noreply(do_refresh_ttl(State2));

do_async_op(delete, #actor_st{is_enabled=IsEnabled, config=Config}=State) ->
    case {IsEnabled, Config} of
        {false, #{dont_delete_on_disabled:=true}} ->
            noreply(State);
        _ ->
            {_Reply, State2} = do_delete(State),
            do_stop(actor_deleted, State2)
    end;
do_async_op({stop, Reason}, State) ->
    ?ACTOR_DEBUG("received stop: ~p", [Reason], State),
    do_stop(Reason, State);

do_async_op({raw_stop, Reason}, State) ->
    % We don't send the deleted event here, since we may not be active at all
    ?ACTOR_LOG(warning, "received raw_stop: ~p", [Reason], State),
    {_, State2} = handle(actor_srv_stop, [Reason], State),
    State3 = do_event({stopped, Reason}, State2),
    {stop, normal, State3#actor_st{stop_reason=raw_stop}};

do_async_op({set_alarm, Class, Body}, State) ->
    noreply(do_add_alarm(Class, Body, State));

do_async_op(clear_all_alarms, State) ->
    noreply(do_clear_all_alarms(State));

do_async_op(Op, State) ->
    ?ACTOR_LOG(notice, "unknown async op: ~p", [Op], State),
    noreply(State).


%% ===================================================================
%% Internals
%% ===================================================================

%% @private
do_pre_init(SrvId, Module, Actor, Config) ->
    #actor{id=#actor_id{uid=UID}=ActorId, metadata=Meta} = Actor,
    ActorId2 = ActorId#actor_id{pid=self()},
    true = is_binary(UID) andalso UID /= <<>>,
    State1 = #actor_st{
        srv = SrvId,
        module = Module,
        config = Config,
        actor = Actor#actor{id=ActorId2},
        run_state = undefined,
        links = nklib_links:new(),
        is_dirty = false,
        is_enabled = maps:get(<<"isEnabled">>, Meta, true),
        save_timer = undefined,
        activated_time = nklib_date:epoch(usecs),
        unload_policy = permanent           % Updated later
    },
    set_debug(State1),
    State2 =  case Meta of
        #{<<"nextStatusTime">>:=NextStatusTime} ->
            do_set_next_status_time(NextStatusTime, State1);
        _ ->
            State1
    end,
    ?ACTOR_DEBUG("actor server starting", [], State2),
    set_unload_policy(State2).


%% @private
do_post_init(State) ->
    #actor_st{actor=#actor{id=ActorId}} = State,
    ?ACTOR_DEBUG("started (~p)", [self()], State),
    State3 = do_event(activated, State),
    State4 = do_check_alarms(State3),
    erlang:send_after(?HEARTBEAT_TIME, self(), nkservice_heartbeat),
    % actor_init could have set the is_dirty flag
    #actor_st{actor=#actor{id=ActorId}} = State,
    nklib_proc:put(?MODULE, ActorId),
    case do_save(init, State4) of
        {ok, State5} ->
            {ok, do_refresh_ttl(State5)};
        {{error, Error}, _State5} ->
            {error, Error}
    end.


%% @private
set_debug(#actor_st{srv=SrvId, actor=#actor{id=ActorId}}=State) ->
    Debug = nkservice_actor_util:get_debug(SrvId, ActorId),
    put(nkservice_actor_debug, Debug),
    ?ACTOR_DEBUG("debug activated", [], State).


%% @private
set_unload_policy(#actor_st{config=Config}=State) ->
    #actor_st{actor=#actor{metadata=Meta}} = State,
    ExpiresTime = maps:get(<<"expiresTime">>, Meta, <<>>),
    Policy = case Config of
        #{permanent:=true} ->
            permanent;
        _ when ExpiresTime /= <<>> ->
            {ok, Expires2} = nklib_date:to_epoch(ExpiresTime, msecs),
            % self() ! nkservice_check_expire,
            {expires, Expires2};
        #{auto_activate:=true} ->
            permanent;
        _ ->
            % A TTL reseated after each operation
            TTL = maps:get(ttl, Config, ?DEFAULT_TTL),
            ?ACTOR_DEBUG("TTL is ~p", [TTL], State),
            {ttl, TTL}
    end,
    ?ACTOR_DEBUG("unload policy is ~p", [Policy], State),
    State#actor_st{unload_policy=Policy}.


%% @private
do_register(Tries, #actor_st{srv = SrvId} = State) ->
    case handle (actor_srv_register, [SrvId], State) of
        {ok, Pid, State2} when is_pid(Pid) ->
            ?ACTOR_DEBUG("registered with master service (pid:~p)", [Pid]),
            monitor(process, Pid),
            {ok, State2#actor_st{father_pid = Pid}};
        {ok, undefined, State2} ->
            {ok, State2};
        {error, Error} ->
            case Tries > 1 of
                true ->
                    ?ACTOR_LOG(notice, "registered with master failed (~p) (~p tries left)",
                        [Error, Tries], State),
                    timer:sleep(1000),
                    do_register(Tries - 1, State);
                false ->
                    ?ACTOR_LOG(notice, "registered with master failed: ~p", [Error], State),
                    {error, Error}
            end
    end.


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
do_save(Reason, #actor_st{srv=SrvId, actor=Actor, is_dirty=true, save_timer=Timer}=State) ->
    nklib_util:cancel_timer(Timer),
    case handle(actor_srv_save, [Actor], State#actor_st{save_timer=undefined}) of
        {ok, SaveActor, #actor_st{config=Config}=State2} ->
            case Config of
                #{async_save:=true} ->
                    Self = self(),
                    spawn_link(
                        fun() ->
                            case ?CALL_SRV(SrvId, actor_db_update, [SrvId, SaveActor]) of
                                {ok, DbMeta} ->
                                    ?ACTOR_DEBUG("save (~p) (~p)", [Reason, DbMeta], State2),
                                    async_op(Self, {send_event, saved});
                                {error, Error} ->
                                    ?ACTOR_LOG(warning, "save error: ~p", [Error], State2)
                            end
                        end),
                    {ok, State2#actor_st{is_dirty = false}};
                _ ->
                    case ?CALL_SRV(SrvId, actor_db_update, [SrvId, SaveActor]) of
                        {ok, DbMeta} ->
                            ?ACTOR_DEBUG("save (~p) (~p)", [Reason, DbMeta], State2),
                            State3 = State2#actor_st{is_dirty=false},
                            {ok, do_event(saved, State3)};
                        {error, not_implemented} ->
                            {{error, not_implemented}, State2};
                        {error, Error} ->
                            ?ACTOR_LOG(warning, "save error: ~p", [Error], State2),
                            {{error, Error}, State2}
                    end
            end;
        {ignore, State2} ->
            {ok, State2}
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
do_stop2(Reason, #actor_st{stop_reason=false}=State) ->
    State2 = State#actor_st{stop_reason=Reason},
    State3 = do_event({stopped, Reason}, State2),
    case handle(actor_srv_stop, [Reason], State3) of
        {ok, State4} ->
            {_, State5} = do_save(unloaded, State4),
            State5;
        {delete, State4} ->
            {_, State5} = do_delete(State4),
            State5
    end;

do_stop2(_Reason, State) ->
    State.



%%%% @private
%%do_update_name(Name, #actor_st{actor=Actor}=State) ->
%%    #actor{id=#actor_id{name=OldName}=Id} = Actor,
%%    lager:error("NKLOG UPDATE NAME ~p", [Name]),
%%    case nkservice_actor_util:normalized_name(Name) of
%%        OldName ->
%%            {ok, State};
%%        NewName ->
%%            Id2 = Id#actor_id{name=NewName},
%%            Actor2 = Actor#actor{id=Id2},
%%            case register_with_leader(State#actor_st{actor=Actor2}) of
%%                {ok, State2} ->
%%                    State3 = State2#actor_st{is_dirty=true},
%%                    State4 = do_update_version(State3),
%%                    case do_save(update, State4) of
%%                        {ok, #actor_st{actor=Actor}=State5} ->
%%                            {ok, do_event({updated, Actor}, State5)};
%%                        {{error, SaveError}, State5} ->
%%                            {error, SaveError, State5}
%%                    end;
%%                {error, RegError} ->
%%                    {error, RegError, State}
%%            end
%%    end.


%% @private
do_update_version(#actor_st{actor=Actor}=State) ->
    Time = nklib_date:now_3339(msecs),
    State#actor_st{actor=nkservice_actor_util:update(Actor, Time)}.


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
do_add_alarm(Class, Body, #actor_st{actor=Actor}=State) when is_map(Body) ->
    #actor{metadata = Meta} = Actor,
    Alarms = maps:get(<<"alarms">>, Meta, #{}),
    Body2 = case maps:is_key(<<"lastTime">>, Body) of
        true ->
            Body;
        false ->
            Body#{<<"lastTime">> => nklib_date:now_3339(secs)}
    end,
    Alarms2 = Alarms#{nklib_util:to_binary(Class) => Body2},
    Meta2 = Meta#{<<"isInAlarm">> => true, <<"alarms">> => Alarms2},
    Actor2 = Actor#actor{metadata = Meta2},
    State2 = State#actor_st{actor=Actor2, is_dirty=true},
    do_refresh_ttl(do_event({alarm_fired, Class, Body}, State2)).


%% @private
do_clear_all_alarms(#actor_st{actor=Actor}=State) ->
    #actor{metadata = Meta} = Actor,
    case Meta of
        #{<<"isInAlarm">>:=true} ->
            Meta2 = maps:without([<<"isInAlarm">>, <<"alarms">>], Meta),
            Actor2 = Actor#actor{metadata = Meta2},
            State2 = State#actor_st{actor=Actor2, is_dirty=true},
            do_refresh_ttl(do_event(alarms_all_cleared, State2));
        _ ->
            State
    end.


%% @private
do_check_save(#actor_st{is_dirty=true, save_timer=undefined, config=Config}=State) ->
    SaveTime = maps:get(save_time, Config, ?DEFAULT_SAVE_TIME),
    Timer = erlang:send_after(SaveTime, self(), nkservice_timer_save),
    State#actor_st{save_timer=Timer};

do_check_save(State) ->
    State.


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
    #actor_st{srv=SrvId} = State,
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
            ?ACTOR_LOG(error, "invalid response for ~p(~p): ~p", [Fun, Args, Other], State),
            error(invalid_handle_response)
    end.


%% @private
link_down(Mon, #actor_st{links=Links}=State) ->
    case nklib_links:down(Mon, Links) of
        {ok, Link, #link_info{data=Data}=LinkInfo, Links2} ->
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
