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
-module(nkservice_pgsql_callbacks).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([actor_db_find/2, actor_db_read/2, actor_db_create/2,
         actor_db_update/2, actor_db_delete/3, actor_db_search/3, actor_db_aggregation/3]).

-include("nkservice.hrl").
-include("nkservice_actor.hrl").
-include_lib("nkpacket/include/nkpacket.hrl").

-define(LLOG(Type, Txt, Args),lager:Type("NkSERVICE HTTPPOOL "++Txt, Args)).



%% ===================================================================
%% Types
%% ===================================================================



%% ===================================================================
%% Plugin Callbacks
%% ===================================================================


actor_db_find(SrvId, Id) ->
    case get_package_id(SrvId) of
        {true, PackageId} ->
            case nkservice_actor_util:is_path(Id) of
                {true, #actor_id{srv=SrvId}=ActorId} ->
                    nkservice_pgsql_actors:find(SrvId, PackageId, ActorId);
                {false, UID} ->
                    nkservice_pgsql_actors:find(SrvId, PackageId, UID)
            end;
        false ->
            continue
    end.


actor_db_read(SrvId, UID) ->
    case get_package_id(SrvId) of
        {true, PackageId} ->
            nkservice_pgsql_actors:load(SrvId, PackageId, to_bin(UID));
        false ->
            continue
    end.


actor_db_create(SrvId, Actor) ->
    case get_package_id(SrvId) of
        {true, PackageId} ->
            nkservice_pgsql_actors:save(SrvId, PackageId, create, Actor);
        false ->
            continue
    end.


actor_db_update(SrvId, Actor) ->
    case get_package_id(SrvId) of
        {true, PackageId} ->
            nkservice_pgsql_actors:save(SrvId, PackageId, update, Actor);
        false ->
            continue
    end.


actor_db_delete(SrvId, UID, Opts) ->
    case get_package_id(SrvId) of
        {true, PackageId} ->
            nkservice_pgsql_actors:delete(SrvId, PackageId, to_bin(UID), Opts);
        false ->
            continue
    end.


actor_db_search(SrvId, SearchType, Opts) ->
    case get_package_id(SrvId) of
        {true, PackageId} ->
            nkservice_pgsql_actors:search(SrvId, PackageId, SearchType, Opts);
        false ->
            continue
    end.


actor_db_aggregation(SrvId, SearchType, Opts) ->
    case get_package_id(SrvId) of
        {true, PackageId} ->
            nkservice_pgsql_actors:aggregation(SrvId, PackageId, SearchType, Opts);
        false ->
            continue
    end.


%% ===================================================================
%% Internal
%% ===================================================================


get_package_id(SrvId) ->
    nkservice_pgsql_util:actor_persistence_package_id(SrvId).


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).