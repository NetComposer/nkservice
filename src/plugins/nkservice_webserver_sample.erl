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
-module(nkservice_webserver_sample).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-define(SRV, web_test).

-compile(export_all).

-include_lib("nkservice/include/nkservice.hrl").

%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts the service
start() ->
    Spec = #{
        callback => ?MODULE,
        nkservice_webserver => [
            #{
                id => web1,
                url => "https://all:9010/test1, http://all:9011/testB",
                opts => #{debug=>false}
            },
            #{
                id => web2,
                url => "https://all:9010/test2",
                file_path => "/tmp"
            }
        ]
    },
    nkservice:start(?SRV, Spec).


%% @doc Stops the service
stop() ->
    nkservice:stop(?SRV).

test1() ->
    Url = "https://127.0.0.1:9010/test1/hi.txt",
    {ok, {{_, 200, _}, _Hs, "nkservice"}} = httpc:request(Url),
    Url2 = "http://127.0.0.1:9011/testB/hi.txt",
    {ok, {{_, 200, _}, _Hs2, "nkservice"}} = httpc:request(Url2),
    Src = filename:join(code:priv_dir(nkservice), "www/hi.txt"),
    {ok, _} = file:copy(Src, "/tmp/hi3.txt"),
    Url3 = "https://127.0.0.1:9010/test2/hi3.txt",
    {ok, {{_, 200, _}, _Hs3, "nkservice"}} = httpc:request(Url3),
    ok.




%% ===================================================================
%% API callbacks
%% ===================================================================

plugin_deps() ->
    [nkservice_webserver].

