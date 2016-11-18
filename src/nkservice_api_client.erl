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

%% @doc 
-module(nkservice_api_client).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([start/5, start/7, cmd/5, reply_ok/3, reply_error/3, stop/1, stop_all/0]).
-export([transports/1, default_port/1]).
-export([conn_init/1, conn_encode/2, conn_parse/3, conn_stop/3]).
-export([conn_handle_call/4, conn_handle_cast/3, conn_handle_info/3]).
-export([print/3, get_all/0, get_user_pids/1, find/1]).


-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE API Client (~s) "++Txt, [State#state.remote| Args])).

-define(PRINT(Txt, Args, State), 
        % print(Txt, Args, State),    % Comment this
        ok).


-define(OP_TIME, 5).            % Maximum operation time (without ACK)
-define(ACKED_TIME, 180).       % Maximum operation time (with ACK)
-define(CALL_TIMEOUT, 180).     % 
-define(WS_TIMEOUT, 60*60*1000).

-include("nkservice.hrl").

%% ===================================================================
%% Types
%% ===================================================================

-type id() :: pid() | binary().


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts a new verto session to FS
-spec start(term(), binary(), map(), function(), term()) ->
    {ok, SessId::binary(), pid()} | {error, term()}.

start(Serv, Url, Login, Fun, UserData) ->
    start(Serv, Url, Login, Fun, UserData, core, user).

    
start(Serv, Url, #{user:=User}=Login, Fun, UserData, Class, Sub) ->
    {ok, SrvId} = nkservice_srv:get_srv_id(Serv),
    ConnOpts = #{
        class => {?MODULE, SrvId},
        monitor => self(),
        idle_timeout => ?WS_TIMEOUT,
        user => {Fun, UserData#{user=>User}}
    },
    case nkpacket:connect(Url, ConnOpts) of
        {ok, Pid} -> 
            case cmd(Pid, Class, Sub, login, Login) of
                {ok, #{<<"session_id">>:=SessId}} ->
                    {ok, SessId, Pid};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} -> 
            {error, Error}
    end.




%% @doc 
stop(Id) ->
    do_cast(Id, stop).


%% @doc 
stop_all() ->
    [stop(Pid) || {_, Pid} <- get_all()].


%% @doc
-spec cmd(id(), atom(), atom(), atom(), map()) ->
    {ok, map()} | {error, {integer(), binary()}} | {error, term()}.

cmd(Id, Class, Sub, Cmd, Data) ->
    Req = #api_req{class=Class, subclass=Sub, cmd=Cmd, data=Data},
    do_call(Id, {cmd, Req}).


%% @doc
reply_ok(Id, TId, Data) ->
    do_cast(Id, {reply_ok, TId, Data}).


%% @doc
reply_error(Id, TId, Code) ->
    do_cast(Id, {reply_error, TId, Code}).


%% @dodc
get_all() ->
    nklib_proc:values(?MODULE).


get_user_pids(User) ->
    [Pid || {_, Pid}<- nklib_proc:values({?MODULE, nklib_util:to_binary(User)})].




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
    trans = #{} :: #{tid() => #trans{}},
    tid = 1000 :: integer(),
    remote :: binary(),
    callback :: function(),
    user :: binary(),
    session_id :: binary(),
    userdata :: term()
}).


%% @private
-spec transports(nklib:scheme()) ->
    [nkpacket:transport()].

transports(_) -> [wss, ws].

-spec default_port(nkpacket:transport()) ->
    inet:port_number() | invalid.

default_port(ws) -> 9010;
default_port(wss) -> 9011.


