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

%% @doc Actor Syntax
-module(nkservice_actor_syntax).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([syntax/0, syntax/2]).
-export([syntax_parse_fun/2]).


%% ===================================================================
%% Syntax
%% ===================================================================


%% @private
syntax() ->
    syntax(map, #{'__allow_unknown' => true}).


%% @private
syntax(Spec, Meta) ->
    #{
        uid => binary,
        srv => atom,
        class => binary,
        type => binary,
        name => binary,
        vsn => binary,
        spec => Spec,
        metadata => Meta#{
            <<"resourceVersion">> => binary,
            <<"generation">> => pos_integer,
            <<"creationTime">> => date_3339,
            <<"updateTime">> => date_3339,
            <<"isEnabled">> => boolean,
            <<"isActivated">> => boolean,
            <<"expiresTime">> => date_3339,
            <<"labels">> => fun ?MODULE:syntax_parse_fun/2,
            <<"annotations">> => fun ?MODULE:syntax_parse_fun/2,
            <<"links">> => fun ?MODULE:syntax_parse_fun/2,
            <<"fts">> => fun ?MODULE:syntax_parse_fun/2,
            <<"isInAlarm">> => boolean,
            <<"alarms">> => {list, binary},
            <<"nextStatusTime">> => date_3339,
            <<"description">> => binary,
            <<"createdBy">> => binary,
            <<"updatedBy">> => binary
        },
        '__mandatory' => [srv, class, type, name, vsn],
        '__defaults' => #{
            spec => #{},
            metadata => #{}
        }
    }.


%% @private
syntax_parse_fun(Key, Map) when is_map(Map) ->
    List = [{to_bin(K), make_value(Key, V)} || {K, V} <- maps:to_list(Map)],
    {ok, maps:from_list(List)};

syntax_parse_fun(_Key, _Val) ->
    error.


%% @private
make_value(<<"labels">>, Val) when is_binary(Val) -> Val;
make_value(<<"labels">>, Val) when is_integer(Val) -> Val;
make_value(<<"labels">>, Val) when is_boolean(Val) -> Val;
make_value(<<"labels">>, Val) -> to_bin(Val);
make_value(<<"annotations">>, Val) when is_binary(Val) -> Val;
make_value(<<"annotations">>, Val) when is_integer(Val) -> Val;
make_value(<<"annotations">>, Val) when is_boolean(Val) -> Val;
make_value(<<"annotations">>, Val) -> to_bin(Val);
make_value(<<"links">>, Val) -> to_bin(Val);
make_value(<<"fts">>, Val) when is_binary(Val) -> normalize_multi(Val);
make_value(<<"fts">>, Val) when is_integer(Val) -> make_value(<<"fts">>, to_bin(Val));
make_value(<<"fts">>, Val) when is_list(Val) -> Val.


%% @doc
normalize_multi(Text) ->
    nklib_parse:normalize_words(Text, #{unrecognized=>keep}).


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).