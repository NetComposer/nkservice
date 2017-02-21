%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc Service main supervisor
%% Each service starts a supervisor named after the service, under
%% 'nkservice_all_srvs_sup'
%% Inside this supervisor, a supervisor for transports and a
%% gen_server (nkservice_srv) is started
%% Also, an ets table is started with the name of the service
-module(nkservice_srv_sup).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(supervisor).

-export([pre_start_service/1, start_service/1, stop_service/1]).
-export([get_pid/1, init/1, start_link/1]).

-include("nkservice.hrl").


%% @private Starts a new service supervisor
-spec pre_start_service(nkservice:id()) ->
    ok | {error, term()}.

pre_start_service(Id) ->
    SupSpec = {
        Id,
        {?MODULE, start_link, [Id]},
        permanent,
        infinity,
        supervisor,
        [?MODULE]
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

start_link(Id) ->
    Childs = [     
        {user,
            {nkservice_srv_user_sup, start_link, [Id]},
            permanent,
            infinity,
            supervisor,
            [nkservice_srv_user_sup]
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


%% @doc
start_service(#{id:=Id}=Service) ->
    ListenSup = {
        listen,
        {nkservice_srv_listen_sup, start_link, [Service]},
        permanent,
        infinity,
        supervisor,
        [nkservice_srv_listen_sup]
    },
    Server = {
        server,
        {nkservice_srv, start_link, [Service]},
        permanent,
        30000,
        worker,
        [nkservice_srv]
    },
    case start_child(Id, ListenSup) of
        ok ->
            case start_child(Id, Server) of
                ok ->
                    ok;
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @private
start_child(Id, Spec) ->
    SupPid = get_pid(Id),
    case supervisor:start_child(SupPid, Spec) of
        {ok, _Pid} ->
            ok;
        {error, {Error, _}} -> 
            stop_service(Id),
            {error, Error};
        {error, Error} -> 
            stop_service(Id),
            {error, Error}
    end.









