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

-export([cmd/5, cmd_async/5, reply_ok/3, reply_error/3, reply_ack/2]).
-export([stop/1, start_ping/2, stop_ping/1]).
-export([register/2, unregister/2]).
-export([subscribe/2, subscribe/3, unsubscribe/2, unsubscribe/3]).
-export([find_user/1, find_session/1, get_subscriptions/1]).
-export([do_register_http/1]).
-export([transports/1, default_port/1]).
-export([conn_init/1, conn_encode/2, conn_parse/3, conn_handle_call/4, 
         conn_handle_cast/3, conn_handle_info/3, conn_stop/3]).
-export([get_all/0, get_all/1, print/3]).


-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE API Server ~s (~s) "++Txt, 
               [State#state.session_id, State#state.user | Args])).

-define(PRINT(Txt, Args, State), 
        print(Txt, Args, State),    % Uncomment this for detailed logs
        ok).


-define(OP_TIME, 10).           % Maximum operation time (without ACK)
-define(ACK_TIME, 180).         % Maximum operation time (with ACK)
-define(CALL_TIMEOUT, 180).     % Maximum sync call time
-define(PING_TIME, 60).

-include("nkservice.hrl").


%% ===================================================================
%% Types
%% ===================================================================

-type id() :: pid() | binary().
-type user_state() :: map().
-type class() :: atom() | binary().
-type subclass() :: atom() | binary().
-type cmd() :: atom() | binary().
-type data() :: map().


%% ===================================================================
%% Public
%% ===================================================================

%% @doc Send a command and wait a response
-spec cmd(id(), class(), subclass(), cmd(), data()) ->
    {ok, Result::binary(), Data::map()} | {error, term()}.

cmd(Id, Class, SubClass, Cmd, Data) ->
    Req = #api_req{class1=Class, subclass1=SubClass, cmd1=Cmd, data=Data},
    do_call(Id, {nkservice_cmd, Req}).


%% @doc Send a command and don't wait for a response
-spec cmd_async(id(), class(), subclass(), cmd(), data()) ->
    ok.

cmd_async(Id, Class, SubClass, Cmd, Data) ->
    Req = #api_req{class1=Class, subclass1=SubClass, cmd1=Cmd, data=Data},
    do_cast(Id, {nkservice_cmd, Req}).


%% @doc Sends an ok reply to a command (when you reply 'ack' in callbacks)
-spec reply_ok(id(), term(), map()) ->
    ok.

reply_ok(Id, TId, Data) ->
    case find(Id) of
        {ok, Pid} ->
            gen_server:cast(Pid, {nkservice_reply_ok, TId, Data});
        not_found ->
            case find_session_http(Id) of
                {ok, Pid} ->
                    gen_server:cast(Pid, {nkservice_api_server, ok, Data});
                _ ->
                    ok
            end
    end.


%% @doc Sends an error reply to a command (when you reply 'ack' in callbacks)
-spec reply_error(id(), term(), nkservice:error()) ->
    ok.

reply_error(Id, TId, Code) ->
    case find(Id) of
        {ok, Pid} ->
            gen_server:cast(Pid, {nkservice_reply_error, TId, Code});
        not_found ->
            case find_session_http(Id) of
                {ok, Pid} ->
                    gen_server:cast(Pid, {nkservice_api_server, error, Code});
                _ ->
                    ok
            end
    end.


%% @doc Sends another ACK to a command (when you reply 'ack' in callbacks)
%% to extend timeout
-spec reply_ack(id(), term()) ->
    ok.

%% @doc Send to extend the timeout for the transaction 
reply_ack(Id, TId) ->
    do_cast(Id, {nkservice_reply_ack, TId}).


%% @doc Start sending pings
-spec start_ping(id(), integer()) ->
    ok.

start_ping(Id, Secs) ->
    do_cast(Id, {nkservice_start_ping, Secs}).


%% @doc Stop sending pings
-spec stop_ping(id()) ->
    ok.

%% @doc 
stop_ping(Id) ->
    do_cast(Id, nkservice_stop_ping).


%% @doc Stops the server
stop(Id) ->
    do_cast(Id, nkservice_stop).


%% @doc Registers a process with the session
-spec register(id(), nklib:link()) ->
    {ok, pid()} | {error, nkservice:error()}.

register(Id, Link) ->
    do_cast(Id, {nkservice_register, Link}).


%% @doc Unregisters a process with the session
-spec unregister(id(), nklib:link()) ->
    ok | {error, nkservice:error()}.

unregister(Id, Link) ->
    do_cast(Id, {nkservice_unregister, Link}).


%% @doc Registers with the Events system
%% All fields except body and pid are used for index
%% Id is not used for real registrations
-spec subscribe(id(), nkservice:event()) ->
    ok.

subscribe(Id, Event) ->
    subscribe(Id, Event, single).


%% @doc Registers with and index
-spec subscribe(id(), nkservice:event(), term()) ->
    ok.

subscribe(Id, Event, InstanceId) ->
    do_cast(Id, {nkservice_subscribe, Event, InstanceId}).


%% @doc Unregisters with the Events systtem
-spec unsubscribe(id(),  nkservice:event()) ->
    ok.

unsubscribe(Id, Event) ->
    unsubscribe(Id, Event, single).


%% @doc 
-spec unsubscribe(id(),  nkservice:event(), term()|all) ->
    ok.

unsubscribe(Id, Event, InstanceId) ->
    do_cast(Id, {nkservice_unsubscribe, Event, InstanceId}).


%% @private
-spec get_all() ->
    [{User::binary(), SessId::binary(), pid()}].

get_all() ->
    [{User, SessId, Pid} || {{User, SessId}, Pid} <- nklib_proc:values(?MODULE)].


%% @private
-spec get_all(nkservice:id()) ->
    [{User::binary(), SessId::binary(), pid()}].

get_all(SrvId) ->
    [{User, SessId, Pid} || {{User, SessId}, Pid} <- nklib_proc:values({?MODULE, SrvId})].


%% @private
-spec find_user(string()|binary()) ->
    [{SessId::binary(), Meta::map(), pid()}].

find_user(User) ->
    User2 = nklib_util:to_binary(User),
    [
        {SessId, Meta, Pid} ||
        {{SessId, Meta}, Pid}<- nklib_proc:values({?MODULE, user, User2})
    ].


%% @private
-spec find_session(binary()) ->
    {ok, User::binary(), pid()} | not_found.

find_session(SessId) ->
    case nklib_proc:values({?MODULE, session, SessId}) of
        [{User, Pid}] -> {ok, User, Pid};
        [] -> not_found
    end.


%% @private
-spec find_session_http(binary()) ->
    {ok, pid()} | not_found.

find_session_http(SessId) ->
    case nklib_proc:values({?MODULE, session, SessId}) of
        [{_, Pid}] -> {ok, Pid};
        [] -> not_found
    end.


%% @private
get_subscriptions(Id) ->
    do_call(Id, nkservice_get_subscriptions).


%% @private
do_register_http(SessId) ->
    case nklib_proc:reg({?MODULE, http, SessId}) of
        true ->
            true;
        {false, _} ->
            false
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

-record(reg, {
    index :: integer(),
    event :: #event{},
    ids :: [term()],
    mon :: reference()
}).

-record(state, {
    srv_id :: nkservice:id(),
    user = <<>> :: binary(),
    session_id = <<>> :: binary(),
    trans = #{} :: #{tid() => #trans{}},
    tid = 1 :: integer(),
    ping :: integer() | undefined,
    regs = [] :: [#reg{}],
    links :: nklib_links:links(),
    % retry_time = 100 :: integer(),
    user_state :: user_state()
}).


%% @private
-spec transports(nklib:scheme()) ->
    [nkpacket:transport()].

transports(_) -> [wss, tls, ws, tcp, http, https].

-spec default_port(nkpacket:transport()) ->
    inet:port_number() | invalid.

default_port(ws) -> 9010;
default_port(wss) -> 9011;
default_port(tcp) -> 9010;
default_port(tls) -> 9011;
default_port(http) -> 9010;
default_port(https) -> 9011.


-spec conn_init(nkpacket:nkport()) ->
    {ok, #state{}}.

conn_init(NkPort) ->
    {ok, {nkservice_api_server, SrvId}, _} = nkpacket:get_user(NkPort),
    {ok, Remote} = nkpacket:get_remote_bin(NkPort),
    UserState = #{type=>api_server, srv_id=>SrvId, remote=>Remote},
    SessId = nklib_util:luid(),
    true = nklib_proc:reg({?MODULE, session, SessId}, <<>>),
    State1 = #state{
        srv_id = SrvId,
        session_id = SessId,
        user_state = UserState,
        links = nklib_links:new()
    },
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
    case Msg of
        #{<<"class">> := Class, <<"cmd">> := Cmd, <<"tid">> := TId} ->
            ?PRINT("received ~s", [Msg], State),
            #state{srv_id=SrvId, user=User, session_id=Session} = State,
            Req = #api_req{
                srv_id = SrvId,
                class1 = Class,
                subclass1 = maps:get(<<"subclass">>, Msg, <<"core">>),
                cmd1 = Cmd,
                tid = TId,
                data = maps:get(<<"data">>, Msg, #{}), 
                user = User,
                session_id = Session
            },
            process_client_req(Req, NkPort, State);
        #{<<"result">> := Result, <<"tid">> := TId} ->
            case extract_op(TId, State) of
                {Trans, State2} ->
                    case Trans of
                        #trans{op=#{cmd:=<<"ping">>}} -> ok;
                        _ -> ?PRINT("received ~s", [Msg], State)
                    end,
                    Data = maps:get(<<"data">>, Msg, #{}),
                    process_client_resp(Result, Data, Trans, NkPort, State2);
                not_found ->
                    ?LLOG(warning, 
                          "received client response for unknown req: ~p, ~p, ~p", 
                          [Msg, TId, State#state.trans], State),
                    {ok, State}
            end;
        #{<<"ack">> := TId} ->
            ?PRINT("received ~s", [Msg], State),
            case extract_op(TId, State) of
                {Trans, State2} ->
                    {ok, extend_op(TId, Trans, State2)};
                not_found ->
                    ?LLOG(warning, "received client ack for unknown req: ~p", 
                          [Msg], State),
                    {ok, State}
            end;
        _ ->
            ?LLOG(warning, "received unrecognized msg: ~p", [Msg], State),
            {stop, normal, State}
    end.


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

conn_handle_call({nkservice_cmd, Req}, From, NkPort, State) ->
    send_request(Req, From, NkPort, State);
    
conn_handle_call(nkservice_get_subscriptions, From, _NkPort, #state{regs=Regs}=State) ->
    Data = [
        #{
            class => Class,
            subclass => Sub,
            type => Type,
            obj_id => ObjId,
            service => SrvId,
            body => Body
        }
        ||
            #reg{event=#event{srv_id=SrvId, class=Class, subclass=Sub, 
                              type=Type, obj_id=ObjId, body=Body}}
            <- Regs
    ],
    gen_server:reply(From, Data),
    {ok, State};

conn_handle_call(get_state, From, _NkPort, State) ->
    gen_server:reply(From, lager:pr(State, ?MODULE)),
    {ok, State};

conn_handle_call(Msg, From, _NkPort, State) ->
    handle(api_server_handle_call, [Msg, From], State).


-spec conn_handle_cast(term(), nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_cast({nkservice_cmd, Req}, NkPort, State) ->
    send_request(Req, undefined, NkPort, State);

conn_handle_cast({nkservice_reply_ok, TId, Data}, NkPort, State) ->
    case extract_op(TId, State) of
        {#trans{op=ack}, State2} ->
            send_reply_ok(Data, TId, NkPort, State2);
        not_found ->
            ?LLOG(warning, "received user reply_ok for unknown req: ~p ~p", [TId, State#state.trans], State), 
            {ok, State}
    end;

conn_handle_cast({nkservice_reply_error, TId, Code}, NkPort, State) ->
    case extract_op(TId, State) of
        {#trans{op=ack}, State2} ->
            send_reply_error(Code, TId, NkPort, State2);
        not_found ->
            ?LLOG(warning, "received user reply_error for unknown req: ~p ~p", [TId, State#state.trans], State), 
            {ok, State}
    end;

conn_handle_cast({nkservice_reply_ack, TId}, NkPort, State) ->
    case extract_op(TId, State) of
        {#trans{op=ack}, State2} ->
            State3 = insert_ack(TId, State2),
            send_ack(TId, NkPort, State3);
        not_found ->
            ?LLOG(warning, "received user reply_ack for unknown req", [], State), 
            {ok, State}
    end;

conn_handle_cast({nkservice_send_event, Event, Body}, NkPort, State) ->
    #state{srv_id=SrvId} = State,
    #event{class=Class, subclass=Sub, type=Type, srv_id=EvSrvId, obj_id=ObjId} = Event,
    Data1 = [
        {class, Class},
        case Sub of
            '*' -> [];
            _ -> {subclass, Sub}
        end,
        case Type of
            '*' -> [];
            _ -> {type, Type}
        end,
        case ObjId of
            '*' -> [];
            _ -> {obj_id, ObjId}
        end,
        case EvSrvId of
            SrvId -> [];
            _ -> {service, nkservice_srv:get_item(EvSrvId, name)}
        end,
        case is_map(Body) andalso map_size(Body) of
            false -> [];
            0 -> [];
            _ -> {body, Body}
        end
    ],
    Data2 = maps:from_list(lists:flatten(Data1)),
    Req = #api_req{class1=core, cmd1=event, data=Data2},
    send_request(Req, undefined, NkPort, State);

conn_handle_cast(nkservice_stop, _NkPort, State) ->
    {stop, normal, State};

conn_handle_cast({nkservice_start_ping, Time}, _NkPort, #state{ping=Ping}=State) ->
    case Ping of
        undefined -> self() ! nkservice_send_ping;
        _ -> ok
    end,
    {ok, State#state{ping=Time}};

conn_handle_cast(nkservice_stop_ping, _NkPort, State) ->
    {ok, State#state{ping=undefined}};

conn_handle_cast({nkservice_subscribe, Event, Id}, _NkPort, State) ->
    #state{regs=Regs} = State,
    Index = event_index(Event),
    {ok, Pid} = nkservice_events:reg(Event),
    Regs2 = case lists:keyfind(Index, #reg.index, Regs) of
        false ->
            ?LLOG(info, "registered event ~p", [Event], State),
            Mon = monitor(process, Pid),
            [#reg{index=Index, event=Event, mon=Mon, ids=[Id]}|Regs];
        #reg{ids=OldsIds}=Reg ->
            ?LLOG(info, "event ~p already registered", [Event], State),
            Reg2 = Reg#reg{event=Event, ids=nklib_util:store_value(Id, OldsIds)},
            lists:keystore(Index, #reg.index, Regs, Reg2)
    end,
    {ok, State#state{regs=Regs2}};

conn_handle_cast({nkservice_unsubscribe, Event, Id}, _NkPort, State) ->
    #state{regs=Regs} = State,
    Index = event_index(Event),
    case lists:keytake(Index, #reg.index, Regs) of
        {value, #reg{ids=[Id], mon=Mon}, Regs2} ->
            demonitor(Mon),
            ?LLOG(info, "unregistered event ~p", [Event], State),
            ok = nkservice_events:unreg(Event),
            {ok, State#state{regs=Regs2}};
        {value, #reg{mon=Mon}, Regs2} when Id==all ->
            demonitor(Mon),
            ?LLOG(info, "unregistered event ~p", [Event], State),
            ok = nkservice_events:unreg(Event),
            {ok, State#state{regs=Regs2}};
        {value, #reg{ids=Ids}=Reg, Regs2} ->
            Reg2 = Reg#reg{ids=Ids -- [Id]},
            {ok, State#state{regs=[Reg2|Regs2]}};
        false ->
            {ok, State}
    end;

conn_handle_cast({nkservice_register, Link}, _NkPort, State) ->
    ?LLOG(info, "registered ~p", [Link], State),
    {ok, links_add(Link, State)};

conn_handle_cast({nkservice_unregister, Link}, _NkPort, State) ->
    ?LLOG(info, "unregistered ~p", [Link], State),
    {ok, links_remove(Link, State)};

conn_handle_cast(Msg, _NkPort, State) ->
    handle(api_server_handle_cast, [Msg], State).


-spec conn_handle_info(term(), nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_info(nkservice_send_ping, _NkPort, #state{ping=undefined}=State) ->
    {ok, State};

conn_handle_info(nkservice_send_ping, NkPort, #state{ping=Time}=State) ->
    erlang:send_after(1000*Time, self(), nkservice_send_ping),
    Req = #api_req{class1=core, cmd1=ping, data = #{time=>Time}},
    send_request(Req, undefined, NkPort, State);

conn_handle_info({timeout, _, {nkservice_op_timeout, TId}}, _NkPort, State) ->
    case extract_op(TId, State) of
        {#trans{op=Op, from=From}, State2} ->
            nklib_util:reply(From, {error, timeout}),
            ?LLOG(warning, "operation ~p (~p) timeout!", [Op, TId], State),
            {stop, normal, State2};
        not_found ->
            {ok, State}
    end;

conn_handle_info({'EXIT', _PId, normal}, _NkPort, State) ->
    {ok, State};

conn_handle_info({'DOWN', Ref, process, _Pid, Reason}=Info, _NkPort, State) ->
    #state{regs=Regs} = State,
    case lists:keytake(Ref, 2, Regs) of
        {value, #reg{event=Event, ids=Ids}, Regs2} ->
            lists:foreach(fun(Id) -> subscribe(self(), Event, Id) end, Ids),
            {ok, State#state{regs=Regs2}};
        false ->
            case links_down(Ref, State) of
                {ok, Link, State2} ->
                    handle(api_server_reg_down, [Link, Reason], State2);
                not_found ->
                    handle(api_server_handle_info, [Info], State)
            end
    end;

%% nkservice_events send this message to all registered to this Event
conn_handle_info({nkservice_event, Event, Body}, NkPort, State) ->
    case handle(api_server_forward_event, [Event, Body], State) of
        {ok, State2} ->
            conn_handle_cast({nkservice_send_event, Event, Body}, NkPort, State2);
        {ok, Event2, Body2, State2} ->
            conn_handle_cast({nkservice_send_event, Event2, Body2}, NkPort, State2);
        {ignore, State2} ->
            {ok, State2}
    end;

conn_handle_info(Info, _NkPort, State) ->
    handle(api_server_handle_info, [Info], State).


%% @doc Called when the connection stops
-spec conn_stop(Reason::term(), nkpacket:nkport(), #state{}) ->
    ok.

conn_stop(Reason, _NkPort, #state{trans=Trans}=State) ->
    lists:foreach(
        fun({_, #trans{from=From}}) -> nklib_util:reply(From, {error, stopped}) end,
        maps:to_list(Trans)),
    ?LLOG(info, "server stop (~p): ~p", [Reason, Trans], State),
    catch handle(api_server_terminate, [Reason], State).



%% ===================================================================
%% Requests
%% ===================================================================

%% @private
process_client_req(Req, NkPort, #state{user=User} = State) ->
    case nkservice_api_lib:process_req(Req, State) of
        {ok, Reply, State2} ->
            send_reply_ok(Reply, Req, NkPort, State2);
        {ack, State2} ->
            State3 = insert_ack(Req, State2),
            send_ack(Req, NkPort, State3);
        {login, User2, Meta, State2} when User == <<>> ->
            process_login(User2, Meta, Req, NkPort, State2);
        {login, _User, _Meta, State2} ->
            send_reply_error(already_authenticated, Req, NkPort, State2);
        {error, Error, State2} ->
            send_reply_error(Error, Req, NkPort, State2)
    end.

%% @private
process_client_resp(Result, Data, #trans{from=From}, _NkPort, State) ->
    nklib_util:reply(From, {ok, Result, Data}),
    {ok, State}.



%% ===================================================================
%% Util
%% ===================================================================

%% @private
process_login(User, Meta, Req, NkPort, State) ->
    #state{srv_id=SrvId, session_id=SessId, user_state=UserState} = State,
    UserState2 = UserState#{user=>User, session_id=>SessId},
    State2 = State#state{user_state=UserState2, user=User},
    nklib_proc:put(?MODULE, {User, SessId}),
    nklib_proc:put({?MODULE, SrvId}, {User, SessId}),
    nklib_proc:put({?MODULE, user, User}, {SessId, Meta}),
    nklib_proc:put({?MODULE, session, SessId}, User),
    Event1 = #event{
        srv_id = SrvId,
        class = <<"core">>,
        subclass = <<"user_event">>,
        obj_id = User
    },
    subscribe(self(), Event1),
    Event2 = Event1#event{
        subclass = <<"session_event">>,
        obj_id = SessId
    },
    subscribe(self(), Event2),
    start_ping(self(), ?PING_TIME),
    send_reply_ok(#{session_id=>SessId}, Req, NkPort, State2).


%% @private
do_call(Id, Msg) ->
    case find(Id) of
        {ok, Pid} ->
            case self() of
                Pid -> {error, blocking_request};
                _ -> nklib_util:call(Pid, Msg, 1000*?CALL_TIMEOUT)
            end;
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
    case find_user(Id) of
        [{_SessId, _Meta, Pid}|_] ->
            {ok, Pid};
        [] ->
            case find_session(Id) of
                {ok, _, Pid} ->
                    {ok, Pid};
                not_found ->
                    not_found
            end
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
insert_ack(#api_req{tid=TId}, State) ->
    insert_ack(TId, State);

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
    lager:warning("NEW TIME: ~p", [1000*?ACK_TIME]),

    Timer2 = erlang:start_timer(1000*?ACK_TIME, self(), {nkservice_op_timeout, TId}),
    Trans2 = Trans#trans{timer=Timer2},
    State#state{trans=maps:put(TId, Trans2, AllTrans)}.


%% @private
send_request(Req, From, NkPort, #state{tid=TId}=State) ->
    #api_req{class1=Class, subclass1=Sub, cmd1=Cmd, data=Data} = Req,
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
send_reply_ok(Data, #api_req{tid=TId}, NkPort, State) ->
    send_reply_ok(Data, TId, NkPort, State);

send_reply_ok(Data, TId, NkPort, State) ->
    Msg1 = #{
        result => ok,
        tid => TId
    },
    Msg2 = case Data of
        #{} when map_size(Data)==0 -> Msg1;
        #{} -> Msg1#{data=>Data};
        % List when is_list(List), length(List)==0 -> Msg1;
        List when is_list(List) -> Msg1#{data=>Data}
    end,
    send(Msg2, NkPort, State).


%% @private
send_reply_error(Error, #api_req{tid=TId}, NkPort, State) ->
    send_reply_error(Error, TId, NkPort, State);

send_reply_error(Error, TId, NkPort, #state{srv_id=SrvId}=State) ->
    {Code, Text} = nkservice_util:error_code(SrvId, Error),
    Msg = #{
        result => error,
        tid => TId,
        data => #{ 
            code => Code,
            error => Text
        }
    },
    send(Msg, NkPort, State).


%% @private
send_ack(#api_req{tid=TId}, NkPort, State) ->
    send_ack(TId, NkPort, State);

send_ack(TId, NkPort, State) ->
    Msg = #{ack => TId},
    send(Msg, NkPort, State).


%% @private
send(Msg, NkPort, State) ->
    ?PRINT("sending ~s", [Msg], State),
    case catch send(Msg, NkPort) of
        ok -> 
            {ok, State};
        _ -> 
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
event_index(Event) ->
    erlang:phash2(Event#event{body=undefined}).


%% @private
links_add(Link, #state{links=Links}=State) ->
    State#state{links=nklib_links:add(Link, Links)}.


%% @private
links_remove(Link, #state{links=Links}=State) ->
    State#state{links=nklib_links:remove(Link, Links)}.


%% @private
links_down(Mon, #state{links=Links}=State) ->
    case nklib_links:down(Mon, Links) of
        {ok, Link, _Data, Links2} -> 
            {ok, Link, State#state{links=Links2}};
        not_found -> 
            not_found
    end.


% %% @private
% links_fold(Fun, Acc, #state{links=Links}) ->
%     nklib_links:fold(Fun, Acc, Links).


%% @private
print(_Txt, [#{cmd:=<<"ping">>}], _State) ->
    ok;
print(Txt, [#{}=Map], State) ->
    print(Txt, [nklib_json:encode_pretty(Map)], State);
print(Txt, Args, State) ->
    ?LLOG(info, Txt, Args, State).

 
