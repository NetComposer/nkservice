%% -------------------------------------------------------------------
%%
%% srvCopyright (c) 2018 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc Actor DB-related module
-module(nkservice_actor_db).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([find/2, is_activated/2, read/3, activate/3]).
-export([create/3, delete/3, delete_multi/2, update/3]).
-export([search/2, search/3, aggregation/2, aggregation/3]).
-export([check_service/4]).
%%-export_type([search_obj/0, search_objs_opts/0]).

-include_lib("nkservice/include/nkservice.hrl").
-include_lib("nkservice/include/nkservice_actor.hrl").


-define(LLOG(Type, Txt, Args), lager:Type("NkSERVICE DB "++Txt, Args)).

%% ===================================================================
%% Types
%% ===================================================================


%%-type parser_fun() ::
%%    fun((nkservice_actor:actor()) -> {ok, nkservice_actor:actor()} | {error, nkservice_msg:msg()}).

-type opts() ::
#{
    ttl => integer(),               % For loading, changes default
    consume => boolean(),           % Remove actor after read (default: false)
    update_opts => nkservice_actor:update_opts(),
    cascade => boolean(),           % For deletes, hard deletes, deletes all linked objects
    force => boolean()              % For hard delete, deletes even if linked objects
}.

-type search_type() :: term().

-type agg_type() :: term().

-type search_obj() :: #{binary() => term()}.

%-type iterate_fun() :: fun((search_obj()) -> {ok, term()}).

%-type aggregation_type() :: term().


