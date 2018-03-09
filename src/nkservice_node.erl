
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

%% @doc
%% Tries to connect to nodes defined in nkservice_app 'nodes'
%% Asks any other node about the local node info and keeps a global view at each node
%% Sends updated node info to all registered service leaders
%% (they call register_service_master/1 at the node they run)
%% Gets periodic information about the status of all services at all nodes.
%% calling nkservice:get_services() at the local node

-module(nkservice_node).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([get_info/0, set_status/1, register_service_master/1]).
-export([start_link/0]).
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2,
         handle_info/2]).

-include("nkservice.hrl").

-define(LLOG(Type, Txt, Args),
    lager:Type("NkSERVICE Node ~p "++Txt, [node()|Args])).

-define(CHECK_TIME, 5000).


%% ===================================================================
%% Types
%% ===================================================================

-type node_status() :: normal | stopping | stopped | down.

-type node_info() ::
    #{
        started_time => nklib_util:m_timestamp(),
        node_status => node_status(),
        status_time => nklib_util:m_timestamp()
    }.

-type info() ::
    #{
        nodes => #{node() => node_info()},
        services => #{nkservice:id() => [nkservice_srv:service_local_info()]}
    }.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc
-spec get_info() ->
    {ok, info()} | {error, term()}.

get_info() ->
    gen_server:call(?MODULE, nkservice_get_info).


%% @doc
-spec set_status(node_status()) ->
    ok | {error, term()}.

set_status(Status) when Status==normal; Status==stopping; Status==stopped ->
    gen_server:call(?MODULE, {nkservice_set_status, Status}).


%% @doc
register_service_master(SrvId) ->
    gen_server:call(?MODULE, {nkservice_register_master, SrvId, self()}).


%% ===================================================================
%% Private
%% ===================================================================


%% @private
-spec start_link() ->
    {ok, pid()} | {error, term()}.

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).




%% ===================================================================
%% gen_server
%% ===================================================================


-record(state, {
    nodes :: #{node() => node_info()},
    services :: #{nkservice:id() => [nkservice:service_info()]},
    masters :: [{nkservice:id(), pid()}]
}).


