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

-define(SRV, rest_test).
-define(WS, "wss://127.0.0.1:9010/ws").
-define(HTTP, "https://127.0.0.1:9010/rpc/api").

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("nkservice/include/nkservice.hrl").

%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts the service
start() ->
    Spec = #{
        callback => ?MODULE,
        nkservice_rest => [
            #{
                id => listen1,
                url => "https://all:9010/test1, wss:all:9010/test1/ws;idle_timeout=10",
                opts => #{
                    cowboy_opts => #{max_headers=>100}, % To test in nkpacket
                    debug=>true
                }
            }
        ],
        debug => [nkservice_rest]
    },
    nkservice:start(?SRV, Spec).


%% @doc Stops the service
stop() ->
    nkservice:stop(?SRV).

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
    Url = "wss://127.0.0.1:9010/test1/ws",
    {ok, #{}, Pid} = nkapi_client:start(?SRV, Url, u1, none, #{}),
    nkapi_client:stop(Pid).




%% ===================================================================
%% API callbacks
%% ===================================================================

plugin_deps() ->
    [nkservice_rest].

% Redirect .../test1/
nkservice_rest_http(<<"listen1">>, get, [<<>>], _Req) ->
    {redirect, "/index.html"};

% Redirect .../test1
nkservice_rest_http(<<"listen1">>, get, [], _Req) ->
    {redirect, "/index.html"};

nkservice_rest_http(<<"listen1">>, get, _Paths, _Req) ->
    {cowboy_static, {priv_dir, nkservice, "/www"}};

nkservice_rest_http(<<"listen1">>, post, [<<"test-a">>], Req) ->
    Qs = maps:from_list(nkservice_rest_http:get_qs(Req)),
    CT = nkservice_rest_http:get_ct(Req),
    {ok, Body, Req2} = nkservice_rest_http:get_body(Req, #{parse=>true}),
    Reply = nklib_json:encode(#{qs=>Qs, ct=>CT, body=>Body}),
    {http, 200, #{<<"header1">> => 1}, Reply, Req2};

nkservice_rest_http(_Id, _Method, _Path, _Req) ->
    continue.


nkservice_rest_text(<<"listen">>, Text, _NkPort, State) ->
    #{
        <<"cmd">> := <<"login">>,
        <<"tid">> := TId
    } = nklib_json:decode(Text),
    Reply = #{
        result => ok,
        tid => TId
    },
    nkservice_rest_protocol:send_async(self(), nklib_json:encode(Reply)),
    {ok, State}.

