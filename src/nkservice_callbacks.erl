%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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
-export([error_code/1]).
-export([api_server_init/2, api_server_terminate/2, 
		 api_server_login/3, api_server_cmd/2, api_server_event/3,
		 api_server_forward_event/3, api_server_get_user_data/1,
		 api_server_reg_down/3,
		 api_server_handle_call/3, api_server_handle_cast/2, 
		 api_server_handle_info/2, api_server_code_change/3]).
-export([api_allow/2, api_subscribe_allow/5, api_cmd/2, api_syntax/4]).

-export_type([continue/0]).

-type continue() :: continue | {continue, list()}.
-type config() :: nkservice:config().
-type error_code() :: nkservice:error().

-include_lib("nkpacket/include/nkpacket.hrl").
-include("nkservice.hrl").



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
-spec plugin_group() ->
    term() | undefined.

plugin_group() ->
	undefined.


%% @doc This function, if implemented, can offer a nklib_config:syntax()
%% that will be checked againts service configuration. Entries passing will be
%% updated on the configuration with their parsed values
-spec plugin_syntax() ->
	nklib_config:syntax().

plugin_syntax() ->
	#{}.


%% @doc This function, if implemented, can offer a defaults specificaction
%% for the syntax processing
-spec plugin_defaults() ->
	map().

plugin_defaults() ->
	#{}.


%% @doc This function can modify the service configuration, and can also
%% generate a specific plugin configuration (in the second return), that will be 
%% accesible in the generated module as config_(plugin_name).
-spec plugin_config(config(), service()) ->
	{ok, config()} | {ok, config(), term()} | {error, term()}.

plugin_config(Config, _Service) ->
	{ok, Config, nkservice_syntax:get_config(Config)}.


%% @doc This function, if implemented, allows to add listening transports.
%% By default start the web_server and api_server transports.
-spec plugin_listen(config(), service()) ->
	[{nkpacket:user_connection(), nkpacket:listener_opts()}].

