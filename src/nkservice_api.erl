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
-export([launch/2]).
-export([cmd/4, syntax/5]).
-export([parse_service/1]).

%% ===================================================================
%% Types
%% ===================================================================

-type class() :: binary().
-type subclass() :: binary().
-type cmd() :: binary().
-type state() :: map().

-include("nkservice.hrl").


%% ===================================================================
%% Public
%% ===================================================================

%% @doc Starts the processing of an external API request
%% It parses the request, getting the syntax calling SrvId:api_syntax()
%% If it is valid, calls SrvId:api_allow() to authorized the request
%% If is is authorized, calls SrvId:api_cmd() to process the request.
%% It received some state (usually from api_server_cmd/5) that can be updated
-spec launch(#api_req{}, state()) ->
    {ok, term(), state()} | {ack, state()} | {error, nkservice:error(), state()}.

launch(#api_req{srv_id=SrvId, data=Data}=Req, State) ->
    {Syntax, Defaults, Mandatory} = SrvId:api_syntax(Req, #{}, #{}, []),
    Opts = #{
        return => map, 
        defaults => Defaults,
        mandatory => Mandatory
    },
    % lager:error("Syntax for ~p: ~p, ~p ~p", [Cmd, Syntax, Defaults, Mandatory]),
    case nklib_config:parse_config(Data, Syntax, Opts) of
        {ok, Parsed, Other} ->
            case maps:size(Other) of
                0 -> 
                    ok;
                _ -> 
                    #api_req{class=Class, subclass=Sub, cmd=Cmd} = Req,
                    lager:notice("NkSERVICE API: Unknown keys in service launch "
                                 "~s:~s:~s: ~p", [Class, Sub, Cmd, maps:keys(Other)])
            end,
            Req2 = Req#api_req{data=Parsed},
            case SrvId:api_allow(Req2, State) of
                {true, State2} ->
                    SrvId:api_cmd(Req2, State2);
                {false, State2} ->
                    {error, unauthorized, State2}
            end;
        {error, {syntax_error, Error}} ->
            {error, {syntax_error, Error}, State};
        {error, {missing_mandatory_field, Field}} ->
            {error, {missing_field, Field}, State}
    end.



%% ===================================================================
%% Commands
%% ===================================================================


%% @doc
-spec cmd(binary(), binary(), #api_req{}, state()) ->
    {ok, map(), state()} | {error, nkservice:error(), state()}.


%% Gets #{User::binary() => [SessId::binary()]}
cmd(<<"user">>, <<"list">>, #api_req{srv_id=SrvId}, State) ->
    Map = nkservice_api_server:list_users(SrvId, #{}),
    {ok, Map, State};


%% Gets #{SessId::binary() => UserData::term()}
cmd(<<"user">>, <<"get">>, #api_req{srv_id=SrvId, data=#{user:=User}}, State) ->
    Map = nkservice_api_server:get_user(SrvId, User, State, #{}),
    case maps:size(Map) of
        0 -> 
            {error, user_not_found, State};
        _ ->
            {ok, Map, State}
    end;

cmd(<<"event">>, <<"subscribe">>, #api_req{srv_id=SrvId, data=Data}, State) ->
    #{class:=Class, subclass:=Sub, type:=Type, obj_id:=ObjId} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    RegId = #reg_id{class=Class, subclass=Sub, type=Type, srv_id=EvSrvId, obj_id=ObjId},
    % lager:warning("SUBS: ~p, ~p", [SrvId, RegId]),
    case SrvId:api_subscribe_allow(EvSrvId, Class, Sub, Type, State) of
        {true, State2} ->
            Body = maps:get(body, Data, #{}),
            nkservice_api_server:register_events(self(), RegId, Body),
            {ok, #{}, State2};
        {false, State2} ->
            {error, unauthorized, State2}
    end;

cmd(<<"event">>, <<"unsubscribe">>, #api_req{srv_id=SrvId, data=Data}, State) ->
    #{class:=Class, subclass:=Sub, type:=Type, obj_id:=ObjId} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    RegId = #reg_id{class=Class, subclass=Sub, type=Type, srv_id=EvSrvId, obj_id=ObjId},
    nkservice_api_server:unregister_events(self(), RegId),
    {ok, #{}, State};

%% Gets [#{class=>...}]
cmd(<<"event">>, <<"get_subscriptions">>, #api_req{tid=TId}, State) ->
    ok = nkservice_api_server:get_subscriptions(TId, State),
    {ack, State};

cmd(<<"event">>, <<"send">>, #api_req{srv_id=SrvId, data=Data}, State) ->

    #{class:=Class, subclass:=Sub, type:=Type, obj_id:=ObjId} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    RegId = #reg_id{class=Class, subclass=Sub, type=Type, srv_id=EvSrvId, obj_id=ObjId},
    Body = maps:get(body, Data, #{}),
    nkservice_events:send(RegId, Body),
    {ok, #{}, State};

cmd(<<"user">>, <<"send_event">>, #api_req{srv_id=SrvId, data=Data}, State) ->
    #{type:=Type, user:=User} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    RegId = #reg_id{
        class = <<"core">>,
        subclass = <<"user_event">>,
        type = Type, 
        srv_id = EvSrvId, 
        obj_id = User
    },
    Body = maps:get(body, Data, #{}),
    nkservice_events:send(RegId, Body),
    {ok, #{}, State};

cmd(<<"session">>, <<"stop">>, #api_req{data=#{session_id:=SessId}}, State) ->
    case nkservice_api_server:find_session(SessId) of
        {ok, User, Pid} ->
            nkservice_api_server:stop(Pid),
            {ok, #{user=>User}, State};
        not_found ->
            {error, session_not_found, State}
    end;

cmd(<<"session">>, <<"send_event">>, #api_req{srv_id=SrvId, data=Data}, State) ->
    #{type:=Type, session_id:=SessId} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    RegId = #reg_id{
        class = <<"core">>,
        subclass = <<"session_event">>,
        type = Type, 
        srv_id = EvSrvId, 
        obj_id = SessId
    },
    Body = maps:get(body, Data, #{}),
    nkservice_events:send(RegId, Body),
    {ok, #{}, State};

cmd(<<"session">>, <<"cmd">>, #api_req{data=Data, tid=TId}, State) ->
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
                        {ok, _Res, _ResData} ->
                            lager:error("Invalid reply: ~p", [_Res]),
                            nkservice_api_server:reply_error(Self, TId, operation_error);
                        {error, Error} ->
                            nkservice_api_server:reply_error(Self, TId, Error)
                    end
                end),
            {ack, State};
        not_found ->
            {error, session_not_found, State}
    end;

cmd(<<"session">>, <<"log">>, Req, State) ->
    Msg = get_log_msg(Req),
    lager:info("Ext API Session Log: ~p", [Msg]),
    {ok, #{}, State};

cmd(_Sub, _Cmd, _Data, State) ->
    {error, unknown_command, State}.


%% ===================================================================
%% Syntax
%% ===================================================================


%% @private
syntax(<<"user">>, <<"get">>, Syntax, Defaults, Mandatory) ->
    {Syntax#{user=>binary}, Defaults, [user|Mandatory]};

syntax(<<"event">>, <<"subscribe">>, Syntax, Defaults, Mandatory) ->
    {S, D, M} = syntax_events(Syntax, Defaults, Mandatory),
    {S#{body => any}, D, M};

syntax(<<"event">>, <<"unsubscribe">>, Syntax, Defaults, Mandatory) ->
    syntax_events(Syntax, Defaults, Mandatory);
  
syntax(<<"event">>, <<"send">>, Syntax, Defaults, Mandatory) ->
    {S, D, M} = syntax_events(Syntax, Defaults, Mandatory),
    {S#{body => any}, D, M};

syntax(<<"user">>, <<"send_event">>, Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            user => binary,
            type => binary,
            body => any
        },
        Defaults#{
            type => <<"*">>
        },
        [user|Mandatory]
    };

syntax(<<"session">>, <<"stop">>, Syntax, Defaults, Mandatory) ->
    {Syntax#{session_id=>binary}, Defaults, [session_id|Mandatory]};

syntax(<<"session">>, <<"send_event">>, Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            session_id => binary,
            type => binary,
            body => any
        },
        Defaults#{
            type => <<"*">>
        },
        [session_id|Mandatory]
    };

syntax(<<"session">>, <<"cmd">>, Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            session_id => binary,
            class => binary,
            subclass => binary,
            cmd => binary,
            data => any
        },
        Defaults#{subclass => <<"core">>},
        [session_id, class, cmd|Mandatory]
    };

syntax(<<"session">>, <<"log">>, Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            source => binary,
            message => binary,
            full_message => binary,
            level => {integer, 1, 7},
            meta => any
        },
        Defaults#{level=>1},
        [source, message|Mandatory]
    };

syntax(_Sub, _Cmd, Syntax, Defaults, Mandatory) ->
    {Syntax, Defaults, Mandatory}.


%% @private
syntax_events(Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            class => binary,
            subclass => binary,
            type => binary,
            obj_id => binary,
            service => fun ?MODULE:parse_service/1
        },
        Defaults#{
            subclass => <<"*">>,
            type => <<"*">>,
            obj_id => <<"*">>
        },
        [class|Mandatory]
    }.






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


%% @private
get_log_msg(#api_req{srv_id=SrvId, data=Data, user=User, session=Session}) ->
    #{source:=Source, message:=Short, level:=Level} = Data,
    Msg = [
        {version, <<"1.1">>},
        {host, Source},
        {message, Short},
        {level, Level},
        {<<"_srv_id">>, SrvId},
        {<<"_user">>, User},
        {<<"_session_id">>, Session},
        case maps:get(full_message, Data, <<>>) of
            <<>> -> [];
            Full -> [{full_message, Full}]
        end
        |
        case maps:get(meta, Data, #{}) of
            Meta when is_map(Meta) ->
                [{<<$_, Key/binary>>, Val} || {Key, Val}<- maps:to_list(Meta)];
            _ ->
                []
        end
    ],
    maps:from_list(lists:flatten(Msg)).


