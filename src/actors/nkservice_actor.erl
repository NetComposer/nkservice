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
%% Actors are identified by its 'uid' or its 'path'
%% - When using uid, it will located only on local node or if is has been cached
%%   at local node. Otherwise a database backend must be used.
%% - Path is always '/srv/class/type/name'. The service will we asked if not cached


-module(nkservice_actor).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([create/1]).
-export([get_actor/1, get_path/1, is_enabled/1, enable/2, update/2, delete/1,
         stop/1, stop/2]).
-export([search_classes/2, search_types/3]).
-export([search_linked_to/4, search_fts/4, search/2, search_ids/2]).
-export_type([actor/0, actor_map/0, id/0]).


-include("nkservice.hrl").
-include("nkservice_actor.hrl").
-include("nkservice_actor_debug.hrl").



%% ===================================================================
%% Callbacks definitions
%% ===================================================================

-type actor() :: #actor{}.

-type actor_map() ::
    #{
        srv => nkservice:id(),              %% Service where it is loaded
        class => class(),         %% Mandatory
        type => type(),           %% Mandatory
        name => name(),           %% Generated if not included
        uid => uid(),             %% Always generated
        vsn => vsn(),             %% DB version
        data => data(),
        metadata => metadata(),
        status => status()
    }.


-type id() :: path() | uid() | #actor_id{}.

-type uid() :: binary().

-type class() :: binary().

-type type() :: binary().

-type path() :: binary().   %% /srv/class/type/name

-type name() :: binary().

-type vsn() :: binary().

-type data() ::
    #{
        binary() => binary() | integer() | float() | boolean()
    }.

-type status() ::
    #{
        is_activated => boolean(),
        term() => term()
    }.


-type filter_op() ::
    eq | ne | lt | lte | gt | gte | values | prefix | exists.


-type search_opts() ::
    #{
        from => pos_integer(),
        size => pos_integer(),
        totals => boolean(),
        deep => boolean(),
        filters => #{
            'and' | 'or' | 'not' => [{Field::binary(), Op::filter_op(), term()}]
        },
        sort => [{asc|desc, Field::binary()}]
    }.


%% Recognized metadata
%% -------------------
%%
%% - resourceVersion (binary)
%%   hash of the Name, Spec and Meta, generated automatically
%%
%% - generation (integer)
%%   incremented at each change
%%
%% - creationTime (rfc3339)
%%   updated on creation
%%
%% - updateTime (rfc3339))
%%   updated on update
%%
%% - isActivated (boolean)
%%   must be loaded at all times
%%
%% - expiresTime (rfc3339)
%%
%% - labels (binary() => binary | integer | boolean)
%%
%% - fts (binary() => [binary()]
%%
%% - links (binary => binary)
%%
%% - annotations (binary => binary | integer | boolean)
%%
%% - isEnabled (boolean)
%%   defaults true, can be overridden on load
%%
%% - isInAlarm (boolean)
%%
%% - alarms ([binary])
%%
%% - nextStatusTime (rfc3339)
%%
%% - description (binary)
%%
%% - createdBy (binary)
%%
%% - updatedBy (binary)
%%


-type metadata() ::
    #{
        binary() => binary() | integer() | float() | boolean()
    }.


%% ===================================================================
%% Public
%% ===================================================================


%% @doc
create(Actor) ->
    nkservice_actor_db:create(Actor, #{}).


%% @doc
-spec get_actor(id()|pid()) ->
    {ok, actor()} | {error, term()}.

get_actor(Id) ->
    nkservice_actor_srv:sync_op(Id, get_actor).


%% @doc
-spec get_path(id()|pid()) ->
    {ok, path()} | {error, term()}.

get_path(Id) ->
    case nkservice_actor_srv:sync_op(Id, get_actor_id) of
        {ok, ActorId} ->
            {ok, nkservice_actor_util:actor_id_to_path(ActorId)};
        {error, Error} ->
            {error, Error}
    end.


%% @doc Check if an actor is enabled
-spec is_enabled(id()|pid()) ->
    {ok, boolean()} | {error, term()}.

is_enabled(Id) ->
    nkservice_actor_srv:sync_op(Id, is_enabled).


%% @doc Enables/disabled an object
-spec enable(id()|pid(), boolean()) ->
    ok | {error, term()}.

enable(Id, Enable) ->
    nkservice_actor_srv:sync_op(Id, {enable, Enable}).


%% @doc Updates an object
-spec update(id()|pid(), map()) ->
    {ok, UnknownFields::[binary()]} | {error, term()}.

update(Id, Update) ->
    nkservice_actor_srv:sync_op(Id, {update, Update}).


%% @doc Remove an object
-spec delete(id()|pid()) ->
    ok | {error, term()}.

delete(Id) ->
    nkservice_actor_srv:sync_op(Id, delete).


%% @doc Unloads the object
-spec stop(id()|pid()) ->
    ok | {error, term()}.

stop(Id) ->
    stop(Id, normal).


%% @doc Unloads the object
-spec stop(id()|pid(), Reason::nkservice:msg()) ->
    ok | {error, term()}.

stop(Id, Reason) ->
    nkservice_actor_srv:async_op(Id, {stop, Reason}).


%% @doc
-spec search_classes(nkservice:id(), #{deep=>boolean()}) ->
    {ok, [{binary(), integer()}], Meta::map()} | {error, term()}.

search_classes(SrvId, Opts) ->
    Deep = maps:get(deep, Opts, true),
    nkservice_actor_db:aggregation(SrvId, {aggregation_service_classes, SrvId, #{deep=>Deep}}).


%% @doc
-spec search_types(nkservice:id(), class(), #{deep=>boolean()}) ->
    {ok, [{binary(), integer()}], Meta::map()} | {error, term()}.

search_types(SrvId, Class, Opts) ->
    Deep = maps:get(deep, Opts, true),
    nkservice_actor_db:aggregation(SrvId, {aggregation_service_types, SrvId, Class, #{deep=>Deep}}).


%% @doc Gets objects pointing to another
-spec search_linked_to(nkservice:id(), nkservice_actor:id(), nkservice_actor:class(),
                       #{from=>pos_integer(), size=>pos_integer()}) ->
    {ok, #{UID::binary() => LinkType::binary()}} | {error, term()}.

search_linked_to(SrvId, Id, LinkType, Params) ->
    case nkservice_actor_db:find(Id) of
        {ok, #actor_id{srv=ActorSrvId, uid=UID}} ->
            nkservice_actor_db:search(ActorSrvId, {search_service_linked, SrvId, UID, LinkType, Params});
        {error, Error} ->
            {error, Error}
    end.


%% @doc Gets objects under a path, sorted by path
-spec search_fts(nkservce:id(), binary(), binary(),
    #{from=>pos_integer(), size=>pos_integer()}) ->
    {ok, [UID::binary()], Meta::map()} | {error, term()}.

search_fts(SrvId, Field, Word, Opts) ->
    nkservice_actor_db:search(SrvId, {search_service_fts, SrvId, Field, Word, Opts}).


%% @doc Generic search returning actors
-spec search(nkservice:id(), search_opts()) ->
    {ok, [actor()], Meta::map()} | {error, term()}.

search(SrvId, Opts) ->
    nkservice_actor_db:search(SrvId, {search_service_actors, SrvId, Opts}).


%% @doc Generic search returning actors
-spec search_ids(nkservice:id(), search_opts()) ->
    {ok, [#actor_id{}], Meta::map()} | {error, term()}.

search_ids(SrvId, Opts) ->
    nkservice_actor_db:search(SrvId, {search_service_actors_id, SrvId, Opts}).
