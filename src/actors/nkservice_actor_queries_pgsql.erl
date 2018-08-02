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
-module(nkservice_actor_queries_pgsql).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([get_query/2]).
-export([pgsql_totals_actors/2, pgsql_actors/2,
         pgsql_totals_actors_id/2, pgsql_actors_id/2]).
-export([filter_path/2, make_sort/2, make_filter/2]).

-include("nkservice_actor.hrl").



%% ===================================================================
%% Core queries
%% ===================================================================


%% @private
%% - deep: boolean()
get_query({aggregation_service_classes, SrvId, Params}, _Opts) ->
    Query = [
        <<"SELECT class, COUNT(class) FROM actors">>,
        <<" WHERE ">>, filter_path(SrvId, Params),
        <<" GROUP BY class;">>
    ],
    {ok, {pgsql, Query, #{}}};

%% - deep: boolean()
get_query({aggregation_service_types, SrvId, Class, Params}, _Opts) ->
    Query = [
        <<"SELECT actor_type, COUNT(actor_type) FROM actors">>,
        <<" WHERE class = ">>, quote(Class), <<" AND ">>, filter_path(SrvId, Params),
        <<" GROUP BY actor_type;">>
    ],
    {ok, {pgsql, Query, #{}}};

%% - from, size: integer()
%% - deep: boolean()
get_query({search_service_linked, SrvId, UID, LinkType, Params}, _Opts) ->
    From = maps:get(from, Params, 0),
    Limit = maps:get(size, Params, 100),
    Query = [
        <<"SELECT uid,link_type FROM links">>,
        <<" WHERE link_target=">>, quote(to_bin(UID)),
        case LinkType of
            any ->
                <<>>;
            _ ->
                [<<" AND link_type=">>, quote(LinkType)]
        end,
        <<" AND ">>, filter_path(SrvId, Params),
        <<" OFFSET ">>, to_bin(From), <<" LIMIT ">>, to_bin(Limit),
        <<";">>
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

%% - from, size: integer()
%% - deep: boolean()
get_query({search_service_fts, SrvId, Field, Word, Params}, _Opts) ->
    From = maps:get(from, Params, 0),
    Limit = maps:get(size, Params, 100),
    Word2 = nklib_parse:normalize(Word, #{unrecognized=>keep}),
    Last = byte_size(Word2)-1,
    Filter = case Word2 of
        <<Word3:Last/binary, $*>> ->
            [<<"fts_word LIKE ">>, quote(<<Word3/binary, $%>>)];
        _ ->
            [<<"fts_word=">>, quote(Word2)]
    end,
    Query = [
        <<"SELECT uid FROM fts">>,
        <<" WHERE ">>, Filter, <<" AND ">>, filter_path(SrvId, Params),
        case Field of
            any ->
                [];
            _ ->
                [<<" AND fts_field = ">>, quote(Field)]
        end,
        <<" ORDER BY fts_word" >>,
        <<" OFFSET ">>, to_bin(From), <<" LIMIT ">>, to_bin(Limit),
        <<";">>
    ],
    ResultFun = fun([{{select, _}, List, _OpMeta}],Meta) ->
        List2 = [UID || {UID} <-List],
        {ok, List2, Meta}
    end,
    {ok, {pgsql, Query, #{result_fun=>ResultFun}}};


%% Params is nkdomain_search:search_spec()
get_query({search_service_actors, SearchSpec}, _Opts) ->
    % lager:error("NKLOG PARAMS ~p", [Params]),
    From = maps:get(from, SearchSpec, 0),
    Size = maps:get(size, SearchSpec, 100),
    Totals = maps:get(totals, SearchSpec, true),
    SQLFilters = make_sql_filters(SearchSpec),
    SQLSort = make_sql_sort(SearchSpec),

    % We could use SELECT COUNT(*) OVER(),src,uid... but it doesn't work if no
    % rows are returned

    Query = [
        case Totals of
            true ->
                [
                    <<"SELECT COUNT(*) FROM actors">>,
                    SQLFilters,
                    <<";">>
                ];
            false ->
                []
        end,
        <<"SELECT uid,srv,class,actor_type,name,vsn,data,metadata FROM actors">>,
        SQLFilters,
        SQLSort,
        <<" OFFSET ">>, to_bin(From), <<" LIMIT ">>, to_bin(Size),
        <<";">>
    ],
    ResultFun = case Totals of
        true ->
            fun ?MODULE:pgsql_totals_actors/2;
        false ->
            fun ?MODULE:pgsql_actors/2
    end,
    {ok, {pgsql, Query, #{result_fun=>ResultFun}}};

get_query({search_service_actors_id, SearchSpec}, _Opts) ->
    % lager:error("NKLOG PARAMS ~p", [Params]),
    From = maps:get(from, SearchSpec, 0),
    Limit = maps:get(size, SearchSpec, 100),
    Totals = maps:get(totals, SearchSpec, true),
    SQLFilters = make_sql_filters(SearchSpec),
    SQLSort = make_sql_sort(SearchSpec),
    Query = [
        case Totals of
            true ->
                [
                    <<"SELECT COUNT(*) FROM actors">>,
                    SQLFilters,
                    <<";">>
                ];
            false ->
                []
        end,
        <<"SELECT uid,srv,class,actor_type,name FROM actors">>,
        SQLFilters,
        SQLSort,
        <<" OFFSET ">>, to_bin(From), <<" LIMIT ">>, to_bin(Limit),
        <<";">>
    ],
    ResultFun = case Totals of
        true ->
            fun ?MODULE:pgsql_totals_actors_id/2;
        false ->
            fun ?MODULE:pgsql_actors_id/2
    end,
    {ok, {pgsql, Query, #{result_fun=>ResultFun}}};

get_query(QueryType, _Opts) ->
    {error, {query_unknown, QueryType}}.




%% ===================================================================
%% SQL processors
%% ===================================================================


%% @private
pgsql_actors([{{select, Size}, Rows, _OpMeta}], Meta) ->
    Actors = [
        #actor{
            id = #actor_id{
                uid = UID,
                srv = nkservice_actor_util:gen_srv_id(SrvId),
                class = Class,
                type = Type,
                name = Name
            },
            vsn = Vsn,
            data = nklib_json:decode(Data),
            metadata = nklib_json:decode(MetaData)
        }
        || {UID, SrvId, Class, Type, Name, Vsn, {jsonb, Data}, {jsonb, MetaData}} <- Rows
    ],
    {ok, Actors, Meta#{size=>Size}}.


%% @private
pgsql_totals_actors([{{select, 1}, [{Total}], _}, {{select, Size}, Rows, _OpMeta}], Meta) ->
    Actors = [
        #actor{
            id = #actor_id{
                uid = UID,
                srv = nkservice_actor_util:gen_srv_id(SrvId),
                class = Class,
                type = Type,
                name = Name
            },
            vsn = Vsn,
            data = nklib_json:decode(Data),
            metadata = nklib_json:decode(MetaData)
        }
        || {UID, SrvId, Class, Type, Name, Vsn, {jsonb, Data}, {jsonb, MetaData}} <- Rows
    ],
    {ok, Actors, Meta#{size=>Size, total=>Total}}.


%% @private
pgsql_actors_id([{{select, Size}, Rows, _OpMeta}], Meta) ->
    Actors = [
        #actor_id{
            srv = nkservice_actor_util:gen_srv_id(SrvId),
            uid = UID,
            class = Class,
            type = Type,
            name = Name
        }
        || {UID, SrvId, Class, Type, Name} <- Rows
    ],
    {ok, Actors, Meta#{size=>Size}}.


%% @private
pgsql_totals_actors_id([{{select, 1}, [{Total}], _}, {{select, Size}, Rows, _OpMeta}], Meta) ->
    Actors = [
        #actor_id{
            srv = nkservice_actor_util:gen_srv_id(SrvId),
            uid = UID,
            class = Class,
            type = Type,
            name = Name
        }
        || {UID, SrvId, Class, Type, Name} <- Rows
    ],
    {ok, Actors, Meta#{size=>Size, total=>Total}}.




%% ===================================================================
%% Filters
%% ===================================================================


%% @private
make_sql_filters(#{srv:=SrvId}=Params) ->
    Filters = maps:get(filter, Params, #{}),
    AndFilters1 = expand_filter(maps:get('and', Filters, []), []),
    AndFilters2 = make_filter(AndFilters1, []),
    OrFilters1 = expand_filter(maps:get('or', Filters, []), []),
    OrFilters2 = make_filter(OrFilters1, []),
    OrFilters3 = nklib_util:bjoin(OrFilters2, <<" OR ">>),
    OrFilters4 = case OrFilters3 of
        <<>> ->
            [];
        _ ->
            [<<$(, OrFilters3/binary, $)>>]
    end,
    NotFilters1 = expand_filter(maps:get('not', Filters, []), []),
    NotFilters2 = make_filter(NotFilters1, []),
    NotFilters3 = case NotFilters2 of
        <<>> ->
            [];
        _ ->
            [<<"(NOT ", F/binary, ")">> || F <- NotFilters2]
    end,
    PathFilter = list_to_binary(filter_path(SrvId, Params)),
    FilterList = [PathFilter | AndFilters2 ++ OrFilters4 ++ NotFilters3],
    Where = nklib_util:bjoin(FilterList, <<" AND ">>),
    [<<" WHERE ">>, Where].


%% @private
expand_filter([], Acc) ->
    Acc;

expand_filter([#{field:=Field, op:=Op, value:=Value}|Rest], Acc) ->
    expand_filter(Rest, [{Field, Op, Value}|Acc]).


%% @private
make_filter([], Acc) ->
    Acc;

make_filter([{<<"metadata.fts._all_fields">>, eq, Val} | Rest], Acc) ->
    Filter = [<<"(fts_words LIKE '%:">>, Val, <<" %')">>],
    make_filter(Rest, [list_to_binary(Filter) | Acc]);

make_filter([{<<"metadata.fts._all_fields">>, prefix, Val} | Rest], Acc) ->
    Filter = [<<"(fts_words LIKE '%:">>, Val, <<"%')">>],
    make_filter(Rest, [list_to_binary(Filter) | Acc]);

make_filter([{<<"metadata.fts.", Field/binary>>, eq, Val} | Rest], Acc) ->
    Filter = [<<"(fts_words LIKE '% ">>, Field, $:, Val, <<" %')">>],
    make_filter(Rest, [list_to_binary(Filter) | Acc]);

make_filter([{<<"metadata.fts.", Field/binary>>, prefix, Val} | Rest], Acc) ->
    Filter = [<<"(fts_words LIKE '% ">>, Field, $:, Val, <<"%')">>],
    make_filter(Rest, [list_to_binary(Filter) | Acc]);

make_filter([{Field, exists, Bool}|Rest], Acc) ->
    L = binary:split(Field, <<".">>, [global]),
    [Field2|Base1] = lists:reverse(L),
    Field3 = get_field2(Field2),
    Base2 = nklib_util:bjoin(lists:reverse(Base1), $.),
    Filter = [
        case Bool of true -> <<"(">>; false -> <<"(NOT ">> end,
        make_json_field(Base2, json),
        <<" ? ">>, quote(Field3), <<")">>
    ],
    make_filter(Rest, [list_to_binary(Filter)|Acc]);

make_filter([{Field, prefix, Val}|Rest], Acc) ->
    {Field2, string} = get_type(Field),
    Field3 = get_field2(Field2),
    Filter = [
        $(,
        make_json_field(Field3, string),
        <<" LIKE ">>, quote(<<Val/binary, $%>>), $)
    ],
    make_filter(Rest, [list_to_binary(Filter)|Acc]);

make_filter([{Field, values, ValList}|Rest], Acc) ->
    Values = nklib_util:bjoin([quote(Val) || Val <- ValList], $,),
    {Field2, Type} = get_type(Field),
    Field3 = get_field2(Field2),
    Filter = [
        $(,
        make_json_field(Field3, Type),
        <<" IN (">>, Values, <<"))">>
    ],
    make_filter(Rest, [list_to_binary(Filter)|Acc]);

make_filter([{Field, Op, Val} | Rest], Acc) ->
    {Field2, Type} = get_type(Field),
    Field3 = get_field2(Field2),
    Filter = [$(, get_op(make_json_field(Field3, Type), Op, Val), $)],
    make_filter(Rest, [list_to_binary(Filter) | Acc]).



%% @private
get_op(Field, eq, Value) -> [Field, << "=" >>, quote(Value)];
get_op(Field, ne, Value) -> [Field, <<" <> ">>, quote(Value)];
get_op(Field, lt, Value) -> [Field, <<" < ">>, quote(Value)];
get_op(Field, lte, Value) -> [Field, <<" <= ">>, quote(Value)];
get_op(Field, gt, Value) -> [Field, <<" > ">>, quote(Value)];
get_op(Field, gte, Value) -> [Field, <<" >= ">>, quote(Value)].


%% @private
get_type({Field, Type}) -> {Field, Type};
get_type(<<"metadata.fts.", _/binary>>=Field) -> {Field, array};
get_type(Field) -> {Field, string}.


%% @private
get_field2(<<"type">>) -> <<"actor_type">>;
get_field2(Field) -> Field.





%% @private
make_sql_sort(Params) ->
    Sort = expand_sort(maps:get(sort, Params, []), []),
    make_sort(Sort, []).


%% @private
expand_sort([], Acc) ->
    lists:reverse(Acc);

expand_sort([#{field:=Field}=Term|Rest], Acc) ->
    Order = maps:get(order, Term, asc),
    expand_sort(Rest, [{Order, Field}|Acc]).



%% @private
make_sort([], []) ->
    <<>>;

make_sort([], Acc) ->
    [<<" ORDER BY ">>, nklib_util:bjoin(lists:reverse(Acc), $,)];

make_sort([{Order, Field}|Rest], Acc) ->
    {Field2, Type} = get_type(Field),
    Item = [
        make_json_field(get_field2(Field2), Type),
        case Order of asc -> <<" ASC">>; desc -> <<" DESC">> end
    ],
    make_sort(Rest, [list_to_binary(Item)|Acc]).


%% @private
%% Extracts a field inside a JSON,  it and casts it to json, string, integer o boolean
make_json_field(Field, Type) ->
    make_json_field(Field, Type, []).


%% @private
make_json_field(Field, Type, Acc) ->
    case binary:split(Field, <<".">>) of
        [Single] when Acc==[] ->
            Single;
        [Last] ->
            case Type of
                json ->
                    Acc++[$', Last, $'];
                string ->
                    Acc++[$>, $', Last, $'];    % '>' finishes ->>
                integer ->
                    [$(|Acc] ++ [$>, $', Last, $', <<")::INTEGER">>];
                boolean ->
                    [$(|Acc] ++ [$>, $', Last, $', <<")::BOOLEAN">>]
            end;
        [Base, Rest] when Acc==[] ->
            make_json_field(Rest, Type, [Base, <<"->">>]);
        [Base, Rest] ->
            make_json_field(Rest, Type, Acc++[$', Base, $', <<"->">>])
    end.


%% @private
filter_path(SrvId, Opts) when is_list(SrvId) ->
    Terms = [list_to_binary(filter_path(T, Opts)) || T <- SrvId],
    [$(, nklib_util:bjoin(Terms, <<" OR ">>), $)];

filter_path(SrvId, Opts) ->
    Path = nkservice_actor_util:make_reversed_srv_id(SrvId),
    case Opts of
        #{deep:=true} ->
            [<<"path LIKE ">>, quote(<<Path/binary, $%>>)];
        _ ->
            [<<"path = ">>, quote(Path)]
    end.


%% @private
quote(Term) ->
    nkservice_pgsql_util:quote(Term).


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).
