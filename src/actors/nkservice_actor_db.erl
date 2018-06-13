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

-export([find/1, find/2, read/1, read/2, activate/1, activate/2]).
-export([create/2, delete/1, delete/2]).
-export([search/2, search/3, aggregation/2, aggregation/3]).
-export([db_read/2]).
%%-export_type([search_obj/0, search_objs_opts/0]).

-include_lib("nkservice/include/nkservice.hrl").
-include_lib("nkservice/include/nkservice_actor.hrl").


-define(LLOG(Type, Txt, Args), lager:Type("NkSERVICE DB "++Txt, Args)).


%% ===================================================================
%% Types
%% ===================================================================


%%-type parser_fun() ::
%%    fun((nkservice_actor:actor()) -> {ok, nkservice_actor:actor()} | {error, nkservice_error:error()}).

-type opts() ::
#{
    db_srv => atom(),               % Service to use for database access
    ttl => integer(),               % For loading, changes default
    activate => boolean(),          % Active object on creation, read
    cascade => boolean(),           % For deletes, hard deletes, deletes all linked objects
    force => boolean()              % For hard delete, deletes even if linked objects
}.

-type search_type() :: term().

-type agg_type() :: term().

-type search_obj() :: #{binary() => term()}.

%-type iterate_fun() :: fun((search_obj()) -> {ok, term()}).

%-type aggregation_type() :: term().




%% ===================================================================
%% Public
%% ===================================================================



