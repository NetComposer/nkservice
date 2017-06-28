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

%% @doc Implementation of the NkAPI External Interface (server)
-module(nkservice_nkapi).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-include("nkservice.hrl").


%% ===================================================================
%% Types
%% ===================================================================

-type req() :: #nkreq{}.
-type data() :: map() | list().


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Returns the server type
-callback type() ->
    session | http.


%% @doc Send a command to the client and wait a response
-callback cmd(pid(), nkservice:req_cmd(), data()) ->
    {ok, Result::binary(), data()} | {error, term()}.


%% @doc Send a command and don't wait for a response
-callback cmd_async(pid(), nkservice:req_cmd(), data()) ->
    ok.


%% @doc Sends an event directly to the client (as it we were subscribed to it)
%% Response is not expected from remote
-callback event(pid(), nkevent:event()) ->
    ok.


%% @doc Sends a reply to a command (when you reply 'ack' in callbacks)
-callback reply(
                    {ok, map(), req()} |
                    {error, nkservice:error(), req()} |
                    {ack, req()} |
                    {ack, pid(), req()}
               ) ->
   ok.


%% @doc Start sending pings
-callback start_ping(pid(), integer()) ->
    ok.


%% @doc Stop sending pings
-callback stop_ping(pid()) ->
    ok.


%% @doc Stops the server
-callback stop(pid()) ->
    ok.


%% @doc Stops the server
-callback stop(pid(), nkservice:error()) ->
    ok.


%% @doc Registers a process with the session
-callback register(pid(), nklib:link()) ->
    ok | {error, nkservice:error()}.


%% @doc Unregisters a process with the session
-callback unregister(pid(), nklib:link()) ->
    ok | {error, nkservice:error()}.


%% @doc Registers with the Events system
-callback subscribe(pid(), nkevent:event()) ->
    ok | {error, term()}.


%% @doc Unregisters with the Events system
-callback unsubscribe(pid(),  nkevent:event()) ->
    ok | {error, term()}.
