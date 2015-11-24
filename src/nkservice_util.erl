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

-export([get_plugins/1, get_syntax/1]).
-export([make_id/1, parse_syntax/1, parse_syntax/2, parse_syntax/3]).


%% ===================================================================
%% Public
%% ===================================================================

%% Gets the expanded list of plugins from a service spec
%% Not used anymore?
-spec get_plugins(map()|list()) ->
    {ok, [atom()]} | {error, term()}.

get_plugins(Spec) ->
    Syntax = nkservice_syntax:syntax(),
    case nkservice_util:parse_syntax(Spec, Syntax, #{return=>map}) of
        {ok, Parsed} -> 
            Plugins1 = maps:get(plugins, Parsed, []),
            Plugins2 = case Spec of
                #{callback:=CallBack} -> [{CallBack, all}|Plugins1];
                _ -> Plugins1
            end,
            case nkservice_cache:get_plugins(Plugins2) of
                {ok, Plugins3} -> {ok, Plugins3};
                {error, Error} -> {error, {plugin_error, Error}}
            end;
        {error, Error} ->
            {error, {parse_error, Error}}
    end.


%% @doc Gets the list of final syntaxis with plugins
-spec get_syntax(map()|list()) ->
    map().

get_syntax(Spec) when is_map(Spec) ->
    case get_plugins(Spec) of
        {ok, Plugins} ->
            get_syntax(Plugins, #{});
        {error, _} ->
            #{}
    end;

get_syntax([First|_]=Plugins) when is_atom(First) ->
    case nkservice_cache:get_plugins(Plugins) of
        {ok, AllPlugins} ->
            get_syntax(AllPlugins, #{});
        {error, _} ->
            #{}
    end.


%% @private
get_syntax([], Syntax) ->
    Syntax;

get_syntax([Plugin|Rest], Syntax) ->
    case nklib_util:apply(Plugin, plugin_syntax, []) of
        Map when is_map(Map) ->
            get_syntax(Rest, maps:merge(Syntax, Map));
        _Other ->
            get_syntax(Rest, Syntax)
    end.





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



