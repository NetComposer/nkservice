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

-export([start_plugin_sup/2, stop_plugin_sup/2]).
-export([update_child/3, remove_child/2, get_pid/1, get_pid/2, get_childs/1]).
-export([init/1, start_link/1, start_link_plugin_sup/2]).

-include("nkservice.hrl").


%% @doc Tries to start a plugin supervisor, or returns existing one
start_plugin_sup(Id, Plugin) ->
    Pid = get_pid(Id),
    Child = #{
        id => Plugin,
        start => {?MODULE, start_link_plugin_sup, [Id, Plugin]},
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
stop_plugin_sup(Id, Plugin) ->
    remove_child(Id, Plugin).


%% @doc Updates (if Spec is different) or starts a new child
-spec update_child(term()|pid(), supervisor:child_spec(), map()) ->
    {ok, pid()} | {upgraded, pid()} | not_updated | {error, term()}.

update_child(Id, Spec, _Opts) ->
    Pid = get_pid(Id),
    ChildId = case Spec of
        #{id:=CI} -> CI;
        _ -> element(1, Spec)
    end,
    case supervisor:get_childspec(Pid, ChildId) of
        {ok, Spec} ->
            not_updated;
        {ok, _OldSpec} ->
            case remove_child(Pid, ChildId) of
                ok ->
                    case supervisor:start_child(Pid, Spec) of
                        {ok, ChildPid} ->
                            {upgraded, ChildPid};
                        {error, Error} ->
                            {error, Error}
                    end;
                {error, Error} ->
                    {error, Error}
            end;
        {error, not_found} ->
            case supervisor:start_child(Pid, Spec) of
                {ok, ChildPid} ->
                    {ok, ChildPid};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc
remove_child(Id, ChildId) ->
    Pid = get_pid(Id),
    case supervisor:terminate_child(Pid, ChildId) of
        ok ->
            supervisor:delete_child(Pid, ChildId),
            ok;
        {error, Error} ->
            {error, Error}
    end.



%% @doc
get_childs(Id) ->
    supervisor:which_children(get_pid(Id)).


%% @private
get_pid(Pid) when is_pid(Pid) ->
    Pid;
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
start_link_plugin_sup(Id, Plugin) ->
    ChildSpec = {{one_for_one, 10, 60}, []},
    {ok, Pid} = supervisor:start_link(?MODULE, ChildSpec),
    yes = nklib_proc:register_name({?MODULE, Id, Plugin}, Pid),
    {ok, Pid}.






