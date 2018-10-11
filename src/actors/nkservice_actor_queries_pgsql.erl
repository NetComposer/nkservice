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
-export([get_query/3]).
-export([pgsql_totals_actors/2, pgsql_actors/2,
         pgsql_totals_actors_id/2, pgsql_actors_id/2]).
-export([filter_path/2, make_sort/2, make_filter/2]).

-include("nkservice_actor.hrl").



%% ===================================================================
%% Core queries
%% ===================================================================


%% @private
%% - deep: boolean()
get_query(_SrvId, {service_aggregation_groups, Domain, Params}, _Opts) ->
    Query = [
        <<"SELECT \"group\", COUNT(\"group\") FROM actors">>,
        <<" WHERE ">>, filter_path(Domain, Params),
        <<" GROUP BY \"group\";">>
    ],
    {ok, {pgsql, Query, #{}}};

%% - deep: boolean()
get_query(_SrvId, {service_aggregation_resources, Domain, Group, Params}, _Opts) ->
    Query = [
        <<"SELECT resource, COUNT(resource) FROM actors">>,
        <<" WHERE \"group\" = ">>, quote(Group), <<" AND ">>, filter_path(Domain, Params),
        <<" GROUP BY resource;">>
    ],
    {ok, {pgsql, Query, #{}}};

%% - from, size: integer()
%% - deep: boolean()
get_query(_SrvId, {service_search_linked, Domain, UID, LinkType, Params}, _Opts) ->
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
        <<" AND ">>, filter_path(Domain, Params),
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
get_query(_SrvId, {service_search_fts, Domain, Field, Word, Params}, _Opts) ->
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
        <<" WHERE ">>, Filter, <<" AND ">>, filter_path(Domain, Params),
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
get_query(_SrvId, {service_search_actors, SearchSpec}, _Opts) ->
    % lager:error("NKLOG SEARCH SPEC ~p", [SearchSpec]),
    From = maps:get(from, SearchSpec, 0),
    Size = maps:get(size, SearchSpec, 10),
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
        <<"SELECT uid,domain,\"group\",vsn,resource,name,data,metadata,hash FROM actors">>,
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

get_query(SrvId, {service_search_actors, Group, Type, SearchSpec}, _Opts) ->
    Filters1 = maps:get(filter, SearchSpec, #{}),
    AndFilters1 = maps:get('and', Filters1, []),
    AndFilters2 = case Group of
        all ->
            AndFilters1;
        _ ->
            [#{field=><<"group">>, op=>eq, value=>Group}|AndFilters1]
    end,
    AndFilters3 = case Type of
        all ->
            AndFilters2;
        _ ->
            [#{field=><<"resource">>, op=>eq, value=>Type}|AndFilters2]
    end,
    Filters2 = Filters1#{'and' => AndFilters3},
    SearchSpec2 = SearchSpec#{filter => Filters2},
    get_query(SrvId, {service_search_actors, SearchSpec2}, []);

get_query(_SrvId, {service_search_actors_id, SearchSpec}, _Opts) ->
    % lager:error("NKLOG SEARCH SPEC ~p", [SearchSpec]),
    From = maps:get(from, SearchSpec, 0),
    Size = maps:get(size, SearchSpec, 10),
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
        <<"SELECT uid,domain,\"group\",vsn,resource,name,last_update FROM actors">>,
        SQLFilters,
        SQLSort,
        <<" OFFSET ">>, to_bin(From), <<" LIMIT ">>, to_bin(Size),
        <<";">>
    ],
    ResultFun = case Totals of
        true ->
            fun ?MODULE:pgsql_totals_actors_id/2;
        false ->
            fun ?MODULE:pgsql_actors_id/2
    end,
    {ok, {pgsql, Query, #{result_fun=>ResultFun}}};

get_query(SrvId, {service_search_actors_type_id, Group, Type, SearchSpec}, _Opts) ->
    Filters1 = maps:get(filter, SearchSpec, #{}),
    AndFilters1 = maps:get('and', Filters1, []),
    AndFilters2 = case Group of
        all ->
            AndFilters1;
        _ ->
            [#{field=><<"group">>, op=>eq, value=>Group}|AndFilters1]
    end,
    AndFilters3 = case Type of
        all ->
            AndFilters2;
        _ ->
            [#{field=><<"resource">>, op=>eq, value=>Type}|AndFilters2]
    end,
    Filters2 = Filters1#{'and' => AndFilters3},
    SearchSpec2 = SearchSpec#{filter => Filters2},
    get_query(SrvId, {service_search_actors_id, SearchSpec2}, []);

get_query(_SrvId, {service_delete_actors, DoDelete, SearchSpec}, _Opts) ->
    SQLFilters = make_sql_filters(SearchSpec),
    Query = [
        case DoDelete of
            false ->
                <<"SELECT COUNT(*) FROM actors">>;
            true ->
                <<"DELETE FROM actors">>
        end,
        SQLFilters,
        <<";">>
    ],
    {ok, {pgsql, Query, #{result_fun=>fun pgsql_delete/2}}};

get_query(_SrvId, {service_delete_old_actors, Domain, Group, Type, Epoch, Opts}, _Opts) ->
    Query = [
        <<"DELETE FROM actors">>,
        <<" WHERE \"group\"=">>, quote(Group), <<" AND resource=">>, quote(Type),
        <<" AND last_update<">>, quote(Epoch),
        <<" AND ">>, filter_path(Domain, Opts),
        <<";">>
    ],
    {ok, {pgsql, Query, #{result_fun=>fun pgsql_delete/2}}};

get_query(_SrvId, QueryType, _Opts) ->
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
                domain = Domain,
                group = Group,
                vsn = Vsn,
                resource = Res,
                name = Name
            },
            data = nklib_json:decode(Data),
            metadata = nklib_json:decode(MetaData),
            hash = Hash
        }
        || {UID, Domain, Group, Vsn, Res, Name, {jsonb, Data}, {jsonb, MetaData}, Hash} <- Rows
    ],
    {ok, Actors, Meta#{size=>Size}}.


%% @private
pgsql_totals_actors([{{select, 1}, [{Total}], _}, {{select, Size}, Rows, _OpMeta}], Meta) ->
    Actors = [
        #actor{
            id = #actor_id{
                uid = UID,
                domain = Domain,
                group = Group,
                vsn = Vsn,
                resource = Res,
                name = Name
            },
            data = nklib_json:decode(Data),
            metadata = nklib_json:decode(MetaData),
            hash = Hash
        }
        || {UID, Domain, Group, Vsn, Res, Name, {jsonb, Data}, {jsonb, MetaData}, Hash} <- Rows
    ],
    {ok, Actors, Meta#{size=>Size, total=>Total}}.


%% @private
pgsql_actors_id([{{select, Size}, Rows, _OpMeta}], Meta) ->
    Actors = [
        #actor_id{
            domain = Domain,
            uid = UID,
            group = Group,
            vsn = Vsn,
            resource = Res,
            name = Name
        }
        || {UID, Domain, Group, Vsn, Res, Name, _Updated} <- Rows
    ],
    Last = case lists:reverse(Rows) of
        [{_UID, _Domain, _Group, _Vsn, _Res, _Name, Updated}|_] ->
            Updated;
        [] ->
            undefined
    end,
    {ok, Actors, Meta#{size=>Size, last_updated=>Last}}.


%% @private
pgsql_totals_actors_id([{{select, 1}, [{Total}], _}, {{select, Size}, Rows, _OpMeta}], Meta) ->
    Actors = [
        #actor_id{
            domain = Domain,
            uid = UID,
            group = Group,
            vsn = Vsn,
            resource = Res,
            name = Name
        }
        || {UID, Domain, Group, Vsn, Res, Name, _Updated} <- Rows
    ],
    Last = case lists:reverse(Rows) of
        [{_UID, _Domain, _Group, _Vsn, _Res, _Name, Updated}|_] ->
            Updated;
        [] ->
            undefined
    end,
    {ok, Actors, Meta#{size=>Size, total=>Total, last_updated=>Last}}.


%% @private
pgsql_delete([{{delete, Total}, [], _}], Meta) ->
    {ok, Total, Meta};

pgsql_delete([{{select, _}, [{Total}], _}], Meta) ->
    {ok, Total, Meta}.



%% ===================================================================
%% Filters
%% ===================================================================

%% @private
make_sql_filters(#{domain:=Domain}=Params) ->
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
    PathFilter = list_to_binary(filter_path(Domain, Params)),
    FilterList = [PathFilter | AndFilters2 ++ OrFilters4 ++ NotFilters3],
    Where = nklib_util:bjoin(FilterList, <<" AND ">>),
    [<<" WHERE ">>, Where].


%% @private
expand_filter([], Acc) ->
    Acc;

expand_filter([#{field:=Field, value:=Value}=Term|Rest], Acc) ->
    Op = maps:get(op, Term, eq),
    Type = maps:get(type, Term, string),
    Value2 = case Type of
        _ when Op==exists ->
            to_boolean(Value);
        string when Op==values, is_list(Value) ->
            [to_bin(V) || V <- Value];
        string ->
            to_bin(Value);
        integer when Op==values, is_list(Value) ->
            [to_integer(V) || V <- Value];
        integer ->
            to_integer(Value);
        boolean when Op==values, is_list(Value) ->
            [to_boolean(V) || V <- Value];
        boolean ->
            to_boolean(Value);
        array ->
            Value
    end,
    expand_filter(Rest, [{Field, Op, Value2, Type}|Acc]).


%% @private
make_filter([], Acc) ->
    Acc;

%% Generates data -> 'spec' -> 'phone' @> '[{"phone": "123"}]
make_filter([{Field, eq, Val, array} | Rest], Acc) ->
    Field2 = get_field_db_name(Field),
    L = binary:split(Field2, <<".">>, [global]),
    [Last|Base1] = lists:reverse(L),
    Base2 = nklib_util:bjoin(lists:reverse(Base1), $.),
    Val2 = if
        is_binary(Val) -> [$", Val, $"];
        is_list(Val) -> [$", Val, $"];
        Val==true; Val==false -> to_bin(Val);
        is_atom(Val) -> [$", to_bin(Val), $"];
        true -> to_bin(Val)
    end,
    Json = [<<"'[{\"">>, Last, <<"\": ">>, Val2, <<"}]'">>],
    Filter = [$(, json_value(Base2, json), <<" @> ">>, Json, $)],
    make_filter(Rest, [list_to_binary(Filter) | Acc]);

make_filter([{Field, _Op, _Val, array} | Rest], Acc) ->
    lager:warning("using invalid array operator at ~p: ~p", [?MODULE, Field]),
    make_filter(Rest, Acc);

make_filter([{<<"group+resource">>, eq, Val, string} | Rest], Acc) ->
    [Group, Type] = binary:split(Val, <<"+">>),
    Filter = <<"(\"group\"='", Group/binary, "' AND resource='", Type/binary, "')">>,
    make_filter(Rest, [Filter | Acc]);

make_filter([{<<"metadata.fts.", Field/binary>>, Op, Val, string} | Rest], Acc) ->
    Word = nkservice_actor_util:fts_normalize_word(Val),
    Filter = case {Field, Op} of
        {<<"*">>, eq} ->
            % We search for an specific word in all fields
            % For example fieldX:valueY, found by LIKE '%:valueY %'
            % (final space makes sure word has finished)
            <<"(fts_words LIKE '%:", Word/binary, " %')">>;
        {<<"*">>, prefix} ->
            % We search for a prefix word in all fields
            % For example fieldX:valueYXX, found by LIKE '%:valueY%'
            <<"(fts_words LIKE '%:", Word/binary, "%')">>;
        {_, eq} ->
            % We search for an specific word in an specific fields
            % For example fieldX:valueYXX, found by LIKE '% FieldX:valueY %'
            <<"(fts_words LIKE '% ", Field/binary, $:, Word/binary, " %')">>;
        {_, prefix} ->
            % We search for a prefix word in an specific fields
            % For example fieldX:valueYXX, found by LIKE '% FieldX:valueY%'
            <<"(fts_words LIKE '% ", Field/binary, $:, Word/binary, "%')">>;
        _ ->
            <<"(TRUE = FALSE)">>
    end,
    make_filter(Rest, [Filter | Acc]);

make_filter([{<<"metadata.isEnabled">>, eq, Bool, boolean}|Rest], Acc) ->
    Filter = case Bool of
        true ->
            <<"((NOT metadata ? 'isEnabled') OR ((metadata->>'isEnabled')::BOOLEAN=TRUE))">>;
        false ->
            <<"((metadata->>'isEnabled')::BOOLEAN=FALSE)">>
    end,
    make_filter(Rest, [Filter|Acc]);

make_filter([{Field, exists, Bool, _}|Rest], Acc)
    when Field==<<"uid">>; Field==<<"domain">>; Field==<<"group">>; Field==<<"vsn">>;
         Field==<<"resource">>; Field==<<"path">>; Field==<<"hash">>; Field==<<"last_update">>;
         Field==<<"expires">>; Field==<<"fts_word">> ->
    Acc2 = case Bool of
        true ->
            Acc;
        false ->
            % Force no records
            [<<"(TRUE = FALSE)">>|Acc]
    end,
    make_filter(Rest, Acc2);

make_filter([{<<"metadata.links.", Ref/binary>>, exists, Bool, _}|Rest], Acc) ->
    Filter = [
        case Bool of
            true -> <<"(">>;
            false -> <<"(NOT ">>
        end,
        <<"metadata->'links' ? ">>, quote(Ref), <<")">>
    ],
    make_filter(Rest, [list_to_binary(Filter)|Acc]);

make_filter([{<<"metadata.labels.", Ref/binary>>, exists, Bool, _}|Rest], Acc) ->
    Filter = [
        case Bool of
            true -> <<"(">>;
            false -> <<"(NOT ">>
        end,
        <<"metadata->'labels' ? ">>, quote(Ref), <<")">>
    ],
    make_filter(Rest, [list_to_binary(Filter)|Acc]);

make_filter([{Field, exists, Bool, _}|Rest], Acc) ->
    Field2 = get_field_db_name(Field),
    L = binary:split(Field2, <<".">>, [global]),
    [Field3|Base1] = lists:reverse(L),
    Base2 = nklib_util:bjoin(lists:reverse(Base1), $.),
    Filter = [
        case Bool of
            true -> <<"(">>;
            false -> <<"(NOT ">>
        end,
        json_value(Base2, json),
        <<" ? ">>, quote(Field3), <<")">>
    ],
    make_filter(Rest, [list_to_binary(Filter)|Acc]);

make_filter([{Field, prefix, Val, string}|Rest], Acc) ->
    Field2 = get_field_db_name(Field),
    Filter = [
        $(,
        json_value(Field2, string),
        <<" LIKE ">>, quote(<<Val/binary, $%>>), $)
    ],
    make_filter(Rest, [list_to_binary(Filter)|Acc]);

make_filter([{Field, values, ValList, Type}|Rest], Acc) when is_list(ValList) ->
    Values = nklib_util:bjoin([quote(Val) || Val <- ValList], $,),
    Field2 = get_field_db_name(Field),
    Filter = [
        $(,
        json_value(Field2, Type),
        <<" IN (">>, Values, <<"))">>
    ],
    make_filter(Rest, [list_to_binary(Filter)|Acc]);

make_filter([{Field, values, Value, Type}|Rest], Acc) ->
    make_filter([{Field, values, [Value], Type}|Rest], Acc);

make_filter([{Field, Op, Val, Type} | Rest], Acc) ->
    Field2 = get_field_db_name(Field),
    Filter = [$(, get_op(json_value(Field2, Type), Op, Val), $)],
    make_filter(Rest, [list_to_binary(Filter) | Acc]).


%% @private
get_op(Field, eq, Value) -> [Field, << "=" >>, quote(Value)];
get_op(Field, ne, Value) -> [Field, <<" <> ">>, quote(Value)];
get_op(Field, lt, Value) -> [Field, <<" < ">>, quote(Value)];
get_op(Field, lte, Value) -> [Field, <<" <= ">>, quote(Value)];
get_op(Field, gt, Value) -> [Field, <<" > ">>, quote(Value)];
get_op(Field, gte, Value) -> [Field, <<" >= ">>, quote(Value)].


%% @private
get_field_db_name(<<"uid">>) -> <<"uid">>;
get_field_db_name(<<"domain">>) -> <<"domain">>;
get_field_db_name(<<"group">>) -> <<"\"group\"">>;
get_field_db_name(<<"vsn">>) -> <<"vsn">>;
get_field_db_name(<<"resource">>) -> <<"resource">>;
get_field_db_name(<<"name">>) -> <<"name">>;
get_field_db_name(<<"hash">>) -> <<"hash">>;
get_field_db_name(<<"path">>) -> <<"path">>;
get_field_db_name(<<"last_update">>) -> <<"last_update">>;
get_field_db_name(<<"expires">>) -> <<"expires">>;
get_field_db_name(<<"fts_word">>) -> <<"fts_word">>;
get_field_db_name(<<"data.", _/binary>>=Field) -> Field;
get_field_db_name(<<"metadata.uid">>) -> <<"uid">>;
get_field_db_name(<<"metadata.domain">>) -> <<"domain">>;
get_field_db_name(<<"metadata.name">>) -> <<"name">>;
get_field_db_name(<<"metadata.resourceVersion">>) -> <<"hash">>;
get_field_db_name(<<"metadata.updateTime">>) -> <<"last_update">>;
% Any other metadata is kept
get_field_db_name(<<"metadata.", _/binary>>=Field) -> Field;
% Any other field should be inside data in this implementation
get_field_db_name(Field) -> <<"data.", Field/binary>>.


%% @private
make_sql_sort(Params) ->
    Sort = expand_sort(maps:get(sort, Params, []), []),
    make_sort(Sort, []).


%% @private
expand_sort([], Acc) ->
    lists:reverse(Acc);

expand_sort([#{field:=Field}=Term|Rest], Acc) ->
    case Field of
        <<"group+resource">> ->
            % Special field used in domains
            expand_sort([Term#{field:=<<"group">>}, Term#{field:=<<"resource">>}|Rest], Acc);
        _ ->
            Order = maps:get(order, Term, asc),
            Type = maps:get(type, Term, string),
            expand_sort(Rest, [{Order, Field, Type}|Acc])
    end.


%% @private
make_sort([], []) ->
    <<>>;

make_sort([], Acc) ->
    [<<" ORDER BY ">>, nklib_util:bjoin(lists:reverse(Acc), $,)];

make_sort([{Order, Field, Type}|Rest], Acc) ->
    Item = [
        json_value(get_field_db_name(Field), Type),
        case Order of asc -> <<" ASC">>; desc -> <<" DESC">> end
    ],
    make_sort(Rest, [list_to_binary(Item)|Acc]).

-compile(export_all).


%% @private
%% Extracts a field inside a JSON,  it and casts it to json, string, integer o boolean
json_value(Field, Type) ->
    json_value(Field, Type, [], []).


%% @private
json_value(Field, Type, [<<"links">>, <<"metadata">>], Acc) ->
    finish_json_value(Type, Field, Acc);

json_value(Field, Type, [<<"labels">>, <<"metadata">>], Acc) ->
    finish_json_value(Type, Field, Acc);

json_value(Field, Type, Heads, Acc) ->
    case binary:split(Field, <<".">>) of
        [Single] when Acc==[] ->
            % No "." at all
            Single;
        [Last] ->
            finish_json_value(Type, Last, Acc);
        [Base, Rest] when Acc==[] ->
            json_value(Rest, Type, [Base|Heads], [Base, <<"->">>]);
        [Base, Rest] ->
            json_value(Rest, Type, [Base|Heads], Acc++[$', Base, $', <<"->">>])
    end.

finish_json_value(Type, Last, Acc) ->
    case Type of
        json ->
            Acc++[$', Last, $'];
        string ->
            Acc++[$>, $', Last, $'];    % '>' finishes ->>
        integer ->
            [$(|Acc] ++ [$>, $', Last, $', <<")::INTEGER">>];
        boolean ->
            [$(|Acc] ++ [$>, $', Last, $', <<")::BOOLEAN">>]
    end.



%% @private
filter_path(Domain, Opts) ->
    Path = nkservice_actor_util:make_path(Domain),
    case Opts of
        #{deep:=true} ->
            case Path of
                <<>> ->
                    [<<"TRUE">>];
                _ ->
                    [<<"(path LIKE ">>, quote(<<Path/binary, "%">>), <<")">>]
            end;
        _ ->
            [<<"(path = ">>, quote(Path), <<")">>]
    end.


%% @private
quote(Term) ->
    nkservice_pgsql_util:quote(Term).


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).

%% @private
to_integer(Term) when is_integer(Term) ->
    Term;
to_integer(Term) ->
    case nklib_util:to_integer(Term) of
        error -> 0;
        Integer -> Integer
    end.

%% @private
to_boolean(Term) when is_boolean(Term) ->
    Term;
to_boolean(Term) ->
    case nklib_util:to_boolean(Term) of
        error -> false;
        Boolean -> Boolean
    end.
