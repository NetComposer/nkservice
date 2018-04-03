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
-module(nkservice_rest_callbacks).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([nkservice_rest_init/3, nkservice_rest_text/4,
         nkservice_rest_handle_call/4, nkservice_rest_handle_cast/3,
         nkservice_rest_handle_info/3, nkservice_rest_terminate/3]).
-export([nkservice_rest_http/4]).


-include_lib("nklib/include/nklib.hrl").

-define(LLOG(Type, Txt, Args),lager:Type("NkSERVICE REST "++Txt, Args)).


%% ===================================================================
%% REST Callbacks
%% ===================================================================

-type state() :: nkapi_server:user_state().
-type continue() :: nkservice_callbacks:continue().
-type id() :: nkservice_rest:id().
-type http_method() :: nkservice_rest:method().
-type http_path() :: nkservice_rest:path().
-type http_req() :: nkservice_rest:req().
-type http_reply() :: nkservice_rest:reply().
-type nkport() :: nkpacket:nkport().


%% @doc called when a new http request has been received
-spec nkservice_rest_http(id(), http_method(), http_path(), http_req()) ->
    http_reply().

nkservice_rest_http(_Id, _Method, _Path, Req) ->
    {Ip, _Port} = nkservice_rest_http:get_peer(Req),
    ?LLOG(error, "path not found (~p, ~p): ~p from ~s", [_Id, _Method, _Path, nklib_util:to_host(Ip)]),
    {http, 404, [], <<"Not Found">>, Req}.


%% @doc Called when a new connection starts
-spec nkservice_rest_init(id(), nkport(), state()) ->
    {ok, state()} | {stop, term()}.

nkservice_rest_init(_Id, _NkPort, State) ->
    {ok, State}.


%% @doc Called when a new connection starts
-spec nkservice_rest_text(id(), binary(), nkport(), state()) ->
    {ok, state()}.

nkservice_rest_text(_Id, _Text, _NkPort, State) ->
    ?LLOG(notice, "unhandled data ~p", [_Text]),
    {ok, State}.


%% @doc Called when the process receives a handle_call/3.
-spec nkservice_rest_handle_call(id(), term(), {pid(), reference()}, state()) ->
    {ok, state()} | continue().

nkservice_rest_handle_call(_Id, Msg, _From, State) ->
    ?LLOG(error, "unexpected call ~p", [Msg]),
    {ok, State}.


%% @doc Called when the process receives a handle_cast/3.
-spec nkservice_rest_handle_cast(id(), term(), state()) ->
    {ok, state()} | continue().

nkservice_rest_handle_cast(_Id, Msg, State) ->
    ?LLOG(error, "unexpected cast ~p", [Msg]),
    {ok, State}.


%% @doc Called when the process receives a handle_info/3.
-spec nkservice_rest_handle_info(id(), term(), state()) ->
    {ok, state()} | continue().

nkservice_rest_handle_info(_Id, Msg, State) ->
    ?LLOG(error, "unexpected cast ~p", [Msg]),
    {ok, State}.


%% @doc Called when a service is stopped
-spec nkservice_rest_terminate(id(), term(), state()) ->
    {ok, state()}.

nkservice_rest_terminate(_Id, _Reason, State) ->
    {ok, State}.


