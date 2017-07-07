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

%% @doc Utilities functions to interact with sessions
-module(nkservice_session).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([cmd/3, cmd_async/3, send_event/2, start_ping/2, stop_ping/1, stop_session/1, stop_session/2]).
-export([subscribe/2, unsubscribe/2, get_subscriptions/1, register/2, unregister/2]).


-include("nkservice.hrl").


%% ===================================================================
%% Types
%% ===================================================================

-type req() :: #nkreq{}.
-type data() :: map() | list().





%% ===================================================================
%% Callbacks
%% ===================================================================


%% @doc Send a command to the client using the session and wait a response
-callback cmd(pid(), nkservice:req_cmd(), data()) ->
    {ok, Result::binary(), data()} | {error, nkservice:error()}.


%% @doc Send a command and don't wait for a response
-callback cmd_async(pid(), nkservice:req_cmd(), data()) ->
    ok | {error, nkservice:error()}.


%% @doc Sends an event directly to the client (as if the session were subscribed to it)
%% Response is not expected from remote
-callback send_event(pid(), nkevent:event()) ->
    ok | {error, nkservice:error()}.


%%%% @doc Sends a reply to a command (when you reply 'ack' in callbacks)
%%-callback reply(pid(),
%%                   {ok, map(), req()} |
%%                   {error, nkservice:error(), req()} |
%%                   {ack, req()} |
%%                   {ack, pid(), req()}
%%               ) ->
%%                   ok.


%% @doc Start sending pings through the session
-callback start_ping(pid(), integer()) ->
    ok | {error, nkservice:error()}.


%% @doc Stops the session
-callback stop_session(pid(), nkservice:error()) ->
    ok | {error, nkservice:error()}.


%% @doc Registers a process with the session
-callback register(pid(), nklib:link()) ->
    ok | {error, nkservice:error()}.


%% @doc Unregisters a process with the session
-callback unregister(pid(), nklib:link()) ->
    ok | {error, nkservice:error()}.


%% @doc Registers the session with the Events system
-callback subscribe(pid(), nkevent:event()) ->
    ok | {error, term()}.


%% @doc Unregisters with the Events system
-callback unsubscribe(pid(),  nkevent:event()) ->
    ok | {error, term()}.


%% @doc Gets all current subscriptions
-callback get_subscriptions(pid()) ->
    {ok, [map()]} | {error, term()}.



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Send a command to the client at the session and waits for a response
-spec cmd(req(), nkservice:req_cmd(), data()) ->
    {ok, Result::binary(), data()} | {error, term()}.

cmd(#nkreq{session_module=Mod, session_pid=Pid}, Cmd, Data) ->
    Mod:cmd(Pid, Cmd, Data).


%% @doc Send a command and don't wait for a response
-spec cmd_async(req(), nkservice:req_cmd(), data()) ->
    ok | {error, term()}.

cmd_async(#nkreq{session_module=Mod, session_pid=Pid}, Cmd, Data) ->
    Mod:cmd_async(Pid, Cmd, Data).


%% @doc Sends an event to the client connected to the session
-spec send_event(req(), nkevent:event()) ->
    ok | {error, term()}.

send_event(#nkreq{session_module=Mod, session_pid=Pid}, Event) ->
    Mod:send_event(Pid, Event).


%% @doc Start sending pings
-spec start_ping(pid(), integer()) ->
    ok | {error, term()}.

start_ping(#nkreq{session_module=Mod, session_pid=Pid}, Time) ->
    Mod:start_ping(Pid, Time).


%% @doc Stop sending pings
-spec stop_ping(req()) ->
    ok | {error, term()}.

stop_ping(#nkreq{session_module=Mod, session_pid=Pid}) ->
    Mod:stop_ping(Pid).


%% @doc Stop session
-spec stop_session(req()) ->
    ok | {error, term()}.

stop_session(Req) ->
    stop_session(Req, user_stop).


%% @doc Stop session
-spec stop_session(req(), nkservice:error()) ->
    ok | {error, term()}.

stop_session(#nkreq{session_module=Mod, session_pid=Pid}, Error) ->
    Mod:stop(Pid, Error).


%% @doc Registers with the Events system
-spec subscribe(req(), nkevent:event()) ->
    ok | {error, term()}.

subscribe(#nkreq{session_module=Mod, session_pid=Pid}, Event) ->
    Mod:subscribe(Pid, Event).


%% @doc Unregisters with the Events system
-spec unsubscribe(req(), nkevent:event()) ->
    ok | {error, term()}.

unsubscribe(#nkreq{session_module=Mod, session_pid=Pid}, Event) ->
    Mod:unsubscribe(Pid, Event).


%% @doc Unregisters with the Events system
-spec get_subscriptions(req()) ->
    {ok, [map()]} | {error, term()}.

get_subscriptions(#nkreq{session_module=Mod, session_pid=Pid}) ->
    Mod:get_subscriptions(Pid).


%% @doc Registers a process with the session
-spec register(req(), nklib:link()) ->
    ok | {error, nkservice:error()}.

register(#nkreq{session_module=Mod, session_pid=Pid}, Link) ->
    Mod:register(Pid, Link).


%% @doc Registers a process with the session
-spec unregister(req(), nklib:link()) ->
    ok | {error, nkservice:error()}.

unregister(#nkreq{session_module=Mod, session_pid=Pid}, Link) ->
    Mod:unregister(Pid, Link).


