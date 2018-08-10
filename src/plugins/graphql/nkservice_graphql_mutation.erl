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

%% @doc Mutation callback
-module(nkservice_graphql_mutation).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([execute/4]).

-include("nkservice.hrl").

%% @doc Called at the beginning of the query processing
%% Must reply with {ok, ActorObj} or {error, term()} or {error, {term(), term()}}.
execute(Ctx, _DummyObj, MutationName, Params) ->
    #{nkmeta:=#{start:=Start, srv:=SrvId}} = Ctx,
    case MutationName of
        <<"node">> ->
            #{<<"id">>:=UID} = Params,
            case ?CALL_SRV(SrvId, nkservice_graphql_get_uid, [SrvId, UID]) of
                {ok, ActorObj} ->
                    {ok, ActorObj};
                {error, Error} ->
                    {error, Error}
            end;
        _ ->
            Params2 = remove_nulls(Params),
            Res = case call_core_mutation(SrvId, MutationName, Params2, Ctx) of
                continue ->
                    case call_actor_mutation(SrvId, MutationName, Params2, Ctx) of
                        continue ->
                            {error, {mutation_unknown, MutationName}};
                        {ok, Obj} ->
                            {ok, Obj};
                        {error, Error} ->
                            {error, Error}
                    end;
                {ok, Obj} ->
                    {ok, Obj};
                {error, Error} ->
                    {error, Error}
            end,
            lager:info("Mutation time: ~p", [nklib_util:m_timestamp()-Start]),
            lager:error("NKLOG Mutation Result ~p", [Res]),
            Res
    end.


%% @private
remove_nulls(Map) ->
    maps:filter(fun(_K, V) -> V /= null end, Map).


%% @private
call_actor_mutation(SrvId, Name, Params, Ctx) ->
    case catch nkservice_graphql_plugin:get_actor_query_meta(SrvId, Name) of
        #{module:=Module}=Meta ->
            case erlang:function_exported(Module, mutation, 5) of
                true ->
                    Module:mutation(SrvId, Name, Params, Meta, Ctx);
                false ->
                    continue
            end;
        _ ->
            continue
    end.


%% @private
call_core_mutation(SrvId, Name, Params, Ctx) ->
    ?CALL_SRV(SrvId, nkservice_graphql_mutation, [SrvId, Name, Params, #{}, Ctx]).
