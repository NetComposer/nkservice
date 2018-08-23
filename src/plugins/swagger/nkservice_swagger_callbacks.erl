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
-export([nkservice_rest_http/4]).

-define(LLOG(Type, Txt, Args), lager:Type("NkDOMAIN Swagger Callbacks: "++Txt, Args)).



%% ===================================================================
%% Types
%% ===================================================================

% -type continue() :: continue | {continue, list()}.



%% ===================================================================
%% Error
%% ===================================================================


%% @doc
msg(_)   		                        -> continue.




%% ===================================================================
%% Queries
%% ===================================================================


%% @doc
nkservice_rest_http(<<"nkservice-swagger">>, <<"GET">>, [<<"api-docs">>,<<"swagger.json">>], Req) ->
    {ok, Json} = nkservice_swagger:get_definition(),
    {http, 200, [{<<"content-type">>, <<"application/json">>}], Json, Req};

nkservice_rest_http(<<"nkservice-swagger">>, _Verb, _Path, _Req) ->
    {cowboy_static, {priv_dir, nkservice, "/swagger"}};

nkservice_rest_http(_Id, _Method, _Path, _Req) ->
    continue.


