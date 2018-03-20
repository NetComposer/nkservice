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

-module(nkservice_test).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([start/0, stop/0, test/0, clean_events/0, call_lua/2]).
-export([service_event/3, test_lua/0]).

-define(SRV, test).
-compile(nowarn_unused_function).

-dialyzer([{nowarn_function, start/0}, {nowarn_function, test/0},
           {nowarn_function, test_start/0}, {nowarn_function, test_lua/0}]).

-include("nkservice.hrl").



start() ->
    Spec = #{
        name => my_name,
        plugins => [?MODULE],
        packages => [
            #{
                id => jose,
                class => 'JOSE'
            },
            #{
                class => 'WebServer',
                config => #{
                    url => "https://all:9010/test1",
                    file_path => "/tmp",
                    opts => #{debug=>false}
                }
            },
            #{
                id => listen,
                class => 'RestServer',
                config => #{
                    url => "https://all:9010/test2"
                }
            }
        ],
        modules => [
            #{
                id => s1,
                class => luerl,
                code => s1()
            }
        ],
        meta => #{self => list_to_binary(pid_to_list(self()))}
    },
    nkservice:start(?SRV, Spec).


stop() ->
    nkservice:stop(?SRV).


s1() -> <<"

    print 'Starting LUA'

    function Service.init(a)
        print 'Start'
        -- return 'error', 'mi error'   -- uncomment to stop starting
    end

    listen = startPackage('RestServer',
                        {
                            id = 'listen2',
                            url = 'https://node:9010/test3',
                            requestCallback = function(a)
                                return 1
                            end
                        })

    jose = startPackage('JOSE')


    function sign(msg)
        return jose.sign(msg, {})
    end

    function verify(msg, opts)
        res, body = jose.verify(msg, opts)
        return res, body
    end



">>.


test() ->
    test_start(),
    test_kill(),
    test_update_packages(),
    test_update_modules(),
    test_lua(),
    test_stop(),
    ok.


