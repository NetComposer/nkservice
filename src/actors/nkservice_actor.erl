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

-module(nkservice_actor).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([get_actor/2, get_path/2, enable/3, update/3, delete/2, unload/2, unload/3]).
-export([search_classes/2, search_paths/2, search_paths_class/3, search_labels/3]).
-export([search_linked/3, search_core_fts/3]).
-export_type([actor/0, id/0]).


-include("nkservice.hrl").
-include("nkservice_actor.hrl").
-include("nkservice_actor_debug.hrl").



%% ===================================================================
%% Callbacks definitions
%% ===================================================================

-type actor() ::
    #{
        srv => nkservice:id(),              %% Service where it is loaded
        uid => uid(),                       %% Generated if not included
        class => class(),                   %% Mandatory
        name => name(),                     %% Generated if not included
        vsn => binary(),                    %% Version of the class, spec
        spec => spec(),
        metadata => metadata()
    }.

-type id() :: uid() | path().

-type uid() :: binary().

-type class() :: binary().

-type path() :: binary().   %% /srv/a.b.c/class/name (or 'root' for domain)

-type name() :: binary().

-type spec() ::
    #{
        binary() => binary() | integer() | float() | boolean()
    }.


%% Recognized metadata
%% -------------------
%%
%% - resourceVersion (integer)
%%   hash of the Name, Spec and Meta, generated automatically
%%
%% - generation (integer)
%%   incremented at each change
%%
%% - creationTimestamp (binary rfc3339)
%%   updated on creation
%%
%% - isDeleted (boolean)
%%   updated on creation
%%
%% - deletionTimestamp (binary, rfc3339)
%%
%% - isActivated (boolean)
%%   must be loaded at all times
%%
%% - expiresUnixTime (integer, msecs)
%%
%% - labels( binary => binary | integer | boolean)
%%
%% - links (binary => binary)
%%
%% - linkedActors (binary => binary)    % Generated automatically
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
%% - nextStatusUnixTime (integer, msecs)
%%

-type metadata() ::
    #{
        binary() => binary() | integer() | float() | boolean()
    }.





%% ===================================================================
%% Public
%% ===================================================================


%% @doc
-spec get_actor(nkservice:id(), id()|pid()) ->
    {ok, actor()} | {error, term()}.

get_actor(SrvId, Id) ->
    nkservice_actor_srv:sync_op(SrvId, Id, get_actor).


%% @doc
-spec get_path(nkservice:id(), id()|pid()) ->
    {ok, map()} | {error, term()}.

get_path(SrvId, Id) ->
    case nkservice_actor_srv:sync_op(SrvId, Id, get_actor_id) of
        {ok, ActorId} ->
            {ok, nkservice_actor_util:actor_id_to_path(ActorId)};
        {error, Error} ->
            {error, Error}
    end.


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


%%%% @doc Updates an object's obj_name
%%-spec update_name(id()|pid(), binary()) ->
%%    ok | {error, term()}.
%%
%%update_name(Id, ObjName) ->
%%    nkservice_actor_srv:sync_op(Id, {update_name, ObjName}).


%% @doc Remove an object
-spec delete(nkservice:id(), id()|pid()) ->
    ok | {error, term()}.

delete(SrvId, Id) ->
    nkservice_actor_srv:sync_op(SrvId, Id, delete).


%% @doc Unloads the object
-spec unload(nkservice:id(), id()|pid()) ->
    ok | {error, term()}.

unload(SrvId, Id) ->
    unload(SrvId, Id, normal).


%% @doc Unloads the object
-spec unload(nkservice:id(), id()|pid(), Reason::nkservice:error()) ->
    ok | {error, term()}.

unload(SrvId, Id, Reason) ->
    nkservice_actor_srv:async_op(SrvId, Id, {unload, Reason}).


%% @doc
-spec search_classes(nkservice:id(), nkservice:id()) ->
    {ok, [{binary(), integer()}], Meta::map()} | {error, term()}.

search_classes(SrvId, Srv) ->
    nkservice_actor_db:aggregation(SrvId, {aggregation_core_classes, Srv}).


%% @doc Gets objects under a path, sorted by path
-spec search_paths(nkservce:id(), nkservice:id()) ->
    {ok, [#actor_id{}]} | {error, term()}.

search_paths(SrvId, Srv) ->
    nkservice_actor_db:search(SrvId, {search_core_paths, Srv}).


%% @doc Gets objects under a path, sorted by path
-spec search_paths_class(nkservce:id(), nkservice:id(), nkservice_actor:class()) ->
    {ok, [#actor_id{}]} | {error, term()}.

search_paths_class(SrvId, Srv, Class) ->
    nkservice_actor_db:search(SrvId, {search_core_paths_class, Srv, Class}).


%% @doc Gets objects under a path, sorted by path
-spec search_labels(nkservce:id(), nkservice:id(), nkservice_actor:class()) ->
    {ok, [#actor_id{}]} | {error, term()}.

search_labels(SrvId, Srv, Labels) ->
    nkservice_actor_db:search(SrvId, {search_core_labels, Srv, Labels}).


%% @doc Gets objects under a path, sorted by path
-spec search_linked(nkservce:id(), nkservice:id(), nkservice_actor:class()) ->
    {ok, [nkservice_actor:uid()]} | {error, term()}.

search_linked(SrvId, UID, Class) ->
    nkservice_actor_db:search(SrvId, {search_core_linked, UID, Class}).


%% @doc Gets objects under a path, sorted by path
-spec search_core_fts(nkservce:id(), nkservice:id(), binary()) ->
    {ok, [#actor_id{}]} | {error, term()}.

search_core_fts(SrvId, Srv, Word) ->
    nkservice_actor_db:search(SrvId, {search_core_fts, Srv, Word}).



