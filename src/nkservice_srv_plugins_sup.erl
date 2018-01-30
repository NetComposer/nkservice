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

%% @doc Supervisor for the plugins
-module(nkservice_srv_plugins_sup).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(supervisor).

-export([start_plugin/2, stop_plugin/2, get_pid/1, get_pid/2]).
-export([init/1, start_link/1, start_plugin_sup/2]).

-include("nkservice.hrl").


%% @doc Tries to start a plugin supervisor, or returns existing one
start_plugin(Id, Plugin) ->
    Pid = get_pid(Id),
    Child = #{
        id => Plugin,
        start => {?MODULE, start_plugin_sup, [Id, Plugin]},
        type => supervisor,
        restart => temporary
    },
    case supervisor:start_child(Pid, Child) of
        {ok, ChildPid} ->
            {ok, ChildPid};
        {error, {already_started, ChildPid}} ->
            {ok, ChildPid};
        {error, Error} ->
            {error, Error}
    end.


%% @doc
stop_plugin(Id, Plugin) ->
    Pid = get_pid(Id),
    case supervisor:terminate_child(Pid, Plugin) of
        ok ->
            supervisor:delete_child(Pid, Plugin),
            ok;
        {error, Error} ->
            {error, Error}
    end.


%% @private
get_pid(Id) ->
    nklib_proc:whereis_name({?MODULE, Id}).


%% @private
get_pid(Id, Plugin) ->
    nklib_proc:whereis_name({?MODULE, Id, Plugin}).


%% @private Starts the main supervisor for all plugins
%% It starts empty, nkservice_srv will add child supervisors calling
%% start_plugin/2
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


%% @private Called for each configured plugin
start_plugin_sup(Id, Plugin) ->
    ChildSpec = {{one_for_one, 10, 60}, []},
    {ok, Pid} = supervisor:start_link(?MODULE, ChildSpec),
    yes = nklib_proc:register_name({?MODULE, Id, Plugin}, Pid),
    {ok, Pid}.






