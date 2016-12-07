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
-export([error_code/1]).
-export([api_server_init/2, api_server_terminate/2, 
		 api_server_syntax/4, api_server_allow/2, 
		 api_server_cmd/2, api_server_login/2,
		 api_server_event/3,
		 api_server_forward_event/2, api_server_get_user_data/1,
		 api_server_reg_down/3,
		 api_server_handle_call/3, api_server_handle_cast/2, 
		 api_server_handle_info/2, api_server_code_change/3]).
-export([api_server_http_download/4, api_server_http_upload/6]).
-export([api_server_http_get/2, api_server_http_post/4]).
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
%% This way, the order of callbacks is the same as the order plugins are defined
%% in this group.
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

%% Code ranges
%% NkService:		100XXX
%%
%% NkSIP:			200XXX
%%
%% NkMEDIA:			300XXX
%% 		Janus		301XXX
%% 		FS         	302XXX
%% 		KMS			303XXX
%% 		Room		3040XX
%%   		Msglog	3041XX
%% 		Call		305XXX
%% 		Verto		306XXX
%% 		JanusProto: 307XXX
%% 		SIP:		308XXX
%%
%% NkCOLLAB			400XXX
%%		Room		401XXX
%% 		Call		402XXX


%% @doc
-spec error_code(term()) ->
	{integer(), binary()} | continue.

error_code(normal_termination) 		-> {100001, "Normal termination"};	
error_code(internal_error)			-> {100002, "Internal error"};
error_code({internal_error, Ref})	-> {100003, "Internal error: ~s", [Ref]};
error_code(invalid_state) 			-> {100004, "Invalid state"};
error_code(timeout) 				-> {100005, "Timeout"};
error_code(not_implemented) 		-> {100006, "Not implemented"};
error_code({exit, _Exit}) 			-> {100007, "Internal error"};
error_code(process_not_found) 		-> {100008, "Process not found"};
error_code(process_down)  			-> {100009, "Process failed"};
error_code(registered_down) 	    -> {100010, "Registered process stopped"};
error_code(user_stop) 				-> {100011, "User stop"};
error_code(member_stop)				-> {100012, "Member stop"};
error_code(api_stop) 				-> {100013, "API stop received"};

error_code(service_not_found) 		-> {100020, "Service not found"};

error_code(unauthorized) 			-> {100030, "Unauthorized"};
error_code(not_authenticated)		-> {100031, "Not authenticated"};
error_code(already_authenticated)	-> {100032, "Already authenticated"};
error_code(user_not_found)			-> {100033, "User not found"};
error_code(duplicated_session_id)	-> {100034, "Duplicated session id"};
error_code(invalid_session_id)		-> {100035, "Invalid session id"};
error_code(member_not_found)		-> {100036, "Member not found"};
error_code(invalid_role)			-> {100037, "Invalid role"};
error_code(invalid_password) 		-> {100038, "Invalid password"};

error_code(invalid_operation) 		-> {100040, "Invalid operation"};
error_code(invalid_parameters) 		-> {100041, "Invalid parameters"};
error_code({unknown_command, Txt})	-> {100042, "Unknown command '~s'", [Txt]};
error_code({invalid_action, Txt})   -> {100043, "Invalid action '~s'", [Txt]};
error_code({syntax_error, Txt})		-> {100044, "Syntax error: ~s", [Txt]};
error_code({missing_field, Txt})	-> {100045, "Missing field: ~s", [Txt]};
error_code({invalid_value, V}) 		-> {100046, "Invalid value: ~s", [V]};
error_code(invalid_reply) 			-> {100047, "Invalid reply"};

error_code(session_timeout) 		-> {100060, "Session timeout"};
error_code(session_stop) 			-> {100061, "Session stop"};
error_code(session_not_found) 		-> {100062, "Session not found"};

error_code(invalid_uri) 			-> {100070, "Invalid Uri"};
error_code(unknown_peer) 			-> {100071, "Unknown peer"};
error_code(invalid_json) 			-> {100072, "Invalid JSON"};
error_code(data_not_available)   	-> {100073, "Data is not available"};


error_code({Code, Txt}) when is_integer(Code), is_binary(Txt) ->
	{Code, Txt};