%% @doc Finds and actor from UUID or Path, in memory and disk
-spec find(nkservice_actor:id()) ->
    {ok, #actor_id{}, Meta::map()} | {error, actor_not_found|term()}.

find(Id) ->
    find(Id, #{}).


%% @doc Finds and actor from UUID or Path, in memory and disk
%% SrvId will be used for calling the bd backend
-spec find(nkservice_actor:id(), opts()) ->
    {ok, #actor_id{}, Meta::map()} | {error, actor_not_found|term()}.

find(Id, Opts) ->
    case id_to_actor_id(Id) of
        {ok, #actor_id{srv=ActorSrvId}=ActorId} ->
            case is_activated(ActorId) of
                {true, ActorId2} ->
                    {ok, ActorId2, #{}};
                false ->
                    SrvId = maps:get(db_srv, Opts, ActorSrvId),
                    case ?CALL_SRV(SrvId, actor_db_find, [SrvId, ActorId]) of
                        {ok, #actor_id{}=ActorId2, Meta} ->
                            % Check if it is loaded, set pid()
                            % 'unknown' is not possible here
                            case is_activated(ActorId2) of
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


%% @doc Reads an actor from memory if loaded, or disk if not
%% It will activate it
-spec read(nkservice_actor:id()) ->
    {ok, nkservice_actor:actor(), Meta::map()} |
    {deleted, nkservice_actor:actor()} |
    {error, term()}.

read(Id) ->
    read(Id, #{}).


%% @doc Reads an actor from memory if loaded, or disk if not
%% It will activate it unless indicated
-spec read(nkservice_actor:id(), opts()) ->
    {ok, nkservice_actor:actor(),  Meta::map()} | {error, actor_not_found|term()}.

read(Id, Opts) ->
    case id_to_actor_id(Id) of
        {ok, #actor_id{}=ActorId} ->
            case is_activated(ActorId) of
                {true, #actor_id{pid=Pid}} ->
                    case nkservice_actor_srv:sync_op(Pid, get_actor) of
                        {ok, Actor} ->
                            {ok, Actor, #{is_loaded=>true}};
                        {error, Error} ->
                            {error, Error}
                    end;
                false ->
                    case maps:get(activate, Opts, true) of
                        true ->
                            case activate(ActorId, Opts) of
                                {ok, #actor_id{pid=Pid}, Meta} ->
                                    case nkservice_actor_srv:sync_op(Pid, get_actor) of
                                        {ok, Actor} ->
                                            {ok, Actor, Meta#{is_loaded=>true}};
                                        {error, Error} ->
                                            {error, Error}
                                    end;
                                {error, Error} ->
                                    {error, Error}
                            end;
                        false ->
                            db_read(ActorId, Opts)
                    end
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc Finds an actors's pid or loads it from storage and activates it
-spec activate(nkservice_actor:id()) ->
    {ok, #actor_id{}, Meta::map()} | {error, actor_not_found|term()}.

activate(Id) ->
    activate(Id, #{}).


%% @doc Finds an actors's pid or loads it from storage
-spec activate(nkservice_actor:id(), opts()) ->
    {ok, #actor_id{}, Meta::map()} | {error, actor_not_found|term()}.

activate(Id, Opts) ->
    case id_to_actor_id(Id) of
        {ok, #actor_id{srv=ActorSrvId}=ActorId} ->
            case is_activated(ActorId) of
                {true, ActorId2} ->
                    {ok, ActorId2, #{}};
                _ ->
                    case db_read(ActorId, Opts) of
                        {ok, Actor, Meta2} ->
                            LoadOpts = load_opts(Opts),
                            case ?CALL_SRV(ActorSrvId, actor_activate, [Actor, LoadOpts]) of
                                {ok, Pid} ->
                                    ActorId2 = nkservice_actor_util:actor_to_actor_id(Actor),
                                    {ok, ActorId2#actor_id{pid=Pid}, Meta2};
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
create(Actor, Opts) ->
    case nkservice_actor_util:make(Actor, Opts) of
        {ok, #{srv:=ActorSrvId}=Actor2} ->
            case maps:get(activate, Opts, true) of
                true ->
                    LoadOpts1 = load_opts(Opts),
                    LoadOpts2 = LoadOpts1#{is_new=>true},
                    % Do we still need to load the object first, now that we
                    % have a consistent database?
                    case ?CALL_SRV(ActorSrvId, actor_activate, [Actor2, LoadOpts2]) of
                        {ok, Pid} ->
                            case nkservice_actor_srv:sync_op(Pid, get_actor) of
                                {ok, Actor3} ->
                                    {ok, Actor3};
                                {error, Error} ->
                                    {error, Error}
                            end;
                        {error, Error} ->
                            {error, Error}
                    end;
                false ->
                    case ?CALL_SRV(ActorSrvId, actor_db_create, [ActorSrvId, Actor2]) of
                        {ok, _Meta} ->
                            {ok, Actor2};
                        {error, Error} ->
                            {error, Error}
                    end
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc Deletes an actor
-spec delete(nkservice_actor:id()) ->
    ok | {error, actor_not_found|term()}.

delete(Id) ->
    delete(Id, #{}).


%% @doc Deletes an actor
-spec delete(nkservice_actor:id(), opts()) ->
    ok | {error, actor_not_found|term()}.

delete(Id, Opts) ->
    case find(Id, Opts) of
        {ok, #actor_id{srv=ActorSrvId, uid=UID, pid=Pid}, _Meta} ->
            case is_pid(Pid) of
                true ->
                    nkservice_actor_srv:actor_is_deleted(Pid);
                false ->
                    ok
            end,
            SrvId = maps:get(db_srv, Opts, ActorSrvId),
            case ?CALL_SRV(SrvId, actor_db_delete, [SrvId, UID, Opts]) of
                {ok, DeleteMeta} ->
                    {ok, DeleteMeta};
                {error, Error} ->
                    {error, Error}
            end;
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



%% ===================================================================
%% Internal
%% ===================================================================



%% @doc Gets a full #actor_id{} based on path or uid
%% If uid, and not cached, a service must be provided and db is hit
%% UID in returning #actor_id{} may be empty
%% CAN GENERATE ATOMS for the srv in ID
id_to_actor_id(#actor_id{}=ActorId) ->
    {ok, ActorId};

id_to_actor_id(Id) ->
    case nkservice_actor_util:is_path(Id) of
        {true, ActorId} ->
            {ok, ActorId};
        false ->
            UID = to_bin(Id),
            case nkservice_master:find_cached_actor(UID) of
                {ok, ActorId} ->
                    {ok, ActorId};
                {error, actor_not_found} ->
                    case nkservice_app:get_db_default_service() of
                        undefined ->
                            error(dbDefaultService_not_defined);
                        DefSrvId ->
                            case ?CALL_SRV(DefSrvId, nkservice_find_uid, [DefSrvId, UID]) of
                                {ok, ActorId, _} ->
                                    {ok, ActorId};
                                {error, Error} ->
                                    {error, Error}
                            end
                    end
            end
    end.



%% @doc Finds if an actor is currently activated
%% If true, full #actor_id{} will be returned (with uid and pid)
-spec is_activated(nkservice_actor:id()) ->
    {true, #actor_id{}} | false.

is_activated(#actor_id{}=ActorId) ->
    case nkservice_master:find_actor(ActorId) of
        {ok, #actor_id{pid=Pid}=ActorId2} when is_pid(Pid) ->
            {true, ActorId2};
        {error, _} ->
            false
    end.


%% @private
load_opts(Opts) ->
    case Opts of
        #{ttl:=TTL} ->
            #{config=>#{ttl=>TTL}};
        _ ->
            #{}
    end.


%% @private
db_read(Id, Opts) ->
    case id_to_actor_id(Id) of
        {ok, #actor_id{srv=ActorSrvId} = ActorId} ->
            SrvId = maps:get(db_srv, Opts, ActorSrvId),
            case ?CALL_SRV(SrvId, actor_db_read, [SrvId, ActorId]) of
                {ok, #{srv:=ActorSrvId, metadata:=Meta}=Actor, DbMeta} ->
                    case check_actor(ActorSrvId, Meta, Actor, Opts) of
                        ok ->
                            {ok, Actor, DbMeta};
                        removed ->
                            {error, actor_not_found}
                    end;
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.



%% @private
check_actor(SrvId, _Meta, Actor, #{parser:=Parser}) ->
    case Parser(Actor) of
        {ok, #{metadata:=Meta2}=Actor2} ->
            check_actor_expired(SrvId, Meta2, Actor2);
        {error, Error} ->
            {error, Error}
    end;

check_actor(SrvId, Meta, Actor, _Opts) ->
    check_actor_expired(SrvId, Meta, Actor).


%% @private
check_actor_expired(SrvId, #{<<"expiresTime">>:=Expires1}=Meta, Actor) ->
    {ok, Expires2} = nklib_date:quick_epoch(Expires1, msecs),
    Now = nklib_date:epoch(msecs),
    case Now > Expires2 of
        true ->
            ok = ?CALL_SRV(SrvId, actor_do_expired, [Actor]),
            removed;
        false ->
            check_actor_active(SrvId, Meta, Actor)
    end;

check_actor_expired(SrvId, Meta, Actor) ->
    check_actor_active(SrvId, Meta, Actor).


%% @private
check_actor_active(SrvId, #{<<"isActivated">>:=true}, Actor) ->
    case ?CALL_SRV(SrvId, actor_do_active, [Actor]) of
        ok ->
            ok;
%%        processed ->
%%            ok;
        removed ->
            removed
    end;

check_actor_active(_SrvId, _Meta, _Actor) ->
    ok.


%% @private
to_bin(T) when is_binary(T)-> T;
to_bin(T) -> nklib_util:to_binary(T).
