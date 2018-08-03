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

%% @doc GraphQL Type Callback
-module(nkservice_graphql_type).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').


-export([execute/1]).


%% @doc Called when a abstract object is found (interface or union)
%% to find its type
%% Called from graphql_execute:514 (others from :778)

execute({actor, Type, _Actor}) ->
    % lager:warning("NKLOG Resolving type ~p", [Type]),
    {ok, Type};

execute(_Obj) ->
    lager:error("NKLOG Invalid type execute  ~p", [_Obj]),
    {error, unknown_object}.
