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

%% @doc
-module(nkservice_graphql_scalar).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([input/2, output/2]).

%% @doc
%%input(<<"UnixTime">>, Input) ->
%%    case is_integer(Input) andalso Input > 0 of
%%        true ->
%%            {ok, Input};
%%        false ->
%%            {error, bad_unixtime}
%%    end;

input(_Type, Val) ->
    %lager:error("In Val: ~p", [Val]),
    {ok, Val}.


%% @doc
output(_Type, Val) ->
    %
    % lager:error("Out Val: ~p", [Val]),
    {ok, Val}.
