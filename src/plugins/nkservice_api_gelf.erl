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

%% @doc GELF logging plugin for external API
-module(nkservice_api_gelf).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([plugin_deps/0, plugin_syntax/0, plugin_start/2, plugin_stop/2]).
-export([api_cmd/2]).

-include("../../include/nkservice.hrl").


%% ===================================================================
%% Plugin callbacks
%% ===================================================================


plugin_deps() ->
    [].


plugin_syntax() ->
    #{
        api_gelf_server => binary,
        api_gelf_port => {integer, 1, 65535}
    }.


plugin_start(Config, #{id:=Id, name:=Name}) ->
    case Config of
        #{api_gelf_server:=Server} ->
            lager:info("Plugin NkSERVICE GELF (~s) starting (~s)", 
                       [Name, Server]),
            Port = maps:get(api_gelf_port, Config, 12201),
            Opts = #{server=>Server, port=>Port},
            Args = [{nkservice_api_gelf, Id}, nklib_log_gelf, Opts],
            case nkservice_srv_user_sup:start_proc(Id, api_gelf, nklib_log, Args) of
                {ok, _} ->
                    {ok, Config};
                {error, Error} ->
                    {error, Error}
            end;
        _ ->
            {ok, Config}
    end.


plugin_stop(Config, #{id:=Id, name:=Name}) ->
    lager:info("Plugin NkSERVICE GELF (~s) stopping", [Name]),
    nklib_log:stop({nkservice_api_gelf, Id}),
    {ok, Config}.




%% ===================================================================
%% Implemented Callbacks
%% ===================================================================


api_cmd(#api_req{class = <<"core">>, subclass = <<"session">>, cmd = <<"log">>} =Req,
        _State) ->
    #api_req{srv_id=SrvId} = Req,
    case nklib_log:find({?MODULE, SrvId}) of
        {ok, Pid} ->
            Msg = get_log_msg(Req),
            ok = nklib_log:message(Pid, Msg),
            continue;
        not_found ->
            continue
    end;

api_cmd(_Req, _State) ->
    continue.




%% ===================================================================
%% Internal
%% ===================================================================


get_log_msg(#api_req{srv_id=SrvId, data=Data, user=User, session=Session}) ->
    #{source:=Source, message:=Short, level:=Level} = Data,
    Meta1 = maps:get(meta, Data, #{}),
    Meta2 = Meta1#{
        srv_id => SrvId,
        user => User,
        session_id => Session
    },
    Msg1 = #{
        host => Source,
        message => Short,
        level => Level,
        meta => Meta2
    },
    case maps:get(full_message, Data, <<>>) of
        <<>> -> Msg1;
        Full -> Msg1#{full_message=>Full}
    end.
