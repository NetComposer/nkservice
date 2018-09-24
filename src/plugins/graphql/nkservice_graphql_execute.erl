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

%% @doc NkDomain main module
-module(nkservice_graphql_execute).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([execute/4]).

%-include("nkdomain.hrl").
-include_lib("nkservice/include/nkservice.hrl").
-include_lib("nkservice/include/nkservice_actor.hrl").

%% ===================================================================
%% GraphQL Object callback
%% ===================================================================


%% @doc Called from GraphQL to extract fields on any type
execute(Ctx, Obj, Field, Args) ->
    #{nkmeta:=#{srv:=SrvId}} = Ctx,
    % lager:notice("NKLOG GraphQL Obj Execute: ~p ~p", [Field, Obj]),
    Res = case call_core_execute(SrvId, Field, Obj, Args) of
        continue ->
            case call_actor_execute(SrvId, Field, Obj, Args) of
                continue ->
                    lager:warning("NKLOG GRAPHQ UNKNOWN ~p ~p ~p ~p", [SrvId, Field, Obj, Args]),
                    {error, {field_unknown, Field}};
                {ok, Obj2} ->
                    {ok, Obj2};
                {error, Error} ->
                    {error, Error}
            end;
        {ok, Obj2} ->
            {ok, Obj2};
        {error, Error} ->
            {error, Error}
    end,
    % lager:error("NKLOG Execute Result ~p", [Res]),
    Res.


%% @private
call_actor_execute(SrvId, Field, Obj, Args) ->
    case catch nkservice_graphql_plugin:get_actor_connection_meta(SrvId, Field) of
        #{module:=Module}=Meta ->
            case erlang:function_exported(Module, execute, 5) of
                true ->
                    Module:execute(SrvId, Field, Obj, Meta, Args);
                false ->
                    continue
            end;
        _ ->
            continue
    end.


%% @private
call_core_execute(SrvId, Field, Obj, Args) ->
    ?CALL_SRV(SrvId, nkservice_graphql_execute, [SrvId, Field, Obj, #{}, Args]).
