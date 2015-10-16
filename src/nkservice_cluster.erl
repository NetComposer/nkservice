%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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

-module(nkservice_cluster).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([register/2, get_services/0, force_update/0]).
-export([update_info/2, get_module/1, update_service/2, remove_service/1]).
-export([start_link/0]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).

-define(TICK_TIME, 5000).

-type id() :: nkservice:id().
-type spec() :: nkservice:spec().
-type class() :: nkservice:class().
-type info() :: nkservice:info().



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Register a new service class with a callback module
-spec register(class(), module()) ->
    ok.

register(ServiceClass, Module) when is_atom(ServiceClass) ->
    {module, Module} = code:ensure_loaded(Module),
    nklib_config:put(?MODULE, {srv, ServiceClass}, Module).


%% @doc
-spec get_services() ->
    #{id() => info()}.

get_services() ->
    gen_server:call(?MODULE, get_services).


%% @doc Forces all nodes in the cluster to update all services
-spec force_update() ->
    ok.

force_update() ->
    abcast(force_update).
    

%% ===================================================================
%% Internal
%% ===================================================================


%% @private Update info about a service
-spec update_info(id(), info()) ->
    ok.

update_info(SrvId, Info) ->
    gen_server:cast(?MODULE, {update_info, SrvId, Info}).


%% @doc Gets a service class callback module
-spec get_module(class()) ->
    module().

get_module(Class) when is_atom(Class) ->
    case nklib_config:get(?MODULE, {srv, Class}, not_found) of
        not_found -> 
            error({service_class_not_found, Class});
        Module -> 
            Module
    end.


%% @private Save in cluster metadata spec for a service
-spec update_service(id(), spec()|deleted) ->
    ok.

update_service(SrvId, #{class:=_}=SrvSpec) ->
    SrvId1 = nklib_util:to_atom(SrvId),
    abcast({update_service, SrvId1, SrvSpec}),
    ok = riak_core_metadata:put({nkservice, service}, SrvId, SrvSpec).


%% @private Removes a service from the cluster
-spec remove_service(id()) ->
    ok.

remove_service(SrvId) when is_binary(SrvId) ->
    SrvId1 = nklib_util:to_atom(SrvId),
    update_service(SrvId1, deleted).


%% @private
-spec start_link() ->
    {ok, pid()} | {error, term()}.

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).



% ===================================================================
%% gen_server behaviour
%% ===================================================================


-record(state, {
    meta_hash :: binary(),
    services = #{} :: #{id() => info()},
    pids = #{} :: #{pid() => id()}
}).


%% @private
-spec init(term()) ->
    {ok, tuple()} | {ok, tuple(), timeout()|hibernate} |
    {stop, term()} | ignore.

init([]) ->
    self() ! tick,
    {ok, #state{}}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}} | {reply, term(), #state{}} |
    {stop, Reason::term(), #state{}} | {stop, Reason::term(), Reply::term(), #state{}}.

handle_call(get_services, _From, #state{services=Srvs}=State) ->
    {reply, Srvs, State};

handle_call(Msg, _From, State) ->
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_cast({update_info, SrvId, Info}, #state{services=Srvs, pids=Pids}=State) ->
    Srvs1 = maps:put(SrvId, Info, Srvs),
    Pids1 = case whereis(SrvId) of
        undefined ->
            Pids;
        Pid ->
            case maps:is_key(Pid, Pids) of
                true -> 
                    Pids;
                false -> 
                    monitor(process, Pid),
                    maps:put(Pid, Pids, SrvId)
            end
    end,
    {noreply, State#state{services=Srvs1, pids=Pids1}};

handle_cast(Msg, State) -> 
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_info(tick, #state{meta_hash=Hash}=State) ->
    % lager:warning("TICK"),
    State1 = case riak_core_metadata:prefix_hash({nkservice, service}) of
        Hash -> 
            State;
        NewHash ->
            update_services(State#state{meta_hash=NewHash})
    end,
    erlang:send_after(?TICK_TIME, self(), tick),
    {noreply, State1};

handle_info({update_service, SrvId, SrvSpec}, #state{services=Srvs}=State) ->
    Srvs1 = update_services([{SrvId, SrvSpec}], Srvs),
    {noreply, State#state{services=Srvs1}};

handle_info(force_update, State) ->
    State1 = update_services(State),
    {noreply, State1};

handle_info({'DOWN', _Ref, process, Pid, Reason}, State) ->
    #state{services=Srvs, pids=Pids} = State,
    case maps:find(Pid, Pids) of
        {ok, SrvId} ->
            case Reason of
                normal -> 
                    lager:debug("NkSERVICE: Service ~p is down (~p)", 
                                 [SrvId, Reason]);
                _ -> 
                    lager:notice("NkSERVICE: Service ~p is down (~p)", 
                                 [SrvId, Reason])
            end,
            Info1 = maps:get(SrvId, Srvs),
            Info2 = Info1#{status=>error, error=><<"Process down">>},
            update_info(SrvId, Info2),
            Pids1 = maps:remove(Pid, Pids),
            {noreply, State#state{pids=Pids1}};
        false ->
            lager:warning("Module ~p received unexpected DOWN: ~p (~p)", 
                          [?MODULE, Pid, State]),
            {noreply, State}
    end;

handle_info(Info, State) -> 
    lager:warning("Module ~p received unexpected info: ~p (~p)", [?MODULE, Info, State]),
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
    


% ===================================================================
%% Internal
%% ===================================================================


%% @private
update_services(#state{services=Srvs}=State) ->
    Updates = get_update_list(),
    Srvs1 = update_services(Updates, Srvs),
    State#state{services=Srvs1}.


%% @private
update_services([], Srvs) ->
    Srvs;

update_services([{SrvId, deleted}|Rest], Srvs) ->
    Srvs1 = case maps:find(SrvId, Srvs) of
        {ok, #{pid:=Pid}} ->
            nkservice_server:remove(Pid),
            maps:remove(SrvId, Srvs);
        {ok, _} ->
            maps:remove(SrvId, Srvs);
        error ->
            Srvs
    end,
    update_services(Rest, Srvs1);

update_services([{SrvId, SrvSpec}|Rest], Srvs) ->
    case maps:find(SrvId, Srvs) of
        {ok, #{pid:=Pid}} ->    
            nkservice_server:update(Pid, SrvSpec);
        _ ->
            spawn_link(fun() -> start_service(SrvId, SrvSpec) end)
    end,
    update_services(Rest, Srvs).


%% @private
start_service(SrvId, #{class:=Class}=SrvSpec) ->
    Info = case nkservice_server:start(SrvId, SrvSpec) of
        {ok, _Pid} ->
            #{
                class => Class,
                status => starting
            };
        {error, Error} ->
            #{
                class => Class,
                status => error, 
                error => nklib_util:to_binary(Error)
            }
    end,
    update_info(SrvId, Info).
  


%% @private
abcast(Msg) ->
    {ok, MyRing} = riak_core_ring_manager:get_my_ring(),
    Nodes = riak_core_ring:all_members(MyRing),
    abcast = rpc:abcast(Nodes, ?MODULE, Msg),
    ok.




%% @private
get_update_list() ->
    riak_core_metadata:fold(
        fun
            ({Key, ['$deleted'|_]}, Acc) -> 
                [{Key, deleted}|Acc];
            ({Key, [Value|_]}, Acc) ->
                [{Key, Value}|Acc]
        end,
        [],
        {nkservice, service}).
