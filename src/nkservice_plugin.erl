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
-export([plugin_deps/0, plugin_group/0, plugin_api/1,
         plugin_config/3, plugin_start/4, plugin_update/5, plugin_stop/4]).
-export_type([continue/0]).

-type continue() :: continue | {continue, list()}.
-type service() :: nkservice:service().

-type package_class() :: nkservice:package_class().
-type package_spec() :: nkservice:package_spec().

%% ===================================================================
%% Plugin Callbacks
%% ===================================================================



%% @doc Called to get the list of plugins this service/plugin depends on.
%% If the option 'optional' is used, and the plugin could not be loaded, it is ignored
-spec plugin_deps() ->
    [module() | {module(), optional}].

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


%% @doc Return the available user callbacks
%% Callbacks are automatically extracted from lua scripts and available
%% in SrvId:callbacks()

-spec plugin_api(package_class()) ->
    #{
        luerl => #{
            Name::atom() => {module(), Fun::atom()}
        }
    }.

plugin_api(_Class) ->
    #{}.


%% @doc This function must parse any configuration for this plugin,
%% and can optionally modify it
%% It can also modify the in-generation service, adding cache entries, secrets, etc.
%% Top-level plugins will be called first, so they can set up configurations for low-level
%% In distributed mode, this functions is called ONLY at the master node,
%% and the configuration and generated service is used at all nodes
-spec plugin_config(package_class(), package_spec(), service()) ->
    ok | {ok, package_spec()} | {ok, package_spec(), service()} | {error, term()}.

plugin_config(_Class, _PackageSpec, _Service) ->
    ok.



%% @doc Called during service's start
%% All plugins are started in parallel. If a plugin depends on another,
%% it can wait for a while, checking nkservice_srv_plugin_sup:get_pid/2 or
%% calling nkservice_srv:get_status/1
%% This call is non-blocking, called at each node
-spec plugin_start(package_class(), package_spec(), Supervisor::pid(), service()) ->
	ok | {error, term()}.

plugin_start(_Class, _PackageSpec, _Pid, _Service) ->
    ok.


%% @doc Called during service's stop
%% The supervisor pid, if started, if passed
%% After the call, the supervisor will be stopped
%% This call is non-blocking, except for full service stop
-spec plugin_stop(package_class(), package_spec(), Supervisor::pid(), service()) ->
	ok | {error, term()}.

plugin_stop(_Class, _PackageSpec, _Pid, _Service) ->
	ok.


%% @doc Called during service's update, for plugins with updated configuration
%% This call is non-blocking, called at each node
-spec plugin_update(package_class(), package_spec(), package_spec(), Supervisor::pid(), service()) ->
    ok | {error, term()}.

plugin_update(_Class, _PackageSpec, _OldPackageSpec, _Pid, _Service) ->
    ok.



