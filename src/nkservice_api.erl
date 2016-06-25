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
-export([launch/8, handle_down/4]).
-export([cmd/4, syntax/1, defaults/1, mandatory/1]).

%% ===================================================================
%% Types
%% ===================================================================

-type class() :: atom().
-type cmd() :: atom().
-type state() :: map().



%% ===================================================================
%% Public
%% ===================================================================

%% @doc This functions launches the processing of an external API request
%% It parses the request, and if it is valid, calls SrvId:api_cmd()
%% It received some state (usually from api_server) that can be updated
-spec launch(nkservice:id(), binary(), binary(), class(), cmd(), map()|list(), 
             term(), state()) ->
    {ok, term(), state()} | {ack, state()} | {error, nkservice:error_code(), state()}.

launch(SrvId, User, SessId, Class, Cmd, Data, TId, State) ->
    {ok, Syntax} = SrvId:api_cmd_syntax(Class, Cmd, Data),
    {ok, Defaults} = SrvId:api_cmd_defaults(Class, Cmd, Data),
    {ok, Mandatory} = SrvId:api_cmd_mandatory(Class, Cmd, Data), 
    Opts = #{
        return => map, 
        defaults => Defaults,
        mandatory => Mandatory
    },
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


%% @doc Called when the connection receives a down, it can be one of 
%% our monitored event servers
-spec handle_down(reference(), pid(), term(), state()) ->
    {ok, state()}.

handle_down(Mon, _Pid, _Reason, State) ->
    Regs = get_regs(State),
    case lists:keytake(Mon, 2, Regs) of
        {value, {{Class, Type, Sub, Id}, Mon}, Regs2} ->
            %% TODO: retry reg or send event to client
            lager:warning("Registration failed for ~p:~p:~p:~p", [Class, Type, Sub, Id]);
        false ->
            Regs2 = Regs
    end,
    {ok, set_regs(Regs2, State)}.



%% ===================================================================
%% Commands
%% ===================================================================


%% @doc
-spec cmd(nkservice:id(), atom(), Data::map(), state()) ->
    {ok, map()} | {error, nkservice:error_code()}.

%% @TODO: must monitor listener proc

cmd(_SrvId, register, Data, State) ->
    #{class:=Class, type:=Type, sub:=Sub, obj_id:=Id} = Data,
    Body = maps:get(body, Data, #{}),
    {ok, Pid} = nkservice_events:reg(Class, Type, Sub, Id, Body),
    Mon = monitor(process, Pid),
    Regs2 = [{{Class, Type, Sub, Id}, Mon}|get_regs(State)],
    {ok, #{}, set_regs(Regs2, State)};

cmd(_SrvId, unregister, Data, State) ->
    #{class:=Class, type:=Type, sub:=Sub, obj_id:=Id} = Data,
    nkservice_events:unreg(Class, Type, Sub, Id),
    Regs = get_regs(State),
    case lists:keytake({Class, Type, Sub, Id}, 1, Regs) of
        {value, {_, Mon}, Regs2} ->
            demonitor(Mon);
        false ->
            Regs2 = Regs
    end,
    {ok, #{}, set_regs(Regs2, State)};

cmd(_SrvId, send_event, Data, State) ->
    #{class:=Class, type:=Type, sub:=Sub, obj_id:=Id} = Data,
    Body = maps:get(body, Data, #{}),
    case maps:get(broadcast, Data, false) of
        true ->
            nkservice_events:send_all(Class, Type, Sub, Id, Body),
            {ok, #{}, State};
        false ->
            case nkservice_events:send_single(Class, Type, Sub, Id, Body) of
                ok ->
                    {ok, #{}, State};
                not_found ->
                    {error, no_event_listener, State}
            end
    end;

cmd(_SrvId, _Other, _Data, State) ->
    {error, unknown_cmd, State}.


%% @private
syntax(send_event) ->
    #{
        class => atom,
        type => atom,
        sub => atom,
        obj_id => binary,
        broadcast => boolean,
        body => any
    };

syntax(register) ->
    #{
        class => atom,
        type => atom,
        sub => atom,
        obj_id => binary,
        body => any
    };

syntax(unregister) ->
    #{
        class => atom,
        type => atom,
        sub => atom,
        obj_id => binary
    };

syntax(_) ->
    #{}.


%% @private
defaults(register) ->
    #{
        type => '*',
        sub => '*',
        obj_id => '*'
    };

defaults(unregister) ->
    defaults(register);

defaults(_) ->
    #{}.


%% @private
mandatory(send_event) ->
    [class, type, sub, obj_id];

mandatory(register) ->
    [class];

mandatory(unregister) ->
    mandatory(register);

mandatory(_) ->
    [].


%% ===================================================================
%% Internal
%% ===================================================================


%% @private
get_regs(State) ->
    ApiData = maps:get(?MODULE, State, #{}),
    maps:get(regs, ApiData, []).


%% @private
set_regs(Regs, State) ->
    ApiData1 = maps:get(?MODULE, State, #{}),
    ApiData2 = ApiData1#{regs=>Regs},
    State#{?MODULE=>ApiData2}.


