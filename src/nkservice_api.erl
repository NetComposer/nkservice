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
-export([launch/8]).
-export([cmd/4, syntax/4]).
-export([parse_service/1]).

%% ===================================================================
%% Types
%% ===================================================================

-type class() :: atom().
-type cmd() :: atom().
-type state() :: map().

-include("nkservice.hrl").


%% ===================================================================
%% Public
%% ===================================================================

%% @doc Starts the processing of an external API request
%% It parses the request, getting the syntax calling SrvId:api_cmd_syntax()
%% If it is valid, calls SrvId:api_allow() to authorized the request
%% If is is authorized, calls SrvId:api_cmd() to process the request.
%% It received some state (usually from api_server_cmd/5) that can be updated
-spec launch(nkservice:id(), binary(), binary(), class(), cmd(), map()|list(), 
             term(), state()) ->
    {ok, term(), state()} | {ack, state()} | {error, nkservice:error(), state()}.

launch(SrvId, User, SessId, Class, Cmd, Data, TId, State) ->
    {Syntax, Defaults, Mandatory} = 
        SrvId:api_cmd_syntax(Class, Cmd, Data, #{}, #{}, []),
    Opts = #{
        return => map, 
        defaults => Defaults,
        mandatory => Mandatory
    },
    % lager:error("Syntax for ~p: ~p, ~p ~p", [Cmd, Syntax, Defaults, Mandatory]),
    case nklib_config:parse_config(Data, Syntax, Opts) of
        {ok, Parsed, _} ->
            case SrvId:api_allow(SrvId, User, Class, Cmd, Parsed, State) of
                {true, State2} ->
                    SrvId:api_cmd(SrvId, User, SessId, Class, Cmd, Parsed, TId, State2);
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
-spec cmd(nkservice:id(), atom(), Data::map(), state()) ->
    {ok, map()} | {error, nkservice:error()}.

cmd(SrvId, subscribe, Data, State) ->
    #{class:=Class, subclass:=Sub, type:=Type, obj_id:=ObjId} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    RegId = #reg_id{class=Class, subclass=Sub, type=Type, srv_id=EvSrvId, obj_id=ObjId},
    lager:warning("SUBS: ~p, ~p", [SrvId, RegId]),
    case SrvId:api_subscribe_allow(SrvId, RegId, State) of
        true ->
            Body = maps:get(body, Data, #{}),
            nkservice_api_server:register(self(), RegId, Body),
            {ok, #{}, State};
        false ->
            {error, unauthorized, State}
    end;

cmd(SrvId, unsubscribe, Data, State) ->
    #{class:=Class, subclass:=Sub, type:=Type, obj_id:=ObjId} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    RegId = #reg_id{class=Class, subclass=Sub, type=Type, srv_id=EvSrvId, obj_id=ObjId},
    nkservice_api_server:unregister(self(), RegId),
    {ok, #{}, State};

cmd(SrvId, send_event, Data, State) ->
    #{class:=Class, subclass:=Sub, type:=Type, obj_id:=ObjId} = Data,
    EvSrvId = maps:get(service, Data, SrvId),
    RegId = #reg_id{class=Class, subclass=Sub, type=Type, srv_id=EvSrvId, obj_id=ObjId},
    Body = maps:get(body, Data, #{}),
    case maps:get(broadcast, Data, false) of
        true ->
            nkservice_events:send_all(RegId, Body),
            {ok, #{}, State};
        false ->
            case nkservice_events:send_single(RegId, Body) of
                ok ->
                    {ok, #{}, State};
                not_found ->
                    {error, no_event_listener, State}
            end
    end;

cmd(_SrvId, _Other, _Data, State) ->
    {error, unknown_command, State}.


%% @private
syntax(send_event, Syntax, Defaults, Mandatory) ->
    {S, D, M} = syntax(unsubscribe, Syntax, Defaults, Mandatory),
    {S#{broadcast => boolean, body => any}, D, M};

syntax(subscribe, Syntax, Defaults, Mandatory) ->
    {S, D, M} = syntax(unsubscribe, Syntax, Defaults, Mandatory),
    {S#{body => any}, D, M};

syntax(unsubscribe, Syntax, Defaults, Mandatory) ->
    syntax_events(Syntax, Defaults, Mandatory);
  
syntax(_, Syntax, Defaults, Mandatory) ->
    {Syntax, Defaults, Mandatory}.


%% @private
syntax_events(Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            class => [atom, binary],
            subclass => [atom, binary],
            type => [atom, binary],
            obj_id => [{enum, ['*']}, binary],
            service => fun ?MODULE:parse_service/1
        },
        Defaults#{
            subclass => '*',
            type => '*',
            obj_id => '*'
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


