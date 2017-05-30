%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Carlos Gonzalez Florido.  All Rights Reserved.
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
-module(nkservice_rest_sample).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-define(SRV, test).
-define(WS, "wss://127.0.0.1:9010/ws").
-define(HTTP, "https://127.0.0.1:9010/rpc/api").

-compile(export_all).

-include_lib("nkservice/include/nkservice.hrl").

%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts the service
start() ->
    Spec = #{
        callback => ?MODULE,
        rest_url => "https://all:9010/test1",
        webserver_url => "https://all:9010/webs",
        % rest_url => "wss:all:9010, ws:all:9011/ws, https://all:9010/test1",
        debug => [nkservice_rest],
        %plugins => [nkapi_log_gelf],
        packet_no_dns_cache => false
    },
    nkservice:start(test, Spec).


%% @doc Stops the service
stop() ->
    nkservice:stop(test).

test1() ->
    Url = "https://127.0.0.1:9010/test1/test-a?b=1&c=2",
    {ok, {{_, 200, _}, Hs, B}} = httpc:request(post, {Url, [], "test/test", "body1"}, [], []),
    [1] = nklib_util:get_value("header1", Hs),
    #{
        <<"ct">> := <<"test/test">>,
        <<"qs">> := #{<<"b">>:=<<"1">>, <<"c">>:=<<"2">>},
        <<"body">> := <<"body1">>
    } =
        nklib_json:decode(B).

test2() ->
    Url = "https://127.0.0.1:9010/webs/www/hi.txt",
    {ok, {{_, 200, _}, _, _B}} = httpc:request(Url).




%% ===================================================================
%% API callbacks
%% ===================================================================

plugin_deps() ->
    [nkservice_rest, nkservice_webserver].


nkservice_rest_http(post, [<<"test-a">>], Req, State) ->
    Qs = maps:from_list(nkservice_rest_http:get_qs(Req)),
    CT = nkservice_rest_http:get_ct(Req),
    Body = nkservice_rest_http:get_body(Req, #{parse=>true}),
    Reply = nklib_json:encode(#{qs=>Qs, ct=>CT, body=>Body}),
    {http, 200, [{<<"header1">>, 1}], Reply, State};

nkservice_rest_http(_Method, _Path, _Req, _State) ->
    continue.
