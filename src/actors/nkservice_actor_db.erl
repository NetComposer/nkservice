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

-export([find/1, is_activated/1, read/2, db_read/1, activate/2]).
-export([create/3, delete/2, delete_multi/2, update/3]).
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
    actor_config => nkservice_actor:config(),
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


%% @doc Finds and actor from UUID or Path, in memory or disk
%% It also checks if it is currently activated, returning the pid
%% Id must use the form including the service to find unloaded UIDs
-spec find(nkservice_actor:id()) ->
    {ok, #actor_id{}, Meta::map()} | {error, actor_not_found|term()}.

find(Id) ->
    case id_to_actor_id(Id) of
        {ok, _SrvId, #actor_id{pid=Pid}=ActorId} when is_pid(Pid) ->
            {ok, ActorId, #{}};
        {ok, SrvId, #actor_id{}=ActorId} ->
            case ?CALL_SRV(SrvId, actor_db_find, [SrvId, ActorId]) of
                {ok, #actor_id{}=ActorId2, Meta} ->
                    % Check if it is loaded, set pid()
                    case is_activated({SrvId, ActorId2}) of
                        {true, ActorId3} ->
                            {ok, ActorId3, Meta};
                        false ->
                            {ok, ActorId2, Meta}
                    end;
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc Checks if an actor is currently activated
%% If true, full #actor_id{} will be returned (with uid and pid)
%% SrvId is only used to find the UID if necessary
-spec is_activated(nkservice_actor:id()) ->
    {true, #actor_id{}} | false.

is_activated(Id) ->
    case id_to_actor_id(Id) of
        {ok, _SrvId, #actor_id{pid=Pid}=ActorId} when is_pid(Pid) ->
            {true, ActorId};
        _ ->
            false
    end.


%% @doc Finds an actors's pid or loads it from storage and activates it
%% Option 'ttl' can be used
-spec activate(nkservice_actor:id(), opts()) ->
    {ok, #actor_id{}, Meta::map()} | {error, actor_not_found|term()}.

activate(Id, Opts) ->
    case id_to_actor_id(Id) of
        {ok, _SrvId, #actor_id{pid=Pid}=ActorId} when is_pid(Pid) ->
            {ok, ActorId, #{}};
        {ok, SrvId, ActorId} ->
            case db_read({SrvId, ActorId}) of
                {ok, Actor2, Meta2} ->
                    Config = maps:get(actor_config, Opts, #{}),
                    case
                        ?CALL_SRV(SrvId, actor_activate, [SrvId, Actor2, Config])
                    of
                        {ok, ActorId3} ->
                            {ok, ActorId3, Meta2};
                        {error, Error} ->
                            {error, Error}
                    end;
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.



%% @doc Reads an actor from memory if loaded, or disk if not
%% It will first try to activate it (unless indicated)
%% If consume is set, it will destroy the object on read
%% SrvId is used for calling the DB
-spec read(nkservice_actor:id(), opts()) ->
    {ok, nkservice_actor:actor(),  Meta::map()} | {error, actor_not_found|term()}.

read(Id, Opts) ->
    Consume = maps:get(consume, Opts, false),
    Op = case Consume of
        true ->
            consume_actor;
        false ->
            get_actor
    end,
    case id_to_actor_id(Id) of
        {ok, SrvId, #actor_id{pid=Pid}=ActorId} when is_pid(Pid) ->
            case nkservice_actor_srv:sync_op({SrvId, ActorId}, Op) of
                {ok, Actor} ->
                    {ok, Actor, #{}};
                {error, Error} ->
                    {error, Error}
            end;
        {ok, SrvId, ActorId} ->
            case maps:get(activate, Opts, true) of
                true ->
                    case activate({SrvId, ActorId}, Opts) of
                        {ok, ActorId2, Meta} ->
                            case nkservice_actor_srv:sync_op({SrvId, ActorId2}, Op) of
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
                    db_read({SrvId, ActorId})
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc Creates a brand new actor
%% It will activate the object, unless indicated
%% ¡¡Must call nkservice_actor_util:check_create_fields(Actor) before!!
create(SrvId, #actor{}=Actor, Opts) ->
    case nkservice_actor_util:check_links(SrvId, Actor) of
        {ok, #actor{}=Actor2} ->
            case maps:get(activate, Opts, true) of
                true ->
                    % If we use the activate option, the object is first
                    % registered with leader, so you cannot have two with same
                    % name even on non-relational databases
                    % The process will send the 'create' event in-server
                    Config = maps:get(actor_config, Opts, #{}),
                    case ?CALL_SRV(SrvId, actor_create, [SrvId, Actor2, Config]) of
                        {ok, #actor_id{pid=Pid}=ActorId} when is_pid(Pid) ->
                            case nkservice_actor_srv:sync_op({SrvId, ActorId}, get_actor) of
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
update(SrvId, #actor{id=ActorId}=Actor, Opts) ->
    case maps:get(activate, Opts, true) of
        true ->
            case activate({SrvId, ActorId}, Opts) of
                {ok, ActorId2, _} ->
                    UpdOpts = maps:get(update_opts, Opts, #{}),
                    case nkservice_actor:update({SrvId, ActorId2}, Actor, UpdOpts) of
                        ok ->
                            {ok, Actor2} = nkservice_actor_srv:sync_op({SrvId, ActorId2}, get_actor),
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

-spec delete(nkservice_actor:id(), opts()) ->
    {ok, [#actor_id{}], map()} | {error, actor_not_found|term()}.

delete(Id, Opts) ->
    case id_to_actor_id(Id) of
        {ok, SrvId, ActorId} ->
            case find({SrvId, ActorId}) of
                {ok, #actor_id{uid=UID, pid=Pid}=ActorId2, _Meta} ->
                    case maps:get(cascade, Opts, false) of
                        false when is_pid(Pid) ->
                            case nkservice_actor_srv:sync_op({SrvId, ActorId2}, delete) of
                                ok ->
                                    % The object is loaded, and it will perform the delete
                                    % itself, including sending the event (a full event)
                                    % It will stop, and when the backend calls raw_stop/2
                                    % the actor would not be activated, unless it is
                                    % reactivated in the middle, and would stop without saving
                                    {ok, ActorId2, #{}};
                                {error, Error} ->
                                    {error, Error}
                            end;
                        Cascade ->
                            % The actor is not activated or we want cascade deletion
                            Opts2 = #{cascade => Cascade},
                            % Implementation must call nkservice_actor_srv:raw_stop/1
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
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc
%% Deletes a number of UIDs and send events
%% Loaded objects wil be unloaded
delete_multi(SrvId, UIDs) ->
    % Implementation must call nkservice_actor_srv:raw_stop/1
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
%% If it is cached at this node, it will have its pid
%% If not cached, it will ask calling actor_find_registered
%% If it is an UID, and not registered, it will be searched on disk calling
%% actor_db_find
id_to_actor_id(Id) ->
    case nkservice_actor_util:id_to_actor_id(Id) of
        {ok, SrvId, #actor_id{}=ActorId} ->
            case nkservice_actor_register:find_registered({SrvId, ActorId}) of
                {true, ActorId2} ->
                    {ok, SrvId, ActorId2};
                false ->
                    %% We don't know if the pid is correct
                    {ok, SrvId, ActorId#actor_id{pid=undefined}}
            end;
        {ok, SrvId, UID} ->
            case nkservice_actor_register:find_registered({SrvId, UID}) of
                {true, ActorId2} ->
                    {ok, SrvId, ActorId2};
                false ->
                    case ?CALL_SRV(SrvId, actor_db_find, [SrvId, UID]) of
                        {ok, #actor_id{}=ActorId, _Meta} ->
                            id_to_actor_id({SrvId, ActorId});
                        {error, actor_db_not_implemented} ->
                            {error, actor_not_found};
                        {error, Error} ->
                            {error, Error}
                    end
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @private
db_read(Id) ->
    case id_to_actor_id(Id) of
        {ok, SrvId, ActorId} ->
            case ?CALL_SRV(SrvId, actor_db_read, [SrvId, ActorId]) of
                {ok, #actor{}=Actor, DbMeta} ->
                    {ok, Actor, DbMeta};
                {error, actor_db_not_implemented} ->
                    {error, actor_not_found};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.


%%%% @private
%%to_bin(T) when is_binary(T)-> T;
%%to_bin(T) -> nklib_util:to_binary(T).
