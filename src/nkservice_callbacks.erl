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
-export([error/1, error/2]).
-export([service_init/2, service_handle_call/3, service_handle_cast/2,
         service_handle_info/2, service_code_change/3, service_terminate/2]).
-export([service_api_syntax/2, service_api_allow/1, service_api_cmd/1, service_api_event/1]).
-export_type([continue/0]).

-include_lib("nkpacket/include/nkpacket.hrl").
-include_lib("nkevent/include/nkevent.hrl").
-include("nkservice.hrl").

-type continue() :: continue | {continue, list()}.
-type config() :: nkservice:config().
-type req() :: #nkreq{}.
-type state() :: map().



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
%% Errors Callbacks
%% ===================================================================



%% @doc
-spec error(nkservice:lang(), nkservice:error()) ->
    atom() |
    tuple() |
    list() |
    {atom(), string()} |
    {Fmt::string(), Vals::string()} |
    {atom(), Fmt::string(), Vals::string()}.

error(SrvId, Error) ->
    SrvId:error(Error).


%% @doc
-spec error(nkservice:error()) ->
    atom() |
    tuple() |
    list() |
    {atom(), string()} |
    {Fmt::string(), Vals::string()} |
    {atom(), Fmt::string(), Vals::string()}.

error(already_authenticated)	-> "Already authenticated";
error(already_started)	        -> "Already started";
error(already_uploaded)   		-> "Already uploaded";
error(api_delete) 				-> "API delete received";
error(api_stop) 				-> "API stop received";
error(data_not_available)   	-> "Data is not available";
error(destionation_not_found)   -> "Destination not found";
error(duplicated_session_id)	-> "Duplicated session";
error(file_read_error)   		-> "File read error";
error(internal_error)			-> "Internal error";
error({internal_error, Ref})	-> {"Internal error: ~s", [Ref]};
error({invalid_action, Txt})    -> {"Invalid action '~s'", [Txt]};
error({invalid_state, St}) 	    -> {"Invalid state: ~s", [St]};
error({invalid_value, V}) 		-> {"Invalid value: '~s'", [V]};
error(invalid_json) 			-> "Invalid JSON";
error(invalid_operation) 		-> "Invalid operation";
error(invalid_login_request)    -> "Invalid login request";
error(invalid_parameters) 		-> "Invalid parameters";
error(invalid_password) 		-> "Invalid password";
error(invalid_reply) 			-> "Invalid reply";
error(invalid_role)			    -> "Invalid role";
error(invalid_session_id)		-> "Invalid session";
error(invalid_state) 			-> "Invalid state";
error(invalid_uri) 			    -> "Invalid Uri";
error(invalid_object_id) 		-> "Invalid ObjectId";
error({missing_field, Txt})	    -> {"Missing field: '~s'", [Txt]};
error(missing_id)				-> "Missing Id";
error(no_usages)           		-> "No remaining usages";
error(normal)           		-> "Normal termination";
error(normal_termination) 		-> "Normal termination";
error(not_authenticated)		-> "Not authenticated";
error(not_found) 				-> "Not found";
error(not_started) 				-> "Not yet started";
error(not_implemented) 		    -> "Not implemented";
error(process_down)  			-> "Process failed";
error(process_not_found) 		-> "Process not found";
error(registered_down) 	        -> "Registered process stopped";
error(service_not_found) 		-> "Service not found";
error(session_not_found) 		-> "Session not found";
error(session_stop) 			-> "Session stop";
error(session_timeout) 		    -> "Session timeout";
error({syntax_error, Txt})		-> {"Syntax error: '~s'", [Txt]};
error(timeout) 				    -> "Timeout";
error(unauthorized) 			-> "Unauthorized";
error({unknown_command, Txt})	-> {"Unknown command '~s'", [Txt]};
error(unknown_peer) 			-> "Unknown peer";
error(unknown_op)   			-> "Unknown operation";
error(user_not_found)			-> "User not found";
error({user_not_found, User})	-> {"User not found: '~s'", [User]};
error(user_stop) 				-> "User stop";
error(_)   		                -> continue.



%% ===================================================================
%% Service Callbacks
%% ===================================================================

-type service() :: nkservice:service().

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

service_api_syntax(SyntaxAcc, Req) ->
    {SyntaxAcc, Req}.


%% @doc Called to authorize process a new API command
-spec service_api_allow(req()) ->
    boolean() | {true, req(), state()}.

service_api_allow(_Req) ->
    false.


%% @doc Called to process a new authorized API command
%% For slow requests, reply ack, and the ServiceModule:reply/2.
-spec service_api_cmd(req()) ->
    {ok, Reply::map()} |
    {ok, Reply::map(), req()} |
    ack |
    {ack, pid()} |
    {ack, pid()|undefined, req()} |
    {error, nkservice:error()}  |
    {error, nkservice:error(), req()}.

service_api_cmd(_Req) ->
    {error, not_implemented}.


%% @doc Called when the service received an event it has subscribed to
%% By default, we forward it to the client
-spec service_api_event(req()) ->
    {ok, req()} |  {forward, req()}.

service_api_event(Req) ->
    {forward, Req}.



