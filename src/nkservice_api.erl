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
-export([api/1, api/2, api/3, event/1, reply/1, add_unknown/2]).

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
-spec api(req()) ->
    {ok, Reply::term(), req()} |
    {ack, pid()|undefined, req()} |
    {error, nkservice:error(), req()}.

api(#nkreq{cmd = <<"event">>=Req}) ->
    #nkreq{srv_id=SrvId, data=Data} = Req,
    ?DEBUG("parsing event ~p", [Data], Req),
    case nkevent_util:parse(Data#{srv_id=>SrvId}) of
        {ok, Event} ->
            Req2 = Req#nkreq{data=Event},
            case nkservice_util:apply(SrvId, service_api_allow, [Req2]) of
                unknown_service ->
                    {error, unknown_service, Req};
                true ->
                    send_event(Event, Req2);
                {true, Req3} ->
                    send_event(Event, Req3);
                false ->
                    ?DEBUG("sending of event NOT authorized", [], Req2),
                    {error, unauthorized, Req}
            end;
        {error, Error} ->
            {error, Error, Req}
    end;

api(Req) ->
    #nkreq{srv_id=SrvId, data=Data} = Req,
    case nkservice_util:apply(SrvId, service_api_syntax, [#{}, Req]) of
        unknown_service ->
            ?LLOG(warning, "error calling API on unknown service '~s'", [SrvId], Req),
            {error, unknown_service, Req};
        {Syntax, Req2} ->
            ?DEBUG("parsing syntax ~p (~p)", [Data, Syntax], Req),
            case nklib_syntax:parse(Data, Syntax) of
                {ok, Parsed, Unknown} ->
                    Req3 = Req2#nkreq{data=Parsed},
                    Req4 = add_unknown(Unknown, Req3),
                    case SrvId:service_api_allow(Req4) of
                        true ->
                            process_api(Req4);
                        {true, Req5} ->
                            process_api(Req5);
                        false ->
                            ?DEBUG("request NOT allowed", [], Req4),
                            {error, unauthorized, Req}
                    end;
                {error, Error} ->
                    {error, Error, Req}
            end
    end.


%% @doc
api(Cmd, Req) ->
    api(Req#nkreq{cmd=Cmd}).


%% @doc
api(Cmd, Data, Req) ->
    api(Req#nkreq{cmd=Cmd, data=Data}).


%% @doc Called when we have received and event we were subscribed to
-spec event(req()) ->
    ok | {forward, req()}.

event(#nkreq{cmd = <<"event">>, srv_id=SrvId}=Req) ->
    case nkservice_util:apply(SrvId, service_api_event, [Req]) of
        unknown_service ->
            ok;
        ok ->
            ok;
        {forward, #nkreq{}=Req2} ->
            {forward, Req2}
    end.


%% @doc Sends a reply to a command (when you reply 'ack' in specs)
-spec reply(
               {ok, map(), req()} |
               {error, nkservice:error(), req()} |
               {ack, req()} |
               {ack, pid(), req()}
           ) ->
               ok | {error, term()}.

reply({_, #nkreq{session_module=Mod, session_pid=Pid}}=Reply) ->
    Mod:reply(Pid, Reply);

reply({_, _, #nkreq{session_module=Mod, session_pid=Pid}}=Reply) ->
    Mod:reply(Pid, Reply).



%% ===================================================================
%% Private
%% ===================================================================

%% @private
process_api(Req) ->
    #nkreq{srv_id=SrvId} = Req,
    ?DEBUG("request allowed", [], Req),
    case SrvId:service_api_cmd(Req) of
        ok ->
            {ok, #{}, Req};
        {ok, Reply} ->
            {ok, Reply, Req};
        {ok, Reply, #nkreq{}=Req2} ->
            {ok, Reply, Req2};
        ack ->
            {ack, undefined, Req};
        {ack, Pid} when is_pid(Pid) ->
            {ack, Pid, Req};
        {ack, Pid, #nkreq{}=Req2} ->
            {ack, Pid, Req2};
        {error, Error} ->
            {error, Error, Req};
        {error, Error, #nkreq{}=Req2} ->
            {error, Error, Req2}
    end.


%% @private
send_event(Event, Req) ->
    ?DEBUG("event allowed", [], Req),
    nkevent:send(Event),
    {ok, #{}, Req}.


%% @private
add_unknown(Fields, #nkreq{unknown_fields=[]}=Req) ->
    Req#nkreq{unknown_fields=Fields};

add_unknown(Fields, #nkreq{unknown_fields=Old}=Req) ->
    Req#nkreq{unknown_fields=lists:usort(Fields++Old)}.


