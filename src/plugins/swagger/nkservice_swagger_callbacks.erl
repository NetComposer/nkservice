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

%% @doc Service callback module
-module(nkservice_swagger_callbacks).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([msg/1]).
-export([nkservice_swagger_get_spec/1]).
-export([nkservice_rest_http/4]).

-define(LLOG(Type, Txt, Args), lager:Type("NkDOMAIN Swagger Callbacks: "++Txt, Args)).
-include("nkservice.hrl").

%% ===================================================================
%% Types
%% ===================================================================

% -type continue() :: continue | {continue, list()}.



%% ===================================================================
%% Error
%% ===================================================================


%% @doc
msg(_) -> continue.


%% ===================================================================
%% Offered callbacks
%% ===================================================================


%% @doc Implement to supply the swagger definition for this service
-spec nkservice_swagger_get_spec(nkservice:id()) ->
    {ok, binary()} | {error, term()}.

nkservice_swagger_get_spec(_SrvId) ->
    Path = filename:join([code:priv_dir(nkservice), "swagger_sample.json"]),
    {ok, File} = file:read_file(Path),
    {ok, File}.



%% ===================================================================
%% Implemented callbacks
%% ===================================================================


%% @doc
nkservice_rest_http(<<"nkservice-swagger">>, <<"GET">>, [], _Req) ->
    {redirect, "/index.html"};

nkservice_rest_http(<<"nkservice-swagger">>, <<"GET">>, [<<"index.html">>], Req) ->
    Path = filename:join([code:priv_dir(nkservice), "swagger", "index.html"]),
    {ok, Index1} = file:read_file(Path),
    Substs = [
        {
            <<"SwaggerUIStandalonePreset">>,
            <<"SwaggerUIStandalonePreset.slice(1)">>     % Remove header
        },
        {
            <<"url: \"https://petstore.swagger.io/v2/swagger.json\"">>,
            <<"url: window.location.protocol + '//' + window.location.host + '/swagger.json'">>
        }
    ],
    Index2 = lists:foldl(
        fun({Old, New}, Acc) -> binary:replace(Acc, Old, New) end,
        Index1,
        Substs
    ),
    {http, 200, [{<<"content-type">>, <<"text/html">>}], Index2, Req};

nkservice_rest_http(<<"nkservice-swagger">>, <<"GET">>, [<<"swagger.json">>], Req) ->
    #{srv:=SrvId} = Req,
    case ?CALL_SRV(SrvId, nkservice_swagger_get_spec, [SrvId]) of
        {ok, Json} ->
            {http, 200, [{<<"content-type">>, <<"application/json">>}], Json, Req};
        {error, Error} ->
            ?LLOG(warning, "error calling ~p:nkservice_swagger_get_spec/1: ~p",
                  [SrvId, Error]),
            {http, 500, [], <<>>, Req}
    end;

nkservice_rest_http(<<"nkservice-swagger">>, _Verb, _Path, _Req) ->
    {cowboy_static, {priv_dir, nkservice, "/swagger"}};

nkservice_rest_http(_Id, _Method, _Path, _Req) ->
    continue.


