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

-module(nkservice_pgsql_actors).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([init/2]).
-export([find/3, load/3, save/4, delete/4, search/4, aggregation/4]).
-export([get_links/4, get_linked/4]).
-export([query/3, query/4]).
-export_type([result_fun/0]).

-include("nkservice.hrl").
-include("nkservice_actor.hrl").



-define(LLOG(Type, Txt, Args), lager:Type("NkSERVICE PGSQL Actors "++Txt, Args)).



%% ===================================================================
%% Types
%% ===================================================================

-type result_fun() :: fun(([[tuple()]], map()) -> {ok, term(), map()} | {error, term()}).



%% ===================================================================
%% API
%% ===================================================================


init(SrvId, PackageId) ->
    query(SrvId, PackageId, create_database(), #{}).



%% TODO: we need to re-create all connections or it will not know about the new database
create_database() ->
    <<"
        DROP TABLE IF EXISTS versions CASCADE;
        DROP TABLE IF EXISTS actors CASCADE;
        DROP TABLE IF EXISTS links CASCADE;
        DROP TABLE IF EXISTS fts CASCADE;
        CREATE TABLE versions (
            id STRING PRIMARY KEY NOT NULL,
            version STRING NOT NULL
        );
        CREATE TABLE actors (
            uid STRING PRIMARY KEY NOT NULL,
            srv STRING NOT NULL,
            class STRING NOT NULL,
            name STRING NOT NULL,
            spec JSONB,
            metadata JSONB,
            path STRING NOT NULL,
            last_update INT NOT NULL,
            expires_time INT,
            UNIQUE INDEX name_idx (srv, class, name),
            INDEX path_idx (path, class),
            INDEX last_update_idx (last_update),
            INDEX expires_time_idx (expires_time),
            INVERTED INDEX spec_idx (spec),
            INVERTED INDEX metadata_idx (metadata)
        );
        INSERT INTO versions VALUES ('actors', '1');
        CREATE TABLE links (
            target STRING NOT NULL,
            link_type STRING NOT NULL,
            orig STRING NOT NULL,
            PRIMARY KEY (target, link_type, orig)
        );
        INSERT INTO versions VALUES ('links', '1');
        CREATE TABLE fts (
            word STRING NOT NULL,
            uid STRING NOT NULL,
            path STRING NOT NULL,
            class STRING NOT NULL,
            PRIMARY KEY (word, uid)
        );
        INSERT INTO versions VALUES ('fts', '1');
    ">>.


%% @doc Called from actor_db_find callback
find(SrvId, PackageId, #actor_id{srv=ActorSrvId, class=Class, name=Name}=ActorId) ->
    Query = [
        <<"SELECT uid FROM actors">>,
        <<" WHERE srv=">>, quote(ActorSrvId),
        <<" AND class=">>, quote(Class),
        <<" AND name=">>, quote(Name), <<";">>
    ],
    case query(SrvId, PackageId, Query) of
        {ok, [[{UID}]], QueryMeta} ->
            {ok, ActorId#actor_id{uid=UID}, QueryMeta};
        {ok, [[]], _} ->
            {error, actor_not_found};
        {error, Error} ->
            {error, Error}
    end;

find(SrvId, PackageId, UID) ->
    Query = [
        <<"SELECT srv,class,name FROM actors">>,
        <<" WHERE uid=">>, quote(UID), <<";">>
    ],
    case query(SrvId, PackageId, Query) of
        {ok, [[{ActorSrvId, Class, Name}]], QueryMeta} ->
            ActorId = #actor_id{
                srv = get_srv(ActorSrvId),
                uid = UID,
                class = Class,
                name = Name
            },
            {ok, ActorId, QueryMeta};
        {ok, [[]], _} ->
            {error, actor_not_found};
        {error, Error} ->
            {error, Error}
    end.


%% @doc Called from actor_db_find callback


%% @doc Called from actor_db_read callback
load(SrvId, PackageId, UID) ->
    UID2 = to_bin(UID),
    Query = [
        <<"SELECT srv,class,name,metadata,spec">>,
        <<" FROM actors WHERE uid=">>, quote(UID2), <<";">>
    ],
    case query(SrvId, PackageId, Query) of
        {ok, [[Fields]], QueryMeta} ->
            {ActorSrvId, Class, Name, {jsonb, Meta}, {jsonb, Spec}} = Fields,
            Actor = #{
                uid => UID2,
                srv => get_srv(ActorSrvId),
                class => Class,
                name => Name,
                spec => nklib_json:decode(Spec),
                metadata => nklib_json:decode(Meta)
            },
            {ok, Actor, QueryMeta};
        {error, Error} ->
            {error, Error}
    end.


%% @doc Called from actor_save callback
save(SrvId, PackageId, Mode, Actor) ->
    #{
        uid := UID,
        srv := ActorSrvId,
        class := Class,
        name := Name,
        spec := Spec,
        metadata := Meta
    } = Actor,
    Path = nkservice_actor_util:make_path(ActorSrvId),
    Fields = fields([
        UID,
        ActorSrvId,
        Class,
        Name,
        Spec,
        Meta,
        Path,
        nklib_util:m_timestamp(),
        maps:get(<<"expiresUnixTime">>, Meta, 0)
    ]),
    Verb = case Mode of
        create ->
            <<"INSERT">>;
        update ->
            <<"UPSERT">>
    end,
    ActorQuery = [
        Verb,
        <<" INTO actors">>,
        <<" (uid,srv,class,name,spec,metadata,path,last_update,expires_time)">>,
        <<" VALUES (">>, Fields, <<");">>
    ],
    Links = maps:get(<<"links">>, Meta, #{}),
    LinksQuery1 = lists:map(
        fun({Type, UID2}) ->
            [
                <<"UPSERT INTO links (target,link_type,orig) VALUES (">>,
                quote(UID2), $,, quote(Type), $,, quote(UID), <<");">>
            ]
        end,
        maps:to_list(Links)),
    LinksQuery2 = [<<"DELETE FROM links WHERE orig=">>, quote(UID), <<";">> | LinksQuery1],
    FTS = maps:get(<<"fts">>, Meta, []),
    FTSQuery1 = lists:map(
        fun(Word) ->
            [
                <<"UPSERT INTO fts (word,uid,path,class) VALUES (">>,
                quote(Word), $,, quote(UID), $,, quote(Path), $,, quote(Class), <<");">>
            ]
        end,
        FTS),
    FTSQuery2 = [<<"DELETE FROM fts WHERE uid=">>, quote(UID), <<";">> | FTSQuery1],
    Query = [<<"BEGIN;">>, ActorQuery, LinksQuery2, FTSQuery2, <<"COMMIT;">>],
    case query(SrvId, PackageId, Query, #{auto_rollback=>true}) of
        {ok, _, SaveMeta} ->
            {ok, SaveMeta};
        {error, Error} ->
            {error, Error}
    end.


%% TODO Fold over operations
%%
%%


%% @doc
delete(SrvId, PackageId, UID, Opts) ->
    UID2 = to_bin(UID),
    QueryFun = fun(Pid) ->
        do_query(Pid, <<"BEGIN;">>, #{}),
        DelQuery = case Opts of
            #{cascade:=true} ->
                lists:foldl(
                    fun(DeleteUID, Acc) ->
                        [
                            [<<"DELETE FROM actors WHERE uid=">>, quote(DeleteUID), <<";">>],
                            [<<"DELETE FROM links WHERE origorig=">>, quote(DeleteUID), <<";">>]
                            | Acc
                        ]
                    end,
                    [],
                    delete_find_nested(Pid, [UID2], sets:new()));
            _ ->
                LinksQ = [<<"SELECT uid1 FROM links WHERE origorig=">>, quote(UID), <<";">>],
                case do_query(Pid, LinksQ, #{}) of
                    {ok, [[]], _} ->
                        ok;
                    _ ->
                        case Opts of
                            #{force:=true} ->
                                ok;
                            _ ->
                                throw(actor_has_linked_actors)
                        end
                end,
                [
                    <<"DELETE FROM actors WHERE uid=">>, quote(UID2), <<";">>,
                    <<"DELETE FROM links WHERE orig=">>, quote(UID2), <<";">>,
                    <<"DELETE FROM fts WHERE uid=">>, quote(UID2), <<";">>
                ]
        end,
        do_query(Pid, DelQuery, #{}),
        do_query(Pid, <<"COMMIT;">>, #{})
    end,
    case query(SrvId, PackageId, QueryFun, #{}) of
        {ok, _, Meta} ->
            {ok, Meta};
        {error, Error} ->
            {error, Error}
    end.

delete_find_nested(_Pid, [], Set) ->
    sets:to_list(Set);

delete_find_nested(Pid, [UID|Rest], Set) ->
    case sets:is_element(UID, Set) of
        true ->
            delete_find_nested(Pid, Rest, Set);
        false ->
            Set2 = sets:add_element(UID, Set),
            case sets:size(Set2) > 5 of
                true ->
                    throw(too_many_actors);
                false ->
                    lager:error("NKLOG LOOKING FOR ~p", [UID]),
                    Q = [<<" SELECT orig FROM links WHERE target=">>, quote(UID), <<";">>],
                    case do_query(Pid, Q, #{}) of
                        {ok, [[]], _} ->
                            lager:error("NO CHILDS"),
                            delete_find_nested(Pid, Rest, Set);
                        {ok, [List2], _} ->
                            List3 = [U || {U} <- List2],
                            lager:error("CHILDS: ~p", [List3]),
                            Set3 = sets:union(Set2, sets:from_list(List3)),
                            delete_find_nested(Pid, List3++Rest, Set3)
                    end
            end
    end.









%% @doc
search(SrvId, PackageId, SearchType, Opts) ->
    case ?CALL_SRV(SrvId, actor_db_get_query, [pgsql, SearchType, Opts]) of
        {ok, {pgsql, Query, QueryMeta}} ->
            query(SrvId, PackageId, Query, QueryMeta);
        {error, Error} ->
            {error, Error}
    end.


%% @doc
aggregation(SrvId, PackageId, SearchType, Opts) ->
    case ?CALL_SRV(SrvId, actor_db_get_query, [pgsql, SearchType, Opts]) of
        {ok, {pgsql, Query, QueryMeta}} ->
            case query(SrvId, PackageId, Query, QueryMeta) of
                {ok, [Res], Meta} ->
                    case (catch maps:from_list(Res)) of
                        {'EXIT', _} ->
                            {error, aggregation_invalid};
                        Map ->
                            {ok, Map, Meta}
                    end;
                {ok, _, _} ->
                    {error, aggregation_invalid};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc Gets, for an UID, all links it has to other objects
%% Returns {Type, UID}
get_links(SrvId, PackageId, UID, Type) ->
    UID2 = to_bin(UID),
    Query = [
        <<"SELECT type,uid2 FROM links">>,
        <<" WHERE uid1=">>, quote(UID2),
        case Type of
            <<>> ->
                <<>>;
            _ ->
                [<<" AND type=">>, quote(Type)]
        end,
        <<";">>
    ],
    case query(SrvId, PackageId, Query, #{}) of
        {ok, [List], Meta} ->
            {ok, List, Meta};
        {error, Error} ->
            {error, Error}
    end.


%% @doc
%% Returns {Type, UID}
get_linked(SrvId, PackageId, UID, Type) ->
    UID2 = to_bin(UID),
    Query = [
        <<"SELECT type,uid1 FROM links">>,
        <<" WHERE uid2=">>, quote(UID2),
        case Type of
            <<>> ->
                <<>>;
            _ ->
                [<<" AND type=;">>, quote(Type)]
        end,
        <<";">>
    ],
    case query(SrvId, PackageId, Query, #{}) of
        {ok, [List], Meta} ->
            {ok, List, Meta};
        {error, Error} ->
            {error, Error}
    end.



%% ===================================================================
%% Internal
%% ===================================================================

%% @private
query(SrvId, PackageId, Fun) ->
    query(SrvId, PackageId, Fun, #{}).


%% @private
query(SrvId, PackageId, Query, QueryMeta) ->
    case nkservice_pgsql:get_connection(SrvId, PackageId) of
        {ok, Pid} ->
            try
                {ok, Data, MetaData}= case is_function(Query, 1) of
                    true ->
                        Query(Pid);
                    false ->
                        do_query(Pid, Query, QueryMeta)
                end,
                {ok, Data, MetaData}
            catch
                throw:Throw ->
                    % Processing 'user' errors
                    % If we are on a transaction, and some line fails,
                    % it will abort but we need to rollback to be able to
                    % reuse the connection
                    case QueryMeta of
                        #{auto_rollback:=false} ->
                            ok;
                        _ ->
                            case catch do_query(Pid, <<"ROLLBACK;">>, #{}) of
                                {ok, _, _} ->
                                    ok;
                                no_transaction ->
                                    ok;
                                Error ->
                                    ?LLOG(notice, "error performing Rollback: ~p", [Error]),
                                    error(rollback_error)
                            end
                    end,
                    {error, Throw};
                Class:CError ->
                    % For other errors, we better close the connection
                    ?LLOG(warning, "error in query: ~p, ~p, ~p", [Class, CError, erlang:get_stacktrace()]),
                    nkservice_pgsql:stop_connection(Pid),
                    {error, internal_error}
            after
                nkservice_pgsql:release_connection(SrvId, PackageId, Pid)
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @private
do_query(Pid, Query, QueryMeta) when is_pid(Pid) ->
    lager:notice("Query: ~s", [Query]),
    case nkservice_pgsql:do_query(Pid, Query) of
        {ok, Ops, PgMeta} ->
            case QueryMeta of
                #{result_fun:=ResultFun} ->
                    ResultFun(Ops, #{pgsql=>PgMeta});
                _ ->
                    L = [Rows || {_Op, Rows, _OpMeta} <- Ops],
                    {ok, L, #{pgsql=>PgMeta}}
            end;
        {error, {pgsql_error, #{routine:=<<"NewUniquenessConstraintViolationError">>}}} ->
            throw(uniqueness_violation);
        {error, {pgsql_error, #{code := <<"XX000">>}}} ->
            throw(no_transaction);
        {error, Error} ->
            throw(Error)
    end.



fields(List) ->
    nkservice_pgsql_util:fields(List).


%% @private
get_srv(ActorSrvId) ->
    nkservice_actor_util:get_srv(ActorSrvId).


%% @private
quote(Field) ->
    nkservice_pgsql_util:quote(Field).


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).




