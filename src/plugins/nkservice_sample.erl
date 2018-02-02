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

-module(nkservice_sample).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([start/0, stop/0, update1/0]).

start() ->
    Spec = #{
        name => my_name,
        plugins => [
            #{
                id => webserver_1,
                class => nkservice_webserver,
                config => #{
                    url => "https://all:9010/test1, http://all:9011/testB",
                    opts => #{debug=>false}
                }
            },
            #{
                id => webserver_2,
                class => nkservice_webserver,
                config => #{
                    url => "https://all:9010/test2",
                    file_path => "/tmp"
                }
            }
        ],
        cache => [
            #{
                key => a,
                value => 1
            }
        ],
        listen => #{
            url => <<"http://all/1/2">>
        },
        debug => [
            #{
                key => a,
                spec => true
            }

        ]
    },
    nkservice:start(sample, Spec).


stop() ->
    nkservice:stop(sample).


% Try to modify parameters, activate remove

update1() ->
    nkservice:update(sample, #{
        plugins => [
            #{
                id => webserver_1,
                class => nkservice_webserver,
                remove => false,
                config => #{
                    url => "https://all:9010/test1, http://all:9011/testB",
                    opts => #{debug=>false}
                }
            },
            #{
                id => webserver_2,
                class => nkservice_webserver,
                remove => false,
                config => #{
                    url => "https://all:9010/test2",
                    file_path => "/tmp"
                }
            }

        ],
        listen => #{
            url => <<"http://all/1/2/3">>,
            remove => false
        }
    }).

