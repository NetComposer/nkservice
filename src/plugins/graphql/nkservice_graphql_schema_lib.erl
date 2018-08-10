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

%% @doc NkDomain GraphQL main module

-module(nkservice_graphql_schema_lib).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([make_schema/1, all_actor_types/1, all_actor_modules/1]).

-include_lib("nkservice/include/nkservice.hrl").
-include_lib("nkservice/include/nkservice_actor.hrl").

-compile([export_all, nowarn_export_all]).
%% ===================================================================
%% API
%% ===================================================================


%% @doc Generates schema
make_schema(SrvId) ->
    SchemaTypes =  [scalars, enums, interfaces, types, inputs, queries, mutations],
    SchemaList = [make_schema(SrvId, SchemaType) || SchemaType <- SchemaTypes],
    list_to_binary(SchemaList).


%% @private
make_schema(SrvId, scalars) ->
    [
        [
            comment(Data#{no_margin=>true}),
            "scalar ", to_bin(T), "\n\n"
        ]
        || {T, Data} <- get_schema(SrvId, scalars)
    ];

make_schema(SrvId, enums) ->
    [
        [
            comment(Data#{no_margin=>true}),
            "enum ", to_bin(Name), " {\n",
            [["    ", to_bin(E), "\n"] || E <- EnumData], "}\n\n"
        ]
        || {Name, #{opts:=EnumData}=Data} <- get_schema(SrvId, enums)
    ];

make_schema(SrvId, types) ->
    [
        case maps:get(class, Data, none) of
            none ->
                [
                    comment(Data#{no_margin=>true}),
                    "type ",to_bin(Name), " {\n",
                    parse_fields(maps:get(fields, Data, #{})), "}\n\n"
                ];
            actor ->
                % For this type, inputs will also be generated on make_schema(SrvId, inputs)
                Fields1 = maps:get(fields, Data, #{}),
                Fields2 = add_type_connections(SrvId, Name, Fields1),
                [
                    comment(Data#{no_margin=>true}),
                    "type ", to_bin(Name), " implements Node, Actor {\n",
                    parse_fields(Fields2), "}\n\n",
                    "type ", to_bin(Name), "SearchResult {\n",
                    parse_fields(#{actors=>{list, Name}, totalCount=>integer}),
                    "}\n\n"
                ];
            connection ->
                Name2 = get_base_type(Name, <<"Connection">>),
                [
                    "type ", Name2, "Connection {\n",
                    parse_fields(#{
                         actors => {list, Name2},
                         totalCount => integer
                    }), "}\n\n"
                ]
        end
        || {Name, Data} <- get_schema(SrvId, types)
    ];

make_schema(SrvId, inputs) ->
    [
        [
            [
                comment(Data#{no_margin=>true}),
                "input ",to_bin(Name), " {\n",
                parse_fields(Fields),
                "}\n\n"
            ]
            || {Name, #{fields:=Fields}=Data} <- get_schema(SrvId, inputs)
        ],
        [
            case maps:get(class, Data, none) of
                actor ->
                    FilterFieldsName = <<(to_bin(Name))/binary, "FilterFields">>,
                    FilterFields = maps:get(filter_fields, Data),
                    QueryFilterName = <<(to_bin(Name))/binary, "FilterSpec">>,
                    QueryFilterFields = #{
                        'and' => {list, FilterFieldsName},
                        'or' => {list, FilterFieldsName},
                        'not' => {list, FilterFieldsName}
                    },
                    QuerySortName = <<(to_bin(Name))/binary, "SortFields">>,
                    SortFields = maps:get(sort_fields, Data),
                    %% Adds:
                    %% input NameFilterFields {
                    %%   ...
                    %% }
                    %% input NameQueryFilter {
                    %%   and : [NameFilterFields]
                    %%   not : [NameFilterFields]
                    %%   or : [NameFilterFields]
                    %% }
                    %%
                    %% input NameQuerySort {
                    %%  ...
                    %% }
                    [
                        "input ", FilterFieldsName, " {\n",
                        parse_fields(FilterFields), "}\n\n",
                        "input ", QueryFilterName, " {\n",
                        parse_fields(QueryFilterFields), "}\n\n",
                        "input ", QuerySortName, " {\n",
                        parse_fields(SortFields), "}\n\n"
                    ];
                _ ->
                    []
            end
            || {Name, Data} <- get_schema(SrvId, types)

        ]
    ];

make_schema(SrvId, interfaces) ->
    [
        [
            comment(Data#{no_margin=>true}),
            "interface ",to_bin(Name), " {\n", parse_fields(Fields), "}\n\n"
        ]
        || {Name, #{fields:=Fields}=Data} <- get_schema(SrvId, interfaces)
    ];

make_schema(SrvId, queries) ->
    [
        "type Query {\n",
        parse_fields(get_schema(SrvId, queries)),
        "}\n\n"
    ];

make_schema(SrvId, mutations) ->
    Schema = get_schema(SrvId, mutations),
    List = [
        [
            comment(Data),
            sp(), to_bin(Name), "(input: ", to_upper(Name), "Input!) : ",
            to_upper(Name), "Payload\n"
        ]
        || {Name, Data} <- Schema
    ],
    Inputs = [
        [
            "input ", to_upper(Name), "Input {\n",
            parse_fields(Input#{clientMutationId => string}),
            "}\n\n"
        ]
        || {Name, #{input:=Input}} <- Schema
    ],
    Types = [
        [
            "type ", to_upper(Name), "Payload {\n",
            parse_fields(Output#{clientMutationId => string}),
            "}\n\n"
        ]
        || {Name, #{output:=Output}} <- Schema
    ],
    [
        "type Mutation {\n", List, "}\n\n",
        Inputs,
        Types
    ].


%% @private
all_actor_types(SrvId) ->
    nkservice_graphql_plugin:get_actor_types(SrvId).


%% @private
all_actor_modules(SrvId) ->
    lists:map(
        fun(Type) ->
            #{module:=Module} = nkservice_graphql_plugin:get_actor_config(SrvId, Type),
            Module
        end,
        all_actor_types(SrvId)).



%% ===================================================================
%% Private
%% ===================================================================

%% @private
%% For a specific schema type, goes through all actor types
%% @see nkservice_graphql_callbacks:nkservice_graphql_schema/2
get_schema(SrvId, SchemaType) ->
    CoreSchema = ?CALL_SRV(SrvId, nkservice_graphql_core_schema, [SrvId, SchemaType, #{}]),
    Map = lists:foldl(
        fun(Mod, Acc) -> maps:merge(Acc, Mod:schema(SchemaType)) end,
        CoreSchema,
        all_actor_modules(SrvId)),
    maps:to_list(Map).


%% @private
get_base_type(Name, Bin) ->
    [Name2, _] = binary:split(to_bin(Name), Bin),
    Name2.


%% @private
add_type_connections(SrvId, ActorType, Fields) ->
    lists:foldl(
        fun(Mod, Acc) ->
            case erlang:function_exported(Mod, connections, 1) of
                true ->
                    maps:merge(Acc, Mod:connections(ActorType));
                false ->
                    Acc
            end
        end,
        Fields,
        all_actor_modules(SrvId)).


%%%% @private
%%core_actor_fields(SrvId) ->
%%    ?CALL_SRV(SrvId, nkservice_graphql_core_actor_fields, [#{}]).
%%
%%
%%%% @private
%%core_actor_filter_fields(SrvId) ->
%%    ?CALL_SRV(SrvId, nkservice_graphql_core_actor_filter_fields, [#{}]).
%%
%%
%%%% @private
%%core_actor_sort_fields(SrvId) ->
%%    ?CALL_SRV(SrvId, nkservice_graphql_core_actor_sort_fields, [#{}]).


%% @private
parse_fields(Map) when is_map(Map) ->
    parse_fields(maps:to_list(Map));

parse_fields(List) when is_list(List) ->
    parse_fields(List, []).


%% @private
parse_fields([], Acc) ->
    [Data || {_Field, Data} <- lists:sort(Acc)];

parse_fields([{Field, Value}|Rest], Acc) ->
    Line = case Value of
        {no_null, V} ->
            [field(Field), " : ", value(V), "!"];
        {no_null, V, Opts} ->
            [comment(Opts), field(Field, Opts), " : ", value(V), "!", default(Opts)];
        {list_no_null, V} ->
            [field(Field), " : [", value(V), "!]"];
        {list_no_null, V, Opts} ->
            [comment(Opts), field(Field, Opts), ": [", value(V), "!]", default(Opts)];
        {list, V} ->
            [field(Field), " : [", value(V), "]"];
        {list, V, Opts} ->
            [comment(Opts), field(Field, Opts), " : [", value(V), "]", default(Opts)];
        {connection, V} ->
            [field(Field), connection(#{}), " : ", to_bin(V), "Connection"];
        {connection, V, Opts} ->
            [comment(Opts), field(Field, Opts), connection(Opts), " : ", to_bin(V), "Connection"];
        {V, Opts} ->
            [comment(Opts), field(Field, Opts), " : ", value(V), default(Opts)];
        _ ->
            [field(Field), " : ", value(Value)]
    end,
    parse_fields(Rest, [{Field, [Line, "\n"]} | Acc]).


%% @private
value(id)       -> <<"ID">>;
value(integer)  -> <<"Int">>;
value(string)   -> <<"String">>;
value(actor)    -> <<"Actor">>;
value(boolean)  -> <<"Boolean">>;
value(Other)    -> to_bin(Other).


%% @private
field(F) ->
    field(F, #{}).


%% @private
field(F, Opts) ->
    [sp(), to_bin(F), params(Opts)].


%% @private
connection(Opts) ->
    Params = maps:with([from, size, filter, sort, last], Opts),
    ["Connection", params(#{params=>Params})].


%%%% @private
%%connection_last() ->
%%    ["Connection", params(#{params=>#{last=>{int, #{default=>5}}}})].


%% @private
comment(#{comment:=C}=Opts) ->
    case to_bin(C) of
        <<>> ->
            [];
        C2 ->
            [
                case Opts of #{no_margin:=true} -> []; _ -> sp() end,
                "+description(text: \"", C2, "\")\n"]
    end;

comment(_) ->
    [].


%% @private
default(#{default:=D}) ->
    <<" = ", (to_bin(D))/binary>>;

default(_Opts) ->
    [].


%% @private
sp() -> <<"    ">>.


%% @private
params(#{params:=Map}) ->
    ["(\n", [[sp(), L] || L <- parse_fields(Map)], sp(), ")"];

params(_) ->
    [].


%% @private
to_bin(T) when is_binary(T)-> T;
to_bin(T) -> nklib_util:to_binary(T).


%% @private A Type with uppercase in the first letter
to_upper(T) ->
    <<First, Rest/binary>> = to_bin(T),
    <<(nklib_util:to_upper(<<First>>))/binary, Rest/binary>>.



