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
%% - Path is always '/domain/group/resource/name'. The service will we asked if not cached


-module(nkservice_actor).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([create/2]).
-export([get_actor/2, get_path/2, is_enabled/2, enable/3, update/3, remove/2,
         stop/2, stop/3]).
-export([search_groups/3, search_resources/4]).
-export([search_linked_to/5, search_fts/5, search/3, search_ids/3,
         delete_all/3, delete_old/6]).
-export_type([actor/0, id/0, uid/0, domain/0, resource/0, path/0, name/0,
              vsn/0, group/0, hash/0,
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

-type domain() :: binary().

-type group() :: binary().

-type vsn() :: binary().

-type hash() :: binary().

-type resource() :: binary().

-type path() :: binary().   %% /domain/group/type/name

-type name() :: binary().

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
create(SrvId, Actor) ->
    Actor2 = nkservice_actor_util:put_create_fields(Actor),
    nkservice_actor_db:create(SrvId, Actor2, #{}).


%% @doc
-spec get_actor(nkservice:id(), id()|pid()) ->
    {ok, actor()} | {error, term()}.

get_actor(SrvId, Id) ->
    nkservice_actor_srv:sync_op(SrvId, Id, get_actor).


%% @doc
-spec get_path(nkservice:id(), id()|pid()) ->
    {ok, path()} | {error, term()}.

get_path(SrvId, Id) ->
    case nkservice_actor_srv:sync_op(SrvId, Id, get_actor_id) of
        {ok, ActorId} ->
            {ok, nkservice_actor_util:actor_id_to_path(ActorId)};
        {error, Error} ->
            {error, Error}
    end.


%% @doc Check if an actor is enabled
-spec is_enabled(nkservice:id(), id()|pid()) ->
    {ok, boolean()} | {error, term()}.

is_enabled(SrvId, Id) ->
    nkservice_actor_srv:sync_op(SrvId, Id, is_enabled).


%% @doc Enables/disabled an object
-spec enable(nkservice:id(), id()|pid(), boolean()) ->
    ok | {error, term()}.

enable(SrvId, Id, Enable) ->
    nkservice_actor_srv:sync_op(SrvId, Id, {enable, Enable}).


%% @doc Updates an object
-spec update(nkservice:id(), id()|pid(), map()) ->
    {ok, UnknownFields::[binary()]} | {error, term()}.

update(SrvId, Id, Update) ->
    nkservice_actor_srv:sync_op(SrvId, Id, {update, Update}).


%% @doc Remove an object
-spec remove(nksservice:id(), id()|pid()) ->
    ok | {error, term()}.

remove(SrvId, Id) ->
    nkservice_actor_srv:sync_op(SrvId, Id, delete).


%% @doc Unloads the object
-spec stop(nkservice:id(), id()|pid()) ->
    ok | {error, term()}.

stop(SrvId, Id) ->
    stop(SrvId, Id, normal).


%% @doc Unloads the object
-spec stop(nkservice:id(), id()|pid(), Reason::nkservice:msg()) ->
    ok | {error, term()}.

stop(SrvId, Id, Reason) ->
    nkservice_actor_srv:async_op(SrvId, Id, {stop, Reason}).


%% @doc Counts classes and objects of each class
-spec search_groups(nkservice:id(), domain(), #{deep=>boolean()}) ->
    {ok, [{binary(), integer()}], Meta::map()} | {error, term()}.

search_groups(SrvId, Domain, Opts) ->
    nkservice_actor_db:aggregation(SrvId, {service_aggregation_groups, Domain, Opts}).


%% @doc
-spec search_resources(nkservice:id(), group(), domain(), #{deep=>boolean()}) ->
    {ok, [{binary(), integer()}], Meta::map()} | {error, term()}.

search_resources(SrvId, Domain, Group, Opts) ->
    nkservice_actor_db:aggregation(SrvId, {service_aggregation_resources, Domain, Group, Opts}).


%% @doc Gets objects pointing to another
-spec search_linked_to(nkservice:id(), domain(), nkservice_actor:id(), binary()|any,
                       #{deep=>boolean(), from=>pos_integer(), size=>pos_integer()}) ->
    {ok, #{UID::binary() => LinkType::binary()}} | {error, term()}.

search_linked_to(SrvId, Domain, Id, LinkType, Opts) ->
    case nkservice_actor_db:find(SrvId, Id) of
        {ok, #actor_id{uid=UID}, _} ->
            nkservice_actor_db:search(SrvId, {service_search_linked, Domain, UID, LinkType, Opts});
        {error, Error} ->
            {error, Error}
    end.


%% @doc Gets objects under a path, sorted by path
-spec search_fts(nkservce:id(), domain(), binary()|any, binary(),
    #{deep=>boolean(), from=>pos_integer(), size=>pos_integer()}) ->
    {ok, [UID::binary()], Meta::map()} | {error, term()}.

search_fts(SrvId, Domain, Field, Word, Opts) ->
    nkservice_actor_db:search(SrvId, {service_search_fts, Domain, Field, Word, Opts}).


%% @doc Generic search returning actors
-spec search(nkservice:id(), nkservice_actor_search:search_spec(),
             nkservice_actor_search:search_opts()) ->
    {ok, [actor()], Meta::map()} | {error, term()}.

search(SrvId, SearchSpec, SearchOpts) ->
    case nkservice_actor_search:parse(SearchSpec, SearchOpts) of
        {ok, SearchSpec2} ->
            nkservice_actor_db:search(SrvId, {service_search_actors, SearchSpec2});
        {error, Error} ->
            {error, Error}
    end.



%% @doc Generic search returning actors
%% Meta will include size, last_updated and total (if not totals=false)
-spec search_ids(nkservice:id(), nkservice_actor_search:search_spec(),
    nkservice_actor_search:search_opts()) ->
    {ok, [#actor_id{}], Meta::map()} | {error, term()}.

search_ids(SrvId, SearchSpec, SearchOpts) ->
    case nkservice_actor_search:parse(SearchSpec, SearchOpts) of
        {ok, SearchSpec2} ->
            nkservice_actor_db:search(SrvId, {service_search_actors_id, SearchSpec2});
        {error, Error} ->
            {error, Error}
    end.


%% @doc Deletes actors older than Epoch (secs)
-spec delete_old(nkservice:id(), domain(), group(), resource(), binary(), #{deep=>boolean()}) ->
    {ok, integer(), Meta::map()}.

delete_old(SrvId, Domain, Group, Type, Date, Opts) ->
    nkservice_actor_db:search(SrvId, {service_delete_old_actors, Domain, Group, Type, Date, Opts}).


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
    case nkservice_actor_search:parse(SearchSpec2, SearchOpts) of
        {ok, SearchSpec3} ->
            case nkservice_actor_db:search(SrvId, {service_delete_actors, Delete, SearchSpec3}) of
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