-type service_info() ::
    #{
        cluster => binary(),
        node => atom(),
        updated => nklib_date:epoch(secs),
        pid => pid()
    }.



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Finds and actor from UUID or Path, in memory and disk
%% It also checks if it is currently activated, returning the pid
%% SrvId is be used for calling the DB backend and finding UID if necessary
-spec find(nkservice:id(), nkservice_actor:id()) ->
    {ok, #actor_id{}, Meta::map()} | {error, actor_not_found|term()}.

find(SrvId, Id) ->
    case id_to_actor_id(SrvId, Id) of
        {ok, #actor_id{pid=Pid}=ActorId} when is_pid(Pid) ->
            {ok, ActorId, #{}};
        {ok, ActorId} ->
            case is_activated(SrvId, ActorId) of
                {true, ActorId2} ->
                    {ok, ActorId2, #{}};
                false ->
                    case ?CALL_SRV(SrvId, actor_db_find, [SrvId, ActorId]) of
                        {ok, #actor_id{}=ActorId2, Meta} ->
                            % Check if it is loaded, set pid()
                            case is_activated(SrvId, ActorId2) of
                                {true, ActorId3} ->
                                    {ok, ActorId3, Meta};
                                false ->
                                    {ok, ActorId2, Meta}
                            end;
                        {error, Error} ->
                            {error, Error}
                    end
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc Checks if an actor is currently activated
%% If true, full #actor_id{} will be returned (with uid and pid)
%% SrvId is only used to find the UID if necessary
-spec is_activated(nkservice:id(), nkservice_actor:id()) ->
    {true, #actor_id{}} | false.

is_activated(SrvId, Id) ->
    case id_to_actor_id(SrvId, Id) of
        {ok, #actor_id{pid=Pid}=ActorId} when is_pid(Pid) ->
            {true, ActorId};
        {ok, ActorId} ->
            case ?CALL_SRV(SrvId, actor_is_activated, [SrvId, ActorId]) of
                {true, #actor_id{pid=Pid}=ActorId2} when is_pid(Pid) ->
                    {true, ActorId2};
                false ->
                    false
            end;
        _ ->
            false
    end.


%% @doc Reads an actor from memory if loaded, or disk if not
%% It will first try to activate it (unless indicated)
%% If consume is set, it will destroy the object on read
%% SrvId is used for calling the DB
-spec read(nkservice:id(), nkservice_actor:id(), opts()) ->
    {ok, nkservice_actor:actor(),  Meta::map()} | {error, actor_not_found|term()}.

read(SrvId, Id, Opts) ->
    Consume = maps:get(consume, Opts, false),
    Op = case Consume of
        true ->
            consume_actor;
        false ->
            get_actor
    end,
    case id_to_actor_id(SrvId, Id) of
        {ok, #actor_id{pid=Pid}=ActorId} when is_pid(Pid) ->
            case nkservice_actor_srv:sync_op(SrvId, ActorId, Op) of
                {ok, Actor} ->
                    {ok, Actor, #{}};
                {error, Error} ->
                    {error, Error}
            end;
        {ok, ActorId} ->
            case is_activated(SrvId, ActorId) of
                {true, ActorId2} ->
                    case nkservice_actor_srv:sync_op(SrvId, ActorId2, Op) of
                        {ok, Actor} ->
                            {ok, Actor, #{}};
                        {error, Error} ->
                            {error, Error}
                    end;
                false ->
                    case maps:get(activate, Opts, true) of
                        true ->
                            case activate(SrvId, ActorId, Opts) of
                                {ok, ActorId2, Meta} ->
                                    case nkservice_actor_srv:sync_op(SrvId, ActorId2, Op) of
                                        {ok, Actor} ->
                                            {ok, Actor, Meta};
                                        {error, Error} ->
                                            {error, Error}
                                    end;
                                {error, Error} ->
                                    {error, Error}
                            end;
                        false when Consume ->
                            {error, cannot_consume};
                        false ->
                            db_read(SrvId, ActorId)
                    end
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc Finds an actors's pid or loads it from storage and activates it
%% Option 'ttl' can be used
-spec activate(nkservice:id(), nkservice_actor:id(), opts()) ->
    {ok, #actor_id{}, Meta::map()} | {error, actor_not_found|term()}.

activate(SrvId, Id, Opts) ->
    case id_to_actor_id(SrvId, Id) of
        {ok, #actor_id{pid=Pid}=ActorId} when is_pid(Pid) ->
            {ok, ActorId, #{}};
        {ok, ActorId} ->
            case is_activated(SrvId, ActorId) of
                {true, ActorId2} ->
                    {ok, ActorId2, #{}};
                _ ->
                    case db_read(SrvId, ActorId) of
                        {ok, Actor2, Meta2} ->
                            case
                                ?CALL_SRV(SrvId, actor_activate, [SrvId, Actor2, Opts])
                            of
                                {ok, ActorId3} ->
                                    {ok, ActorId3, Meta2};
                                {error, Error} ->
                                    {error, Error}
                            end;
                        {error, Error} ->
                            {error, Error}
                    end
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc Creates a brand new actor
%% It will activate the object, unless indicated
%% ¡¡Must call nkservice_actor_util:check_create_fields(Actor) before!!
create(SrvId, Actor, Opts) ->
    case nkservice_actor_util:check_links(SrvId, Actor) of
        {ok, #actor{}=Actor2} ->
            case maps:get(activate, Opts, true) of
                true ->
                    % If we use the activate option, the object is first
                    % registered with leader, so you cannot have two with same
                    % name even on non-relational databases
                    % The process will send the 'create' event in-server
                    case ?CALL_SRV(SrvId, actor_create, [SrvId, Actor2, Opts]) of
                        {ok, #actor_id{pid=Pid}=ActorId} when is_pid(Pid) ->
                            case nkservice_actor_srv:sync_op(SrvId, ActorId, get_actor) of
                                {ok, Actor3} ->
                                    {ok, Actor3, #{}};
                                {error, Error} ->
                                    {error, Error}
                            end;
                        {error, actor_already_registered} ->
                            {error, uniqueness_violation};
                        {error, Error} ->
                            {error, Error}
                    end;
                false ->
                    % Non recommended for non-relational databases, if name is not
                    % randomly generated
                    case ?CALL_SRV(SrvId, actor_db_create, [SrvId, Actor2]) of
                        {ok, Meta} ->
                            % Use the alternative method for sending the event
                            nkservice_actor_util:send_external_event(SrvId, created, Actor2),
                            {ok, Actor2, Meta};
                        {error, Error} ->
                            {error, Error}
                    end
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc Updates an actor
%% It will activate the object, unless indicated
update(SrvId, Actor, Opts) ->
    case maps:get(activate, Opts, true) of
        true ->
            case activate(SrvId, Actor, Opts) of
                {ok, ActorId, _} ->
                    UpdOpts = maps:get(update_opts, Opts, #{}),
                    case nkservice_actor:update(SrvId, ActorId, Actor, UpdOpts) of
                        ok ->
                            {ok, Actor2} = nkservice_actor_srv:sync_op(SrvId, ActorId, get_actor),
                            {ok, Actor2, #{}};
                        {error, Error} ->
                            {error, Error}
                    end;
                {error, Error} ->
                    {error, Error}
            end;
        false ->
            % TODO: perform the manual update?
            % nkservice_actor_util:send_external_event(SrvId, update, Actor2),
            {error, update_not_implemented}
    end.


%% @doc Deletes an actor
%% Uses options srv_db, cascade

-spec delete(nkservice:id(), nkservice_actor:id(), opts()) ->
    {ok, [#actor_id{}], map()} | {error, actor_not_found|term()}.

delete(SrvId, Id, Opts) ->
    case find(SrvId, Id) of
        {ok, #actor_id{uid=UID, pid=Pid}=ActorId, _Meta} ->
            case maps:get(cascade, Opts, false) of
                false when is_pid(Pid) ->
                    case nkservice_actor_srv:sync_op(SrvId, ActorId, delete) of
                        ok ->
                            % The object is loaded, and it will perform the delete
                            % itself, including sending the event (a full event)
                            % It will stop, and when the backend calls raw_stop/2
                            % the actor would not be activated, unless it is
                            % reactivated in the middle, and would stop without saving
                            {ok, ActorId, #{}};
                        {error, Error} ->
                            {error, Error}
                    end;
                Cascade ->
                    % The actor is not activated or we want cascade deletion
                    Opts2 = #{cascade => Cascade},
                    % Implementation must call nkservice_actor_srv:raw_stop/2
                    case ?CALL_SRV(SrvId, actor_db_delete, [SrvId, UID, Opts2]) of
                        {ok, ActorIds, DeleteMeta} ->
                            % In this case, we must send the deleted events
                            lists:foreach(
                                fun(AId) ->
                                    FakeActor = #actor{id=AId},
                                    nkservice_actor_util:send_external_event(SrvId, deleted, FakeActor)
                                end,
                                ActorIds),
                            {ok, ActorIds, DeleteMeta};
                        {error, Error} ->
                            {error, Error}
                    end
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc
%% Deletes a number of UIDs and send events
%% Loaded objects wil be unloaded
delete_multi(SrvId, UIDs) ->
    % Implementation must call nkservice_actor_srv:raw_stop/2
    case ?CALL_SRV(SrvId, actor_db_delete, [SrvId, UIDs, #{}]) of
        {ok, ActorIds, DeleteMeta} ->
            lists:foreach(
                fun(AId) ->
                    FakeActor = #actor{id=AId},
                    nkservice_actor_util:send_external_event(SrvId, deleted, FakeActor)
                end,
                ActorIds),
            {ok, ActorIds, DeleteMeta};
        {error, Error} ->
            {error, Error}
    end.



%% @doc
-spec search(nkservice:id(), search_type()) ->
    {ok, [search_obj()], Meta::map()} | {error, term()}.

search(SrvId, SearchType) ->
    search(SrvId, SearchType, #{}).


%% @doc
-spec search(nkservice:id(), search_type(), opts()) ->
    {ok, [search_obj()], Meta::map()} | {error, term()}.

search(SrvId, SearchType, Opts) ->
    ?CALL_SRV(SrvId, actor_db_search, [SrvId, SearchType, Opts]).


%%%% @doc Internal iteration
%%-spec iterate(type()|core, search_type(), iterate_fun(), term()) ->
%%    {ok, term()} | {error, term()}.
%%
%%iterate(Type, SearchType, Fun, Acc) ->
%%    iterate(Type, SearchType, Fun, Acc, #{}).
%%
%%
%%%% @doc
%%-spec iterate(type()|core, search_type(), iterate_fun(), term(), opts()) ->
%%    {ok, term()} | {error, term()}.
%%
%%iterate(Type, SearchType, Fun, Acc, Opts) ->
%%    SrvId = maps:get(srv, Opts, ?ROOT_DOMAIN),
%%    ?CALL_SRV(SrvId, actor_db_iterate_objs, [SrvId, Type, SearchType, Fun, Acc, Opts]).
%%
%%
%% @doc Internal aggregation
-spec aggregation(nkservice:id(), agg_type()) ->
    {ok, [{binary(), integer()}], Meta::map()} | {error, term()}.

aggregation(SrvId, AggType) ->
    aggregation(SrvId, AggType, #{}).


%% @doc
-spec aggregation(nkservice:id(), agg_type(), opts()) ->
    {ok, [{binary(), integer()}], Meta::map()} | {error, term()}.

aggregation(SrvId, AggType, Opts) ->
    ?CALL_SRV(SrvId, actor_db_aggregate, [SrvId, AggType, Opts]).

%% @doc Check if the info on database for service is up to date, and update it
%% - If the current info belongs to us (or it is missing), the time is updated
%% - If the info does not belong to us, but it is old (more than serviceDbMaxHeartbeatTime)
%%   it is overwritten
%% - If it is recent, and error alternate_service is returned

-spec check_service(nkservice:id(), nkservice:id(), binary(), integer()) ->
    ok | {alternate_service, service_info()} | {error, term()}.

check_service(SrvId, ActorSrvId, Cluster, MaxTime) ->
    Node = node(),
    Pid = self(),
    case ?CALL_SRV(SrvId, actor_db_get_service, [SrvId, ActorSrvId]) of
        {ok, #{cluster:=Cluster, node:=Node, pid:=Pid}, _} ->
            check_service_update(SrvId, ActorSrvId, Cluster);
        {ok, #{updated:=Updated}=Info, _} ->
            Now = nklib_date:epoch(secs),
            case Now - Updated < (MaxTime div 1000) of
                true ->
                    % It is recent, we consider it valid
                    {alternate_service, Info};
                false ->
                    % Too old, we overwrite it
                    check_service_update(SrvId, ActorSrvId, Cluster)
            end;
        {error, service_not_found} ->
            check_service_update(SrvId, ActorSrvId, Cluster);
        {error, Error} ->
            {error, Error}
    end.


%% @private
check_service_update(SrvId, ActorSrvId, Cluster) ->
    case ?CALL_SRV(SrvId, actor_db_update_service, [SrvId, ActorSrvId, Cluster]) of
        {ok, _} ->
            ok;
        {error, Error} ->
            {error, Error}
    end.





%% ===================================================================
%% Internal
%% ===================================================================


%% @doc Gets a full #actor_id{} based on path, #actor_id{} or uid
%% It will remove the pid if present (we don't know if it is correct)
%% Can add pid if cached (only for UIDs)
id_to_actor_id(_SrvId, #actor_id{}=ActorId) ->
    {ok, ActorId#actor_id{pid=undefined}};

id_to_actor_id(_SrvId, #actor{id=#actor_id{}=ActorId}) ->
    {ok, ActorId#actor_id{pid=undefined}};

id_to_actor_id(SrvId, Id) ->
    case nkservice_actor_util:is_actor_id(Id) of
        {true, #actor_id{}=ActorId} ->
            {ok, ActorId};
        false ->
            % It is an UID
            case ?CALL_SRV(SrvId, actor_is_activated, [SrvId, Id]) of
                {true, ActorId} ->
                    {ok, ActorId};      % Has pid
                false ->
                    case ?CALL_SRV(SrvId, actor_db_find, [SrvId, Id]) of
                        {ok, #actor_id{}=ActorId, _Meta} ->
                            {ok, ActorId};
                        {error, Error} ->
                            {error, Error}
                    end
            end

    end.


%% @private
db_read(SrvId, Id) ->
    case id_to_actor_id(SrvId, Id) of
        {ok, ActorId} ->
            case ?CALL_SRV(SrvId, actor_db_read, [SrvId, ActorId]) of
                {ok, #actor{}=Actor, DbMeta} ->
                    {ok, Actor, DbMeta};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.


%%%% @private
%%to_bin(T) when is_binary(T)-> T;
%%to_bin(T) -> nklib_util:to_binary(T).
