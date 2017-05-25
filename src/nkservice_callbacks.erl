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

%% @doc Default callbacks
-module(nkservice_callbacks).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([plugin_deps/0, plugin_group/0, 
	     plugin_syntax/0, plugin_defaults/0, plugin_config/2, 
		 plugin_listen/2, plugin_start/2, plugin_update/2, plugin_stop/2]).
-export([service_init/2, service_handle_call/3, service_handle_cast/2,
         service_handle_info/2, service_code_change/3, service_terminate/2]).
-export([service_api_syntax/2, service_api_allow/1, service_api_cmd/1,
         service_api_event/2]).
-export_type([continue/0]).

-include_lib("nkpacket/include/nkpacket.hrl").
-include_lib("nkevent/include/nkevent.hrl").
-include("nkservice.hrl").

-type continue() :: continue | {continue, list()}.
-type config() :: nkservice:config().
-type req() :: #nkreq{}.
%%-type error_code() :: nkservice:error().



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


%% @doc This function, if implemented, can offer a nklib_config:syntax()
%% that will be checked against service configuration. Entries passing will be
%% updated on the configuration with their parsed values
-spec plugin_syntax() ->
	nklib_config:syntax().

plugin_syntax() ->
	#{}.


%% @doc This function, if implemented, can offer a defaults specification
%% for the syntax processing
-spec plugin_defaults() ->
	map().

plugin_defaults() ->
	#{}.


%% @doc This function can modify the service configuration, and can also
%% generate a specific plugin configuration (in the second return), that will be 
%% accessible in the generated module as config_(plugin_name).
-spec plugin_config(config(), service()) ->
	{ok, config()} | {ok, config(), term()} | {error, term()}.

plugin_config(Config, _Service) ->
	{ok, Config, #{}}.


%% @doc This function, if implemented, allows to add listening transports.
%% By default start the web_server and api_server transports.
-spec plugin_listen(config(), service()) ->
	[{nkpacket:user_connection(), nkpacket:listener_opts()}].

plugin_listen(_Config, #{id:=_SrvId}) ->
	[].


%% @doc Called during service's start
%% The plugin must start and can update the service's config
-spec plugin_start(config(), service()) ->
	{ok, config()} | {error, term()}.

plugin_start(Config, _Service) ->
	{ok, Config}.


%% @doc Called during service's update
-spec plugin_update(config(), service()) ->
	{ok, config()} | {error, term()}.

plugin_update(Config, _Service) ->
	{ok, Config}.


%% @doc Called during service's stop
%% The plugin must remove any key from the service
-spec plugin_stop(config(), service()) ->
	{ok, config()}.

plugin_stop(Config, _Service) ->
	{ok, Config}.



%% ===================================================================
%% Service Callbacks
%% ===================================================================


-type service() :: nkservice:service().
-type state() :: map().

%% @doc Called when a new service starts
-spec service_init(service(), state()) ->
	{ok, state()} | {stop, term()}.

service_init(_Service, State) ->
	{ok, State}.

%% @doc Called when the service process receives a handle_call/3.
-spec service_handle_call(term(), {pid(), reference()}, state()) ->
	{reply, term(), state()} | {noreply, state()} | continue().

service_handle_call(Msg, _From, State) ->
    lager:error("Module nkservice_srv received unexpected call ~p", [Msg]),
    {noreply, State}.


%% @doc Called when the NkApp process receives a handle_cast/3.
-spec service_handle_cast(term(), state()) ->
	{noreply, state()} | continue().

service_handle_cast(Msg, State) ->
    lager:error("Module nkservice_srv received unexpected cast ~p", [Msg]),
	{noreply, State}.


%% @doc Called when the NkApp process receives a handle_info/3.
-spec service_handle_info(term(), state()) ->
	{noreply, state()} | continue().

service_handle_info({'EXIT', _, normal}, State) ->
	{noreply, State};

service_handle_info(Msg, State) ->
    lager:notice("Module nkservice_srv received unexpected info ~p", [Msg]),
	{noreply, State}.


-spec service_code_change(term()|{down, term()}, state(), term()) ->
    ok | {ok, service()} | {error, term()} | continue().

service_code_change(OldVsn, State, Extra) ->
	{continue, [OldVsn, State, Extra]}.


%% @doc Called when a service is stopped
-spec service_terminate(term(), service()) ->
	{ok, service()}.

service_terminate(_Reason, State) ->
	{ok, State}.



%% ===================================================================
%% Service API
%% ===================================================================

%% @doc Called to get the syntax for an external API command
-spec service_api_syntax(nklib_syntax:syntax(), req()) ->
    {nklib_syntax:syntax(), req()}.

service_api_syntax(Req, SyntaxAcc) ->
    {SyntaxAcc, Req}.


%% @doc Called to authorize process a new API command
-spec service_api_allow(req()) ->
    {boolean(), req()}.

service_api_allow(Req) ->
    {false, Req}.


%% @doc Called to process a new authorized API command
%% For slow requests, reply ack, and the ServiceModule:reply/2.
-spec service_api_cmd(req()) ->
    {ok, Reply::map(), req()} | {ack, req()} |
    {login, Reply::map(), User::nkservice:user_id(), Meta::nkservice:user_meta(), req()} |
    {error, nkservice:error(), state()}.

service_api_cmd(Req) ->
    {error, not_implemented, Req}.


%% @doc Called when the client sent an authorized event to us
%% For slow requests, reply ack, and the ServiceModule:reply/2.
-spec service_api_event(#nkevent{}, req()) ->
    {ok, req()} |  {error, nkservice:error(), state()}.

service_api_event(_Event, Req) ->
    {ok, Req}.



