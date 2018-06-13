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
-export([make_sort/2, make_filter/2]).

-include("nkservice_actor.hrl").


%% ===================================================================
%% Core queries
%% ===================================================================


%% @private
get_query({aggregation_service_classes, SrvId, Params}, _Opts) ->
    Query = [
        <<"SELECT class, COUNT(class) FROM actors">>,
        <<" WHERE ">>, filter_path(SrvId, Params),
        <<" GROUP BY class;">>
    ],
    {ok, {pgsql, Query, #{}}};

get_query({aggregation_service_types, SrvId, Class, Params}, _Opts) ->
    Query = [
        <<"SELECT actor_type, COUNT(actor_type) FROM actors">>,
        <<" WHERE class = ">>, quote(Class), <<" AND ">>, filter_path(SrvId, Params),
        <<" GROUP BY actor_type;">>
    ],
    {ok, {pgsql, Query, #{}}};

get_query({search_service_linked, SrvId, UID, LinkType, Params}, _Opts) ->
    From = maps:get(from, Params, 0),
    Limit = maps:get(size, Params, 100),
    Query = [
        <<"SELECT uid,link_type FROM links">>,
        <<" WHERE link_target=">>, quote(to_bin(UID)),
        case to_bin(LinkType) of
            <<>> ->
                <<>>;
            LinkType2 ->
                [<<" AND link_type=">>, quote(LinkType2)]
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

get_query({search_service_fts, SrvId, Field, Word, Params}, _Opts) ->
    From = maps:get(from, Params, 0),
    Limit = maps:get(size, Params, 100),
    Word2 = to_bin(Word),
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
            <<>> ->
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

get_query({search_service_actors, SrvId, Params}, _Opts) ->
    lager:error("NKLOG PARAMS ~p", [Params]),
    From = maps:get(from, Params, 0),
    Limit = maps:get(size, Params, 100),
    Totals = maps:get(totals, Params, true),
    Filters1 = maps:get(filters, Params, #{}),
    Filters2 = add_srv_filter(SrvId, Filters1, Params),
    SQLFilters = make_filters(Filters2),
    SQLSort = make_sort(maps:get(sort, Params, [])),

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
        <<"SELECT uid,srv,class,actor_type,name,vsn,spec,metadata FROM actors">>,
        SQLFilters,
        SQLSort,
        <<" OFFSET ">>, to_bin(From), <<" LIMIT ">>, to_bin(Limit),
        <<";">>
    ],
    ResultFun = case Totals of
        true ->
            fun ?MODULE:pgsql_totals_actors/2;
        false ->
            fun ?MODULE:pgsql_actors/2
    end,
    {ok, {pgsql, Query, #{result_fun=>ResultFun}}};

get_query({search_service_actors_id, SrvId, Params}, _Opts) ->
    % lager:error("NKLOG PARAMS ~p", [Params]),
    From = maps:get(from, Params, 0),
    Limit = maps:get(size, Params, 100),
    Totals = maps:get(totals, Params, true),
    Filters1 = maps:get(filters, Params, #{}),
    Filters2 = add_srv_filter(SrvId, Filters1, Params),
    SQLFilters = make_filters(Filters2),
    SQLSort = make_sort(maps:get(sort, Params, [])),
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
        #{
            uid => UID,
            srv => nkservice_actor_util:gen_srv_id(SrvId),
            class => Class,
            type => Type,
            vsn => Vsn,
            name => Name,
            spec => nklib_json:decode(Spec),
            metadata => nklib_json:decode(MetaData)
        }
        || {UID, SrvId, Class, Type, Name, Vsn, {jsonb, Spec}, {jsonb, MetaData}} <- Rows
    ],
    {ok, Actors, Meta#{size=>Size}}.


%% @private
pgsql_totals_actors([{{select, 1}, [{Total}], _}, {{select, Size}, Rows, _OpMeta}], Meta) ->
    Actors = [
        #{
            uid => UID,
            srv => nkservice_actor_util:gen_srv_id(SrvId),
            class => Class,
            type => Type,
            vsn => Vsn,
            name => Name,
            spec => nklib_json:decode(Spec),
            metadata => nklib_json:decode(MetaData)
        }
        || {UID, SrvId, Class, Type, Name, Vsn, {jsonb, Spec}, {jsonb, MetaData}} <- Rows
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

%%core_list_filters(_Filters) ->
%%    <<>>.
%%
%%
%%core_list_order(_Filters) ->
%%    <<>>.


%% @private
make_filters(Filters) ->
    AndFilters1 = make_filter(maps:get('and', Filters, []), []),
    OrFilters1 = make_filter(maps:get('or', Filters, []), []),
    OrFilters2 = nklib_util:bjoin(OrFilters1, <<" OR ">>),
    OrFilters3 = case OrFilters2 of
        <<>> ->
            [];
        _ ->
            [<<$(, OrFilters2/binary, $)>>]
    end,
    NotFilters1 = make_filter(maps:get('not', Filters, []), []),
    NotFilters2 = case NotFilters1 of
        <<>> ->
            [];
        _ ->
            [<<"(NOT ", F/binary, ")">> || F <- NotFilters1]
    end,
    FilterList = AndFilters1 ++ OrFilters3 ++ NotFilters2,
    case nklib_util:bjoin(FilterList, <<" AND ">>) of
        <<>> ->
            [];
        Filters3 ->
            [<<" WHERE ">>, Filters3]
    end.


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
add_srv_filter(SrvId, Filters, #{deep:=true}) ->
    Path = nkservice_actor_util:make_reversed_srv_id(SrvId),
    And1 = maps:get('and', Filters, []),
    And2 = [{<<"path">>, prefix, Path} | And1],
    Filters#{'and' => And2};

add_srv_filter(SrvId, Filters, _Opts) ->
    And1 = maps:get('and', Filters, []),
    And2 = [{<<"srv">>, eq, SrvId} | And1],
    Filters#{'and' => And2}.


%%%% @private
%%get_op(eq) -> <<" = ">>;
%%get_op(ne) -> <<" <> ">>;
%%get_op(lt) -> <<" < ">>;
%%get_op(lte) -> <<" <= ">>;
%%get_op(gt) -> <<" > ">>;
%%get_op(gte) -> <<" >= ">>.


%% @private
get_op(Field, eq, Value) -> [Field, << "=" >>, quote(Value)];
get_op(Field, ne, Value) -> [Field, <<" <> ">>, quote(Value)];
get_op(Field, lt, Value) -> [Field, <<" < ">>, quote(Value)];
get_op(Field, lte, Value) -> [Field, <<" <= ">>, quote(Value)];
get_op(Field, gt, Value) -> [Field, <<" > ">>, quote(Value)];
get_op(Field, gte, Value) -> [Field, <<" >= ">>, quote(Value)].


%%%% @private
%%get_prefix_value(Val) ->
%%    case binary:split(to_bin(Val), <<"*">>) of
%%        [Val2, <<>>] ->
%%            [<<" LIKE ">>, quote(<<Val2/binary, $%>>)];
%%        [Val2] ->
%%            [<<" = ">>, quote(Val2)]
%%    end.


%% @private
get_type({Field, Type}) -> {Field, Type};
get_type(<<"metadata.fts.", _/binary>>=Field) -> {Field, array};
get_type(Field) -> {Field, string}.


%% @private
get_field2(<<"type">>) -> <<"actor_type">>;
get_field2(Field) -> Field.



%% @private
make_sort(Fields) ->
    make_sort(Fields, []).


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


%%%% @private
%%make_json_field(Field) ->
%%    make_json_field(Field, string).


make_json_field(Field, Type) ->
    make_json_field(Field, Type, []).


%% @private
make_json_field(Field, Type, Acc) ->
    case binary:split(Field, <<".">>) of
        [Single] when Acc==[] ->
            Single;
        [Last] ->
            case Type of
                string ->
                    Acc++[$>, $', Last, $'];    % '>' finishes ->>
                json ->
                    Acc++[$', Last, $'];
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
