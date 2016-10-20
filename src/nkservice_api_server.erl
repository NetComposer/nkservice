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
-export([register_event/2, unregister_event/2]).
-export([find_user/1, find_session/1]).
-export([transports/1, default_port/1]).
-export([conn_init/1, conn_encode/2, conn_parse/3, conn_handle_call/4, 
         conn_handle_cast/3, conn_handle_info/3, conn_stop/3]).
-export([list_users/2, get_user/4, get_subscriptions/2]).
-export([get_all/0, get_all/1, print/3, get_data/1]).


-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE API Server ~s (~s) "++Txt, 
               [State#state.session_id, State#state.user | Args])).

-define(PRINT(Txt, Args, State), 
        print(Txt, Args, State),    % Uncomment this for detailed logs
        ok).


-define(OP_TIME, 5).            % Maximum operation time (without ACK)
-define(ACK_TIME, 180).         % Maximum operation time (with ACK)
-define(CALL_TIMEOUT, 180).     % Maximum sync call time

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
    Req = #api_req{class=Class, subclass=SubClass, cmd=Cmd, data=Data},
    do_call(Id, {nkservice_cmd, Req}).


%% @doc Send a command and don't wait for a response
-spec cmd_async(id(), class(), subclass(), cmd(), data()) ->
    ok.

cmd_async(Id, Class, SubClass, Cmd, Data) ->
    Req = #api_req{class=Class, subclass=SubClass, cmd=Cmd, data=Data},
    do_cast(Id, {nkservice_cmd, Req}).


%% @doc Sends an ok reply to a command (when you reply 'ack' in callbacks)
-spec reply_ok(id(), term(), map()) ->
    ok.

reply_ok(Id, TId, Data) ->
    do_cast(Id, {reply_ok, TId, Data}).


%% @doc Sends an error reply to a command (when you reply 'ack' in callbacks)
-spec reply_error(id(), term(), nkservice:error()) ->
    ok.

reply_error(Id, TId, Code) ->
    do_cast(Id, {reply_error, TId, Code}).


%% @doc Sends another ACK to a command (when you reply 'ack' in callbacks)
%% to extend timeout
-spec reply_ack(id(), term()) ->
    ok.

%% @doc Send to extend the timeout for the transaction 
reply_ack(Id, TId) ->
    do_cast(Id, {reply_ack, TId}).


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
%% You case use any field of the event to make it different (for example, "id")
-spec register_event(id(), nkservice:event()) ->
    ok.

register_event(Id, Event) ->
    do_cast(Id, {nkservice_register_event, Event}).


%% @doc Registers with the Events system
-spec unregister_event(id(),  nkservice:event()) ->
    ok.

unregister_event(Id, Event) ->
    do_cast(Id, {nkservice_unregister_event, Event}).


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


-spec find_user(string()|binary()) ->
    [{SessId::binary(), pid()}].

find_user(User) ->
    User2 = nklib_util:to_binary(User),
    nklib_proc:values({?MODULE, user, User2}).


-spec find_session(binary()) ->
    {ok, User::binary(), pid()} | not_found.

find_session(SessId) ->
    case nklib_proc:values({?MODULE, session, SessId}) of
        [{User, Pid}] -> {ok, User, Pid};
        [] -> not_found
    end.


%% @private
get_data(Id) ->
    do_call(Id, get_data).




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
    session_id = <<>> :: binary(),
    trans = #{} :: #{tid() => #trans{}},
    tid = 1 :: integer(),
    ping :: integer() | undefined,
    regs = [] :: [{nkservice:event(), reference()}],
    links :: nklib_links:links(),
    retry_time = 100 :: integer(),
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
    UserState = #{type=>api_server, srv_id=>SrvId, remote=>Remote},
    State1 = #state{
        srv_id = SrvId, 
        user_state = UserState,
        links = nklib_links:new()
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
    case Msg of
        #{<<"class">> := Class, <<"cmd">> := Cmd, <<"tid">> := TId} ->
            ?PRINT("received ~s", [Msg], State),
            #state{srv_id=SrvId, user=User, session_id=Session} = State,
            Sub = maps:get(<<"subclass">>, Msg, <<"core">>),
            Req = #api_req{
                srv_id = SrvId,
                class = Class,
                subclass = Sub,
                cmd = Cmd,
                tid = TId,
                data = maps:get(<<"data">>, Msg, #{}),
                user = User,
                session = Session
            },
            process_client_req(Class, Sub, Cmd, Req, NkPort, State);
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
                    ?LLOG(warning, "received client response for unknown req: ~p, ~p, ~p", 
                          [Msg, TId, State#state.trans], State),
                    {ok, State}
            end;
        #{<<"ack">> := TId} ->
            ?PRINT("received ~s", [Msg], State),
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
    
conn_handle_call(nkservice_get_user_data, From, _NkPort, State) ->
    #state{user_state=UserState} = State,
    gen_server:reply(From, get_user_data(self(), UserState)),
    {ok, State};

conn_handle_call(nkservice_get_regs, From, _NkPort, #state{regs=Regs}=State) ->
    Data = [
        #{
            id => Id,
            class => Class,
            subclass => Sub,
            type => Type,
            obj_id => ObjId,
            service => SrvId,
            body => Body
        }
        ||
            {
                #event{id=Id, srv_id=SrvId, class=Class, subclass=Sub, 
                        type=Type, obj_id=ObjId, body=Body}, 
                _Mon
            }
            <- Regs
    ],
    gen_server:reply(From, Data),
    {ok, State};

conn_handle_call(get_data, From, _NkPort, #state{regs=Regs, links=Links}=State) ->
    gen_server:reply(From, {ok, Regs, Links}),
    {ok, State};

conn_handle_call(get_state, From, _NkPort, State) ->
    gen_server:reply(From, {ok, State}),
    {ok, State};
    
conn_handle_call(Msg, From, _NkPort, State) ->
    handle(api_server_handle_call, [Msg, From], State).


-spec conn_handle_cast(term(), nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_cast({nkservice_cmd, Req}, NkPort, State) ->
    send_request(Req, undefined, NkPort, State);

conn_handle_cast({reply_ok, TId, Data}, NkPort, State) ->
    case extract_op(TId, State) of
        {#trans{op=ack}, State2} ->
            send_reply_ok(Data, TId, NkPort, State2);
        not_found ->
            ?LLOG(warning, "received user reply_ok for unknown req: ~p ~p", [TId, State#state.trans], State), 
            {ok, State}
    end;

conn_handle_cast({reply_error, TId, Code}, NkPort, State) ->
    case extract_op(TId, State) of
        {#trans{op=ack}, State2} ->
            send_reply_error(Code, TId, NkPort, State2);
        not_found ->
            ?LLOG(warning, "received user reply_error for unknown req: ~p ~p", [TId, State#state.trans], State), 
            {ok, State}
    end;

conn_handle_cast({reply_ack, TId}, NkPort, State) ->
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
        case map_size(Body) of
            0 -> [];
            _ -> {body, Body}
        end
    ],
    Data2 = maps:from_list(lists:flatten(Data1)),
    Req = #api_req{class = <<"core">>, cmd = <<"event">>, data=Data2},
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

conn_handle_cast({nkservice_register_event, Event}, _NkPort, State) ->
    #state{regs=Regs} = State,
    case lists:keymember(Event, 1, Regs) of
        false ->
            ?LLOG(info, "registered event ~p", [Event], State),
            {ok, Pid} = nkservice_events:reg(Event),
            Mon = monitor(process, Pid),
            {ok, State#state{regs=[{Event, Mon}|Regs]}};
        true ->
            ?LLOG(info, "event ~p already registered", [Event], State),
            {ok, State}
    end;

conn_handle_cast({nkservice_unregister_event, Event}, _NkPort, State) ->
    #state{regs=Regs} = State,
    case lists:keytake(Event, 1, Regs) of
        {value, {_,  Mon}, Regs2} ->
            demonitor(Mon),
            ?LLOG(info, "unregistered event ~p", [Event], State),
            ok = nkservice_events:unreg(Event),
            {ok, State#state{regs=Regs2}};
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
    Req = #api_req{class = <<"core">>, cmd = <<"ping">>, data = #{time=>Time}},
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

conn_handle_info({'DOWN', Ref, process, _Pid, Reason}=Info, _NkPort, State) ->
    #state{regs=Regs} = State,
    case lists:keytake(Ref, 2, Regs) of
        {value, {Event, Ref}, Regs2} ->
            register_event(self(), Event),
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
process_client_req(<<"core">>, <<"user">>, <<"login">>, Req, NkPort, 
                   #state{session_id = <<>>} = State) ->
    _ = send_ack(Req, NkPort, State),
    #api_req{data=Data} = Req,
    SessId = case Data of
        #{<<"session_id">>:=UserSessId} -> UserSessId;
        _ -> nklib_util:uuid_4122()
    end,
    case handle(api_server_login, [Data, SessId], State) of
        {true, User, State2} ->
            process_login(User, SessId, Req, NkPort, State2);
        {true, User, NewSessId, State2} ->
            process_login(User, NewSessId, Req, NkPort, State2);
        {false, Error, State2} ->
            #state{retry_time=Time} = State2,
            timer:sleep(Time),
            State3 = State2#state{retry_time=2*Time},
            send_reply_error(Error, Req, NkPort, State3)
    end;

process_client_req(<<"core">>, <<"user">>, <<"login">>, Req, NkPort, State) ->
    send_reply_error(already_authenticated, Req, NkPort, State);

process_client_req(_Class, _Sub, _Cmd, Req, NkPort, #state{session_id = <<>>}=State) ->
    send_reply_error(not_authenticated, Req, NkPort, State);

process_client_req(<<"core">>, <<"core">>, <<"event">>, Req, NkPort, State) ->
    #api_req{data=#{<<"class">>:=Class}=Data} = Req, 
    #state{srv_id=SrvId} = State,
    case send_reply_ok(#{}, Req, NkPort, State) of
        {ok, State2} ->
            Event = #event{
                srv_id = maps:get(<<"service">>, Data, SrvId),
                class = Class, 
                subclass = maps:get(<<"subclass">>, Data, <<"*">>),
                type = maps:get(<<"type">>, Data, <<"*">>),
                obj_id = maps:get(<<"obj_id">>, Data, <<"*">>)
            },
            Body = maps:get(<<"body">>, Data, #{}),
            {ok, State3} = handle(api_server_event, [Event, Body], State2),
            {ok, State3};
        Other ->
            Other
    end;

process_client_req(_Class, _Sub, _Cmd, #api_req{tid=TId}=Req, NkPort, State) ->
    case handle(api_server_cmd, [Req], State) of
        {ok, Reply, State2} when is_map(Reply); is_list(Reply) ->
            send_reply_ok(Reply, Req, NkPort, State2);
        {ack, State2} ->
            State3 = insert_ack(TId, State2),
            send_ack(Req, NkPort, State3);
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
process_login(User, SessId, Req, NkPort, State) when is_binary(SessId), SessId /= <<>> ->
    case nklib_proc:reg({?MODULE, session, SessId}, User) of
        true ->
            #state{srv_id=SrvId, user_state=UserState} = State,
            UserState2 = UserState#{user=>User, session_id=>SessId},
            State2 = State#state{user_state=UserState2, user=User, session_id=SessId},
            nklib_proc:put(?MODULE, {User, SessId}),
            nklib_proc:put({?MODULE, SrvId}, {User, SessId}),
            nklib_proc:put({?MODULE, user, User}, SessId),
            Event1 = #event{
                srv_id = SrvId,
                class = <<"core">>,
                subclass = <<"user_event">>,
                obj_id = User
            },
            register_event(self(), Event1),
            Event2 = Event1#event{
                subclass = <<"session_event">>,
                obj_id = SessId
            },
            register_event(self(), Event2),
            send_reply_ok(#{session_id=>SessId}, Req, NkPort, State2);
        {false, _} -> 
            stop(self()),
            send_reply_error(duplicated_session_id, Req, NkPort, State)
end;

process_login(_User, _SessId, Req, NkPort, State) ->
    stop(self()),
    send_reply_error(invalid_session_id, Req, NkPort, State).


%% @private
list_users(SrvId, Acc) ->
    lists:foldl(
        fun({User, SessId, _Pid}, FunAcc) ->
            Sessions = maps:get(User, FunAcc, []),
            maps:put(User, [SessId|Sessions], FunAcc)
        end,
        Acc,
        get_all(SrvId)
    ).


%% @private
get_user(_SrvId, User, UserState, Acc) ->
    lists:foldl(
        fun({SessId, Pid}, FunAcc) ->
            case get_user_data(Pid, UserState) of
                {ok, UserData} ->
                    maps:put(SessId, UserData, FunAcc);
                _ ->
                    FunAcc
            end
        end,
        Acc,
        find_user(User)
    ).


%% @private
get_user_data(Pid, _UserState) when Pid/= self() ->
    nklib_util:call(Pid, nkservice_get_user_data);

get_user_data(_Pid, #{srv_id:=SrvId}=UserState) ->
    UserState2 = maps:without([session_id, srv_id, user], UserState),
    SrvId:api_server_get_user_data(UserState2).


%% @private
get_subscriptions(TId, #{type:=api_server}) ->
    Self = self(),
    _ = spawn_link(
        fun() ->
            Subs = gen_server:call(Self, nkservice_get_regs),
            reply_ok(Self, TId, Subs)        
        end),
    ok;

get_subscriptions(_TId, _) ->
    continue.


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
        [{_, Pid}|_] ->
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

 
