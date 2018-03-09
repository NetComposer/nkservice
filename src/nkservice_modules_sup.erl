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

%% @doc Supervisor for the modules
-module(nkservice_modules_sup).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(supervisor).

-export([start_module_sup/2, restart_module_sup/2, stop_module_sup/2]).
-export([get_pid/1, get_modules/1, get_instances/2]).
-export([init/1, start_link/1, start_link_module_sup/3]).

-include("nkservice.hrl").


%% @doc Tries to start a module supervisor, or returns existing one
-spec start_module_sup(nkservice:id(), nkservice:module_id()) ->
    {ok, pid()} | {error, term()}.

start_module_sup(SrvId, ModuleId) ->
    Pid = get_pid(SrvId),
    Childs = [
        #{
            id => main,
            start => {nkservice_luerl_instance, start_link, [SrvId, ModuleId, main, #{}]},
            shutdown => 30000
        }
    ],
    SupSpec = #{
        id => ModuleId,
        start => {?MODULE, start_link_module_sup, [SrvId, ModuleId, Childs]},
        type => supervisor
    },
    case supervisor:start_child(Pid, SupSpec) of
        {ok, ChildPid} ->
            {ok, ChildPid};
        {error, {already_started, ChildPid}} ->
            {ok, ChildPid};
        {error, Error} ->
            {error, Error}
    end.


%% @doc
restart_module_sup(SrvId, ModuleId) ->
    stop_module_sup(SrvId, ModuleId),
    timer:sleep(100),
    start_module_sup(SrvId, ModuleId).


%% @doc
stop_module_sup(SrvId, ModuleId) ->
    Pid = get_pid(SrvId),
    case supervisor:terminate_child(Pid, ModuleId) of
        ok ->
            supervisor:delete_child(Pid, ModuleId),
            ok;
        {error, Error} ->
            {error, Error}
    end.


%% @doc
get_modules(SrvId) ->
    supervisor:which_children(get_pid(SrvId)).


%% @doc
get_instances(SrvId, ModuleId) ->
    supervisor:which_children(get_pid(SrvId, ModuleId)).



%% @private
get_pid(Pid) when is_pid(Pid) ->
    Pid;
get_pid(SrvId) ->
    nklib_proc:whereis_name({?MODULE, SrvId}).


%% @private
get_pid(SrvId, ModuleId) ->
    nklib_proc:whereis_name({?MODULE, SrvId, ModuleId}).


%% @private Starts the main supervisor for all modules
%% It starts empty, nkservice_srv will add child processes
-spec start_link(nkservice:id()) ->
    {ok, pid()}.

start_link(Id) ->
    ChildSpec = {{one_for_one, 10, 60}, []},
    {ok, Pid} = supervisor:start_link(?MODULE, ChildSpec),
    yes = nklib_proc:register_name({?MODULE, Id}, Pid),
    {ok, Pid}.


%% @private
init(ChildsSpec) ->
    {ok, ChildsSpec}.


%% @private Called for each configured module
start_link_module_sup(Id, ModuleId, Childs) ->
    ChildSpec = {{one_for_one, 10, 60}, Childs},
    {ok, Pid} = supervisor:start_link(?MODULE, ChildSpec),
    yes = nklib_proc:register_name({?MODULE, Id, ModuleId}, Pid),
    {ok, Pid}.




