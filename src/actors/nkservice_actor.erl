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
-export([get_actor/1, get_path/1, is_enabled/1, enable/2, update/2, remove/1,
         stop/1, stop/2]).
-export([search_classes/2, search_types/3]).
-export([search_linked_to/4, search_fts/4, search/3, search_ids/3,
         delete_all/3, delete_old/5]).
-export_type([actor/0, id/0, uid/0, class/0, type/0, path/0, name/0, vsn/0,
              data/0, metadata/0, alarm_class/0, alarm_body/0]).


-include("nkservice.hrl").
-include("nkservice_actor.hrl").
-include("nkservice_actor_debug.hrl").



%% ===================================================================
%% Callbacks definitions
%% ===================================================================

-type actor() :: #actor{}.

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


-type alarm_class() :: binary().

%% Recommended alarm fields
%% ------------------------
%% - code (binary)
%% - message (binary)
%% - lastTime (binary, rfc3339)
%% - meta (map)

-type alarm_body() :: map().


%% Recognized metadata
%% -------------------
%% (see nkservice_actor_syntax)
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
%% - subtype (binary)
%%
%% - isInAlarm (boolean)
%%
%% - alarms [alarm()]
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
-spec remove(id()|pid()) ->
    ok | {error, term()}.

remove(Id) ->
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


%% @doc Counts classes and objects of each class
-spec search_classes(nkservice:id(), #{deep=>boolean(), srv=>nksevice:id()}) ->
    {ok, [{binary(), integer()}], Meta::map()} | {error, term()}.

search_classes(SrvId, Opts) ->
    QuerySrvId = maps:get(srv, Opts, SrvId),
    nkservice_actor_db:aggregation(SrvId, {service_aggregation_classes, QuerySrvId, Opts}).


%% @doc
-spec search_types(nkservice:id(), class(), #{deep=>boolean(), srv=>nksevice:id()}) ->
    {ok, [{binary(), integer()}], Meta::map()} | {error, term()}.

search_types(SrvId, Class, Opts) ->
    QuerySrvId = maps:get(srv, Opts, SrvId),
    nkservice_actor_db:aggregation(SrvId, {service_aggregation_types, QuerySrvId, Class, Opts}).


%% @doc Gets objects pointing to another
-spec search_linked_to(nkservice:id(), nkservice_actor:id(), binary()|any,
                       #{from=>pos_integer(), size=>pos_integer(),srv=>nksevice:id()}) ->
    {ok, #{UID::binary() => LinkType::binary()}} | {error, term()}.

search_linked_to(SrvId, Id, LinkType, Opts) ->
    case nkservice_actor_db:find(Id) of
        {ok, #actor_id{uid=UID}, _} ->
            QuerySrvId = maps:get(srv, Opts, SrvId),
            nkservice_actor_db:search(SrvId, {service_search_linked, QuerySrvId, UID, LinkType, Opts});
        {error, Error} ->
            {error, Error}
    end.


%% @doc Gets objects under a path, sorted by path
-spec search_fts(nkservce:id(), binary()|any, binary(),
    #{from=>pos_integer(), size=>pos_integer(), srv=>nksevice:id()}) ->
    {ok, [UID::binary()], Meta::map()} | {error, term()}.

search_fts(SrvId, Field, Word, Opts) ->
    QuerySrvId = maps:get(srv, Opts, SrvId),
    nkservice_actor_db:search(SrvId, {service_search_fts, QuerySrvId, Field, Word, Opts}).


%% @doc Generic search returning actors
-spec search(nkservice:id(), nkservice_actor_search:search_spec(),
             nkservice_actor_search:search_opts()) ->
    {ok, [actor()], Meta::map()} | {error, term()}.

search(SrvId, SearchSpec, SearchOpts) ->
    SearchSpec2 = maps:merge(#{srv=>SrvId}, SearchSpec),
    case nkservice_actor_search:parse(SearchSpec2, SearchOpts) of
        {ok, SearchSpec3} ->
            nkservice_actor_db:search(SrvId, {service_search_actors, SearchSpec3});
        {error, Error} ->
            {error, Error}
    end.


%% @doc Generic search returning actors
%% Meta will include size, last_updated and total (if not totals=false)
-spec search_ids(nkservice:id(), nkservice_actor_search:search_spec(),
    nkservice_actor_search:search_opts()) ->
    {ok, [#actor_id{}], Meta::map()} | {error, term()}.

search_ids(SrvId, SearchSpec, SearchOpts) ->
    SearchSpec2 = maps:merge(#{srv=>SrvId}, SearchSpec),
    case nkservice_actor_search:parse(SearchSpec2, SearchOpts) of
        {ok, SearchSpec3} ->
            nkservice_actor_db:search(SrvId, {service_search_actors_id, SearchSpec3});
        {error, Error} ->
            {error, Error}
    end.


%% @doc Deletes actors older than Epoch (secs)
-spec delete_old(nkservice:id(), class(), type(), binary(),
                        #{deep=>boolean(), srv=>nksevice:id()}) ->
    {ok, integer(), Meta::map()}.

delete_old(SrvId, Class, Type, Date, Opts) ->
    QuerySrvId = maps:get(srv, Opts, SrvId),
    nkservice_actor_db:search(SrvId, {service_delete_old_actors, QuerySrvId, Class, Type, Date, Opts}).


%% @doc Generic deletion of objects
%% Use delete=>true for real deletion
%% Use search_opts() to be able to use special fields, otherwise anything is accepted
-spec delete_all(nkservice:id(), nkservice_actor_search:search_spec()|#{delete=>boolean()},
                 nkservice_actor_search:search_opts()) ->
    {ok|deleted, integer(), Meta::map()}.

delete_all(SrvId, SearchSpec, SearchOpts) ->
    {Delete, SearchSpec2} = case maps:take(delete, SearchSpec) of
        error ->
            {false, SearchSpec};
        {Test0, SearchSpec0} ->
            {Test0, SearchSpec0}
    end,
    SearchSpec3 = maps:merge(#{srv=>SrvId}, SearchSpec2),
    case nkservice_actor_search:parse(SearchSpec3, SearchOpts) of
        {ok, SearchSpec4} ->
            case nkservice_actor_db:search(SrvId, {service_delete_actors, Delete, SearchSpec4}) of
                {ok, Total, Meta} when Delete ->
                    {deleted, Total, Meta};
                {ok, Total, Meta} ->
                    {ok, Total, Meta};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.



