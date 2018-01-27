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

-export([start_plugin/2, stop_plugin/2, get_pid/1]).
-export([init/1, start_link/1, start_plugin_sup/2]).

-include("nkservice.hrl").


start_plugin(Id, Plugin) ->
    Pid = get_pid(Id),
    Child = #{
        id => Plugin,
        start => {?MODULE, start_plugin_sup, [Id, Plugin]},
        type => supervisor
    },
    case supervisor:start_child(Pid, Child) of
        {ok, _} ->
            ok;
        {error, Error} ->
            {error, Error}
    end.


stop_plugin(Id, Plugin) ->
    Pid = get_pid(Id),
    case supervisor:terminate_child(Pid, Plugin) of
        ok ->
            ok = supervisor:delete_child(Pid, Plugin);
        {error, Error} ->
            {error, Error}
    end.


get_pid(Id) ->
    nklib_proc:whereis_name({?MODULE, Id}).


%% @private
-spec start_link(nkservice:id()) ->
    {ok, pid()}.

start_link(Id) ->
    Childs = [
        #{
            id => Plugin,
            start => {?MODULE, start_plugin_sup, [Id, Plugin]},
            type => supervisor
        }
        || Plugin <- ?CALL_SRV(Id, plugins)
    ],

    yes = nklib_proc:register_name({?MODULE, Id}, self()),
    ChildSpec = {{one_for_one, 10, 60}, Childs},
    supervisor:start_link(?MODULE, ChildSpec).



%% @private
init(ChildsSpec) ->
    {ok, ChildsSpec}.


%% @private Called for each configured plugin
start_plugin_sup(Id, Plugin) ->
    Childs = [],
    ChildSpec = {{one_for_one, 10, 60}, Childs},
    lager:notice("Start plugin ~p ~p", [Id, Plugin]),
    supervisor:start_link(?MODULE, ChildSpec).