error_code(Other) -> 
	{999999, nklib_util:to_binary(Other)}.



%% ===================================================================
%% API Server Callbacks
%% ===================================================================


%% @doc Called when a new connection starts
-spec api_server_init(nkpacket:nkport(), state()) ->
	{ok, state()} | {stop, term()}.

api_server_init(_NkPort, State) ->
	{ok, State}.


%% @doc Called to get the syntax for an external API command
%% Called from nkservice_api_lib
-spec api_server_syntax(#api_req{}, map(), map(), list()) ->
	{Syntax::map(), Defaults::map(), Mandatory::list()}.

api_server_syntax(#api_req{class=core}=Req, Syntax, Defaults, Mandatory) ->
	#api_req{subclass=Sub, cmd=Cmd} = Req,
	nkservice_api_syntax:syntax(Sub, Cmd, Syntax, Defaults, Mandatory);
	
api_server_syntax(_Req, Syntax, Defaults, Mandatory) ->
	{Syntax, Defaults, Mandatory}.


%% @doc Called when a new API command has arrived and called nkservice_api:launch_cmd/6
%% to authorized the (already parsed) request
%% Called from nkservice_api_lib
-spec api_server_allow(#api_req{}, state()) ->
	{boolean(), state()}.

api_server_allow(_Req, State) ->
	{false, State}.


%% @doc Called when a new API command has arrived and is authorized
-spec api_server_cmd(#api_req{}, state()) ->
	{ok, map(), state()} | {ack, state()} | {error, nkservice:error(), state()}.

api_server_cmd(#api_req{class=core, subclass=Sub, cmd=Cmd}=Req, State) ->
	nkservice_api:cmd(Sub, Cmd, Req, State);

api_server_cmd(_Req, State) ->
	{error, not_implemented, State}.


%% @doc Used when the standard login apply
%% Called from nkservice_api or nkservice_api_server_http
-spec api_server_login(map(), state()) ->
	{true, User::binary(), Meta::map(), state()} | 
	{false, error_code(), state()} | continue.

api_server_login(_Data, State) ->
	{false, unauthorized, State}.


%% @doc Called when a new event has been received from the remote end
-spec api_server_event(nkservice_event:event(), nkservice_event:body(), state()) ->
	{ok, state()} | continue().

api_server_event(_Event, _Body, State) ->
	{ok, State}.
	

%% @doc Called when the API server receives an event notification from 
%% nkservice_events. We can send it to the remote side or ignore it.
-spec api_server_forward_event(nkservice_event:event(), state()) ->
	{ok, nkservice_event:event(), continue()} |
	{ignore, state()}.

api_server_forward_event(Event, State) ->
	{ok, Event, State}.


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
-spec api_server_terminate(term(), state()) ->
	{ok, service()}.

api_server_terminate(_Reason, State) ->
	{ok, State}.


%% @doc called when a new download request has been received
-spec api_server_http_download(Mod::atom(), ObjId::term(), Name::term(), state()) ->
	{ok, CT::binary(), Bin::binary(), state()} |
	{error, nkservice:error(), state()}.

api_server_http_download(_Mod, _ObjId, _Name, State) ->
	{error, not_found, State}.


%% @doc called when a new upload request has been received
-spec api_server_http_upload(Mod::atom(), ObjId::term(), Name::term(), 
							 CT::binary(), Bin::binary(), state()) ->
	{ok, state()} |
	{error, nkservice:error(), state()}.

api_server_http_upload(_Mod, _ObjId, _Name, _CT, _Bin, State) ->
	{error, not_found, State}.


%% @doc called when a GET is received
-spec api_server_http_get([binary()], state()) ->
	{ok, Code::integer(), Hds::[{binary(), binary()}], Body::map()|binary(), state()}.

api_server_http_get(_Path, State) ->
	{ok, 404, [], <<"Unhandled Request">>, State}.


%% @doc called when a PUT is received
-spec api_server_http_post([binary()], CT::binary(), Body::binary(), state()) ->
	{ok, Code::integer(), Hds::[{binary(), binary()}], Body::map()|binary(), state()}.

api_server_http_post(_Path, _CT, _Body, State) ->
	{ok, 404, [], <<"Unhandled Request">>, State}.


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
