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
-module(nkservice_httppool_sample).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-define(SRV, pool_test).

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
                id => pool1,
                class => 'HttpPool',
                config => #{
                    targets => [
                        #{
                            url => "http://127.0.0.1:9000"
                        }
                    ],
                    debug => true
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


getRequest() ->
    nkservice_luerl_instance:call({?SRV, s1, main}, [getRequest], []).


s1() -> <<"
    poolConfig = {
        id = 'pool2',
        targets = {
            {
                url = 'http://127.0.0.1:9000',
                weight = 100,
                pool = 5
            }
        },
        resolveInterval = 0,
        debug = true
    }

    mypool2 = startPackage('HttpPool', poolConfig)

    function getRequest()
        return mypool2.request('get', '/', {}, '')
    end

">>.

