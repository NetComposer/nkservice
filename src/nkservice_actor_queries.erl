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

%% @doc Default plugin callbacks
-module(nkservice_actor_queries).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([get_query/3]).
-export([pgsql_actor_id/2, pgsql_actor_total/2]).

-include("nkservice_actor.hrl").


%% ===================================================================
%% Core queries
%% ===================================================================


%% @private
get_query(pgsql, {aggregation_core_classes, Srv}, _Opts) ->
    Query = [
        <<"SELECT class, COUNT(class) FROM actors">>,
        <<" WHERE ">>, path(Srv),
        <<" GROUP BY class;">>
    ],
    {ok, {pgsql, Query, #{}}};

get_query(pgsql, {search_core_paths, Srv}, _Opts) ->
    Query = [
        <<"SELECT srv,uid,class,name,COUNT(*) OVER() FROM actors">>,
        <<" WHERE ">>, path(Srv),
        <<" ORDER BY srv,class,name" >>,
        <<" LIMIT 100;">>
    ],
    {ok, {pgsql, Query, #{result_fun=>fun ?MODULE:pgsql_actor_total/2}}};

get_query(pgsql, {search_core_paths_class, Srv, Class}, _Opts) ->
    Query = [
        <<"SELECT srv,uid,class,name,COUNT(*) OVER() FROM actors">>,
        <<" WHERE class=">>, quote(Class),
        <<" AND ">>, path(Srv),
        <<" ORDER BY srv,class,name" >>,
        <<" LIMIT 100;">>
    ],
    {ok, {pgsql, Query, #{result_fun=>fun ?MODULE:pgsql_actor_total/2}}};

get_query(pgsql, {search_core_labels, Srv, Labels}, _Opts) ->
    LabelSpec1 = lists:map(
        fun({K, V}) ->
            K2 = nkservice_pgsql_util:quote_double(K),
            V2 = nkservice_pgsql_util:quote_double(V),
            list_to_binary([
                <<"metadata->'labels' @> '{">>, K2, <<": ">>, V2, <<"}'">>])
        end,
        maps:to_list(Labels)),
    LabelSpec2 = nklib_util:bjoin(LabelSpec1, <<" AND ">>),
    Query = [
        <<"SELECT srv,uid,class,name FROM actors">>,
        <<" WHERE ">>, LabelSpec2,
        <<" AND ">>, path(Srv),
        <<" ORDER BY srv,class,name" >>,
        <<" LIMIT 100;">>
    ],
    {ok, {pgsql, Query, #{result_fun=>fun ?MODULE:pgsql_actor_id/2}}};

get_query(pgsql, {search_core_linked, UID, LinkType}, _Opts) ->
    Query = [
        <<"SELECT link_type,orig FROM links">>,
        <<" WHERE target=">>, quote(to_bin(UID)),
        case to_bin(LinkType) of
            <<>> ->
                <<>>;
            LinkType2 ->
                [<<" AND link_type=">>, quote(LinkType2)]
        end,
        <<" LIMIT 100;">>
    ],
    ResultFun = fun(Ops, Meta) ->
        case Ops of
            [{{select, _}, [], _OpMeta}] ->
                {ok, #{}, Meta};
            [{{select, Size}, Rows, _OpMeta}] ->
                {ok, maps:from_list(Rows), Meta#{size=>Size}}
        end
    end,
    {ok, {pgsql, Query, #{result_fun=>ResultFun}}};

get_query(pgsql, {search_core_fts, Srv, Word}, _Opts) ->
    Word2 = to_bin(Word),
    Last = byte_size(Word2)-1,
    Filter = case Word2 of
        <<Word3:Last/binary, $*>> ->
            [<<"word LIKE ">>, quote(<<Word3/binary, $%>>)];
        _ ->
            [<<"word=">>, quote(Word2)]
    end,
    Query = [
        <<"SELECT uid,path,class FROM fts">>,
        <<" WHERE ">>, Filter,
        <<" AND ">>, path(Srv),
        <<" ORDER BY word" >>,
        <<" LIMIT 100;">>
    ],
    {ok, {pgsql, Query, #{}}};

get_query(_Backend, _QueryType, _Opts) ->
    {error, unknown_query}.


%% ===================================================================
%% Internal
%% ===================================================================

%% @private
pgsql_actor_id([{{select, _}, [], _OpMeta}], Meta) ->
    {ok, [], Meta#{size=>0}};

pgsql_actor_id([{{select, Size}, Rows, _OpMeta}], Meta) ->
    ActorIds = [
        #actor_id{
            srv = Srv,
            uid = UID,
            class = Class,
            name = Name
        }
        || {Srv, UID, Class, Name} <- Rows
    ],
    {ok, ActorIds, Meta#{size=>Size}}.


%% @private
pgsql_actor_total([{{select, _Size}, [], _OpMeta}], Meta) ->
    {ok, [], Meta#{size=>0, total=>0}};

pgsql_actor_total([{{select, Size}, Rows, _OpMeta}], Meta) ->
    [{_, _, _, _, Total}|_] = Rows,
    ActorIds = [
        #actor_id{
            srv = Srv,
            uid = UID,
            class = Class,
            name = Name
        }
        || {Srv, UID, Class, Name, _Total} <- Rows
    ],
    {ok, ActorIds, Meta#{size=>Size, total=>Total}}.


%% @private
path(Srv) ->
    Path = <<(nkservice_actor_util:make_path(Srv))/binary, $%>>,
    [<<"path LIKE ">>, quote(Path)].


%% @private
quote(Term) ->
    nkservice_pgsql_util:quote(Term).


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).