-spec conn_init(nkpacket:nkport()) ->
    {ok, #state{}}.

%% TODO: Send and receive pings from session when they are not in same cluster
conn_init(NkPort) ->
    {ok, {_, SrvId}, {CB, UserData}} = nkpacket:get_user(NkPort),
    {ok, Remote} = nkpacket:get_remote_bin(NkPort),
    State = #state{
        srv_id = SrvId,
        remote = Remote,
        callback = CB,
        userdata = UserData
    },
    ?LLOG(info, "new session (~p)", [self()], State),
    nklib_proc:put(?MODULE),
    {ok, State}.


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
        #{<<"class">> := <<"core">>, <<"cmd">> := <<"ping">>, <<"tid">> := TId} ->
            send_reply_ok(#{}, TId, NkPort, State);
        #{<<"class">> := Class, <<"cmd">> := Cmd, <<"tid">> := TId} ->
            Sub = maps:get(<<"subclass">>, Msg, <<"core">>),
            Data = maps:get(<<"data">>, Msg, #{}),
            case make_req(Class, Sub, Cmd, Data, TId, State) of
                {ok, Req} ->
                    process_server_req(Req, NkPort, State);
                error ->
                    send_reply_error(not_implemented, TId, NkPort, State)
            end;
        #{<<"result">> := Result, <<"tid">> := TId} ->
            case extract_op(TId, State) of
                {Trans, State2} ->
                    Data = maps:get(<<"data">>, Msg, #{}),
                    process_server_resp(Result, Data, Trans, NkPort, State2);
                not_found ->
                    ?LLOG(warning, "received server response for unknown req: ~p", 
                          [Msg], State),
                    {ok, State}
            end;
        #{<<"ack">> := TId} ->
            case extract_op(TId, State) of
                {Trans, State2} ->
                    {ok, extend_op(TId, Trans, State2)};
                not_found ->
                    ?LLOG(warning, "received server response for unknown req: ~p", 
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


conn_handle_call({cmd, Req}, From, NkPort, State) ->
    send_request(Req, From, NkPort, State);

conn_handle_call(Msg, _From, _NkPort, State) ->
    ?LLOG(error, "unexpected handle_call: ~p", [Msg], State),
    {ok, State}.


-spec conn_handle_cast(term(), nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_cast({reply_ok, TId, Data}, NkPort, State) ->
    case extract_op(TId, State) of
        {_Trans, State2} ->
            send_reply_ok(Data, TId, NkPort, State2);
        not_found ->
            ?LLOG(warning, "received reply response for unknown req", [], State), 
            {ok, State}
    end;

conn_handle_cast({reply_error, TId, Code}, NkPort, State) ->
    case extract_op(TId, State) of
        {_Trans, State2} ->
            send_reply_error(Code, TId, NkPort, State2);
        not_found ->
            ?LLOG(warning, "received reply response for unknown req", [], State), 
            {ok, State}
    end;

conn_handle_cast(stop, _NkPort, State) ->
    {stop, normal, State};

conn_handle_cast(Msg, _NkPort, State) ->
    ?LLOG(error, "unexpected handle_cast: ~p", [Msg], State),
    {ok, State}.


-spec conn_handle_info(term(), nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_info({timeout, _, {op_timeout, TId}}, _NkPort, State) ->
    case extract_op(TId, State) of
        {#trans{from=From}, State2} ->
            nklib_util:reply(From, {error, timeout}),
            ?LLOG(warning, "operation ~p timeout!", [TId], State),
            {stop, normal, State2};
        not_found ->
            {ok, State}
    end;

conn_handle_info(Info, _NkPort, State) ->
    ?LLOG(error, "unexpected handle_info: ~p", [Info], State),
    {ok, State}.


%% @doc Called when the connection stops
-spec conn_stop(Reason::term(), nkpacket:nkport(), #state{}) ->
    ok.

conn_stop(Reason, _NkPort, State) ->
    ?LLOG(info, "client stop (~p)", [Reason], State).


%% ===================================================================
%% Requests
%% ===================================================================

%% @private
process_server_req(#api_req{tid=TId}=Req, NkPort, State) ->
    #state{callback=CB, userdata=UserData, user=User, session_id=SessId} = State,


    case CB(Req#api_req{user=User, session_id=SessId}, UserData) of
        {ok, Reply, UserData2} ->
            send_reply_ok(Reply, TId, NkPort, State#state{userdata=UserData2});
        {ack, UserData2} ->
            send_ack(TId, NkPort, State#state{userdata=UserData2});
        {error, Error, UserData2} ->
            send_reply_error(Error, TId, NkPort, State#state{userdata=UserData2})
    end.


%% @private
process_server_resp(<<"ok">>, Data, #trans{from=From}=Trans, _NkPort, State) ->
    State2 = case Trans of
        #trans{op=#{cmd:=login, data:=#{user:=User}}} ->
            #{<<"session_id">>:=SessId} = Data,
            nklib_proc:put(?MODULE, User),
            nklib_proc:put({?MODULE, User}),
            State#state{user=User, session_id=SessId};
        _ ->
            State
    end,
    nklib_util:reply(From, {ok, Data}),
    {ok, State2};

process_server_resp(<<"error">>, Data, #trans{from=From}, _NkPort, State) ->
    Code = maps:get(<<"code">>, Data, 0),
    Error = maps:get(<<"error">>, Data, <<>>),
    nklib_util:reply(From, {error, {Code, Error}}),
    {ok, State}.



%% ===================================================================
%% Util
%% ===================================================================


%% @private
do_call(Id, Msg) ->
    case find(Id) of
        {ok, Pid} ->
            nklib_util:call(Pid, Msg, 1000*?CALL_TIMEOUT);
        not_found ->
            {error, not_found}
    end.


%% @private
do_cast(Id, Msg) ->
    case find(Id) of
        {ok, Pid} ->
            gen_server:cast(Pid, Msg);
        not_found ->
            ok
    end.


%% @private
find(Pid) when is_pid(Pid) ->
    {ok, Pid};

find(Id) ->
    case get_user_pids(Id) of
        [Pid|_] ->
            {ok, Pid};
        [] ->
            not_found
    end.



%% @private
insert_op(TId, Op, From, #state{trans=AllTrans}=State) ->
    Trans = #trans{
        op = Op,
        from = From,
        timer = erlang:start_timer(1000*?OP_TIME, self(), {op_timeout, TId})
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
    Timer2 = erlang:start_timer(1000*?ACKED_TIME, self(), {op_timeout, TId}),
    Trans2 = Trans#trans{timer=Timer2},
    State#state{trans=maps:put(TId, Trans2, AllTrans)}.


%% @private
make_req(Class, Sub, Cmd, Data, TId, State) ->
    try
        Class2 = nklib_util:to_existing_atom(Class),
        Sub2 = nklib_util:to_existing_atom(Sub),
        Cmd2 = nklib_util:to_existing_atom(Cmd),
        #state{srv_id=SrvId, user=User, session_id=Session} = State,
        Req = #api_req{
            srv_id = SrvId,
            class = Class2,
            subclass = Sub2,
            cmd = Cmd2,
            tid = TId,
            data = Data, 
            user = User,
            session_id = Session
        },
        {ok, Req}
    catch
        _:_ -> error
    end.


%% @private
send_request(Req, From, NkPort, #state{tid=TId}=State) ->
    #api_req{class=Class, subclass=Sub, cmd=Cmd, data=Data} = Req,
    Msg1 = #{
        class => Class,
        cmd => Cmd,
        tid => TId
    },
    Msg2 = case Sub == <<"core">> orelse Sub == core of
        true  -> Msg1;
        false -> Msg1#{subclass=>Sub}
    end,
    Msg3 = case is_map(Data) andalso map_size(Data)>0  of
        true -> Msg2#{data=>Data};
        false -> Msg2
    end,
    State2 = insert_op(TId, Msg3, From, State),
    send(Msg3, NkPort, State2#state{tid=TId+1}).


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
    {Code, Text} = nkservice_util:error_code(SrvId, Error),
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
    _ = send(Msg, NkPort, State),
    {ok, State}.


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
print(Txt, [#{}=Map], State) ->
    print(Txt, [nklib_json:encode_pretty(Map)], State);
print(Txt, Args, State) ->
    ?LLOG(info, Txt, Args, State).




