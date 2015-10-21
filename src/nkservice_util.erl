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

-export([parse_syntax/1, parse_syntax/2, parse_syntax/3]).
-export([defaults/0, syntax/0]).
-export([safe_call/3]).




%% ===================================================================
%% Public
%% ===================================================================




%% @private
-spec parse_syntax(map()|list()) ->
    {ok, map()} | {error, term()}.

parse_syntax(Data) ->
    parse_syntax(Data, syntax(), defaults()).


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


%% @private
-spec safe_call(module(), atom(), list()) ->
    term() | not_exported | error.

safe_call(Module, Fun, Args) ->
    try
        case erlang:function_exported(Module, Fun, length(Args)) of
            false ->
                not_exported;
            true ->
                apply(Module, Fun, Args)
        end
    catch
        C:E ->
            Trace = erlang:get_stacktrace(),
            lager:warning("Exception calling ~p:~p: ~p:~p\n~p",
                          [Module, Fun, C, E, Trace]),
            error
    end.


%% @private
syntax() ->
    #{
        id => atom,
        name => any,
        class => atom,
        plugins => {list, atom},
        callback => atom,
        log_level => log_level,
        transports => fun parse_transports/3
    }.


%% @private
defaults() ->
    #{
        log_level => debug
    }.


%% @private
parse_transports(_, [{{_Protocol, _Transp, _Ip, _Port}, _Opts}|_], _) ->
    ok;

parse_transports(_, Spec, _) ->
    case nkpacket:multi_resolve(Spec, #{resolve_type=>listen}) of
        {ok, List} ->
            {ok, List};
        _ ->
            error
    end.
