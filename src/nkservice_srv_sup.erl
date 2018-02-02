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

%% @doc Service main supervisor
%% Each service starts a supervisor named after the service, under
%% 'nkservice_all_srvs_sup'
%% Inside this supervisor, a supervisor for transports and a
%% gen_server (nkservice_srv) is started
%% Also, an ets table is started with the name of the service
-module(nkservice_srv_sup).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(supervisor).

-export([start_service/1, stop_service/1]).
-export([get_pid/1, init/1, start_link/1]).

-include("nkservice.hrl").


%% @doc
start_service(#{id:=Id}=Service) ->
    Child = #{
        id => Id,
        start => {?MODULE, start_link, [Service]},
        type => supervisor
    },
    case supervisor:start_child(nkservice_all_srvs_sup, Child) of
        {ok, Pid} ->
            {ok, Pid};
        {error, {Error, _}} ->
            {error, Error};
        {error, Error} ->
            {error, Error}
    end.



%% @private Stops a service supervisor
-spec stop_service(nkservice:id()) ->
    ok | {error, term()}.

stop_service(Id) ->
    case supervisor:terminate_child(nkservice_all_srvs_sup, Id) of
        ok -> 
            ok = supervisor:delete_child(nkservice_all_srvs_sup, Id);
        {error, not_found} ->
            {error, not_running};
        {error, Error} ->
            {error, Error}
    end.


%% @private Gets the service's transport supervisor's pid()
-spec get_pid(nkservice:id()) ->
    pid() | undefined.

get_pid(Id) ->
    nklib_proc:whereis_name({?MODULE, Id}).


%% @private
-spec start_link(nkservice:spec()) ->
    {ok, pid()}.

start_link(#{id:=Id}=Spec) ->
    Childs = [
        #{
            id => plugins,
            start => {nkservice_srv_plugins_sup, start_link, [Id]},
            type => supervisor
        },
        #{
            id => server,
            start => {nkservice_srv, start_link, [Spec]},
            shutdown => 30000       % Time for plugins to stop
        }
    ],
    % If server or any supervisor fails, everything is restarted
    ChildSpec = {Id, {{one_for_all, 10, 60}, Childs}},
    supervisor:start_link(?MODULE, ChildSpec).


%% @private
init({Id, ChildsSpec}) ->
    % The service ETS table is associated to its supervisor to avoid losing it
    % in case of process fail 
    ets:new(Id, [named_table, public]),
    yes = nklib_proc:register_name({?MODULE, Id}, self()),
    {ok, ChildsSpec}.









