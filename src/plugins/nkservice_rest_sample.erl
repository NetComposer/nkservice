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
-module(nkservice_rest_sample).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-define(SRV, rest_test).
-define(WS, "wss://127.0.0.1:9010/ws").
-define(HTTP, "https://127.0.0.1:9010/rpc/api").

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("nkservice/include/nkservice.hrl").

-dialyzer({nowarn_function, start/0}).

%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts the service
start() ->
    Spec = #{
        plugins => [?MODULE],
        packages => [
            #{
                id => myrest,
                class => 'RestServer',
                config => #{
                    url => "https://node:9010/test1, wss:node:9010/test1/ws;idle_timeout=5000",
                    opts => #{
                        cowboy_opts => #{max_headers=>100}  % To test in nkpacket
                    },
                    debug => [nkpacket, http, ws]
                }
            }
        ],
        modules => [
            #{
                id => s1,
                class => luerl,
                code => s1(),
                debug => true
            }
        ]
    },
    nkservice:start(?SRV, Spec).


%% @doc Stops the service
stop() ->
    nkservice:stop(?SRV).



s1() -> <<"
    request = function(a)
        log.notice(json.encodePretty(a))
        if a.method == 'POST' then
            local body = {
                qs = a.qs,
                ct = a.contentType,
                body = a.body
            }
            body = json.encodePretty(body)
            return {code=200, headers={header1=1}, body=body}
        else
            return {code=501}
        end
    end

    restConfig = {
        id = 'myrest2',
        url = 'https://node:9010/test2, wss:node:9010/test2/ws;idle_timeout=5000',
        requestGetBody = true,
        requestParseBody = true,
        requestGetQs = true,
        requestCallback = request,
        debug = {'nkpacket', 'http', 'ws'}
    }

    myrest2 = startPackage('RestServer', restConfig)

    function dumpTable(o)
        if type(o) == 'table' then
            local s = '{ '
            for k,v in pairs(o) do
                if type(k) ~= 'number' then k = '\"'..k..'\"' end
                s = s .. '['..k..'] = ' .. dumpTable(v) .. ','
            end
            return s .. '} '
        else
            return tostring(o)
        end
    end

">>.



test1() ->
    Url = "https://127.0.0.1:9010/test1/test-a?b=1&c=2",
    {ok, {{_, 200, _}, Hs, B}} = httpc:request(post, {Url, [], "test/test", "body1"}, [], []),
    [1] = nklib_util:get_value("header1", Hs),
    #{
        <<"ct">> := <<"test/test">>,
        <<"qs">> := #{<<"b">>:=<<"1">>, <<"c">>:=<<"2">>},
        <<"body">> := <<"body1">>
    } =
        nklib_json:decode(B),
    ok.


test2() ->
    Url1 = "https://127.0.0.1:9010/test1/index.html",
    {ok, {{_, 200, _}, _, "<!DOC"++_}} = httpc:request(Url1),
    Url2 = "https://127.0.0.1:9010/test1/",
    {ok, {{_, 200, _}, _, "<!DOC"++_}} = httpc:request(Url2),
    Url3 = "https://127.0.0.1:9010/test1",
    {ok, {{_, 200, _}, _, "<!DOC"++_}} = httpc:request(Url3),
    Url4 = "https://127.0.0.1:9010/test1/dir/hi.txt",
    {ok, {{_, 200, _}, _, "nkservice"}} = httpc:request(Url4),
    ok.


test3() ->
    {ok, ConnPid} = gun:open("127.0.0.1", 9010, #{transport=>ssl}),
    gun:ws_upgrade(ConnPid, "/test1/ws"),
    receive {gun_ws_upgrade, ConnPid, ok, _Hds} -> ok after 100 -> error(?LINE) end,
    gun:ws_send(ConnPid, {text, "text1"}),
    receive {gun_ws, ConnPid, {text, <<"Reply: text1">>}} -> ok after 100 -> error(?LINE) end,
    gun:ws_send(ConnPid, {binary, <<"text2">>}),
    receive {gun_ws, ConnPid, {binary, <<"Reply2: text2">>}} -> ok after 100 -> error(?LINE) end,
    gun:ws_send(ConnPid, {text, nklib_json:encode(#{a=>1})}),
    Json = receive {gun_ws, ConnPid, {text, J}} -> J after 100 -> error(?LINE) end,
    #{<<"a">>:=1, <<"b">>:=2} = nklib_json:decode(Json),
    gun:close(ConnPid),
    gun:flush(ConnPid).


test4() ->
    Url = "https://127.0.0.1:9010/test2/test-a?b=1&c=2",
    {ok, {{_, 200, _}, Hs, B}} = httpc:request(post, {Url, [], "test/test", "body1"}, [], []),
    "1.0" = nklib_util:get_value("header1", Hs),
    #{
        <<"ct">> := <<"test/test">>,
        <<"qs">> := #{<<"b">>:=<<"1">>, <<"c">>:=<<"2">>},
        <<"body">> := <<"body1">>
    } =
        nklib_json:decode(B),
    {ok, {{_, 501, _}, _, _}} = httpc:request(Url),
    ok.







%% ===================================================================
%% API callbacks
%% ===================================================================

plugin_deps() ->
    [nkservice_rest].

% Redirect .../test1/
nkservice_rest_http(<<"myrest">>, <<"GET">>, [<<>>], _Req) ->
    {redirect, "/index.html"};

% Redirect .../test1
nkservice_rest_http(<<"myrest">>, <<"GET">>, [], _Req) ->
    {redirect, "/index.html"};

nkservice_rest_http(<<"myrest">>, <<"GET">>, _Paths, _Req) ->
    {cowboy_static, {priv_dir, nkservice, "/www"}};

nkservice_rest_http(<<"myrest">>, <<"POST">>, [<<"test-a">>], #{content_type:=CT}=Req) ->
    {ok, Body, Req2} = nkservice_rest_http:get_body(Req, #{parse=>true}),
    Qs = nkservice_rest_http:get_qs(Req),
    Reply = nklib_json:encode(#{qs=>maps:from_list(Qs), ct=>CT, body=>Body}),
    {http, 200, #{<<"header1">> => 1}, Reply, Req2};

nkservice_rest_http(_Id, _Method, _Path, _Req) ->
    continue.


nkservice_rest_frame(<<"myrest">>, {text, <<"{", _/binary>>=Json}, _NkPort, State) ->
    Decode1 = nklib_json:decode(Json),
    Decode2 = Decode1#{b=>2},
    {reply, {json, Decode2}, State};

nkservice_rest_frame(<<"myrest">>, {text, Text}, _NkPort, State) ->
    {reply, {text, <<"Reply: ", Text/binary>>}, State};

nkservice_rest_frame(<<"myrest">>, {binary, Bin}, _NkPort, State) ->
    {reply, {binary, <<"Reply2: ", Bin/binary>>}, State}.
