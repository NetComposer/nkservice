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
-module(nkservice_openapi_callbacks).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([msg/1]).
-export([nkservice_openapi_get_spec/1]).
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


%% @doc Implement to supply the openapi definition for this service
-spec nkservice_openapi_get_spec(nkservice:id()) ->
    {ok, binary()} | {error, term()}.

nkservice_openapi_get_spec(_SrvId) ->
    Path = filename:join([code:priv_dir(nkservice), "swagger_sample.json"]),
    {ok, File} = file:read_file(Path),
    Map = nklib_json:decode(File),
    {ok, Map}.



%% ===================================================================
%% Implemented callbacks
%% ===================================================================


%% @doc
nkservice_rest_http(<<"nkservice-openapi">>, <<"GET">>, Path, Req) ->
    nkservice_openapi:rest_http(Path, Req);

nkservice_rest_http(_Id, _Method, _Path, _Req) ->
    continue.


