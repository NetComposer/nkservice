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

-module(nkservice_sample).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([start/0, stop/0, trace/0, update/0]).
-export([get_table/1, call/2]).
-compile(nowarn_unused_function).
-compile(export_all).
-compile(nowarn_export_all).

-dialyzer({nowarn_function, start/0}).
-dialyzer({nowarn_function, update/0}).


-include_lib("syntax_tools/include/merl.hrl").


-define(SRV, sample).



start() ->
    List = [
        #{
            id => my_jose,
            class => 'JOSE'
        },
        #{
            class => 'WebServer',
            config => #{
                url => "https://node:9012/test1",
                file_path => "/tmp",
                opts => #{debug=>false}
            }
        },
        #{
            id => listen,
            class => 'RestServer',
            config => #{
                url => "https://node:9010/test2"
            },
            remove => false
        }
    ],
    Spec = #{
        name => my_name,
        plugins => [?MODULE],
        packages => List,
        modules => [
            #{
                id => module_s1,
                class => luerl,
                code => s1()
            }
        ],
        secret => [
            #{
                key => s1,
                value => v1
            }
        ],
        meta => #{
            self => list_to_binary(pid_to_list(self()))
        }
    },
    nkservice:start(?SRV, Spec).


stop() ->
    nkservice:stop(?SRV).



s1() -> <<"
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


    print 'Hola'
    log.info 'Hello'

    Service.callbacks.init = function()
        log.info 'Starting module'
    end

    Service.callbacks.terminate = function()
        log.notice 'Stopping module'
    end

    listenOpts = {
        id = 'my_listen2',
        url='https://node:9010/test3',
        requestCallback = function(a)
            return 1
        end
    }

    listen = startPackage('RestServer', listenOpts)

    jose = startPackage('JOSE')


    function sign1(a, b)
        print('Signing ' .. json.encode(a, {pretty=true}))
        print('Opts ' .. json.encode(b))

        token = jose.sign(a,b)

        print('Verifying ' .. token)

        return jose.verify(token)
    end



    return {listen, Service}


">>.

%%s1() -> <<"
%%
%%    print 'Hola'
%%
%%    listen = new Plugin{class=nkservice_rest, id='listen', url='http:...'}
%%
%%
%%
%%
%%
%%    listen.callbacks.request = function(a)
%%        print 'Callback'
%%    end
%%
%%    service.init = function(a)
%%        print 'Start'
%%        -- return 'error', 'mi error'   -- uncomment to stop starting
%%    end
%%">>.





get_table(Table) when is_list(Table) ->
    nkservice_luerl_instance:get_table({?SRV, module_s1, main}, Table).

call(Fun, Args) when is_list(Fun), is_list(Args) ->
    nkservice_luerl_instance:call({?SRV, module_s1, main}, Fun, Args).


trace() ->
    otter_span_pdict_api:start("radius request"),
    otter_span_pdict_api:tag("request_id", <<"123">>),
    otter_span_pdict_api:log("invoke user db"),
    otter_span_pdict_api:log("user db result"),
    otter_span_pdict_api:tag("user_db_result", "ok"),
    otter_span_pdict_api:tag("final_result", "error"),
    otter_span_pdict_api:tag("final_result_reason", "unknown user"),
    otter_span_pdict_api:finish().



update() ->
    Spec = #{
        modules => [
            #{
                id => module_s1,
                remove => false,
                class => luerl,
                code => s1()
            }
        ]
    },
    nkservice:update(?SRV, Spec).
