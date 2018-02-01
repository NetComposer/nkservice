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
-export([start/0, stop/0, update1/0, update2/0, update3/0]).

start() ->
    Spec = #{
        name => my_name,
        plugins => [
            #{
                class => nkservice_webserver,
                config => webserver_config()
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



update1() ->
    nkservice:update(sample, #{
        plugins => [
            #{
                class => nkservice_webserver,
                remove => true
            }

        ]
    }).


update2() ->
    nkservice:update(sample, #{
        plugins => [
            #{
                class => nkservice_webserver,
                config => webserver_config()
            }
        ]
    }).


update3() ->
    nkservice:update(sample, #{
        plugins => [
            #{
                class => nkservice_webserver,
                config => #{
                    servers => [
                        #{
                            id => web1,
                            url => <<>>
                        }
                    ]
                }
            }
        ]
    }).



%%
%%update3_b() ->
%%    nkservice:update(sample, #{
%%        plugins => [
%%            #{
%%                id => web1,
%%                class => nkservice_webserver,
%%                config => #{
%%                    url => <<>>
%%                }
%%            }
%%        ]
%%    }).



webserver_config() ->
    #{
        servers => [
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
    }.
