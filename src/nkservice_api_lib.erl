%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc Implementation of the NkService External Interface (server)
-module(nkservice_api_lib).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([process_req/2]).

-include("nkservice.hrl").

-type state() :: map().



%% @doc Starts the processing of an external API request
%% It parses the request, getting the syntax calling SrvId:api_syntax()
%% If it is valid, calls SrvId:api_allow() to authorized the request
%% If is is authorized, calls SrvId:api_cmd() to process the request.
%% It received some state (usually from api_server_cmd/5) that can be updated
-spec process_req(#api_req{}, state()) ->
    {ok, term(), state()} | {ack, state()} | {error, nkservice:error(), state()}.

process_req(Req, State) ->
    case set_atoms(Req) of
        #api_req{srv_id=SrvId, user=User, data=Data} = Req2 ->
            {Syntax, Defaults, Mandatory} = SrvId:api_server_syntax(Req2, #{}, #{}, []),
            Opts = #{
                return => map, 
                defaults => Defaults,
                mandatory => Mandatory
            },
            % lager:info("Syntax for ~p: ~p, ~p ~p", 
            %             [lager:pr(Req, ?MODULE), Syntax, Defaults, Mandatory]),
            case nklib_config:parse_config(Data, Syntax, Opts) of
                {ok, Parsed, Other} ->
                    case map_size(Other) of
                        0 -> ok;
                        _ -> send_unrecognized_fields(Req, maps:keys(Other))
                    end,
                    Req3 = Req2#api_req{data=Parsed},
                    case SrvId:api_server_allow(Req3, State) of
                        {true, State2} ->
                            % lager:notice("Calling ~p", [Req3]),
                            SrvId:api_server_cmd(Req3, State2);
                        {false, State2} ->
                            {error, unauthorized, State2}
                    end;
                {error, {syntax_error, Error}} ->
                    {error, {syntax_error, Error}, State};
                {error, {missing_mandatory_field, Field}} ->
                    {error, {missing_field, Field}, State}
            end;
        error ->
            lager:error("Atom not found"),
            {error, not_implemented, State}
    end.


%% @private
set_atoms(#api_req{class=Class, subclass=Sub, cmd=Cmd}=Req) ->
    try
        Req#api_req{
            class = nklib_util:to_existing_atom(Class),
            subclass = nklib_util:to_existing_atom(Sub),
            cmd = nklib_util:to_existing_atom(Cmd)
        }
    catch
        _:_ -> error
    end.



%% @private
send_unrecognized_fields(Req, Fields) ->
    #api_req{
        srv_id = SrvId, 
        class = Class, 
        subclass = Sub, 
        cmd = Cmd, 
        session_id = SessId
    } = Req,
    Event = #event{
        class = core,
        subclass = session_event,
        type = unrecognized_fields,
        srv_id = SrvId, 
        obj_id = SessId,
        body = #{class=>Class, subclass=>Sub, cmd=>Cmd, fields=>Fields}
    },
    nkservice_events:send(Event),
    lager:notice("NkSERVICE API: Unknown keys in service launch "
                 "~s:~s:~s: ~p", [Class, Sub, Cmd, Fields]).


