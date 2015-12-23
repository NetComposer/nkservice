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

-export([service_init/2, service_handle_call/3, service_handle_cast/2, 
		 service_handle_info/2, service_code_change/3, service_terminate/2]).
-export_type([continue/0]).


-type state() :: map().
-type continue() :: continue | {continue, list()}.


%% @doc Called when a new service starts
-spec service_init(nkservice:spec(), state()) ->
	{ok, state()} | {stop, term()}.

service_init(_SrvSpec, State) ->
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
    ok | {ok, state()} | {error, term()} | continue().

service_code_change(OldVsn, State, Extra) ->
	{continue, [OldVsn, State, Extra]}.


%% @doc Called when a service is stopped
-spec service_terminate(term(), state()) ->
	{ok, state()}.

service_terminate(_Reason, State) ->
	{ok, State}.



%% This function, if implemented, is called after the syntax processing, and
%% high level plugins have the opportunity to modify the specification for lower
%% levels plugins

plugin_spec(UserSpec) ->
	{ok, Spec}.



%% Called before the service has started
%% UserSpec has parsed specifications, and Service must be updated
%% - add or updated the values of the 'cache' key. They will be expanded as
%%   functions cache_... at the compiled run-time module
%% - add or updated the values of the 'transport' key. They will be started as
%%   transports
%% - add a plugin-specific key for its configuration
plugin_init(_UserSpec, Service) ->
	{ok, Service}.

plugin_cache(UserSpec) ->
	{ok, #{}}.

plugin_transports()



