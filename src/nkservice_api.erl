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
-module(nkservice_api).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([api/2, event/2]).

-include_lib("nkevent/include/nkevent.hrl").
-include("nkservice.hrl").


-define(DEBUG(Txt, Args, Req),
    case Req#nkreq.debug of
        true -> ?LLOG(debug, Txt, Args, Req);
        _ -> ok
    end).

-define(LLOG(Type, Txt, Args, Req),
    lager:Type(
        [
            {session_id, Req#nkreq.session_id},
            {user_id, Req#nkreq.user_id},
            {cmd, Req#nkreq.cmd}
        ],
        "NkSERVICE API (~s, ~s, ~s) "++Txt,
        [
            Req#nkreq.user_id,
            Req#nkreq.session_id,
            Req#nkreq.cmd
            | Args
        ])).


%% ===================================================================
%% Types
%% ===================================================================

-type req() :: #nkreq{}.
-type state() :: map().


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts the processing of an external API request
%% It parses the request, getting the syntax calling SrvId:api_server_syntax()
%% If it is valid, calls SrvId:api_server_allow() to authorized the request
%% If is is authorized, calls SrvId:api_server_cmd() to process the request.
%% It received some state (usually from api_server_cmd/5) that can be updated
-spec api(req(), state()) ->
    {ok, Reply::term(), [binary()], state()} | {ok, state()} |
    {ack, [binary()], state()} |
    {login, Reply::term(), nkservice:user_id(), nkservice:user_meta(), [binary()], state()} |
    {error, nkservice:error(), state()}.

api(Req, State) ->
    #nkreq{srv_id=SrvId, data=Data} = Req,
    {Syntax, Req2} = SrvId:service_api_syntax(#{}, Req),
    ?DEBUG("parsing syntax ~p (~p)", [Data, Syntax], Req),
    case nklib_syntax:parse(Data, Syntax) of
        {ok, Parsed, Unknown} ->
            Req3 = Req2#nkreq{data=Parsed},
            case SrvId:service_api_allow(Req3, State) of
                {true, State4} ->
                    process_api(Req3, Unknown, State4);
                {true, Req4, State4} ->
                    process_api(Req4, Unknown, State4);
                {false, State2} ->
                    ?DEBUG("request NOT allowed", [], Req3),
                    {error, unauthorized, State2}
            end;
        {error, Error} ->
            {error, Error, State}
    end.


%% @doc Process event sent from client
-spec event(req(), state()) ->
    {ok, state()} | {error, nkservice:error(), state()}.

event(Req, State) ->
    #nkreq{srv_id=SrvId, data=Data} = Req,
    ?DEBUG("parsing event ~p", [Data], Req),
    case nkevent_util:parse(Data#{srv_id=>SrvId}) of
        {ok, Event} ->
            Req2 = Req#nkreq{data=Event},
            case SrvId:service_api_allow(Req2, State) of
                {true, State3} ->
                    process_event(Event, Req2, State3);
                {true, Req3, State3} ->
                    process_event(Event, Req3, State3);
                {false, State2} ->
                    ?DEBUG("sending of event NOT authorized", [], Req2),
                    {error, unauthorized, State2}
            end;
        {error, Error} ->
            {error, Error, State}
    end.


%% ===================================================================
%% Private
%% ===================================================================

%% @private
process_api(Req, Unknown, State) ->
    #nkreq{srv_id=SrvId} = Req,
    ?DEBUG("request allowed", [], Req),
    case SrvId:service_api_cmd(Req, State) of
        {ok, Reply, State2} ->
            {ok, Reply, Unknown, State2};
        {login, Reply, UserId, Meta, State2} when UserId /= <<>> ->
            {login, Reply, UserId, Meta, Unknown, State2};
        {ack, State2} ->
            {ack, Unknown, State2};
        {error, Error, State2} ->
            {error, Error, State2}
    end.


%% @private
process_event(Event, Req, State) ->
    ?DEBUG("event allowed", [], Req),
    nkevent:send(Event),
    {ok, State}.
