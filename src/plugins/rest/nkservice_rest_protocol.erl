%% -------------------------------------------------------------------
%%
%% Copyright (c) 2018 Carlos Gonzalez Florido.  All Rights Reserved.
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
    lager:Type("NkSERVICE REST (~s:~s) (~s) "++Txt,
               [State#state.srv, State#state.plugin_id, State#state.remote|Args])).



%% ===================================================================
%% Types
%% ===================================================================

-type msg() :: {text, iolist()} | {binary, iolist()} | {json, iolist()}.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc Callbacks for protocol
transports(_) ->
    [http, https, ws, wss].


%% @doc Callbacks for protocol
default_port(http) -> 80;
default_port(https) -> 443;
default_port(ws) -> 80;
default_port(wss) -> 443.


%% @doc Send a command to the client and wait a response
-spec send(pid(), msg()) ->
    ok | {error, term()}.

send(Pid, Data) ->
    gen_server:call(Pid, {nkservice_rest_send, Data}).


%% @doc Send a command and don't wait for a response
-spec send_async(pid(), msg()) ->
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
    srv :: nkservice:id(),
    plugin_id :: nkservice_plugin:id(),
    remote :: binary(),
    user_state = #{} :: map()
}).


-spec conn_init(nkpacket:nkport()) ->
    {ok, #state{}}.

conn_init(NkPort) ->
    {ok, {nkservice_rest, SrvId, Id}} = nkpacket:get_class(NkPort),
    {ok, Remote} = nkpacket:get_remote_bin(NkPort),
    State1 = #state{srv=SrvId, plugin_id =Id, remote=Remote},
    set_debug(State1),
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
    call_rest_frame({text, Text}, NkPort, State);

conn_parse({binary, Bin}, NkPort, State) ->
    call_rest_frame({binary, Bin}, NkPort, State).


-spec conn_encode(term(), nkpacket:nkport()) ->
    {ok, nkpacket:outcoming()} | continue | {error, term()}.

conn_encode({text, Text}, _NkPort) ->
    {ok, {text, Text}};

conn_encode({binary, Bin}, _NkPort) ->
    {ok, {binary, Bin}};

conn_encode({json, Term}, _NkPort) ->
    case nklib_json:encode(Term) of
        error ->
            lager:warning("invalid json in ~p: ~p", [?MODULE, Term]),
            {error, invalid_json};
        Json ->
            {ok, {text, Json}}
    end.


-spec conn_handle_call(term(), {pid(), term()}, nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_call({nkservice_rest_send, Data}, From, NkPort, State) ->
    case do_send(Data, NkPort, State) of
        {ok, State2} ->
            gen_server:reply(From, ok),
            {ok, State2};
        {stop, Error, State2} ->
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
call_rest_frame(Frame, NkPort, #state{plugin_id =Id, srv=SrvId, user_state=UserState}=State) ->
    case apply(SrvId, nkservice_rest_frame, [Id, Frame, NkPort, UserState]) of
        {reply, {text, Text}, UserState2} ->
            do_send({text, Text}, NkPort, State#state{user_state=UserState2});
        {reply, {binary, Bin}, UserState2} ->
            do_send({binary, Bin}, NkPort, State#state{user_state=UserState2});
        {reply, {json, Term}, UserState2} ->
            Text = nklib_json:encode(Term),
            do_send({text, Text}, NkPort, State#state{user_state=UserState2});
        {ok, UserState2} ->
            {ok, State#state{user_state=UserState2}}
    end.


%% @private
set_debug(#state{srv=SrvId, plugin_id =Id}=State) ->
    Debug = nkservice_util:get_debug(SrvId, nkservice_rest, Id, ws) == true,
    put(nkservice_rest_debug, Debug),
    ?DEBUG("debug system activated", [], State).


%% @private
do_send(Msg, NkPort, State) ->
    case nkpacket_connection:send(NkPort, Msg) of
        ok ->
            {ok, State};
        Other ->
            ?DEBUG("connection send error: ~p", [Other], State),
            {stop, normal, State}
    end.


%% @private
handle(Fun, Args, #state{plugin_id =Id}=State) ->
    nklib_gen_server:handle_any(Fun, [Id|Args], State, #state.srv, #state.user_state).
