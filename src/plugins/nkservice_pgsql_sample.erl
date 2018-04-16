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
-module(nkservice_pgsql_sample).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-define(SRV, pgsql).

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
                id => pg1,
                class => 'PgSQL',
                config => #{
                    targets => [
                        #{
                            url => "postgresql://root@127.0.0.1:26257",
                            pool => 3
                        }
                    ],
                    actorPersistence => true,
                    database => <<"system">>,
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


% select * from system.eventlog
luerl_query(Sql) ->
    nkservice_luerl_instance:call({?SRV, s1, main}, [query], [nklib_util:to_binary(Sql)]).


s1() -> <<"
    pgConfig = {
        targets = {
            {
                url = 'postgresql://root@127.0.0.1:26257',
                pool = 5
            }
        },
        resolveInterval = 0,
        debug = true
    }

    pg = startPackage('PgSQL', pgConfig)

    function query(sql)
        return pg.query(sql)
    end

">>.


%% ===================================================================
%% Tests
%% ===================================================================

% https://www.cockroachlabs.com/docs/stable/
% https://www.cockroachlabs.com/docs/dev/

q1() ->
    Sql = <<"
        DROP DATABASE IF EXISTS nkobjects;
        CREATE DATABASE nkobjects;
        SET DATABASE TO nkobjects;
        DROP TABLE IF EXISTS nkobjects.object CASCADE;
        DROP TABLE IF EXISTS nkobjects.aliases CASCADE;

        CREATE TABLE object (
            obj_id STRING PRIMARY KEY NOT NULL,
            path STRING UNIQUE NOT NULL,
            domain_id STRING NOT NULL,
            subtype STRING,
            created_by STRING,
            created_time INT,
            updated_by STRING,
            updated_time INT,
            enabled BOOL DEFAULT TRUE,
            active BOOL DEFAULT TRUE,
            expires_time INT,
            destroyed_time INT,
            destroyed_code STRING,
            destroyed_reason STRING,
            name STRING,
            description STRING,
            icon_id STRING,
            INDEX (path),
            INDEX (created_time)
        );

        CREATE TABLE aliases (
            obj_id STRING PRIMARY KEY NOT NULL,
            parent_id STRING NOT NULL,
            INDEX (obj_id)
        );


    ">>,
    query(Sql).


query(Str) ->
    nkservice_pgsql:query(?SRV, <<"pg1">>, Str).
