%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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

-module(nkservice_srv_sup).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(supervisor).

-export([start_service/1, stop_service/1]).
-export([get_pid/1, init/1, start_link/1]).

-include("nkservice.hrl").


%% @private Starts a new service supervisor
-spec start_service(nkservice:service()) ->
    ok | {error, term()}.

start_service(#{id:=Id}=Service) ->
    SupSpec = {
        Id,
            {nkservice_srv_sup, start_link, [Service]},
            permanent,
            infinity,
            supervisor,
            [nkservice_srv_sup]
    },
    case supervisor:start_child(nkservice_all_srvs_sup, SupSpec) of
        {ok, _SupPid} -> 
            ok;
        {error, {{shutdown, {failed_to_start_child,server, Error}}, _Desc}} ->
            {error, Error};
        {error, Error} -> 
            {error, Error}
    end.


%% @private Stops a service supervisor
-spec stop_service(nkservice:id()) ->
    ok | error.

stop_service(Id) ->
    case supervisor:terminate_child(nkservice_all_srvs_sup, Id) of
        ok -> 
            ok = supervisor:delete_child(nkservice_all_srvs_sup, Id);
        {error, _} -> 
            error
    end.


%% @private Gets the service's transport supervisor's pid()
-spec get_pid(nkservice:id()) ->
    pid() | undefined.

get_pid(Id) ->
    nklib_proc:whereis_name({?MODULE, Id}).


%% @private
-spec start_link(nkservice:service()) ->
    {ok, pid()}.

start_link(#{id:=Id}=Service) ->
    Childs = [     
        {server,
            {nkservice_srv, start_link, [Service]},
            permanent,
            30000,
            worker,
            [nkservice_srv]
        },
        {transports,
            {nkservice_srv_listen_sup, start_link, [Id]},
            permanent,
            infinity,
            supervisor,
            [nkservice_srv_listen_sup]
        }
    ],
    ChildSpec = {Id, {{one_for_one, 10, 60}, Childs}},
    supervisor:start_link(?MODULE, ChildSpec).


%% @private
init({Id, ChildsSpec}) ->
    % The service ETS table is associated to its supervisor to avoid losing it
    % in case of process fail 
    ets:new(Id, [named_table, public]),
    yes = nklib_proc:register_name({?MODULE, Id}, self()),
    {ok, ChildsSpec}.


