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

%% @doc NkDomain service callback module
-module(nkservice_graphql_callbacks).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([msg/1]).
-export([nkservice_graphql_core_schema/3,
         nkservice_graphql_get_uid/2,
         nkservice_graphql_query/5,
         nkservice_graphql_mutation/5,
         nkservice_graphql_execute/5]).
-export([nkservice_rest_http/4]).

-define(LLOG(Type, Txt, Args), lager:Type("NkDOMAIN GraphQL Callbacks: "++Txt, Args)).



%% ===================================================================
%% Types
%% ===================================================================

-type continue() :: continue | {continue, list()}.
-type schema_type() :: nkservice_graphql_schema:schema_type().
-type schema_def() :: nkservice_graphql_schema:schema_def().
%-type schema_fields() :: nkservice_graphql_schema:schema_fields().



%% ===================================================================
%% Error
%% ===================================================================


%% @doc
msg({query_unknown, Query}) ->          {"Query '~s' unknown", [Query]};
msg({mutation_unknown, Query}) ->       {"Mutation '~s' unknown", [Query]};
msg(_)   		                        -> continue.



%% ===================================================================
%% Graphql related callbacks
%% ===================================================================


%% @doc Implement to add your own core schema
-spec nkservice_graphql_core_schema(nkservice:id(), schema_type(), schema_def()) ->
    schema_def().

nkservice_graphql_core_schema(_SrvId, _SchemaType, Schema) ->
    Schema.


%% @doc Called to retrieve objects by UID
%% Can retry any object, later used in execute, etc.
-spec nkservice_graphql_get_uid(nkservice:id(), binary()) ->
    {ok, nkservice_graphql:object()} | {error, nkservice_graphql:error()} | continue().

nkservice_graphql_get_uid(_SrvId, _UID) ->
    {error, not_implemented}.


%% @doc Process an incoming graphql query
%% Can retry any object, later used in execute, etc.
-spec nkservice_graphql_query(nkservice:id(), binary(), map(), map(), map()) ->
    {ok, nkservice_graphql:object()} | {error, nkservice_graphql:error()} |  continue().

nkservice_graphql_query(_SrvId, _Name, _Params, _Meta, _Ctx) ->
    continue.


%% @doc Process an incoming graphql mutation
-spec nkservice_graphql_mutation(nkservice:id(), binary(), map(), map(), map()) ->
    {ok, nkservice_graphql:object()} | {error, nkservice_graphql:error()} | continue().

nkservice_graphql_mutation(_SrvId, _Name, _Params, _Meta, _Ctx) ->
    continue.


%% @doc Process an execute on a field
-spec nkservice_graphql_execute(nkservice:id(), binary(), nkservice_graphql:object(), map(), map()) ->
    {ok, term()} | null | {error, nkservice_graphql:error()} | continue().

nkservice_graphql_execute(_SrvId, Field, Obj, _Meta, _Args) when is_map(Obj) ->
    {ok, maps:get(Field, Obj, null)};

nkservice_graphql_execute(_SrvId, _Field, _Obj, _Meta, _Args) ->
    continue.



%% ===================================================================
%% Queries
%% ===================================================================


%% @doc
nkservice_rest_http(<<"nkservice-graphiql">>, Verb, Path, Req) ->
    nkservice_graphiql_server:http(Verb, Path, Req);


nkservice_rest_http(_Id, _Method, _Path, _Req) ->
    continue.



