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

%% @doc Backend module for luerl supporting Lager operations
-module(nkservice_luerl_lager).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([install/1]).

%% @private
install(State) ->
    luerl_emul:alloc_table(table(), State).

table() ->
    [
        {<<"debug">>, {function, fun debug/2}},
        {<<"info">>, {function, fun info/2}},
        {<<"notice">>, {function, fun notice/2}},
        {<<"warning">>, {function, fun warning/2}},
        {<<"error">>, {function, fun error/2}}
    ].


debug([Bin], State) when is_binary(Bin) ->
    lager:debug(Bin),
    {[], State}.

info([Bin], State) when is_binary(Bin) ->
    lager:info(Bin),
    {[], State}.

notice([Bin], State) when is_binary(Bin) ->
    lager:notice(Bin),
    {[], State}.

warning([Bin], State) when is_binary(Bin) ->
    lager:warning(Bin),
    {[], State}.

error([Bin], State) when is_binary(Bin) ->
    lager:error(Bin),
    {[], State}.

