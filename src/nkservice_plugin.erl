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

%% @doc Default callbacks for plugin definitions
-module(nkservice_plugin).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([plugin_deps/0, plugin_group/0, plugin_config/3, plugin_start/4,
         plugin_update/4, plugin_stop/4]).
-export_type([continue/0]).

-type continue() :: continue | {continue, list()}.
-type service() :: nkservice:service().
-type plugin_id() :: nkservice:plugin_id().
-type plugin_config() :: map().

%% ===================================================================
%% Plugin Callbacks
%% ===================================================================



%% @doc Called to get the list of plugins this service/plugin depends on.
-spec plugin_deps() ->
    [module()].

plugin_deps() ->
	[].


%% @doc Optionally set the plugin 'group'
%% All plugins within a group are added a dependency on the previous defined plugins
%% in the same group.
%% This way, the order of callbacks is the same as the order plugins are defined
%% in this group.
-spec plugin_group() ->
    term() | undefined.

plugin_group() ->
	undefined.


%% @doc This function can modify the service configuration, and can also
%% generate a specific plugin configuration (in the second return), that will be 
%% accessible in the generated module as config_(plugin_name).
%% Top-level plugins will be called first, so they can set up configurations for low-level
%% This call will block the startup or upgrade of the service!
-spec plugin_config(plugin_id(), plugin_config(), service()) ->
	ok | {ok, NewConfig::map()} | {ok, NewConfig::map(), service()} | {error, term()}.

plugin_config(_PluginId, _Config, _Service) ->
	ok.


%% @doc Called during service's start
%% All plugins are started in parallel. If a plugin depends on another,
%% it can wait for a while, checking nkservice_srv_plugin_sup:get_pid/2 or
%% calling nkservice_srv:get_status/1
%% This call is non-blocking
%% The plugin must start and can update the service's config
-spec plugin_start(plugin_id(), plugin_config(), Supervisor::pid(), service()) ->
	ok | {error, term()}.

plugin_start(_PluginId, _Config, _Pid, _Service) ->
    ok.


%% @doc Called during service's stop
%% The supervisor pid, if started, if passed
%% After the call, the supervisor will be stopped
-spec plugin_stop(plugin_id(), plugin_config(), Supervisor::pid(), service()) ->
	ok | {error, term()}.

plugin_stop(_PluginId, _Config, _Pid, _Service) ->
	ok.


%% @doc Called during service's update, for plugins with updated configuration
-spec plugin_update(plugin_id(), plugin_config(), Supervisor::pid(), service()) ->
    ok | {error, term()}.

plugin_update(_PluginId, _Config, _Pid, _Service) ->
    ok.


