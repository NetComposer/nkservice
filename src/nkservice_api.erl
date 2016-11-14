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

%% @doc NkSERVICE external API

-module(nkservice_api).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export_type([class/0, cmd/0]).
-export([cmd/4]).
-export([parse_service/1]).

%% ===================================================================
%% Types
%% ===================================================================

-type class() :: atom().
-type subclass() :: atom().
-type cmd() :: atom().
-type state() :: map().

-include("nkservice.hrl").



%% ===================================================================
%% Commands
%% ===================================================================


%% @doc
-spec cmd(binary(), binary(), #api_req{}, state()) ->
    {ok, map(), state()} | {error, nkservice:error(), state()}.


cmd(user, login, #api_req{srv_id=SrvId, data=Data}, 
        #{session_type:=nkservice_api_server}=State) ->
    case SrvId:api_server_login(Data, State) of
        {true, User, Meta, State2} ->
            {login, User, Meta, State2};
        {false, Error, State2} ->
            timer:sleep(1000),
            {error, Error, State2}
    end;

cmd(core, event, #api_req{srv_id=SrvId, data=Data}, State) ->
    #{<<"class">>:=Class} = Data,
    Event = #event{
        srv_id = maps:get(<<"service">>, Data, SrvId),
        class = Class, 
        subclass = maps:get(<<"subclass">>, Data, <<"*">>),
        type = maps:get(<<"type">>, Data, <<"*">>),
        obj_id = maps:get(<<"obj_id">>, Data, <<"*">>)
    },
    Body = maps:get(<<"body">>, Data, #{}),
    {ok, State2} = SrvId:api_server_event(Event, Body, State),
    {ok, #{}, State2};

cmd(user, list, #api_req{srv_id=SrvId}, State) ->
    Data1 = lists:foldl(
        fun({User, SessId, _Pid}, Acc) ->
            Sessions = maps:get(User, Acc, []),
            maps:put(User, [SessId|Sessions], Acc)
        end,
        #{},
        nkservice_api_server:get_all(SrvId)),
    Data2 = case map_size(Data1) of
        0 -> [];
        _ -> Data1
    end,
    {ok, Data2, State};

cmd(user, get, #api_req{data=#{user:=User}}, State) ->
    Data = lists:foldl(
        fun({SessId, Meta, _Pid}, Acc) ->
            maps:put(SessId, Meta, Acc)
        end,
        #{},
        nkservice_api_server:find_user(User)),
    case map_size(Data) of
        0 -> 
            {error, user_not_found, State};
        _ ->
            {ok, Data, State}
    end;

cmd(event, subscribe, #api_req{srv_id=SrvId, data=Data},
        #{session_type:=nkservice_api_server}=State) ->
    #{class:=Class, subclass:=Sub, type:=Type, obj_id:=ObjId} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    Event = #event{
        class = Class, 
        subclass = Sub, 
        type = Type, 
        srv_id = EvSrvId, 
        obj_id = ObjId,
        body = maps:get(body, Data, #{})
    },
    % lager:warning("SUBS: ~p, ~p", [SrvId, Event]),
    nkservice_api_server:subscribe(self(), Event),
    {ok, #{}, State};

cmd(event, unsubscribe, #api_req{srv_id=SrvId, data=Data},
        #{session_type:=nkservice_api_server}=State) ->
    #{class:=Class, subclass:=Sub, type:=Type, obj_id:=ObjId} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    Event = #event{class=Class, subclass=Sub, type=Type, srv_id=EvSrvId, obj_id=ObjId},
    nkservice_api_server:unsubscribe(self(), Event),
    {ok, #{}, State};

%% Gets [#{class=>...}]
cmd(event, get_subscriptions, #api_req{tid=TId}, 
        #{session_type:=nkservice_api_server}=State) ->
    Self = self(),
    spawn_link(
        fun() ->
            Reply = nkservice_api_server:get_subscriptions(Self),
            nkservice_api_server:reply_ok(Self, TId, Reply)
        end),
    {ack, State};

cmd(event, send, #api_req{srv_id=SrvId, data=Data}, State) ->
    #{class:=Class, subclass:=Sub, type:=Type, obj_id:=ObjId} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    Event = #event{
        class = Class, 
        subclass = Sub, 
        type = Type, 
        srv_id = EvSrvId, 
        obj_id = ObjId,
        body = maps:get(body, Data, undefined)
    },
    nkservice_events:send(Event),
    {ok, #{}, State};

cmd(user, send_event, #api_req{srv_id=SrvId, data=Data}, State) ->
    #{type:=Type, user:=User} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    Event = #event{
        class = <<"core">>,
        subclass = <<"user_event">>,
        type = Type, 
        srv_id = EvSrvId, 
        obj_id = User,
        body = maps:get(body, Data, undefined)
    },
    nkservice_events:send(Event),
    {ok, #{}, State};

cmd(session, stop, #api_req{data=#{session_id:=SessId}},
        #{session_type:=nkservice_api_server}=State) ->
    case nkservice_api_server:find_session(SessId) of
        {ok, _User, Pid} ->
            nkservice_api_server:stop(Pid),
            {ok, #{}, State};
        not_found ->
            {error, session_not_found, State}
    end;

cmd(session, send_event, #api_req{srv_id=SrvId, data=Data}, State) ->
    #{type:=Type, session_id:=SessId} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    Event = #event{
        class = <<"core">>,
        subclass = <<"session_event">>,
        type = Type, 
        srv_id = EvSrvId, 
        obj_id = SessId,
        body = maps:get(body, Data, undefined)
    },
    nkservice_events:send(Event),
    {ok, #{}, State};

cmd(session, cmd, #api_req{data=Data, tid=TId}, State) ->
    #{session_id:=SessId, class:=Class, subclass:=Sub, cmd:=Cmd} = Data,
    case nkservice_api_server:find_session(SessId) of
        {ok, _User, Pid} ->
            CmdData = maps:get(data, Data, #{}),
            Self = self(),
            _ = spawn_link(
                fun() ->
                    case nkservice_api_server:cmd(Pid, Class, Sub, Cmd, CmdData) of
                        {ok, <<"ok">>, ResData} ->
                            nkservice_api_server:reply_ok(Self, TId, ResData);
                        {ok, <<"error">>, #{<<"code">>:=Code, <<"error">>:=Error}} ->
                            nkservice_api_server:reply_error(Self, TId, {Code, Error});
                        {ok, Res, _ResData} ->
                            Ref = nklib_util:uid(),
                            lager:error("Internal error ~s: Invalid reply: ~p", 
                                        [Ref, Res]),
                            nkservice_api_server:reply_error(Self, TId, 
                                                             {internal_error, Ref});
                        {error, Error} ->
                            nkservice_api_server:reply_error(Self, TId, Error)
                    end
                end),
            {ack, State};
        not_found ->
            {error, session_not_found, State}
    end;

cmd(session, log, #api_req{data=Data}, State) ->
    Txt = "API Session Log: ~p",
    case maps:get(level, Data, 6) of
        7 -> lager:debug(Txt, [Data]);
        6 -> lager:info(Txt, [Data]);
        5 -> lager:notice(Txt, [Data]);
        4 -> lager:warning(Txt, [Data]);
        _ -> lager:error(Txt, [Data])
    end,
    {ok, #{}, State};

cmd(test, async, #api_req{tid=TId, data=Data}, State) ->
    Self = self(),
    Data2 = maps:get(data, Data, #{}),
    spawn_link(
        fun() ->
            timer:sleep(2000),
            nkservice_api_server:reply_ok(Self, TId, Data2)
        end),
    {ack, State};

cmd(_Sub, Cmd, _Data, State) ->
    lager:error("Unknown command: ~p, ~p, ~p", [_Sub, Cmd, State]),
    {error, {unknown_command, Cmd}, State}.


%% ===================================================================
%% Internal
%% ===================================================================


%% @private
parse_service(Service) ->
    case nkservice_srv:get_srv_id(Service) of
        {ok, SrvId} -> 
            {ok, SrvId};
        not_found ->
            case catch binary_to_existing_atom(Service, utf8) of
                {'EXIT', _} -> 
                     {error, {syntax_error, <<"unknown service">>}};
                Atom ->
                    case nkservice_srv:get_srv_id(Atom) of
                        {ok, SrvId} -> 
                            {ok, SrvId};
                        not_found ->
                             {error, {syntax_error, <<"unknown service">>}}
                    end
            end
    end.

