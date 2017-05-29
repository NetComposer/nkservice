%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Carlos Gonzalez Florido.  All Rights Reserved.
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
-module(nkservice_rest).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([plugin_deps/0, plugin_syntax/0, plugin_listen/2]).
-export([nkservice_rest_init/2, nkservice_rest_text/3,
         nkservice_rest_handle_call/3, nkservice_rest_handle_cast/2,
         nkservice_rest_handle_info/2, nkservice_rest_terminate/2]).


-include_lib("nklib/include/nklib.hrl").

%% ===================================================================
%% Plugin Callbacks
%% ===================================================================

plugin_deps() ->
	[].


plugin_syntax() ->
    nkpacket:register_protocol(nkservice_rest, nkservice_rest_ws),
    nkpacket_util:get_plugin_net_syntax(#{
        rest_url => fun nkservice_rest_util:parse_rest_server/1
    }).


plugin_listen(Config, #{id:=SrvId}) ->
    {parsed_urls, RestSrv} = maps:get(rest_url, Config, {parsed_urls, []}),
    RestSrvs1 = nkservice_rest_util:get_rest_http(SrvId, RestSrv, Config),
    RestSrvs2 = nkservice_rest_util:get_rest_ws(SrvId, RestSrv, Config),
    RestSrvs1 ++ RestSrvs2.




%% ===================================================================
%% REST Callbacks
%% ===================================================================

-type state() :: nkapi_server:user_state().
-type continue() :: nkservice_callbacks:continue().


%% @doc Called when a new connection starts
-spec nkservice_rest_init(nkpacket:nkport(), state()) ->
    {ok, state()} | {stop, term()}.

nkservice_rest_init(_NkPort, State) ->
    {ok, State}.


%% @doc Called when a new connection starts
-spec nkservice_rest_text(binary(), nkpacket:nkport(), state()) ->
    {ok, state()}.

nkservice_rest_text(_Text, _NkPort, State) ->
    {ok, State}.


%% @doc Called when the process receives a handle_call/3.
-spec nkservice_rest_handle_call(term(), {pid(), reference()}, state()) ->
    {ok, state()} | continue().

nkservice_rest_handle_call(Msg, _From, State) ->
    lager:error("Module nkservice_rest received unexpected call ~p", [Msg]),
    {ok, State}.


%% @doc Called when the process receives a handle_cast/3.
-spec nkservice_rest_handle_cast(term(), state()) ->
    {ok, state()} | continue().

nkservice_rest_handle_cast(Msg, State) ->
    lager:error("Module nkservice_rest received unexpected cast ~p", [Msg]),
    {ok, State}.


%% @doc Called when the process receives a handle_info/3.
-spec nkservice_rest_handle_info(term(), state()) ->
    {ok, state()} | continue().

nkservice_rest_handle_info(Msg, State) ->
    lager:notice("Module nkservice_rest received unexpected info ~p", [Msg]),
    {ok, State}.


%% @doc Called when a service is stopped
-spec nkservice_rest_terminate(term(), state()) ->
    {ok, state()}.

nkservice_rest_terminate(_Reason, State) ->
    {ok, State}.

