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
-export([plugin_deps/0, plugin_syntax/0, plugin_defaults/0, plugin_config/2, 
		 plugin_listen/2, plugin_start/2, plugin_update/2, plugin_stop/2]).
-export([service_init/2, service_handle_call/3, service_handle_cast/2, 
		 service_handle_info/2, service_code_change/3, service_terminate/2]).
-export([error_code/1]).
-export([api_server_init/2, api_server_terminate/2, 
		 api_server_login/3, api_server_cmd/5,
		 api_server_handle_call/3, api_server_handle_cast/2, 
		 api_server_handle_info/2, api_server_code_change/3]).

-export_type([continue/0]).

-type continue() :: continue | {continue, list()}.
-type config() :: nkservice:config().
-type error_code() :: nkservice:error_code().

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


%% @doc This function, if implemented, allows to set modules offering APIs 
%% for the Lua Scripting Environment
-spec plugin_lua_modules(config(), service()) ->
	[{atom(), module()}].

plugin_lua_modules(_Config, _Service) ->
	[
		{log, nkservice_luerl_lager},
		{kv, nkservice_luerl_kv}
	].




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
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @doc Called when the NkApp process receives a handle_cast/3.
-spec service_handle_cast(term(), state()) ->
	{noreply, state()} | continue().

service_handle_cast(Msg, State) ->
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
	{noreply, State}.


%% @doc Called when the NkApp process receives a handle_info/3.
-spec service_handle_info(term(), state()) ->
	{noreply, state()} | continue().

service_handle_info(Msg, State) ->
    lager:notice("Module ~p received unexpected info ~p", [?MODULE, Msg]),
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
%% External Server Callbacks
%% ===================================================================




%% ===================================================================
%% Error Codes
%% ===================================================================

%% @docd
-spec error_code(term()) ->
	{integer(), binary()} | continue.

error_code(not_implemented) 	-> {1000, <<"Not Implemented">>};
error_code(unauthorized) 		-> {1001, <<"Unauthorized">>};
error_code(not_authenticated)	-> {1002, <<"Not Authenticated">>};
error_code(internal_error)		-> {1003, <<"Internal Error">>};
error_code({syntax_error, Msg})	-> {1004, <<"Syntax Error: ", Msg/binary>>};
error_code(_) 					-> {9999, <<"Unknown Error">>}.



%% ===================================================================
%% API Server Callbacks
%% ===================================================================

-type class() :: atom().
-type cmd() :: atom().
-type data() :: map().
-type tid() :: term().


%% @doc Called when a new connection starts
-spec api_server_init(nkpacket:nkport(), state()) ->
	{ok, state()} | {stop, term()}.

api_server_init(_NkPort, State) ->
	{ok, State}.


%% @doc Cmd "login" is received (class "core")
%% You get the class and data fields, along with a server-generated session id
%% You can accept the request setting an 'user' for this connection
%% and, optionally, changing the session id (for example for session recovery)
-spec api_server_login(data(), SessId::binary(), state()) ->
	{true, User::binary(), state()} | 
	{true, User::binary(), SessId::binary(), state()} | 
	{false, error_code(), state()} | continue.

api_server_login(_Data, _SessId, State) ->
	{false, unauthorized, State}.


%% @doc Called when a new cmd is received
-spec api_server_cmd(class(), cmd(), data(), tid(), state()) ->
	{ok, data(), state()} | {ack, state()} | 
	{error, error_code(), state()} | continue().

api_server_cmd(_Class, _Cmd, _Data, _Tid, State) ->
    {error, not_implemented, State}.


%% @doc Called when the xzservice process receives a handle_call/3.
-spec api_server_handle_call(term(), {pid(), reference()}, state()) ->
	{ok, state()} | continue().

api_server_handle_call(Msg, _From, State) ->
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {ok, State}.


%% @doc Called when the NkApp process receives a handle_cast/3.
-spec api_server_handle_cast(term(), state()) ->
	{ok, state()} | continue().

api_server_handle_cast(Msg, State) ->
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
	{ok, State}.


%% @doc Called when the NkApp process receives a handle_info/3.
-spec api_server_handle_info(term(), state()) ->
	{ok, state()} | continue().

api_server_handle_info(Msg, State) ->
    lager:notice("Module ~p received unexpected info ~p", [?MODULE, Msg]),
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


