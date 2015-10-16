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

%% @doc
-module(nkservice_callbacks).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([init/2, handle_call/3, handle_cast/2, handle_info/2, code_change/3,
		 terminate/2]).
-export([plugin_start/1, plugin_stop/1]).

-type state() :: nkservice_server:sub_state().
-type nks_common() :: continue | {continue, list()}.


-include("nkservice.hrl").



%%%%%%%%%%% Services


%% @doc Called when a new service starts
-spec init(nkservice:spec(), state()) ->
	{ok, state()} | {stop, term()} | nks_common().

init(_SrvSpec, State) ->
	{ok, State}.


%% @doc Called when the service process receives a handle_call/3.
-spec handle_call(term(), {pid(), reference()}, state()) ->
	{reply, term(), state()} | {noreply, state()} | nks_common().

handle_call(Msg, _From, State) ->
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @doc Called when the NkApp process receives a handle_cast/3.
-spec handle_cast(term(), state()) ->
	{noreply, state()} | nks_common().

handle_cast(Msg, State) ->
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
	{noreply, State}.


%% @doc Called when the NkApp process receives a handle_info/3.
-spec handle_info(term(), state()) ->
	{noreply, state()} | nks_common().

handle_info(Msg, State) ->
    lager:notice("Module ~p received unexpected info ~p", [?MODULE, Msg]),
	{noreply, State}.


-spec code_change(term()|{down, term()}, state(), term()) ->
    ok | {ok, state()} | {error, term()} | nks_common().

code_change(OldVsn, State, Extra) ->
	{continue, [OldVsn, State, Extra]}.


%% @doc Called when a service is stopped
-spec terminate(term(), state()) ->
	{ok, state()} | nks_common().

terminate(_Reason, State) ->
	{ok, State}.



%%%%%%%%%%% Plugins - not to be used in user services


%% @doc Called when a new plugin starts
-spec plugin_start(nkservice:spec()) ->
	{ok, nkservice:spec()} | {stop, term()}.

plugin_start(SrvSpec) ->
	{ok, SrvSpec}.


%% @doc Called when a new plugin starts
-spec plugin_stop(nkservice:spec()) ->
	{ok, nkservice:spec()}.

plugin_stop(SrvSpec) ->
	{ok, SrvSpec}.





