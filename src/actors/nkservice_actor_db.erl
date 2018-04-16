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

-export([find/2, find/3, is_loaded/2, read/2, read/3, load/2, load/3]).
-export([delete/2, delete/3, hard_delete/2, hard_delete/3]).
-export([search/2, search/3, aggregation/2, aggregation/3]).
%%-export_type([search_obj/0, search_objs_opts/0]).

-include_lib("nkservice/include/nkservice.hrl").
-include_lib("nkservice/include/nkservice_actor.hrl").


-define(LLOG(Type, Txt, Args), lager:Type("NkSERVICE DB "++Txt, Args)).


%% ===================================================================
%% Types
%% ===================================================================

-type opts() ::
#{
    srv => atom(),                  % Service to use for searching, loading, etc.
    get_deleted => boolean(),
    ttl => integer(),               % For loading
    cascade => boolean(),           % For hard deletes, deletes all linked objects
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


%% @private Find a loaded Actor by uid() or path()
%% By uid(), will not find it is started at another node
-spec is_loaded(nkservice:id(), nkservice_actor:id()|#actor_id{}) ->
    {ok, #actor_id{}} | {error, actor_not_found|term()}.

is_loaded(SrvId, #actor_id{}=ActorId) ->
    % If we have a srv id, we can check for sure
    case nkservice_master:find_actor(SrvId, ActorId) of
        {ok, ActorId2} ->
            {true, ActorId2};
        {error, _} ->
            false
    end;

is_loaded(SrvId, Id) ->
    case nkservice_actor_util:is_path(Id) of
        {true, #actor_id{}=ActorId} ->
            is_loaded(SrvId, ActorId);
        {false, UID} ->
            % We may fail to find the object if it is loaded at other node
            case nkservice_master:find_cached_actor(UID) of
                {ok, ActorId} ->
                    {true, ActorId};
                _ ->
                    false
            end
    end.



%% @doc Finds and actor from UUID or Path, in memory and disk
-spec find(nkservice:id(), nkservice_actor:id()) ->
    {ok, #actor_id{}, Meta::map()} | {error, actor_not_found|term()}.

find(SrvId, Id) ->
    find(SrvId, Id, #{}).


%% @doc Finds and actor using a service's functions
-spec find(nkservice:id(), nkservice_actor:id(), opts()) ->
    {ok, #actor_id{}, Meta::map()} | {error, actor_not_found|term()}.

find(SrvId, Id, _Opts) ->
    case is_loaded(SrvId, Id) of
        {true, ActorId} ->
            {ok, ActorId, #{}};
        false ->
            case ?CALL_SRV(SrvId, actor_db_find, [SrvId, to_bin(Id)]) of
                {ok, ActorId, Meta} ->
                    % Check if it is loaded, set pid()
                    case is_loaded(SrvId, ActorId) of
                        {true, ActorId2} ->
                            {ok, ActorId2, Meta};
                        false ->
                            {ok, ActorId, Meta}
                    end;
                {error, Error} ->
                    {error, Error}
            end
    end.




%% @doc Reads an actor from memory if loaded, or disk if not
-spec read(nkservice:id(), nkservice_actor:id()) ->
    {ok, #actor_id{}, nkdomain:obj(), Meta::map()} |
    {deleted, #actor_id{}, nkdomain:obj()} |
    {error, term()}.

read(SrvId, Id) ->
    read(SrvId, Id, #{}).


%% @doc Reads an actor from memory if loaded, or disk if not
-spec read(nkservice:id(), nkservice_actor:id(), opts()) ->
    {ok, nkservice_actor:actor(),  Meta::map()} | {error, actor_not_found|term()}.

read(SrvId, Id, Opts) ->
    case find(SrvId, Id, Opts) of
        {ok, #actor_id{pid=Pid}, _Meta} when is_pid(Pid) ->
            case nkservice_actor_srv:sync_op(Pid, get_actor) of
                {ok, Actor} ->
                    {ok, Actor, #{}};
                {error, Error} ->
                    {error, Error}
            end;
        {ok, #actor_id{uid=UID}, _Meta} ->
            do_read(SrvId, UID, Opts);
        {error, actor_not_found} ->
            do_read(SrvId, Id, Opts);
        {error, Error} ->
            {error, Error}
    end.


%% @doc Finds an actors's pid or loads it from storage
-spec load(nkservice:id(), nkdomain:id()) ->
    {ok, nkservice:actor()} | {error, actor_not_found|term()}.

load(SrvId, Id) ->
    load(SrvId, Id, #{}).


%% @doc Finds an actors's pid or loads it from storage
-spec load(nkservice:id(), nkdomain:id(), opts()) ->
    {ok, #actor_id{}, Meta::map()} | {error, actor_not_found|term()}.

load(SrvId, Id, Opts) ->
    case find(SrvId, Id, Opts) of
        {ok, #actor_id{pid=Pid}=ActorId, Meta} when is_pid(Pid) ->
            {ok, ActorId, Meta};
        {ok, #actor_id{uid=UID}=ActorId, _Meta} ->
            case do_read(SrvId, UID, Opts#{get_deleted=>false}) of
                {ok, Actor, Meta2} ->
                    LoadOpts = maps:with([ttl], Opts),
                    case nkservice_actor_srv:start(Actor, LoadOpts) of
                        {ok, Pid} ->
                            {ok, ActorId#actor_id{pid=Pid}, Meta2};
                        {error, Error} ->
                            {error, Error}
                    end;
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc Marks an actor as deleted
-spec delete(nkservice:id(), nkdomain:id()) ->
    ok | {error, actor_not_found|term()}.

delete(SrvId, Id) ->
    delete(SrvId, Id, #{}).


%% @doc Marks an actor as deleted
-spec delete(nkservice:id(), nkdomain:id(), opts()) ->
    {ok, Meta::map()} | {error, actor_not_found|term()}.

delete(SrvId, Id, Opts) ->
    case find(SrvId, Id, Opts#{get_deleted=>false}) of
        {ok, #actor_id{uid=UID, pid=Pid}, _} ->
            case is_pid(Pid) of
                true ->
                    nkservice_actor_srv:actor_is_deleted(Pid);
                false ->
                    ok
            end,
            case ?CALL_SRV(SrvId, actor_db_read, [SrvId, UID]) of
                {ok, #{metadata:=Meta}=Actor, _Meta} ->
                    case Meta of
                        #{<<"isDeleted">>:=true} ->
                            {error, actor_already_deleted};
                        _ ->
                            {ok, Time} = nklib_util:rfc3339_m(),
                            Meta2 = Meta#{
                                <<"isDeleted">> => true,
                                <<"deletionDate">> => Time
                            },
                            Meta3 = maps:without([
                                <<"isEnabled">>,
                                <<"isActive">>,
                                <<"expiresUnixTime">>,
                                <<"isInAlaram">>,
                                <<"alarms">>
                            ], Meta2),
                            Actor3 = Actor#{metadata:=Meta3},
                            case ?CALL_SRV(SrvId, actor_db_update, [SrvId, Actor3]) of
                                {ok, SaveMeta} ->
                                    {ok, SaveMeta};
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



%% @doc Marks an actor as deleted
-spec hard_delete(nkservice:id(), nkdomain:id()) ->
    ok | {error, actor_not_found|term()}.

hard_delete(SrvId, Id) ->
    hard_delete(SrvId, Id, #{}).


%% @doc Marks an actor as hard_deleted
-spec hard_delete(nkservice:id(), nkdomain:id(), opts()) ->
    ok | {error, actor_not_found|term()}.

hard_delete(SrvId, Id, Opts) ->
    case find(SrvId, Id, Opts#{get_deleted=>true}) of
        {ok, #actor_id{uid=UID, pid=Pid}, _Meta} ->
            case is_pid(Pid) of
                true ->
                    nkservice_actor_srv:actor_is_deleted(Pid);
                false ->
                    ok
            end,
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
    ?CALL_SRV(SrvId, actor_db_aggregation, [SrvId, AggType, Opts]).



%% ===================================================================
%% Internal
%% ===================================================================


%% @private
do_read(SrvId, Id, Opts) ->
    case ?CALL_SRV(SrvId, actor_db_read, [SrvId, Id]) of
        {ok, #{metadata:=#{<<"isDeleted">>:=true}}=Actor, Meta} ->
            case Opts of
                #{get_deleted:=true} ->
                    % Removed parse
                    {deleted, Actor, Meta};
                _ ->
                    {error, actor_not_found}
            end;
        {ok, Actor, Meta} ->
            % Removed parse
            case check_actor(Actor) of
                ok ->
                    {ok, Actor, Meta};
                removed ->
                    {error, actor_not_found}
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @private
check_actor(#{srv:=SrvId, metadata:=Meta}=Actor) ->
    check_actor_expired(SrvId, Meta, Actor).


%% @private
check_actor_expired(SrvId, #{<<"expiresUnixTime">>:=Expires}=Meta, Actor) ->
    Now = nklib_util:m_timestamp(),
    case Now > Expires of
        true ->
            ok = ?CALL_SRV(SrvId, actor_do_expired, [Actor]),
            removed;
        false ->
            check_actor_expired(SrvId, Meta, Actor)
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