test_start() ->
    stop(),
    timer:sleep(1000),
    clean_events(),
    start(),

    true = is_binary(nkservice_util:get_secret(?SRV, <<"jose_secret">>)),

    next_event(service_started),
    next_event({package_status,#{package_id => <<"jose">>,status => starting}}),
    next_event({package_status,#{package_id => <<"jose">>,status => running}}),
    next_event({package_status,#{package_id => <<"WebServer">>,status => starting}}),
    next_event({package_status,#{package_id => <<"WebServer">>,status => running}}),
    next_event({package_status,#{package_id => <<"listen">>,status => starting}}),
    next_event({package_status,#{package_id => <<"listen">>,status => running}}),
    next_event({module_status,#{module_id => <<"s1">>,status => starting}}),
    next_event({module_status,#{module_id => <<"s1">>,status => running}}),
    next_event({package_status,#{package_id => <<"s1-JOSE">>,status => starting}}),
    next_event({package_status,#{package_id => <<"s1-JOSE">>,status => running}}),
    next_event({package_status,#{package_id => <<"listen2">>,status => starting}}),
    next_event({package_status,#{package_id => <<"listen2">>,status => running}}),

    {ok,
        #{packages := #{
            <<"listen">> := #{status := running},
            <<"jose">> := #{status := running},
            <<"WebServer">> := #{status := running},
            <<"s1-JOSE">> := #{status := running},
            <<"listen2">> := #{status := running}
        },
        modules := #{
            <<"s1">> := #{status := running}
        }}} =
            nkservice_srv:get_status(?SRV),
    check_no_pending_events(),
    ok.


test_kill() ->
    % Let's kill a package, should be restarted
    P1 = nkservice_packages_sup:get_pid(?SRV, <<"WebServer">>),
    exit(P1, kill),     % We kill the WebServer supervisor
    next_event({package_status,#{package_id => <<"WebServer">>,status => failed}}),
    timer:sleep(500),
    {ok,
        #{packages := #{
            <<"listen">> := #{status := running},
            <<"jose">> := #{status := running},
            <<"WebServer">> := #{status := failed, last_error := supervisor_down},
            <<"s1-JOSE">> := #{status := running},
            <<"listen2">> := #{status := running}
        },
            modules := #{
                <<"s1">> := #{status := running}
            }}
    } = nkservice_srv:get_status(?SRV),
    nkservice_srv:launch_check_status(?SRV),  % Don't wait for next iteration
    next_event({package_status,#{package_id => <<"WebServer">>,status => starting}}),
    next_event({package_status,#{package_id => <<"WebServer">>,status => running}}),
    P2 = nkservice_packages_sup:get_pid(?SRV, <<"WebServer">>),
    false = (P1 == P2),
    check_no_pending_events().


test_update_packages() ->
    % Empty update
    ok = nkservice:update(?SRV, #{}),
    next_event(update_received),
    next_event({service_updated,
            #{
                packages_to_start => [],
                packages_to_stop => [],
                packages_to_update => [],
                packages_unchanged => [<<"WebServer">>, <<"jose">>,<<"listen">>, <<"listen2">>, <<"s1-JOSE">>],
                modules_to_start => [],
                modules_to_stop => [],
                modules_to_update => [],
                modules_unchanged => [<<"s1">>]
            }}),

    % Package not updated
    ok = nkservice:update(?SRV, #{
        packages => [
            #{
                class => <<"WebServer">>,
                config => #{
                    url => "https://all:9010/test1",
                    file_path => "/tmp",
                    opts => #{debug=>false}
                }
            }]}),
    next_event(update_received),
    next_event({service_updated,
        #{
            packages_to_start => [],
            packages_to_stop => [],
            packages_to_update => [],
            packages_unchanged => [<<"WebServer">>,<<"jose">>,<<"listen">>, <<"listen2">>, <<"s1-JOSE">>],
            modules_to_start => [],
            modules_to_stop => [],
            modules_to_update => [],
            modules_unchanged => [<<"s1">>]
        }}),

    % Package updated
    ok = nkservice:update(?SRV, #{
        packages => [
            #{
                class => <<"WebServer">>,
                config => #{
                    url => "https://all:9010/test1",
                    file_path => "/tmp1",
                    opts => #{debug=>false}
                }
            }]}),
    next_event(update_received),
    next_event({package_status,#{package_id => <<"WebServer">>,status => updating}}),
    next_event({package_status,#{package_id => <<"WebServer">>,status => running}}),
    next_event({service_updated,
        #{
            packages_to_start => [],
            packages_to_stop => [],
            packages_to_update => [<<"WebServer">>],
            packages_unchanged => [<<"jose">>,<<"listen">>, <<"listen2">>, <<"s1-JOSE">>],
            modules_to_start => [],
            modules_to_stop => [],
            modules_to_update => [],
            modules_unchanged => [<<"s1">>]
        }}),

    % We stop listen and module s1, related packages will stop
    ok = nkservice:update(?SRV, #{
        packages => [
            #{
                class => <<"WebServer">>,
                remove => false,
                config => #{
                    url => "https://all:9010/test1",
                    file_path => "/tmp",
                    opts => #{debug=>false}
                }
            },
            #{
                id => listen,
                class => <<"RestServer">>,
                remove => true
            }],
        modules => [
            #{
                id => s1,
                class => luerl,
                remove => true
            }
        ]}),
    next_event(update_received),
    next_event({package_status,#{package_id => <<"WebServer">>,status => updating}}),
    next_event({package_status,#{package_id => <<"WebServer">>,status => running}}),
    next_event({package_status,#{package_id => <<"listen">>,status => stopping}}),
    next_event({package_status,#{package_id => <<"listen">>,status => stopped}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>stopping}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>stopped}}),
    next_event({package_status,#{package_id => <<"s1-JOSE">>,status => stopping}}),
    next_event({package_status,#{package_id => <<"s1-JOSE">>,status => stopped}}),
    next_event({package_status,#{package_id => <<"listen2">>,status => stopping}}),
    next_event({package_status,#{package_id => <<"listen2">>,status => stopped}}),
    next_event({service_updated,
        #{
            packages_to_start => [],
            packages_to_stop => [<<"listen">>, <<"listen2">>, <<"s1-JOSE">>],
            packages_to_update => [<<"WebServer">>],
            packages_unchanged => [<<"jose">>],
            modules_to_start => [],
            modules_to_stop => [<<"s1">>],
            modules_to_update => [],
            modules_unchanged => []
        }}),
    {ok,
        #{
            packages := #{
                <<"jose">> := #{status := running},
                <<"WebServer">> := #{status := running}
            } = Plugins1,
            modules := Scripts1
        }
    } = nkservice_srv:get_status(?SRV),
    2 = maps:size(Plugins1),
    0 = maps:size(Scripts1),

    % Restart listen and the module
    ok = nkservice:update(?SRV, #{
        packages => [
            #{
                id => listen,
                class => <<"RestServer">>,
                config => #{
                    url => "https://all:9010/test2"
                }
            }
        ],
        modules => [
            #{
                id => s1,
                class => luerl,
                code => s1()
            }
        ]
    }),
    next_event(update_received),
    next_event({service_updated,
        #{
            packages_to_start => [<<"listen">>, <<"listen2">>, <<"s1-JOSE">>],
            packages_to_stop => [],
            packages_to_update => [],
            packages_unchanged => [<<"WebServer">>, <<"jose">>],
            modules_to_start => [<<"s1">>],
            modules_to_stop => [],
            modules_to_update => [],
            modules_unchanged => []
        }}),
    next_event({package_status,#{package_id => <<"listen">>,status => starting}}),
    next_event({package_status,#{package_id => <<"listen">>,status => running}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>starting}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>running}}),
    next_event({package_status,#{package_id => <<"s1-JOSE">>,status => starting}}),
    next_event({package_status,#{package_id => <<"s1-JOSE">>,status => running}}),
    next_event({package_status,#{package_id => <<"listen2">>,status => starting}}),
    next_event({package_status,#{package_id => <<"listen2">>,status => running}}),
    check_no_pending_events().


test_update_modules() ->
    % No update
    ok = nkservice:update(?SRV, #{
        modules =>
            [
                #{
                    id => s1,
                    class => luerl,
                    code => s1()
                }
            ]
        }),
    next_event(update_received),
    next_event({service_updated,
        #{
            packages_to_start => [],
            packages_to_stop => [],
            packages_to_update => [],
            packages_unchanged => [<<"WebServer">>,<<"jose">>,<<"listen">>,<<"listen2">>,<<"s1-JOSE">>],
            modules_to_start => [],
            modules_to_stop => [],
            modules_to_update => [],
            modules_unchanged => [<<"s1">>]
        }
    }),

    % Reload
    ok = nkservice:update(?SRV, #{
        modules =>
        [
            #{
                id => s1,
                class => luerl,
                code => s1(),
                reload => true
            }
        ]
    }),
    next_event(update_received),
    next_event({service_updated,
        #{
            packages_to_start => [],
            packages_to_stop => [],
            packages_to_update => [],
            packages_unchanged => [<<"WebServer">>,<<"jose">>, <<"listen">>, <<"listen2">>, <<"s1-JOSE">>],
            modules_to_start => [],
            modules_to_stop => [],
            modules_to_update => [<<"s1">>],
            modules_unchanged => []
        }}),
    next_event({module_status, #{module_id=><<"s1">>, status=>stopping}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>stopped}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>starting}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>running}}),

    %% Remove a package from the module
    S2 = re:replace(s1(), <<"jose = startPackage\\('JOSE'\\)">>, <<>>, [{return, binary}]),
    ok = nkservice:update(?SRV, #{
        modules =>[
            #{
                id => s1,
                class => luerl,
                code => S2
            }
        ]
    }),
    next_event(update_received),
    next_event({service_updated,
        #{
            packages_to_start => [],
            packages_to_stop => [<<"s1-JOSE">>],
            packages_to_update => [],
            packages_unchanged => [<<"WebServer">>,<<"jose">>,<<"listen">>,<<"listen2">>],
            modules_to_start => [],
            modules_to_stop => [],
            modules_to_update => [<<"s1">>],
            modules_unchanged => []
        }}),
    next_event({module_status, #{module_id=><<"s1">>, status=>stopping}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>stopped}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>starting}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>running}}),
    next_event({package_status,#{package_id => <<"s1-JOSE">>,status => stopping}}),
    next_event({package_status,#{package_id => <<"s1-JOSE">>,status => stopped}}),

    %% Put it back
    ok = nkservice:update(?SRV, #{
        modules =>[
            #{
                id => s1,
                class => luerl,
                code => s1()
            }
        ]
    }),
    next_event(update_received),
    next_event({service_updated,
        #{
            packages_to_start => [<<"s1-JOSE">>],
            packages_to_stop => [],
            packages_to_update => [],
            packages_unchanged => [<<"WebServer">>,<<"jose">>,<<"listen">>,<<"listen2">>],
            modules_to_start => [],
            modules_to_stop => [],
            modules_to_update => [<<"s1">>],
            modules_unchanged => []
        }}),
    next_event({module_status, #{module_id=><<"s1">>, status=>stopping}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>stopped}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>starting}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>running}}),
    next_event({package_status,#{package_id => <<"s1-JOSE">>,status => starting}}),
    next_event({package_status,#{package_id => <<"s1-JOSE">>,status => running}}),

    % Update code
    S3 = <<"a = 1\n", (s1())/binary>>,
    ok = nkservice:update(?SRV, #{
        modules =>
        [
            #{
                id => s1,
                class => luerl,
                code => S3
            }
        ]
    }),
    next_event(update_received),
    next_event({module_status, #{module_id=><<"s1">>, status=>stopping}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>stopped}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>starting}}),
    next_event({module_status, #{module_id=><<"s1">>, status=>running}}),
    next_event({service_updated,
        #{
            packages_to_start => [],
            packages_to_stop => [],
            packages_to_update => [],
            packages_unchanged => [<<"WebServer">>,<<"jose">>,<<"listen">>,<<"listen2">>, <<"s1-JOSE">>],
            modules_to_start => [],
            modules_to_stop => [],
            modules_to_update => [<<"s1">>],
            modules_unchanged => []
        }}),

    S4 = re:replace(s1(), <<"'listen2'">>, <<"'listen'">>, [{return, binary}]),
    {error, {duplicated_id, <<"packages.id.listen">>}} = nkservice:update(?SRV, #{
        packages => [
            #{
                id => listen,
                class => 'RestServer',
                config => #{
                    url => "https://all:9010/test2"
                }
            }
        ],
        modules =>[
            #{
                id => s1,
                class => luerl,
                code => S4
            }
        ]
    }),
    check_no_pending_events().


test_lua() ->
    {ok, [JWT]} = call_lua([sign], [#{a=>1}]),
    {ok, [true, [{<<"a">>,1.0}]]} = call_lua([verify], [JWT]),
    {ok, [false, [{<<"a">>,1.0}]]} = call_lua([verify], [JWT, #{key=>other}]),
    ok.


test_stop() ->
    stop(),
    next_event(service_stopping),
    check_no_pending_events().




next_event(Ev) ->
    receive
        {test_event, Ev} ->
            ok
    after
        2000 ->
            print_events(),
            error({next_event, Ev})
    end.


clean_events() ->
    receive
        _ ->
            clean_events()
    after
        0 ->
            ok
    end.


check_no_pending_events() ->
    receive
        Msg ->
            error({unexpected_event, Msg})
    after
        500 ->
            ok
    end.


print_events() ->
    receive
        Ev ->
            lager:notice("Unexpected event ~p", [Ev]),
            print_events()
    after
        1000 ->
            ok
    end.




call_lua(Name, Args) ->
    nkservice_luerl_instance:call({?SRV, s1, main}, Name, Args).



%%%%%%%%% CALLBACKS



service_event(Event, _Service, State) ->
    #{self:=Self} = ?SRV:meta(),
    Pid = list_to_pid(binary_to_list(Self)),
    Pid ! {test_event, Event},
    {ok, State}.
