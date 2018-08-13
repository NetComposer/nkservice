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

%% @doc Actor Search
-module(nkservice_actor_search).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([parse/1, parse/2]).
-export_type([search_spec/0, filter/0]).

-include("nkservice_actor.hrl").



%% ==================================================================
%% Types
%% ===================================================================



-type search_spec() ::
    #{
        srv => nkservice:id(),
        deep => boolean(),
        from => pos_integer(),
        size => pos_integer(),
        totals => boolean(),
        filter => filter(),
        sort => [sort_spec()]
    }.


-type filter() ::
    #{
        'and' => [filter_spec()],
        'or' => [filter_spec()],
        'not' => [filter_spec()]
    }.

% '.' used to separate levels in JSON
-type field_name() :: binary().


% Field types are used to cast the correct value from JSON
% Byt default, they will be extracted as strings (so they will be sorted incorrectly)
-type field_type() :: string | boolean | integer.


-type filter_spec() ::
    #{
        field => field_name(),
        type => field_type(),
        op => eq | ne | lt | lte | gt | gte | values | exists | prefix,
        value => value() | [value()]
    }.


-type value() :: string() | binary() | integer() | boolean().


-type sort_spec() ::
    #{
        field => field_name(),      % '.' used to separate levels in JSON
        type => field_type(),
        order => asc | desc
    }.

-type search_opts() ::
    #{
        filter_fields => ordsets:ordset(binary()),
        sort_fields => ordsets:ordset(binary()),
        field_type => #{field_name() => field_type()},
        field_trans => #{field_name() => field_name()|fun((field_name()) -> field_name())}
    }.



%% ===================================================================
%% Syntax
%% ===================================================================

%% @doc
-spec parse(map()) ->
    {ok, map(), list()} | {error, term()}.

parse(Term) ->
    parse(Term, #{}).


%% @doc
%% If a field is defined in FieldTypes, 'type' will be added
-spec parse(map(), search_opts()) ->
    {ok, map(), list()} | {error, term()}.

parse(Term, Opts) ->
    case nklib_syntax:parse(Term, search_spec_syntax(), #{search_opts=>Opts}) of
        {ok, Parsed, []} ->
            {ok, Parsed};
        {ok, _, [Field|_]} ->
            {error, {field_unknown, Field}};
        {error, Error} ->
            {error, Error}
    end.


%% @private
search_spec_syntax() ->
    #{
        from => pos_integer,
        size => pos_integer,
        srv => atom,
        deep => boolean,
        totals => boolean,
        filter => #{
            'and' => {list, search_spec_syntax_filter()},
            'or' => {list, search_spec_syntax_filter()},
            'not' => {list, search_spec_syntax_filter()}
        },
        sort => {list, search_spec_syntax_sort()},
        '__mandatory' => [srv]
    }.


%% @private
search_spec_syntax_filter() ->
    #{
        field => binary,
        type => {atom, [string, integer, boolean]},
        op => {atom, [eq, ne, lt, lte, gt, gte, values, exists, prefix]},
        value => any,
        '__mandatory' => [field, value],
        '__defaults' => #{op => eq},
        '__post_check' => fun syntax_parse_filter/2
    }.


%% @private
search_spec_syntax_sort() ->
    #{
        field => binary,
        type => {atom, [string, integer, boolean]},
        order => {atom, [asc, desc]},
        '__mandatory' => [field],
        '__defaults' => #{order => asc},
        '__post_check' => fun syntax_parse_sort/2
    }.


%% @private
syntax_parse_filter(List, #{search_opts:=Opts}) ->
    Valid = maps:get(filter_fields, Opts, []),
    syntax_parse_fields(List, Valid, Opts).


%% @private
syntax_parse_sort(List, #{search_opts:=Opts}) ->
    Valid = maps:get(sort_fields, Opts, []),
    syntax_parse_fields(List, Valid, Opts).


%% @private
%% Checks the filter in the valid list
syntax_parse_fields(List, ValidFields, Opts) ->
    {Field, List2} = get_field(List, Opts),
    case Field of
        <<"metadata.labels.", _/binary>> ->
            syntax_parse_type(Field, List2, Opts);
        <<"metadata.links.", _/binary>> ->
            syntax_parse_type(Field, List2, Opts);
        <<"metadata.fts.", _/binary>> ->
            syntax_parse_type(Field, List2, Opts);
        _ ->
            case ValidFields of
            [] ->
                syntax_parse_type(Field, List2, Opts);
            _ ->
                case ordsets:is_element(Field, ValidFields) of
                    true ->
                        syntax_parse_type(Field, List2, Opts);
                    false ->
                        {error, {field_invalid, Field}}
                end
        end
    end.


%% @private
get_field(List, Opts) ->
    {field, Field} = lists:keyfind(field, 1, List),
    Trans = maps:get(field_trans, Opts, #{}),
    Field2 = case maps:find(Field, Trans) of
        {ok, Value} when is_binary(Value) ->
            Value;
        {ok, Value} when is_function(Value, 1)->
            Value(Field);
        error ->
            Field
    end,
    List2 = case Field == Field2 of
        true ->
            List;
        false ->
            lists:keystore(field, 1, List, {field, Field2})
    end,
    {Field2, List2}.


%% @private
syntax_parse_type(Field, List, Opts) ->
    Types = maps:get(field_type, Opts, #{}),
    case maps:find(Field, Types) of
        {ok, Type} ->
            case lists:keyfind(type, 1, List) of
                {type, ListType} when Type /= ListType ->
                    {error, {conflicting_field_type, Field}};
                {type, Type} ->
                    {ok, List};
                false ->
                    {ok, [{type, Type}|List]}
            end;
        error ->
            {ok, List}
    end.




%%%% @private
%%to_bin(Term) when is_binary(Term) -> Term;
%%to_bin(Term) -> nklib_util:to_binary(Term).