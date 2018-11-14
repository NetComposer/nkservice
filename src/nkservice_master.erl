
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

%% @doc Started after nkservice_srv on each node, one of them is elected 'leader'
%% - We register with our node process to get updated status of all available nodes,
%%   each time an update is received we check the nodes where we must start or
%%   stop the service
%% - Each service instance sends us periodically full status, each time we check if
%%   it is running the our same version, or update it if not
%%   We also perform registrations for actors.
%% - A master is elected, and re-checked periodically
%% - If we die, a new leader is elected, actors will register again

-module(nkservice_master).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([get_info/1, stop/1, update/2, replace/2]).
-export([get_leader_pid/1]).
-export([updated_nodes_info/2, updated_service_status/2]).
-export([register_actor/2, find_registered_actor/2, get_registered_actors/1]).
-export([call_leader/2, cast_leader/2]).
-export([start_link/1]).
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2,
         handle_info/2]).
-export([resolve/3]).

-include("nkservice.hrl").
-include("nkservice_actor.hrl").

-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE Master (~s) "++Txt, [State#state.id | Args])).

-define(CHECK_TIME, 5000).

%% ===================================================================
%% Types
%% ===================================================================

-type id() :: nkservice:id().

-type info() ::
    #{
        nodes => #{node() => nkservice_node:node_info()},
        instances => #{node() => nkservice:service_status()},
        leader_pid => pid(),
        slaves => #{}
    }.


%% ===================================================================
%% Public
%% ===================================================================


%% @doc
-spec get_info(id()) ->
    {ok, info()} | {error, leader_not_found|term()}.

get_info(SrvId) ->
    call_leader(SrvId, nkservice_get_info).


%% @doc
-spec stop(id()) ->
    ok | {error, leader_not_found|term()}.

stop(SrvId) ->
    call_leader(SrvId, nkservice_stop).


%% @doc
%% We replace the config at the master's node, it will be detected by master
%% and distributed to all nodes
%% We don't want to block the master (it should reply fast to actor names)
-spec replace(id(), nkservice:spec()) ->
    ok | {error, term()}.

replace(SrvId, Spec) ->
    case get_leader_pid(SrvId) of
        Pid when is_pid(Pid) ->
            rpc:call(node(Pid), nkservice_srv, replace, [SrvId, Spec]);
        undefined ->
            {error, leader_not_found}
    end.


%% @doc
-spec update(id(), nkservice:spec()) ->
    ok | {error, term()}.

update(SrvId, Spec) ->
    case get_leader_pid(SrvId) of
        Pid when is_pid(Pid) ->
            rpc:call(node(Pid), nkservice_srv, update, [SrvId, Spec]);
        undefined ->
            {error, leader_not_found}
    end.


