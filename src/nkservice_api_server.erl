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
-module(nkservice_api_server).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([cmd/4, cmd_async/4, reply_ok/3, reply_error/3, reply_ack/2]).
-export([stop/1, start_ping/2, stop_ping/1]).
-export([find_user/1, find_sess_id/1]).
-export([transports/1, default_port/1]).
-export([conn_init/1, conn_encode/2, conn_parse/3, conn_handle_call/4, 
         conn_handle_cast/3, conn_handle_info/3, conn_stop/3]).
-export([get_all/0, print/3]).


-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkMEDIA Admin Server (~s) "++Txt, [State#state.user | Args])).

-define(PRINT(Txt, Args, State), 
        print(Txt, Args, State),    % Uncomment this for detailed logs
        ok).


-define(OP_TIME, 5).            % Maximum operation time (without ACK)
-define(ACK_TIME, 180).         % Maximum operation time (with ACK)
-define(CALL_TIMEOUT, 180).     % Maximum sync call time




%% ===================================================================
%% Types
%% ===================================================================


-type user_state() :: map().


%% ===================================================================
%% Public
%% ===================================================================

%% @doc
cmd(Pid, Class, Cmd, Data) ->
    do_call(Pid, {nkservice_cmd, Class, Cmd, Data}).

%% @doc
cmd_async(Pid, Class, Cmd, Data) ->
    gen_server:cast(Pid, {nkservice_cmd, Class, Cmd, Data}).


%% @doc
reply_ok(Pid, TId, Data) ->
    gen_server:cast(Pid, {reply_ok, TId, Data}).


%% @doc
reply_error(Pid, TId, Code) ->
    gen_server:cast(Pid, {reply_error, TId, Code}).


%% @doc Send to extend the timeout for the transaction 
reply_ack(Pid, TId) ->
    gen_server:cast(Pid, {reply_ack, TId}).


%% @doc Stops the server
stop(Pid) ->
    gen_server:cast(Pid, nkservice_stop).


%% @doc 
start_ping(Pid, Time) ->
    gen_server:cast(Pid, {nkservice_start_ping, Time}).


%% @doc 
stop_ping(Pid) ->
    gen_server:cast(Pid, nkservice_stop_ping).


%% @private
-spec get_all() ->
    [{User::binary(), SessId::binary(), pid()}].

get_all() ->
    [{User, SessId, Pid} || {{User, SessId}, Pid} <- nklib_proc:values(?MODULE)].


-spec find_user(string()|binary()) ->
    [{SessId::binary(), pid()}].

find_user(User) ->
    User2 = nklib_util:to_binary(User),
    nklib_proc:values({?MODULE, user, User2}).


-spec find_sess_id(binary()) ->
    {ok, User::binary(), pid()} | not_found.

find_sess_id(SessId) ->
    case nklib_proc:values({?MODULE, session, SessId}) of
        [{User, Pid}] -> {ok, User, Pid};
        [] -> not_found
    end.



%% ===================================================================
%% Protocol callbacks
%% ===================================================================

-type tid() :: integer().

-record(trans, {
    op :: term(),
    timer :: reference(),
    from :: {pid(), term()} | {async, pid(), term()}
}).

-record(state, {
    srv_id :: nkservice:id(),
    user = <<>> :: binary(),
    trans :: #{tid() => #trans{}},
    tid :: integer(),
    ping :: integer() | undefined,
    user_state :: user_state()
}).


%% @private
-spec transports(nklib:scheme()) ->
    [nkpacket:transport()].

transports(_) -> [wss, tls, ws, tcp].

-spec default_port(nkpacket:transport()) ->
    inet:port_number() | invalid.

default_port(ws) -> 9010;
default_port(wss) -> 9011;
default_port(tcp) -> 9010;
default_port(tls) -> 9011.