%% @private
init([]) ->
    Now = nklib_util:m_timestamp(),
    NodeInfo = #{
        started_time => Now,
        node_status => normal,
        status_time => Now
    },
    State = #state{
        nodes = #{node() => NodeInfo},
        services = #{},
        masters = []
    },
    ?LLOG(notice, "starting", []),
    net_kernel:monitor_nodes(true, [nodedown_reason]),
    self() ! nkservice_spawn_check,
    {ok, State}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}} | {reply, term(), #state{}} |
    {stop, Reason::term(), #state{}} | {stop, Reason::term(), Reply::term(), #state{}}.

handle_call(nkservice_get_info, _From, State) ->
    #state{nodes=Nodes, services=Services} = State,
    Data = #{
        nodes => Nodes,
        services => Services
    },
    {reply, {ok, Data}, State};

handle_call({nkservice_set_status, Status}, _From, State) ->
    {Reply, State2} = update_status(Status, State),
    {reply, Reply, State2};

handle_call(nkservice_get_local_node, _From, #state{nodes=Nodes}=State) ->
    {reply, {ok, maps:get(node(), Nodes)}, State};

handle_call({nkservice_register_master, SrvId, Pid}, _From, State) ->
    #state{masters=Masters, nodes=Nodes} = State,
    monitor(process, Pid),
    ?LLOG(info, "master for service ~p registered (~p)", [SrvId, Pid]),
    Masters2 = lists:keystore(SrvId, 1, Masters, {SrvId, Pid}),
    {reply, {ok, self(), Nodes}, State#state{masters=Masters2}};

handle_call(Msg, _From, State) ->
    lager:error("Unexpected handle_call at ~p: ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_cast(nkservice_spawn_checks_completed, State) ->
    erlang:send_after(?CHECK_TIME, self(), nkservice_spawn_check),
    {noreply, State};

handle_cast({nkservice_set_nodes_info, Nodes}, State) ->
    #state{nodes=OldNodes, masters=Masters} = State,
    Local = maps:get(node(), OldNodes),
    % Leave failed nodes
    Nodes2 = maps:merge(OldNodes, Nodes),
    Nodes3 = Nodes2#{node() => Local},
    State2 = State#state{nodes=Nodes3},
    notify_masters(Masters, State2),
    {noreply, State2};

handle_cast({nkservice_set_services_info, Services}, State) ->
    {noreply, State#state{services=Services}};

handle_cast({nkservice_set_nodes, Services}, State) ->
    State2 = State#state{services=Services},
    %notify_leaders(State2),
    {noreply, State2};

handle_cast(Msg, State) ->
    lager:error("Unexpected handle_cast at ~p: ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_info(nkservice_spawn_check, State) ->
    Self = self(),
    spawn_link(fun() -> spawn_checks(Self) end),
    {noreply, State};

handle_info({nodeup, _Node, _InfoList}, State) ->
    {noreply, State};

handle_info({nodedown, Node, InfoList}, #state{nodes=Nodes}=State) ->
    State2 = case maps:find(Node, Nodes) of
        {ok, Info} ->
            ?LLOG(warning, "node ~p is DOWN: ~p", [Node, InfoList]),
            Info2 = Info#{
                node_status := down,
                status_time := nklib_util:m_timestamp()
            },
            Nodes2 = Nodes#{Node => Info2},
            State#state{nodes=Nodes2};
        error ->
            ?LLOG(info, "node ~p is down: ~p", [Node, InfoList]),
            State
    end,
    {noreply, State2};

handle_info({'DOWN', _Ref, process, Pid, Reason}, #state{masters=Masters}=State) ->
    State2 = case lists:keytake(Pid, 2, Masters) of
        {value, {SrvId, Pid}, Masters2} ->
            case Reason of
                shutdown ->
                    ?LLOG(info, "master for service ~p is shutting down: ~p",
                          [SrvId, Reason]);
                _ ->
                    ?LLOG(notice, "master for service ~p is down: ~p",
                          [SrvId, Reason])
            end,
            State#state{masters=Masters2};
        false ->
            State
    end,
    {noreply, State2};

handle_info(Msg, State) ->
    lager:error("Unexpected handle_info at ~p: ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec code_change(term(), #state{}, term()) ->
    {ok, #state{}}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% @private
-spec terminate(term(), #state{}) ->
    ok.

terminate(_Reason, _State) ->
    ok.



%% ===================================================================
%% Internal
%% ===================================================================

%% @private
update_status(Status, #state{nodes=Nodes}=State) ->
    #{node_status:=OldStatus} = Local = maps:get(node(), Nodes),
    case Status of
        OldStatus ->
            {ok, State};
        _ ->
            ?LLOG(notice, "status ~p -> ~p", [OldStatus, Status]),
            Local2 = Local#{
                node_status := Status,
                status_time := nklib_util:m_timestamp()
            },
            Nodes2 = Nodes#{node() := Local2},
            {ok, State#state{nodes=Nodes2}}
    end.


%% @private
spawn_checks(Self) ->
    Nodes1 = [nklib_util:to_atom(N) || N <- nkservice_app:get(nodes, [])],
    Nodes2 = Nodes1 -- [node()|nodes()],
    lists:foreach(
        fun(Node) ->
            case net_kernel:connect(Node) of
                true ->
                    ?LLOG(notice, "connected to node ~s", [Node]);
                false ->
                    ?LLOG(warning, "could not connect to node ~s", [Node]);
                ignored ->
                    ok
            end
        end,
        Nodes2),
    % Ask at each node about the local node info
    {Replies, _Bad} = gen_server:multi_call(nodes(), ?MODULE, nkservice_get_local_node),
    Nodes3 = [{Node, Info} || {Node, {ok, Info}} <- Replies],
    Nodes4 = maps:from_list(Nodes3),
    gen_server:cast(Self, {nkservice_set_nodes_info, Nodes4}),
    Services = nkservice:get_services(),
    gen_server:cast(Self, {nkservice_set_services_info, Services}),
    gen_server:cast(Self, nkservice_spawn_checks_completed).


%% @private
notify_masters([], _State) ->
    ok;

notify_masters([{_SrvId, Pid}|Rest], #state{nodes=Nodes}=State) ->
    nkservice_master:updated_nodes_info(Pid, Nodes),
    notify_masters(Rest, State).



%%%% @private
%%to_bin(Term) when is_binary(Term) -> Term;
%%to_bin(Term) -> nklib_util:to_binary(Term).
