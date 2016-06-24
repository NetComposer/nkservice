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
-export([launch/6, cmd/4]).
-export([syntax/1, defaults/1, mandatory/1]).

%% ===================================================================
%% Types
%% ===================================================================

-type class() :: atom().
-type cmd() :: atom().

-type state() ::
    #{
    }.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc This functions launches the processing of an external API request
-spec launch(nkservice:id(), class(), cmd(), map()|list(), term(), term()) ->
    {ok, term()} | {error, term()} | {syntax, binary()}.

launch(SrvId, Class, Cmd, Data, TId, State) ->
    Opts = #{
        return => map, 
        defaults => SrvId:api_cmd_defaults(Class, Cmd, Data),
        mandatory => SrvId:api_cmd_mandatory(Class, Cmd, Data)
    },
    Syntax = SrvId:api_cmd_syntax(Class, Cmd, Data),
    case nklib_config:parse_config(Data, Syntax, Opts) of
        {ok, Parsed, _} ->
            SrvId:api_cmd(SrvId, Class, Cmd, Parsed, TId, State);
        {error, {syntax_error, Error}} ->
            {syntax, Error};
        {error, Error} ->
            error(Error)
    end.




%% ===================================================================
%% Commands
%% ===================================================================


%% @doc
-spec cmd(nkservice:id(), atom(), Data::map(), state()) ->
    {ok, map(), state()} | {error, nkservice:error_code(), state()}.

cmd(_SrvId, register, Data, State) ->
    #{class:=Class, type:=Type, sub:=Sub, id:=Id} = Data,
    Body = maps:get(body, Data, #{}),
    nkservice_events:reg(Class, Type, Sub, Id, Body),
    {ok, #{}, State};

cmd(_SrvId, unregister, Data, State) ->
    #{class:=Class, type:=Type, sub:=Sub, id:=Id} = Data,
    nkservice_events:unreg(Class, Type, Sub, Id),
    {ok, #{}, State};

cmd(_SrvId, send_event, Data, State) ->
    #{class:=Class, type:=Type, sub:=Sub, id:=Id} = Data,
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



%% ===================================================================
%% Internal
%% ===================================================================


%% @private
syntax(send_event) ->
    #{
        class => atom,
        type => atom,
        sub => atom,
        id => binary,
        broadcast => boolean,
        body => any
    };

syntax(register) ->
    #{
        class => atom,
        type => atom,
        sub => atom,
        id => binary,
        body => any
    };

syntax(unregister) ->
    #{
        class => atom,
        type => atom,
        sub => atom,
        id => binary
    }.

%% @private
defaults(register) ->
    #{
        type => '*',
        sub => '*',
        id => '*'
    };

defaults(unregister) ->
    #{
        type => '*',
        sub => '*',
        id => '*'
    };

defaults(_) ->
    #{}.


%% @private
mandatory(send_event) ->
    [class, type, sub, id];

mandatory(register) ->
    [class].


