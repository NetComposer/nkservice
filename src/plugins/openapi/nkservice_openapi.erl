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

%% @doc OpenAPI server and support
%%
%% - Contents in priv/openapi copied directly from dist in
%%   https://github.com/swagger-api/swagger-ui
%% - Script updates index.html in nkservice_openapi_callbacks
%% - Must implement nkservice_openapi_get_spec/1
%% - https://swagger.io/docs/specification/about/

-module(nkservice_openapi).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([compile/1, rest_http/2]).

-define(LLOG(Type, Txt, Args), lager:Type("NkSERVICE OpenAPI: "++Txt, Args)).
-include("nkservice.hrl").


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Generate de JSON specification
compile(SrvId) ->
    case ?CALL_SRV(SrvId, nkservice_openapi_get_spec, [SrvId]) of
        {ok, Map} when is_map(Map) ->
            {ok, nklib_json:encode_sorted(Map)};
        {ok, Json} when is_binary(Json) ->
            {ok, Json};
        {error, Error} ->
            {error, Error}
    end.


%% @doc REST processing
rest_http([], _Req) ->
    {redirect, "/index.html"};

rest_http([<<"index.html">>], Req) ->
    Path = filename:join([code:priv_dir(nkservice), "swagger-ui", "index.html"]),
    {ok, Index1} = file:read_file(Path),
    UrlPath1 = nkservice_rest_http:get_full_path(Req),
    UrlPath2 = binary:replace(UrlPath1, <<"index.html">>, <<"openapi.json">>),
    Substs = [
        {
            <<"SwaggerUIStandalonePreset">>,
            <<"SwaggerUIStandalonePreset.slice(1)">>     % Remove header
        },
        {
            <<"url: \"https://petstore.swagger.io/v2/swagger.json\"">>,
            <<"url: window.location.protocol + '//' + window.location.host + '",
                UrlPath2/binary, "'">>
        }
    ],
    Index2 = lists:foldl(
        fun({Old, New}, Acc) -> binary:replace(Acc, Old, New) end,
        Index1,
        Substs
    ),

    {http, 200, [{<<"content-type">>, <<"text/html">>}], Index2, Req};

rest_http([<<"openapi.json">>], #{srv:=SrvId}=Req) ->
    case compile(SrvId) of
        {ok, Json} ->
            {http, 200, [{<<"content-type">>, <<"application/json">>}], Json, Req};
        {error, Error} ->
            ?LLOG(warning, "error calling ~p:nkservice_openapi_get_spec/1: ~p",
                [SrvId, Error]),
            {http, 500, [], <<>>, Req}
    end;

rest_http(_Path, _Req) ->
    Dir = code:priv_dir(nkservice),
    _File = filename:join([Dir, <<"swagger-ui">>, _Path]),
    {ok, Bin} = file:read_file(_File),
    {http, 200, [], Bin, _Req}.


%%    lager:error("NKLOG PATH ~p ~p ~p", [Dir, _Path, _File]),
%%    {cowboy_static, {priv_dir, nkservice, "swagger-ui"}}.