plugin_listen(Config, #{id:=SrvId}) ->
	nkservice_util:get_core_listeners(SrvId, Config).


%% @doc Called during service's start
%% The plugin must start and can update the service's config
-spec plugin_start(config(), service()) ->
	{ok, service()} | {error, term()}.

plugin_start(Config, _Service) ->
	{ok, Config}.


%% @doc Called during service's update
-spec plugin_update(config(), service()) ->
	{ok, service()} | {error, term()}.

plugin_update(Config, _Service) ->
	{ok, Config}.


%% @doc Called during service's stop
%% The plugin must remove any key from the service
-spec plugin_stop(config(), service()) ->
	{ok, service()}.

plugin_stop(Config, _Service) ->
	{ok, Config}.


%% ===================================================================
%% Error Codes
%% ===================================================================

%% @docd
-spec error_code(term()) ->
	{integer(), binary()} | continue.

error_code(internal_error)			-> {1001, <<"Internal error">>};
error_code(normal) 					-> {1002, <<"Normal termination">>};	% CHANGE
error_code(anormal_termination)     -> {1003, <<"Anormal termination">>};
error_code(invalid_state) 			-> {1004, <<"Invalid state">>};
error_code(timeout) 				-> {1005, <<"Timeout">>};
error_code(not_implemented) 		-> {1006, <<"Not implemented">>};

error_code(process_not_found) 		-> {1010, <<"Process not found">>};
error_code(process_down)  			-> {1011, <<"Process failed">>};
error_code(registered_down) 	    -> {1012, <<"Registered process stopped">>};
error_code(user_stop) 				-> {1013, <<"User stop">>};

error_code(service_not_found) 		-> {1020, <<"Service not found">>};

error_code(unauthorized) 			-> {1030, <<"Unauthorized">>};
error_code(not_authenticated)		-> {1031, <<"Not authenticated">>};
error_code(already_authenticated)	-> {1032, <<"Already authenticated">>};
error_code(user_not_found)			-> {1033, <<"User not found">>};
error_code(duplicated_session_id)	-> {1034, <<"Duplicated session id">>};
error_code(invalid_session_id)		-> {1035, <<"Invalid session id">>};

error_code(operation_error) 		-> {1040, <<"Operation error">>};
error_code(unknown_command)			-> {1041, <<"Unknown command">>};
error_code(unknown_class)			-> {1042, <<"Unknown class">>};
error_code(incompatible_operation) 	-> {1043, <<"Incompatible operation">>};
error_code(unknown_operation) 		-> {1044, <<"Unknown operation">>};
error_code(invalid_operation) 		-> {1045, <<"Invalid operation">>};
error_code({syntax_error, Txt})		-> {1046, {"Syntax error: ~s", [Txt]}};
error_code({missing_field, Txt})	-> {1047, {"Missing field: ~s", [Txt]}};
error_code(invalid_parameters) 		-> {1048, <<"Invalid parameters">>};
error_code({invalid_value, V}) 		-> {1049, {"Invalid value: ~s", [V]}};

error_code(session_timeout) 		-> {1060, <<"Session timeout">>};
error_code(session_stop) 			-> {1061, <<"Session stop">>};
error_code(session_not_found) 		-> {1062, <<"Session not found">>};

error_code(invalid_uri) 			-> {1070, <<"Invalid Uri">>};

error_code({Code, Txt}) when is_integer(Code), is_binary(Txt) ->
	{Code, Txt};

error_code(Other) -> 
	{9999, nklib_util:to_binary(Other)}.



%% ===================================================================
%% API Server Callbacks
%% ===================================================================


%% @doc Called when a new connection starts
-spec api_server_init(nkpacket:nkport(), state()) ->
	{ok, state()} | {stop, term()}.

api_server_init(_NkPort, State) ->
	{ok, State}.


%% @doc Cmd "login" is received (class "core")
%% You get the class and data fields, along with a server-generated session id
%% You can accept the request setting an 'user' for this connection
%% and, optionally, changing the session id (for example for session recoverty)
-spec api_server_login(map(), SessId::binary(), state()) ->
	{true, User::binary(), state()} | 
	{true, User::binary(), SessId::binary(), state()} | 
	{false, error_code(), state()} | continue.

api_server_login(_Data, _SessId, State) ->
	{false, unauthorized, State}.


%% @doc Called when a new cmd is received
-spec api_server_cmd(#api_req{}, state()) ->
	{ok, map(), state()} | {ack, state()} | 
	{error, error_code(), state()} | continue().

api_server_cmd(#api_req{class = <<"core">>}=Req, State) ->
	nkservice_api:launch(Req, State);
	
api_server_cmd(_Req, State) ->
    {error, not_implemented, State}.


%% @doc Called when a new event has been received from the remote end
-spec api_server_event(nkservice_event:reg_id(), nkservice_event:body(), state()) ->
	{ok, state()} | continue().

api_server_event(_RegId, _Body, State) ->
	{ok, State}.
	

%% @doc Called when the API server receives an event notification from 
%% nkservice_events. We can send it to the remote side or ignore it.
-spec api_server_forward_event(nkservice_event:reg_id(), 
							   nkservice_event:body(), state()) ->
	{ok, state()} | 
	{ok, nkservice_event:reg_id(), nkservice_event:body(), continue()} |
	{ignore, state()}.

api_server_forward_event(_RegId, _Body, State) ->
	{ok, State}.


%% @doc Called when the API server receives an event notification from 
%% nkservice_events. We can send it to the remote side or ignore it.
-spec api_server_get_user_data(state()) ->
	{ok, term()}.

api_server_get_user_data(State) ->
	{ok, State}.


%% @doc Called when the xzservice process receives a handle_call/3.
-spec api_server_reg_down(nklib:link(), Reason::term(), state()) ->
	{ok, state()} | continue().

api_server_reg_down(_Link, _Reason, State) ->
    {ok, State}.


%% @doc Called when the xzservice process receives a handle_call/3.
-spec api_server_handle_call(term(), {pid(), reference()}, state()) ->
	{ok, state()} | continue().

api_server_handle_call(Msg, _From, State) ->
    lager:error("Module nkservice_api_server received unexpected call ~p", [Msg]),
    {ok, State}.


%% @doc Called when the NkApp process receives a handle_cast/3.
-spec api_server_handle_cast(term(), state()) ->
	{ok, state()} | continue().

api_server_handle_cast(Msg, State) ->
    lager:error("Module nkservice_api_server received unexpected cast ~p", [Msg]),
	{ok, State}.


%% @doc Called when the NkApp process receives a handle_info/3.
-spec api_server_handle_info(term(), state()) ->
	{ok, state()} | continue().


% api_server_handle_info({'DOWN', Mon, process, Pid, Reason}, State) ->
% 	{ok, State2} = nkservice_api:handle_down(Mon, Pid, Reason, State),
% 	{ok, State2};

api_server_handle_info(Msg, State) ->
    lager:notice("Module nkservice_api_server received unexpected info ~p", [Msg]),
	{ok, State}.


-spec api_server_code_change(term()|{down, term()}, state(), term()) ->
    ok | {ok, service()} | {error, term()} | continue().

api_server_code_change(OldVsn, State, Extra) ->
	{continue, [OldVsn, State, Extra]}.


%% @doc Called when a service is stopped
-spec api_server_terminate(term(), service()) ->
	{ok, service()}.

api_server_terminate(_Reason, State) ->
	{ok, State}.



%% ===================================================================
%% API Management Callbacks
%% ===================================================================

%% @doc Called to get the syntax for an external API command
-spec api_syntax(#api_req{}, map(), map(), list()) ->
	{Syntax::map(), Defaults::map(), Mandatory::list()}.

api_syntax(#api_req{class = <<"core">>}=Req, Syntax, Defaults, Mandatory) ->
	#api_req{subclass=Sub, cmd=Cmd} = Req,
	nkservice_api:syntax(Sub, Cmd, Syntax, Defaults, Mandatory);
	
api_syntax(_Req, Syntax, Defaults, Mandatory) ->
	{Syntax, Defaults, Mandatory}.


%% @doc Called when a new API command has arrived and called nkservice_api:launch/6
%% to authorized the (already parsed) request
-spec api_allow(#api_req{}, state()) ->
	{boolean(), state()}.

api_allow(_Req, State) ->
	{false, State}.


%% @doc Called when a 'subscribe' external command arrives
%% You should allow subscribing to other service's events without care.
-spec api_subscribe_allow(nkservice:id(), nkservice_events:class(),	 
						  nkservice_events:subclass(), nkservice_events:type(), map()) ->
	{boolean(), map()}.

api_subscribe_allow(_SrvId, _Class, _SubClass, _Type, State) ->
	{false, State}.


%% @doc Called when a new API command has arrived and is authorized
-spec api_cmd(#api_req{}, state()) ->
	{ok, map(), state()} | {ack, state()} | {error, nkservice:error(), state()}.

api_cmd(#api_req{class = <<"core">>}=Req, State) ->
	#api_req{subclass=Sub, cmd=Cmd} = Req,
	nkservice_api:cmd(Sub, Cmd, Req, State);

api_cmd(_Req, State) ->
	{error, not_implemented, State}.



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

