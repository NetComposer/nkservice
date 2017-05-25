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
-export([api/1]).

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



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts the processing of an external API request
%% It parses the request, getting the syntax calling SrvId:api_server_syntax()
%% If it is valid, calls SrvId:api_server_allow() to authorized the request
%% If is is authorized, calls SrvId:api_server_cmd() to process the request.
%% It received some state (usually from api_server_cmd/5) that can be updated
-spec api(req()) ->
    {ok, Reply::term(), req()} |
    {ack, req()} |
    {login, Reply::term(), req()} |
    {error, nkservice:error(), req()}.

api(#nkreq{cmd = <<"event">>}=Req) ->
    process_event(Req);

api(Req) ->
    #nkreq{srv_id=SrvId, data=Data} = Req,
    {Syntax, Req2} = SrvId:service_api_syntax(Req, #{}),
    ?DEBUG("parsing syntax ~p (~p)", [Data, Syntax], Req),
    case nklib_syntax:parse(Data, Syntax) of
        {ok, Parsed, Unknown} ->
            Req3 = Req2#nkreq{data=Parsed, unknown_fields=Unknown},
            case SrvId:service_api_allow(Req3) of
                {true, Req4} ->
                    process_api(Req4);
                {false, Req4} ->
                    ?DEBUG("request NOT allowed", [], Req4),
                    {error, unauthorized, Req4}
            end;
        {error, {syntax_error, Error}} ->
            {error, {syntax_error, Error}, Req2};
        {error, {missing_mandatory_field, Field}} ->
            {error, {missing_field, Field}, Req2};
        {error, Error} ->
            {error, Error, Req2}
    end.



%% ===================================================================
%% Private
%% ===================================================================

%% @private
process_api(Req) ->
    #nkreq{srv_id=SrvId} = Req,
    ?DEBUG("request allowed", [], Req),
    case SrvId:service_api_cmd(Req) of
        {ok, Reply, Req2} ->
            {ok, Reply, Req2};
        {login, Reply, UserId, Meta, Req2} when UserId /= <<>> ->
            Req3 = Req2#nkreq{user_id=UserId, user_meta=Meta},
            {login, Reply, Req3};
        {ack, Req2} ->
            {ack, Req2};
        {error, Error, Req2} ->
            {error, Error, Req2}
    end.


%% @doc Process event sent from client
-spec process_event(req()) ->
    {ok, req()} | {error, nkservice:error(), req()}.

process_event(Req) ->
    #nkreq{srv_id=SrvId, data=Data} = Req,
    ?DEBUG("parsing event ~p", [Data], Req),
    case nkevent_util:parse(Data#{srv_id=>SrvId}) of
        {ok, Event} ->
            Req2 = Req#nkreq{data=Event},
            case SrvId:service_api_allow(Req2) of
                {true, Req2} ->
                    ?DEBUG("event allowed", [], Req),
                    SrvId:service_api_event(Event, Req2);
                {false, Req2} ->
                    ?DEBUG("sending of event NOT authorized", [], Req),
                    {error, unauthorized, Req2}
            end;
        {error, Error} ->
            {error, Error, Req}
    end.