-spec conn_init(nkpacket:nkport()) ->
    {ok, #state{}}.

conn_init(NkPort) ->
    {ok, {nkservice_api_server, SrvId}, _} = nkpacket:get_user(NkPort),
    {ok, Remote} = nkpacket:get_remote_bin(NkPort),
    UserState = #{srv_id=>SrvId, remote=>Remote},
    State1 = #state{
        srv_id = SrvId,
        trans = #{}, 
        tid = erlang:phash2(self()),
        user_state = UserState

    },
    nklib_proc:put(?MODULE, <<>>),
    ?LLOG(info, "new connection (~s, ~p)", [Remote, self()], State1),
    {ok, State2} = handle(api_server_init, [NkPort], State1),
    {ok, State2}.


%% @private
-spec conn_parse(term()|close, nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, term(), #state{}}.

conn_parse(close, _NkPort, State) ->
    {ok, State};

conn_parse({text, Text}, NkPort, State) ->
    Msg = case nklib_json:decode(Text) of
        error ->
            ?LLOG(warning, "JSON decode error: ~p", [Text], State),
            error(json_decode);
        Json ->
            Json
    end,
    ?PRINT("received ~s", [Msg], State),
    case Msg of
        #{<<"class">> := Class, <<"cmd">> := Cmd, <<"tid">> := TId} ->
            case catch binary_to_existing_atom(Class, latin1) of
                {'EXIT', _} ->
                    send_reply_error(unknown_class, TId, NkPort, State);
                Class2 ->
                    case catch binary_to_existing_atom(Cmd, latin1) of
                        {'EXIT', _} ->
                            send_reply_error(unknown_cmd, TId, NkPort, State);
                        Cmd2 ->
                            Data = maps:get(<<"data">>, Msg, #{}),
                            process_client_req(Class2, Cmd2, Data, TId, NkPort, State)
                    end
            end;
        #{<<"result">> := Result, <<"tid">> := TId} ->
            case extract_op(TId, State) of
                {Trans, State2} ->
                    Data = maps:get(<<"data">>, Msg, #{}),
                    process_client_resp(Result, Data, Trans, NkPort, State2);
                not_found ->
                    ?LLOG(warning, "received client response for unknown req: ~p", 
                          [Msg], State),
                    {ok, State}
            end;
        #{<<"ack">> := TId} ->
            lager:error("ACK!"),
            case extract_op(TId, State) of
                {Trans, State2} ->
                    {ok, extend_op(TId, Trans, State2)};
                not_found ->
                    ?LLOG(warning, "received client response for unknown req: ~p", 
                          [Msg], State),
                    {ok, State}
            end;
        _ ->
            ?LLOG(warning, "received unrecognized msg: ~p", [Msg], State),
            {stop, normal, State}
    end.


-spec conn_encode(term(), nkpacket:nkport()) ->
    {ok, nkpacket:outcoming()} | continue | {error, term()}.

conn_encode(Msg, _NkPort) when is_map(Msg) ->
    Json = nklib_json:encode(Msg),
    {ok, {text, Json}};

conn_encode(Msg, _NkPort) when is_binary(Msg) ->
    {ok, {text, Msg}}.


-spec conn_handle_call(term(), {pid(), term()}, nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_call({nkservice_cmd, Class, Cmd, Data}, From, NkPort, State) ->
    send_request(Class, Cmd, Data, From, NkPort, State);

conn_handle_call(Msg, From, _NkPort, State) ->
    handle(api_server_handle_call, [Msg, From], State).


-spec conn_handle_cast(term(), nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_cast({nkservice_cmd, Class, Cmd, Data}, NkPort, State) ->
    send_request(Class, Cmd, Data, undefined, NkPort, State);

conn_handle_cast({reply_ok, TId, Data}, NkPort, State) ->
    case extract_op(TId, State) of
        {#trans{op=ack}, State2} ->
            send_reply_ok(Data, TId, NkPort, State2);
        not_found ->
            ?LLOG(warning, "received reply response for unknown req", [], State), 
            {ok, State}
    end;

conn_handle_cast({reply_error, TId, Code}, NkPort, State) ->
    case extract_op(TId, State) of
        {#trans{op=ack}, State2} ->
            send_reply_error(Code, TId, NkPort, State2);
        not_found ->
            ?LLOG(warning, "received reply response for unknown req", [], State), 
            {ok, State}
    end;

conn_handle_cast({reply_ack, TId}, NkPort, State) ->
    case extract_op(TId, State) of
        {#trans{op=ack}, State2} ->
            State3 = insert_ack(TId, State2),
            send_ack(TId, NkPort, State3);
        not_found ->
            ?LLOG(warning, "received reply response for unknown req", [], State), 
            {ok, State}
    end;


conn_handle_cast(nkservice_stop, _NkPort, State) ->
    {stop, normal, State};

conn_handle_cast({nkservice_start_ping, Time}, _NkPort, #state{ping=Ping}=State) ->
    case Ping of
        undefined -> self() ! send_ping;
        _ -> ok
    end,
    {ok, State#state{ping=Time}};

conn_handle_cast(nkservice_stop_ping, _NkPort, State) ->
    {ok, State#state{ping=undefined}};

conn_handle_cast(Msg, _NkPort, State) ->
    handle(api_server_handle_cast, [Msg], State).


-spec conn_handle_info(term(), nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_info(send_ping, _NkPort, #state{ping=undefined}=State) ->
    {ok, State};

conn_handle_info(send_ping, NkPort, #state{ping=Time}=State) ->
    erlang:send_after(1000*Time, self(), send_ping),
    send_request(core, ping, #{time=>Time}, undefined, NkPort, State);

conn_handle_info({timeout, _, {nkservice_op_timeout, TId}}, _NkPort, State) ->
    case extract_op(TId, State) of
        {#trans{op=Op, from=From}, State2} ->
            nklib_util:reply(From, {error, timeout}),
            ?LLOG(warning, "operation ~p timeout!", [Op], State),
            {stop, normal, State2};
        not_found ->
            {ok, State}
    end;

conn_handle_info(Info, _NkPort, State) ->
    handle(api_server_handle_info, [Info], State).


%% @doc Called when the connection stops
-spec conn_stop(Reason::term(), nkpacket:nkport(), #state{}) ->
    ok.

conn_stop(Reason, _NkPort, State) ->
    ?LLOG(info, "server stop (~p)", [Reason], State),
    catch handle(api_server_terminate, [Reason], State).



%% ===================================================================
%% Requests
%% ===================================================================

%% @private
process_client_req(Class, login, Data, TId, NkPort, State) ->
    _ = send_ack(TId, NkPort, State),
    SessId = nklib_util:uuid_4122(),
    case handle(api_server_login, [Class, Data, SessId], State) of
        {true, User, State2} ->
            SessId2 = SessId;
        {true, User, SessId2, State2} ->
            ok;
        {false, Error, State2} ->
            User = SessId2 = {error, Error}
    end,
    case SessId2 of
        {error, ReplyError} ->
            stop(self()),
            send_reply_error(ReplyError, TId, NkPort, State2);
        _ ->
            #state{user_state=UserState2} = State2,
            UserState3 = UserState2#{user=>User, session_id=>SessId2},
            State3 = State2#state{user_state=UserState3, user=User},
            nklib_proc:put(?MODULE, {User, SessId2}),
            nklib_proc:put({?MODULE, user, User}, SessId2),
            true = nklib_proc:reg({?MODULE, session, SessId2}, User),
            send_reply_ok(#{session_id=>SessId}, TId, NkPort, State3)
    end;

process_client_req(Class, Cmd, Data, TId, NkPort, State) ->
    case handle(api_server_cmd, [Class, Cmd, Data, TId], State) of
        {ok, Reply, State2} when is_map(Reply) ->
            send_reply_ok(Reply, TId, NkPort, State2);
        {ack, State2} ->
            State3 = insert_ack(TId, State2),
            send_ack(TId, NkPort, State3);
        {error, Error, State2} ->
            send_reply_error(Error, TId, NkPort, State2)
    end.


%% @private
process_client_resp(Result, Data, #trans{from=From}, _NkPort, State) ->
    nklib_util:reply(From, {ok, Result, Data}),
    {ok, State}.



%% ===================================================================
%% Util
%% ===================================================================

%% @private
do_call(Pid, Msg) ->
    case self() of
        Pid -> {error, blocking_request};
        _ -> nklib_util:call(Pid, Msg, 1000*?CALL_TIMEOUT)
    end.


%% @private
insert_op(TId, Op, From, #state{trans=AllTrans}=State) ->
    Trans = #trans{
        op = Op,
        from = From,
        timer = erlang:start_timer(1000*?OP_TIME, self(), {nkservice_op_timeout, TId})
    },
    State#state{trans=maps:put(TId, Trans, AllTrans)}.


%% @private
insert_ack(TId, #state{trans=AllTrans}=State) ->
    Trans = #trans{
        op = ack,
        timer = erlang:start_timer(1000*?ACK_TIME, self(), {nkservice_op_timeout, TId})
    },
    State#state{trans=maps:put(TId, Trans, AllTrans)}.


%% @private
extract_op(TId, #state{trans=AllTrans}=State) ->
    case maps:find(TId, AllTrans) of
        {ok, #trans{timer=Timer}=OldTrans} ->
            nklib_util:cancel_timer(Timer),
            State2 = State#state{trans=maps:remove(TId, AllTrans)},
            {OldTrans, State2};
        error ->
            not_found
    end.


%% @private
extend_op(TId, #trans{timer=Timer}=Trans, #state{trans=AllTrans}=State) ->
    nklib_util:cancel_timer(Timer),
    lager:warning("NEW TIME: ~p", [000*?ACK_TIME]),

    Timer2 = erlang:start_timer(1000*?ACK_TIME, self(), {nkservice_op_timeout, TId}),
    Trans2 = Trans#trans{timer=Timer2},
    State#state{trans=maps:put(TId, Trans2, AllTrans)}.


%% @private
send_request(Class, Cmd, Data, From, NkPort, #state{tid=TId}=State) ->
    Msg1 = #{
        class => Class,
        cmd => Cmd,
        tid => TId
    },
    Msg2 = case map_size(Data) of
        0 -> Msg1;
        _ -> Msg1#{data=>Data}
    end,
    State2 = insert_op(TId, Msg2, From, State),
    send(Msg2, NkPort, State2#state{tid=TId+1}).



%% @private
send_reply_ok(Data, TId, NkPort, State) ->
    Msg1 = #{
        result => ok,
        tid => TId
    },
    Msg2 = case map_size(Data) of
        0 -> Msg1;
        _ -> Msg1#{data=>Data}
    end,
    send(Msg2, NkPort, State).


%% @private
send_reply_error(Error, TId, NkPort, #state{srv_id=SrvId}=State) ->
    {Code, Text} = SrvId:error_code(Error),
    Msg = #{
        result => error,
        tid => TId,
        data => #{ 
            code => Code,
            error => nklib_util:to_binary(Text)
        }
    },
    send(Msg, NkPort, State).


%% @private
send_ack(TId, NkPort, State) ->
    Msg = #{ack => TId},
    send(Msg, NkPort, State).


%% @private
send(Msg, NkPort, State) ->
    ?PRINT("sending ~s", [Msg], State),
    case send(Msg, NkPort) of
        ok -> 
            {ok, State};
        error -> 
            ?LLOG(notice, "error sending reply:", [], State),
            {stop, normal, State}
    end.


%% @private
send(Msg, NkPort) ->
    nkpacket_connection:send(NkPort, Msg).


%% @private
handle(Fun, Args, State) ->
    nklib_gen_server:handle_any(Fun, Args, State, #state.srv_id, #state.user_state).
    

%% @private
print(Txt, [#{}=Map], State) ->
    print(Txt, [nklib_json:encode_pretty(Map)], State);
print(Txt, Args, State) ->
    ?LLOG(info, Txt, Args, State).

 
