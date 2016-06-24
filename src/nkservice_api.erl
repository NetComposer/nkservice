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
-export([launch/5, cmd/3]).
-export([syntax/1, defaults/1, mandatory/1]).

%% ===================================================================
%% Types
%% ===================================================================

-type class() :: atom().
-type cmd() :: atom().


%% ===================================================================
%% Public
%% ===================================================================

%% @doc This functions launches the processing of an external API request
%% It parses the request, and if it is valid, calls SrvId:api_cmd()
-spec launch(nkservice:id(), class(), cmd(), map()|list(), term()) ->
    {ok, term()} | ack | {error, nkservice:error_code()}.

launch(SrvId, Class, Cmd, Data, TId) ->
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
            SrvId:api_cmd(SrvId, Class, Cmd, Parsed, TId);
        {error, {syntax_error, Error}} ->
            {error, {syntax_error, Error}};
        {error, {missing_mandatory_field, Field}} ->
            {error, {missing_field, Field}}
    end.



%% ===================================================================
%% Commands
%% ===================================================================


%% @doc
-spec cmd(nkservice:id(), atom(), Data::map()) ->
    {ok, map()} | {error, nkservice:error_code()}.

cmd(_SrvId, register, Data) ->
    #{class:=Class, type:=Type, sub:=Sub, obj_id:=Id} = Data,
    Body = maps:get(body, Data, #{}),
    nkservice_events:reg(Class, Type, Sub, Id, Body),
    {ok, #{}};

cmd(_SrvId, unregister, Data) ->
    #{class:=Class, type:=Type, sub:=Sub, obj_id:=Id} = Data,
    nkservice_events:unreg(Class, Type, Sub, Id),
    {ok, #{}};

cmd(_SrvId, send_event, Data) ->
    #{class:=Class, type:=Type, sub:=Sub, obj_id:=Id} = Data,
    Body = maps:get(body, Data, #{}),
    case maps:get(broadcast, Data, false) of
        true ->
            nkservice_events:send_all(Class, Type, Sub, Id, Body),
            {ok, #{}};
        false ->
            case nkservice_events:send_single(Class, Type, Sub, Id, Body) of
                ok ->
                    {ok, #{}};
                not_found ->
                    {error, no_event_listener}
            end
    end;

cmd(_SrvId, _Other, _Data) ->
    {error, unknown_cmd}.



%% ===================================================================
%% Internal
%% ===================================================================


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