%% @doc Register an actor with the master server
%% By default, nkservice registers all actors with the master server
-spec register_actor(nkservice:id(), #actor_id{}) ->
    {ok, pid()} | {error, nkservice:msg()}.

register_actor(SrvId, #actor_id{uid=UID, pid=Pid}=ActorId) ->
    true = is_binary(UID) andalso UID /= <<>>,
    true = is_pid(Pid),
    call_leader(SrvId, {register_actor, ActorId}).


%% @doc Finds an actor loaded and registered with the service master
-spec find_registered_actor(nkservice:id(), nkservice_actor:id()) ->
    {true, #actor_id{}}| false | {error, nkservice:msg()}.

find_registered_actor(SrvId, Id) ->
    call_leader(SrvId, {find_registered_actor, Id}).


get_registered_actors(SrvId) ->
    call_leader(SrvId, get_registered_actors).



%% @doc Gets the pid of current leader for this service
-spec get_leader_pid(nkservice:id()) ->
    pid() | undefined.

get_leader_pid(SrvId) ->
    global:whereis_name(global_name(SrvId)).


%%%% @private
%%call_leader_retry(SrvId, Msg) ->
%%    call_leader_retry(SrvId, Msg, 3).
%%
%%
%%%% @private
%%call_leader_retry(SrvId, Msg, Try) when is_atom(SrvId), Try > 0 ->
%%    case call_leader(SrvId, Msg, 5000) of
%%        {error, leader_not_found} ->
%%            lager:notice("Leader for ~p not found, retrying (~p)", [SrvId, Msg]),
%%            timer:sleep(1000),
%%            call_leader_retry(SrvId, Msg, Try-1);
%%        Other ->
%%            Other
%%    end;
%%
%%call_leader_retry(_SrvId, _Msg, _Try) ->
%%    {error, leader_not_found}.


%% @doc
call_leader(SrvId, Msg) ->
    call_leader(SrvId, Msg, 5000).

%% @doc
call_leader(SrvId, Msg, Timeout) ->
    case get_leader_pid(SrvId) of
        Pid when is_pid(Pid) ->
            case nklib_util:call2(Pid, Msg, Timeout) of
                {error, process_not_found} ->
                    {error, leader_not_found};
                Other ->
                    Other
            end;
        undefined ->
            {error, leader_not_found}
    end.


%% @doc
cast_leader(SrvId, Msg) ->
    case get_leader_pid(SrvId) of
        Pid when is_pid(Pid) ->
            gen_server:cast(Pid, Msg);
        undefined ->
            {error, leader_not_found}
    end.


%% @doc Receive updates from nkservice_node
-spec updated_nodes_info(pid(), #{node()=>nkservice_node:node_info()}) ->
    ok.

updated_nodes_info(Pid, NodesInfo) ->
    gen_server:cast(Pid, {nkservice_updated_nodes_info, NodesInfo}).


%% @doc Receive updates from nkservice_srv instances
updated_service_status(SrvId, Status) ->
    cast_leader(SrvId, {nkservice_update_status, Status}).



%% ===================================================================
%% Private
%% ===================================================================


%% @private
-spec start_link(id()) ->
    {ok, pid()} | {error, term()}.

start_link(SrvId) ->
    gen_server:start_link(?MODULE, [SrvId], []).



%% ===================================================================
%% gen_server
%% ===================================================================


-record(state, {
    id :: nkservice:id(),
    is_leader :: boolean(),
    leader_pid :: pid() | undefined,
    node_pid :: pid(),
    slaves :: #{node() => pid()},
    nodes :: #{node() => nkservice_node:node_info()},
    instances :: #{node() => nkservice:service_status()},
    register_ets :: term(),
    user :: map()
}).


%% @private
init([SrvId]) ->
    true = nklib_proc:reg({?MODULE, SrvId}),
    nklib_proc:put(?MODULE, SrvId),
    % nkservice:put(SrvId, nkservice_leader_start, nklib_util:l_timestamp()),
    {ok, NodePid, Nodes} = nkservice_node:register_service_master(SrvId),
    monitor(process, NodePid),
    {ok, UserState} = ?CALL_SRV(SrvId, service_master_init, [SrvId, #{}]),
    State = #state{
        id = SrvId,
        is_leader = false,
        leader_pid = undefined,
        node_pid = NodePid,
        nodes = Nodes,
        slaves = #{},
        instances = #{},
        register_ets = ets:new(nkservice_master_register, []),
        user = UserState
    },
    self() ! nkservice_timed_check_leader,
    {ok, State}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}} | {reply, term(), #state{}} |
    {stop, Reason::term(), #state{}} | {stop, Reason::term(), Reply::term(), #state{}}.

handle_call(nkservice_get_info, _From, State) ->
    #state{
        leader_pid = MasterPid,
        nodes = Nodes,
        instances = Instances,
        slaves = Slaves
    } = State,
    Data = #{
        leader_pid => MasterPid,
        nodes => Nodes,
        slaves => Slaves,
        instances => Instances
    },
    {reply, {ok, Data}, State};


handle_call(nkservice_stop, _From, #state{id=SrvId}=State) ->
    rpc:eval_everywhere([node()|nodes()], nkservice_srv, stop, [SrvId]),
    {reply, ok, State};

handle_call({register_actor, ActorId}, _From, State) ->
    Reply = do_register_actor(ActorId, State),
    {reply, Reply, State};

handle_call({find_registered_actor, Id}, _From, State) ->
    Reply = do_find_actor_id(Id, State),
    {reply, Reply, State};

handle_call(get_registered_actors, _From, #state{register_ets=Ets}=State) ->
    List = [ActorId || {{uid, _}, ActorId} <- ets:tab2list(Ets)],
    {reply, List, State};

handle_call(Msg, From, State) ->
    handle(service_master_handle_call, [Msg, From], State).


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_cast({nkservice_updated_nodes_info, Nodes}, #state{is_leader=true}=State) ->
    State2 = State#state{nodes=Nodes},
    {noreply, check_started(State2)};

handle_cast({nkservice_updated_nodes_info, Nodes}, #state{is_leader=false}=State) ->
    {noreply, State#state{nodes=Nodes}};

handle_cast({nkservice_update_status, Status}, #state{is_leader=true}=State) ->
    #{node:=Node} = Status,
    #state{instances=Instances} = State,
    State2 = State#state{instances=Instances#{Node => Status}},
    {noreply, check_instance(Node, State2)};

handle_cast({nkservice_update_status, _Status}, #state{is_leader=false}=State) ->
    ?LLOG(warning, "received status at not-leader ~p", [self()], State),
    {noreply, State};

handle_cast(nkservice_check_leader, State) ->
    case find_leader(State) of
        {ok, State2} ->
            {noreply, State2};
        {error, Error} ->
            {stop, Error, State}
    end;

handle_cast({nkservice_register_slave, Slave}, #state{is_leader=true, slaves=Slaves}=State) ->
    Slaves2 = Slaves#{node(Slave) => Slave},
    {noreply, State#state{slaves=Slaves2}};

handle_cast({nkservice_register_slave, Slave}, #state{is_leader=false}=State) ->
    ?LLOG(warning, "not-leader received register_slave from ~p (~p)",
          [Slave, self()], State),
    {noreply, State};

handle_cast(Msg, State) ->
    handle(service_master_handle_cast, [Msg], State).


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_info(nkservice_timed_check_leader, State) ->
    erlang:send_after(?CHECK_TIME, self(), nkservice_timed_check_leader),
    case find_leader(State) of
        {ok, #state{id=SrvId, is_leader=IsLeader, leader_pid=Pid}=State2} ->
            {ok, State3} = handle(service_master_leader, [SrvId, IsLeader, Pid], State2),
            {noreply, State3};
        {error, Error} ->
            {stop, Error, State}
    end;

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #state{leader_pid=Pid}=State) ->
    #state{id=SrvId, is_leader=false} = State,
    ?LLOG(warning, "leader has failed (~p)", [Pid], State),
    gen_server:cast(self(), nkservice_check_leader),
    {ok, State2} = handle(service_master_leader, [SrvId, false, undefined], State),
    {noreply, State2};

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #state{node_pid=Pid}=State) ->
    ?LLOG(error, "node server has failed!", [], State),
    error(node_server_has_failed);

%% @private
handle_info({'DOWN', _Ref, process, Pid, _Reason}=Msg, State) ->
    case do_remove_actor(Pid, State) of
        true ->
            {noreply, State};
        false ->
            handle(service_master_handle_info, [Msg], State)
    end;

handle_info(Msg, State) ->
    handle(service_master_handle_info, [Msg], State).


%% @private
-spec code_change(term(), #state{}, term()) ->
    {ok, #state{}}.

code_change(OldVsn, #state{id=Id, user=UserState}=State, Extra) ->
    case apply(Id, service_code_change, [OldVsn, UserState, Extra]) of
        {ok, UserState2} ->
            {ok, State#state{user=UserState2}};
        {error, Error} ->
            {error, Error}
    end.


%% @private
-spec terminate(term(), #state{}) ->
    ok.

terminate(Reason, State) ->
    catch handle(service_master_terminate, [Reason], State).



%% ===================================================================
%% Internal
%% ===================================================================

%% @private
check_started(#state{instances=Instances}=State) ->
    {Running,  NotRunning, _Unknown} = get_nodes(State),
    InstanceNodes = maps:keys(Instances),
    case nklib_util:find_duplicated(NotRunning++InstanceNodes) of
        [] ->
            ok;
        ToStop ->
            %% We have an instance running at a stopped node
            %% If something is running at a node we know nothing about,
            %% let's keep it there for now, we will know eventually
            ?LLOG(notice, "stopping instances at nodes: ~p", [ToStop], State),
            spawn_link(fun() -> stop_instances(ToStop, State) end)
    end,
    case Running -- InstanceNodes of
        [] ->
            ok;
        ToStart ->
            %% We have nodes with no running instance, try to start it
            %% It will appear up in next get status
            ?LLOG(notice, "starting instances at nodes: ~p", [ToStart], State),
            spawn_link(fun() -> start_instances(ToStart, State) end)
    end,
    UnknownInstances = (InstanceNodes -- Running) -- NotRunning,
    case UnknownInstances of
        [] ->
            State;
        _ ->
            ?LLOG(warning, "removing unknown state instances: ~s",
                  [nklib_util:bjoin(UnknownInstances)], State),
            Instances2 = maps:without(UnknownInstances, Instances),
            State#state{instances=Instances2}
    end.


%% @private
check_instance(Node, #state{id=SrvId, instances=Instances, nodes=Nodes}=State) ->
    case maps:find(Node, Nodes) of
        {ok, #{node_status:=normal}} ->
            % All instances must run the same version as master's node
            Hash = ?CALL_SRV(SrvId, hash),
            case maps:find(Node, Instances) of
                {ok, #{hash:=Hash}} ->
                    ok;
                {ok, _} ->
                    ?LLOG(notice, "instance at ~p is using old version, updating",
                          [Node], State),
                    spawn_link(fun() -> update_instance(Node, State) end);
                error ->
                    ok
            end;
        _ ->
            % Instance is running in invalid node will be stopped on next
            % node check iteration
            ok
    end,
    State.


%% @private
start_instances([], State) ->
    State;

start_instances([Node|Rest], #state{id=SrvId}=State) ->
    Service = nkservice_config_cache:get_full_service(SrvId),
    case rpc:call(Node, nkservice_srv, start, [Service]) of
        ok ->
            ?LLOG(notice, "service started at node ~s", [Node], State);
        {error, already_started} ->
            ?LLOG(info, "service is already started at node ~s)", [Node], State);
        {error, Error} ->
            ?LLOG(warning, "service could not start at node ~s: ~p", [Node, Error], State);
        {badrpc, Reason} ->
            ?LLOG(warning, "service could not start at node ~s: ~p", [Node, Reason], State)
    end,
    start_instances(Rest, State).


%% @private
stop_instances([], State) ->
    State;

stop_instances([Node|Rest], #state{id=SrvId}=State) ->
    case rpc:call(Node, nkservice_srv, stop, [SrvId]) of
        {badrpc, Reason} ->
            ?LLOG(warning, "service could not be stopped at node ~s: ~p",
                  [Node, Reason], State);
        _ ->
            ?LLOG(notice, "service stopped at node ~s", [Node], State)
    end,
    stop_instances(Rest, State).


%% @private
update_instance(Node, #state{id=Id}=State) ->
    Service = nkservice_config_cache:get_full_service(Id),
    case rpc:call(Node, nkservice_srv, do_update, [Service]) of
        ok ->
            ?LLOG(notice, "service upgraded at node ~s", [Node], State);
        {error, Error} ->
            ?LLOG(warning, "service not upgraded at node ~s: ~p", [Node, Error], State);
        {badrpc, Reason} ->
            ?LLOG(warning, "service not upgraded at node ~s: ~p", [Node, Reason], State)
    end.


%% @private Return 'known' nodes, active and not-active
get_nodes(#state{nodes=Nodes}) ->
    lists:foldl(
        fun({Node, #{node_status:=Status}}, {Acc1, Acc2, Acc3}) ->
            case Status of
                normal->
                    {[Node|Acc1], Acc2, Acc3};
                down ->
                    {Acc1, Acc2, [Node|Acc3]};
                _ ->
                    {Acc1, [Node|Acc2], Acc3}
            end
        end,
        {[], [], []},
        maps:to_list(Nodes)).



%% ===================================================================
%% Internal - Leader election
%% ===================================================================

find_leader(#state{id=SrvId, leader_pid=undefined}=State) ->
    case get_leader_pid(SrvId) of
        Pid when is_pid(Pid) ->
            ?LLOG(notice, "new leader is ~s (~p) (me:~p)", [node(Pid), Pid, self()], State),
            monitor(process, Pid),
            find_leader(State#state{leader_pid=Pid});
        undefined ->
            case global:register_name(global_name(SrvId), self(), fun ?MODULE:resolve/3) of
                yes ->
                    ?LLOG(notice, "WE are the new leader (~p)", [self()], State),
                    nklib_proc:put(?MODULE, {SrvId, leader}),
                    nklib_proc:put({?MODULE, SrvId}, leader),
                    rpc:abcast(?MODULE, nkservice_check_leader),
                    {ok, State#state{is_leader=true, leader_pid=self()}};
                no ->
                    ?LLOG(notice, "could not register as leader, waiting (me:~p)", [self()], State),
                    % Wait for next iteration
                    {ok, State}
            end
    end;

% We already have a registered leader, and we are that leader
% We recheck we are the real registered leader
find_leader(#state{id=SrvId, is_leader=true}=State) ->
    case get_leader_pid(SrvId) of
        Pid when Pid==self() ->
            {ok, State};
        Other ->
            ?LLOG(warning, "we were leader but is NOT the registered leader: ~p (me:~p)",
                  [Other, self()], State),
            {error, other_is_leader}
    end;

% We already have a registered leader
% We recheck the current leader is the one we have registered, and we re-register with it
find_leader(#state{id=SrvId, leader_pid=Pid}=State) ->
    case get_leader_pid(SrvId) of
        Pid ->
            % ?LLOG(info, "register with leader ~p (me:~p)", [node(Pid), self()], State),
            gen_server:cast(Pid, {nkservice_register_slave, self()});
        undefined ->
            ?LLOG(notice, "could not register as leader, waiting (me:~p)", [self()], State);
        Other ->
            % Wait for leader to fail and detect 'DOWN'
            ?LLOG(warning, "my old leader is NOT the registered leader: ~p (~p)"
                  " (me:~p), waiting",
                  [Other, Pid, self()], State)
    end,
    {ok, State}.


%% @private
global_name(SrvId) ->
    {nkservice_leader, SrvId}.


%% @private
resolve({nkservice_leader, SrvId}, Pid1, Pid2) ->
    Node1 = node(Pid1),
    Node2 = node(Pid2),
    Time1 = rpc:call(Node1, nkservice_app, get, [nkservice_start_time]),
    Time2 = rpc:call(Node2, nkservice_app, get, [nkservice_start_time]),
    if
        Time1 < Time2 ->
            lager:error("Resolving leader conflict for service '~s'. "
            "Node ~p was started before node ~p, so it is selected",
                [SrvId, Node1, Node2]),
            gen_server:cast(Pid2, nkservice_other_is_leader),
            Pid1;
        Time1 >= Time2 ->
            lager:error("Resolving leader conflict for service '~s'. "
            "Node ~p was started before node ~p, so it is selected",
                [SrvId, Node2, Node1]),
            gen_server:cast(Pid1, nkservice_other_is_leader),
            Pid2
    end.


%% ===================================================================
%% Register & Counters
%% ===================================================================

do_register_actor(ActorId, #state{register_ets=Ets}=State) ->
    #actor_id{
        domain = Domain,
        group = Group,
        resource = Res, name=Name,
        uid = UID,
        pid = Pid
    } = ActorId,
    case do_find_actor_id(ActorId, State) of
        false ->
            Ref = monitor(process, Pid),
            Objs = [
                {{name, Domain, Group, Res, Name}, ActorId},
                {{uid, UID}, ActorId},
                {{pid, Pid}, {name, Domain, Group, Res, Name}, UID, Ref}
            ],
            ets:insert(Ets, Objs),
            {ok, self()};
        {true, _OldActorId} ->
            {error, actor_already_registered}
    end.


%% @private
do_find_actor_id(#actor_id{}=ActorId, #state{register_ets=Ets}) ->
    #actor_id{domain=Domain, group=Group, resource=Res, name=Name} = ActorId,
    case ets:lookup(Ets, {name, Domain, Group, Res, Name}) of
        [{_, ActorId2}] ->
            {true, ActorId2};
        [] ->
            false
    end;

do_find_actor_id(UID, #state{register_ets=Ets}) ->
    case ets:lookup(Ets, {uid, UID}) of
        [{_, ActorId2}] ->
            {true, ActorId2};
        [] ->
            false
    end.


%% @private
do_remove_actor(Pid, #state{register_ets=Ets}) ->
    case ets:lookup(Ets, {pid, Pid}) of
        [{{pid, Pid}, {name, Domain, Group, Res, Name}, UID, Ref}] ->
            nklib_util:demonitor(Ref),
            ets:delete(Ets, {pid, Pid}),
            ets:delete(Ets, {name, Domain, Group, Res, Name}),
            ets:delete(Ets, {uid, UID}),
            true;
        [] ->
            false
    end.


%%%% @private
%%do_stop_all_actors(#state{register_ets=Ets}=State) ->
%%    ets:foldl(
%%        fun
%%            ({{pid, Pid}, {name, _Domain, _Group, _Res, _Name}, _UID, _Ref}, Acc) ->
%%                nkservice_actor_srv:async_op(none, Pid, {raw_stop, father_stopped}),
%%                Acc+1;
%%            (_Term, Acc) ->
%%                Acc
%%        end,
%%        0,
%%        Ets).



%% ===================================================================
%% Util
%% ===================================================================


%% @private
%% Will call the service's functions
handle(Fun, Args, #state{id=SrvId, user=UserState}=State) ->
    case apply(SrvId, Fun, Args++[UserState]) of
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


%%%% @private
%%to_bin(Term) when is_binary(Term) -> Term;
%%to_bin(Term) -> nklib_util:to_binary(Term).



