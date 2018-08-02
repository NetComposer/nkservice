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
-export([parse/1]).
-export_type([search_spec/0]).

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
        filter => #{
            'and' => [filter_spec()],
            'or' => [filter_spec()],
            'not' => [filter_spec()]
        },
        sort => [sort_spec()]
    }.

% '.' used to separate levels in JSON
-type field() :: binary() | {binary(), field_value()}.

-type field_value() :: string | boolean | integer | json.

-type filter_spec() ::
    #{
        field => field(),
        op => eq | ne | lt | lte | gt | gte | values | exists | prefix,
        value => value() | [value()]
    }.


-type value() :: string() | binary() | integer() | boolean().


-type sort_spec() ::
    #{
        field => field(),      % '.' used to separate levels in JSON
        order => asc | desc
    }.



%% ===================================================================
%% Syntax
%% ===================================================================

%% @doc
parse(Term) ->
    case nklib_syntax:parse(Term, search_spec_syntax()) of
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
        field => fun syntax_field/1,
        op => {atom, [eq, ne, lt, lte, gt, gte, values, exists, prefix]},
        value => any,
        '__mandatory' => [field, value],
        '__defaults' => #{op => eq}
        % '__post_check' => fun syntax_parse_value/1
    }.


%% @private
search_spec_syntax_sort() ->
    #{
        field => fun syntax_field/1,
        order => {atom, [asc, desc]},
        '__mandatory' => [field],
        '__defaults' => #{order => asc}
    }.


%% @private
syntax_field({Key, Type}) when Type==string; Type==integer; Type==boolean; Type==json ->
    {ok, {to_bin(Key), Type}};

syntax_field(Key) ->
    {ok, to_bin(Key)}.



%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).