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

%% @doc
-module(nkservice_rest_protocol).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([transports/1, default_port/1]).
-export([send/2, send_async/2, stop/1]).
-export([conn_init/1, conn_encode/2, conn_parse/3, conn_handle_call/4,
         conn_handle_cast/3, conn_handle_info/3, conn_stop/3]).
-export([http_init/4]).

-define(DEBUG(Txt, Args, State),
    case erlang:get(nkservice_rest_debug) of
        true -> ?LLOG(debug, Txt, Args, State);
        _ -> ok
    end).

-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE REST (~s) "++Txt, [State#state.remote|Args])).



%% ===================================================================
%% Types
%% ===================================================================



%% ===================================================================
%% Public
%% ===================================================================

transports(_) ->
    [http, https, ws, wss].


default_port(http) -> 80;
default_port(https) -> 443;
default_port(ws) -> 80;
default_port(wss) -> 443.




%% @doc Send a command to the client and wait a response
-spec send(pid(), binary()) ->
    ok | {error, term()}.

send(Pid, Data) ->
    gen_server:call(Pid, {nkservice_rest_send, Data}).


%% @doc Send a command and don't wait for a response
-spec send_async(pid(), binary()) ->
    ok | {error, term()}.

send_async(Pid, Data) ->
    gen_server:cast(Pid, {nkservice_rest_send, Data}).


%% @doc
stop(Pid) ->
    gen_server:cast(Pid, nkservice_rest_stop).


%% ===================================================================
%% WS Protocol callbacks
%% ===================================================================

-record(state, {
    srv_id :: nkservice:id(),
    id :: nkservice_rest:id(),
    remote :: binary(),
    user_state = #{} :: map()
}).


-spec conn_init(nkpacket:nkport()) ->
    {ok, #state{}}.

conn_init(NkPort) ->
    {ok, {nkservice_rest, SrvId, Id}} = nkpacket:get_class(NkPort),
    {ok, Remote} = nkpacket:get_remote_bin(NkPort),
    State1 = #state{srv_id=SrvId, id=Id, remote=Remote},
    set_log(SrvId),
    %% nkservice_util:register_for_changes(SrvId),
    ?LLOG(info, "new connection (~s, ~p)", [Remote, self()], State1),
    {ok, State2} = handle(nkservice_rest_init, [NkPort], State1),
    {ok, State2}.


%% @private
-spec conn_parse(term()|close, nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, term(), #state{}}.

conn_parse(close, _NkPort, State) ->
    {ok, State};

conn_parse({text, Text}, NkPort, State) ->
    {ok, State2} = handle(nkservice_rest_text, [Text, NkPort], State),
    {ok, State2}.


-spec conn_encode(term(), nkpacket:nkport()) ->
    {ok, nkpacket:outcoming()} | continue | {error, term()}.

conn_encode(Msg, _NkPort) when is_map(Msg); is_list(Msg) ->
    case nklib_json:encode(Msg) of
        error ->
            lager:warning("invalid json in ~p: ~p", [?MODULE, Msg]),
            {error, invalid_json};
        Json ->
            {ok, {text, Json}}
    end;

conn_encode(Msg, _NkPort) when is_binary(Msg) ->
    {ok, {text, Msg}}.


-spec conn_handle_call(term(), {pid(), term()}, nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_call({nkservice_rest_send, Data}, From, NkPort, State) ->
    case do_send(Data, NkPort, State) of
        {ok, State2} ->
            gen_server:reply(From, ok),
            {ok, State2};
        {error, Error, State2} ->
            {error, Error, State2}
    end;

conn_handle_call(Msg, From, _NkPort, State) ->
    handle(nkservice_rest_handle_call, [Msg, From], State).


-spec conn_handle_cast(term(), nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_cast({nkservice_rest_send, Data}, NkPort, State) ->
    do_send(Data, NkPort, State);

conn_handle_cast(nkservice_rest_stop, _NkPort, State) ->
    {stop, normal, State};

conn_handle_cast(Msg, _NkPort, State) ->
    handle(nkservice_rest_handle_cast, [Msg], State).


-spec conn_handle_info(term(), nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_info(Info, _NkPort, State) ->
    handle(nkservice_rest_handle_info, [Info], State).


%% @doc Called when the connection stops
-spec conn_stop(Reason::term(), nkpacket:nkport(), #state{}) ->
    ok.

conn_stop(Reason, _NkPort, State) ->
    catch handle(nkservice_rest_terminate, [Reason], State).


%% ===================================================================
%% HTTP Protocol callbacks
%% ===================================================================

%% For HTTP based connections, http_init is called
%% See nkpacket_protocol

http_init(Paths, Req, Env, NkPort) ->
    nkservice_rest_http:init(Paths, Req, Env, NkPort).



%% ===================================================================
%% Requests
%% ===================================================================

%% @private
set_log(SrvId) ->
    Debug = case nkservice_util:get_debug_info(SrvId, nkservice_rest) of
        {true, _} -> true;
        _ -> false
    end,
    put(nkservice_rest_debug, Debug).


%% @private
do_send(Msg, NkPort, State) ->
    case catch do_send(Msg, NkPort) of
        ok ->
            {ok, State};
        _ ->
            {stop, normal, State}
    end.


%% @private
do_send(Msg, NkPort) ->
    nkpacket_connection:send(NkPort, Msg).


%% @private
handle(Fun, Args, #state{id=Id}=State) ->
    nklib_gen_server:handle_any(Fun, [Id|Args], State, #state.srv_id, #state.user_state).
