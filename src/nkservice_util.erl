%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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

-module(nkservice_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([make_id/1, parse_syntax/1, parse_syntax/2, parse_syntax/3]).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Generates the service id from any name
-spec make_id(nkservice:name()) ->
    nkservice:id().

make_id(Name) ->
    list_to_atom(
        string:to_lower(
            case binary_to_list(nklib_util:hash36(Name)) of
                [F|Rest] when F>=$0, F=<$9 -> [$A+F-$0|Rest];
                Other -> Other
            end)).


%% @private
-spec parse_syntax(map()|list()) ->
    {ok, map()} | {error, term()}.

parse_syntax(Data) ->
    parse_syntax(Data, nkservice_syntax:syntax(), nkservice_syntax:defaults()).


%% @private
-spec parse_syntax(map()|list(), map()|list()) ->
    {ok, map()} | {error, term()}.

parse_syntax(Data, Syntax) ->
    parse_syntax(Data, Syntax, []).


%% @private
-spec parse_syntax(map()|list(), map()|list(), map()|list()) ->
    {ok, map()} | {error, term()}.

parse_syntax(Data, Syntax, Defaults) ->
    ParseOpts = #{return=>map, defaults=>Defaults},
    case nklib_config:parse_config(Data, Syntax, ParseOpts) of
        {ok, Parsed, Other} ->
            {ok, maps:merge(Other, Parsed)};
        {error, Error} ->
            {error, Error}
    end.



