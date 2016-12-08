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
-module(nkservice_events).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).
-export([send/1, reg/1, unreg/1]).
-export([call/1]).
-export([parse/3]).
-export([start_link/3, get_all/0, remove_all/3, dump/3]).
-export([init/1, terminate/2, code_change/3, handle_call/3, 
         handle_cast/2, handle_info/2]).
% -export([atest/0]).

-include("nkservice.hrl").

-define(DEBUG(SrvId, Txt, Args, State),
    case erlang:get({?MODULE, SrvId}) of
        true -> ?LLOG(info, Txt, Args, State);
        _ -> ok
    end).

-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE Events '~s/~s/~s' "++Txt, 
               [State#state.class, State#state.sub, State#state.type|Args])).



%% ===================================================================
%% Types
%% ===================================================================

-type event() :: #event{}.

-type srv_id() :: nkservice:id() | all.

% Native formats are binary. Atoms will be converted to binaries.
-type class() :: atom() | binary().
-type subclass() :: atom() | binary(). 
-type type() :: atom() | binary().
-type obj_id() :: atom() | binary(). 
-type body() :: map().




%% ===================================================================
%% Public
%% ===================================================================


%% @doc Send to an specific pid() if registered
-spec send(event()) ->
    ok | not_found.

send(Event) ->
    Event2 = normalize(Event),
    lists:foreach(
        fun(Server) -> gen_server:cast(Server, {send, Event2}) end,
        find_servers(Event2)).


%% @doc
-spec call(event()) ->
    ok | not_found.

call(Event) ->
    Event2 = normalize(Event),
    do_call(find_servers(Event2), Event2).


%% @private
do_call([], _Event) ->
    not_found;

do_call([Pid|Rest], Event) ->
    case gen_server:call(Pid, {call, Event}) of
        ok ->
            ok;
        _ ->
            do_call(Rest, Event)
    end.


%% @doc
%% missing or <<>> fields mean 'any'
%% service can be 'all'
-spec reg(event()) ->
    {ok, pid()}.

reg(Event) ->
    Event2 = normalize_self(Event),
    Server = start_server(Event2),
    gen_server:cast(Server, {reg, Event2}),
    {ok, Server}.


%% @doc
-spec unreg(event()) ->
    ok.

unreg(Event) ->
    Event2 = normalize_self(Event),
    Server = start_server(Event2),
    gen_server:cast(Server, {unreg, Event2}).



%% @private
get_all() ->
    nklib_proc:values(?MODULE).


%% @private
remove_all(Class, Sub, Type) ->
    Class2 = nklib_util:to_binary(Class),
    Sub2 = nklib_util:to_binary(Sub),
    Type2 = nklib_util:to_binary(Type),
    case find_servers(Class2, Sub2, Type2) of
        [Pid] -> gen_server:cast(Pid, remove_all);
        [] -> not_found
    end.


%% @private
dump(Class, Sub, Type) ->
    Class2 = nklib_util:to_binary(Class),
    Sub2 = nklib_util:to_binary(Sub),
    Type2 = nklib_util:to_binary(Type),
    case find_servers(Class2, Sub2, Type2) of
        [Pid] -> gen_server:call(Pid, dump);
        [] -> not_found
    end.



%% @doc Tries to parse a event-type object
parse(SrvId, Data, Pid) ->
  {Syntax, Defaults, Mandatory} = nkservice_api_syntax:events(#{}, #{}, []),
    Opts = #{
        return => map, 
        defaults => Defaults,
        mandatory => Mandatory
    },
    case nklib_config:parse_config(Data, Syntax, Opts) of
        {ok, Parsed, Other} ->
            case map_size(Other)>0 andalso is_pid(Pid) of
                true ->
                    MEvent = #event{
                        srv_id = SrvId,
                        class = <<"core">>,
                        subclass = <<"session">>,
                        type = <<"unrecognized_fields">>,
                        body = #{
                            class => event,
                            body => maps:keys(Other)
                        }
                    },
                    Pid ! {nkservice_event, MEvent};
                false -> 
                    ok
            end,
            #{
                class := Class,
                subclass := Sub,
                type := Type,
                obj_id := ObjId
            } = Parsed,
            Event = #event{
                srv_id = SrvId,
                class = Class,
                subclass = Sub,
                type = Type,
                obj_id = ObjId,
                body = maps:get(body, Parsed, #{})
            },
            {ok, Event};
        {error, {syntax_error, Error}} ->
            {error, {syntax_error, Error}};
        {error, {missing_mandatory_field, Field}} ->
            {error, {missing_field, Field}}
    end.



%% ===================================================================
%% gen_server
%% ===================================================================

-type key() :: {srv_id(), obj_id()}.

-record(state, {
    class :: class(),
    sub :: subclass(),
    type :: type(),
    regs = #{} :: #{key() => [{pid(), body()}]},
    pids = #{} :: #{pid() => {reference(), [key()]}}
}).

%% @private
start_link(Class, Sub, Type) -> 
    gen_server:start_link(?MODULE, [Class, Sub, Type], []).
        

%% @private 
-spec init(term()) ->
    {ok, #state{}}.

init([Class, Sub, Type]) ->
    true = nklib_proc:reg({?MODULE, Class, Sub, Type}),
    nklib_proc:put(?MODULE, {Class, Sub, Type}),
    State = #state{class=Class, sub=Sub, type=Type},
    ?LLOG(info, "starting server (~p)", [self()], State),
    {ok, State}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {reply, term(), #state{}} | {noreply, #state{}} | {stop, normal, ok, #state{}}.

handle_call({call, Event}, _From, State) ->
    #event{class=Class, srv_id=SrvId, obj_id=ObjId} = Event,
    #state{class=Class, regs=Regs} = State,
    PidTerms = case maps:get({SrvId, ObjId}, Regs, []) of
        [] ->
            maps:get({SrvId, <<>>}, Regs, []);
        List ->
            List
    end,
    ?DEBUG(SrvId, "call ~s:~s: ~p", [SrvId, ObjId, PidTerms], State),
    case PidTerms of
        [] ->
            {reply, not_found, State};
        _ ->
            Pos = nklib_util:l_timestamp() rem length(PidTerms) + 1,
            {Pid, RegBody} = lists:nth(Pos, PidTerms),
            send_events([{Pid, RegBody}], Event#event{pid=undefined}, State),
            {reply, ok, State}
    end;

handle_call(dump, _From, #state{regs=Regs, pids=Pids}=State) ->
    {reply, {lists:sort(maps:to_list(Regs)), lists:sort(maps:to_list(Pids))}, State};

handle_call(Msg, _From, State) ->
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}}.

handle_cast({send, Event}, State) ->
    #state{class=Class, regs=Regs} = State,
    #event{class=Class, srv_id=SrvId, obj_id=ObjId} = Event,
    PidTerms1 = maps:get({SrvId, ObjId}, Regs, []),
    PidTerms2 = maps:get({SrvId, <<>>}, Regs, []) -- PidTerms1,
    PidTerms3 = maps:get({all, <<>>}, Regs, []) -- PidTerms1 -- PidTerms2,
    ?DEBUG(SrvId, "send ~s:~s ~p,~p,~p", 
          [SrvId, ObjId, PidTerms1, PidTerms2, PidTerms3], State),
    send_events(PidTerms1, Event, State),
    send_events(PidTerms2, Event, State),
    send_events(PidTerms3, Event, State),
    {noreply, State};

handle_cast({reg, Event}, State) ->
    #event{srv_id=SrvId, obj_id=ObjId, body=Body, pid=Pid} = Event,
    set_log(SrvId),
    ?DEBUG(SrvId, "registered ~s:~s (~p)", [SrvId, ObjId, Pid], State),
    State2 = do_reg({SrvId, ObjId}, Body, Pid, State),
    {noreply, State2};

handle_cast({unreg, Event}, State) ->
    #event{srv_id=SrvId, obj_id=ObjId, pid=Pid} = Event,
    ?DEBUG(SrvId, "unregistered ~s:~s (~p)", [SrvId, ObjId, Pid], State),
    State2 = do_unreg([{SrvId, ObjId}], Pid, State),
    {noreply, State2};

handle_cast(remove_all, #state{pids=Pids}=State) ->
    ?LLOG(info, "remove all", [], State),
    lists:foreach(fun({_Pid, {Mon, _}}) -> demonitor(Mon) end, maps:to_list(Pids)),
    {noreply, State#state{regs=#{}, pids=#{}}};

handle_cast(Msg, State) ->
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}}.

handle_info({'DOWN', Mon, process, Pid, _Reason}, #state{pids=Pids}=State) ->
    case maps:find(Pid, Pids) of
        {ok, {Mon, Keys}} ->
            lists:foreach(
                fun({SrvId, ObjId}) ->
                    ?DEBUG(SrvId, "unregistered ~s:~s (down)", [SrvId, ObjId], State)
                end,
                Keys),
            State2 = do_unreg(Keys, Pid, State),
            {noreply, State2};
        error ->
            lager:warning("Module ~p received unexpected down: ~p", [?MODULE, Pid]),
            {noreply, State}
    end;

handle_info({nkservice_updated, SrvId}, State) ->
    force_set_log(SrvId),
    {noreply, State};

handle_info(Info, State) -> 
    lager:warning("Module ~p received unexpected info ~p", [?MODULE, Info]),
    {noreply, State}.


%% @private
-spec code_change(term(), #state{}, term()) ->
    {ok, #state{}}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% @private
-spec terminate(term(), #state{}) ->
    ok.

terminate(_Reason, State) ->  
    ?LLOG(info, "stopping server (~p)", [self()], State),
    ok.



%% ===================================================================
%% Private
%% ===================================================================

%% @private
normalize(Event) ->
    #event{
        class = Class,
        subclass = Sub,
        type = Type,
        obj_id = ObjId,
        body = Body,
        pid = Pid
    } = Event,
    Body2 = case is_map(Body) of
        true -> 
            Body;
        false ->
            lager:warning("~p is not a map (~s:~s:~s)", [Body, Class, Sub, Type]),
            #{}
    end,
    Pid2 = case is_pid(Pid) orelse Pid==undefined of
        true ->
            Pid;
        false ->
            lager:warning("~p is not a pid (~s:~s:~s)", [Pid, Class, Sub, Type]),
            undefined
    end,
    Event#event{
        class = nklib_util:to_binary(Class),
        subclass = nklib_util:to_binary(Sub),
        type = nklib_util:to_binary(Type),
        obj_id = nklib_util:to_binary(ObjId),
        body = Body2,
        pid = Pid2

    }.


%% @private
normalize_self(#event{pid=Pid}=Event) ->
    Event2 = normalize(Event),
    case Pid of
        undefined -> Event2#event{pid=self()};
        _ -> Event2
    end.


%% @private
find_servers(#event{class=Class, subclass=Sub, type=Type}) ->
    find_servers(Class, Sub, Type).
    

%% @private
find_servers(Class, <<>>, <<>>) ->
    do_find_server(Class, <<>>, <<>>, []);

find_servers(Class, Sub, <<>>) ->
    Acc = do_find_server(Class, <<>>, <<>>, []),
    do_find_server(Class, Sub, <<>>, Acc);

find_servers(Class, Sub, Type) ->
    Acc1 = do_find_server(Class, <<>>, <<>>, []),
    Acc2 = do_find_server(Class, Sub, <<>>, Acc1),
    do_find_server(Class, Sub, Type, Acc2).


%% @private
do_find_server(Class, Sub, Type, Acc) ->
    case nklib_proc:values({?MODULE, Class, Sub, Type}) of
        [{undefined, Pid}] ->
            [Pid|Acc];
        [] ->
            Acc
end.


%% @private
start_server(#event{class=Class, subclass=Sub, type=Type}) ->
    case do_find_server(Class, Sub, Type, []) of
        [Pid] ->
            Pid;
        [] ->
            Spec = {
                {Class, Sub, Type},
                {?MODULE, start_link, [Class, Sub, Type]},
                permanent,
                5000,
                worker,
                [?MODULE]
            },
            case supervisor:start_child(nkservice_events_sup, Spec) of
                {ok, Pid}  -> Pid;
                {error, {already_started, Pid}} -> Pid
            end
    end.


%% @private
do_reg(Key, Body, Pid, #state{regs=Regs, pids=Pids}=State) ->
    PidBodyList2 = case maps:find(Key, Regs) of
        {ok, PidBodyList} ->   % [{pid(), body)}]
            lists:keystore(Pid, 1, PidBodyList, {Pid, Body});
        error ->
            [{Pid, Body}]
    end,
    Regs2 = maps:put(Key, PidBodyList2, Regs),
    {Mon2, Keys2} = case maps:find(Pid, Pids) of
        {ok, {Mon, Keys}} ->    % [reference(), [key()]]
            {Mon, nklib_util:store_value(Key, Keys)};
        error ->
            Mon = monitor(process, Pid),
            {Mon, [Key]}
    end,
    Pids2 = maps:put(Pid, {Mon2, Keys2}, Pids),
    State#state{regs=Regs2, pids=Pids2}.


%% @private
do_unreg([], _Pid, State) ->
    State;

do_unreg([Key|Rest], Pid, #state{regs=Regs, pids=Pids}=State) ->
    Regs2 = case maps:find(Key, Regs) of
        {ok, PidBodyList} ->
            case lists:keydelete(Pid, 1, PidBodyList) of
                [] ->
                    maps:remove(Key, Regs);
                PidBodyList2 ->
                    maps:put(Key, PidBodyList2, Regs)
            end;
        error ->
            Regs
    end,
    Pids2 = case maps:find(Pid, Pids) of
        {ok, {Mon, Keys}} ->
            case Keys -- [Key] of
                [] ->
                    demonitor(Mon),
                    maps:remove(Pid, Pids);
                Keys2 ->
                    maps:put(Pid, {Mon, Keys2}, Pids)
            end;
        error ->
            Pids
    end,
    do_unreg(Rest, Pid, State#state{regs=Regs2, pids=Pids2}).


%% @private
send_events([], _Event, _State) ->
    ok;

send_events([{Pid, _}|Rest], #event{pid=PidE}=Event, State) 
        when is_pid(PidE), Pid/=PidE ->
    send_events(Rest, Event, State);

send_events([{Pid, RegBody}|Rest], Event, State) ->
    #event{srv_id=SrvId, body=Body}=Event, 
    Event2 = Event#event{body=maps:merge(RegBody, Body)},
    ?DEBUG(SrvId, "sending event ~p to ~p", [lager:pr(Event2, ?MODULE), Pid], State),
    Pid ! {nkservice_event, Event2},
    send_events(Rest, Event, State).



%% @private
set_log(SrvId) ->
    case get({?MODULE, SrvId}) of
        undefined ->
            force_set_log(SrvId),
            nkservice_util:register_for_changes(SrvId);
        _ ->
            ok
    end.


%% @private
force_set_log(SrvId) ->
    Debug = case nkservice_util:get_debug_info(SrvId, ?MODULE) of
        {true, _} -> true;
        _ -> false
    end,
    put({?MODULE, SrvId}, Debug).



%% ===================================================================
%% Tests
%% ===================================================================


% % -define(TEST, 1).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-compile([export_all]).

basic_test_() ->
    {setup, 
        fun() -> 
            ?debugFmt("Starting ~p", [?MODULE]),
            case do_find_server(<<"c">>, <<"s">>, <<"t">>, []) of
                [] ->
                    {ok, _} = gen_server:start(?MODULE, [<<"c">>, <<"s">>, <<"t">>], []),
                    do_stop;
                _ -> 
                    remove_all(c, s, t),
                    ok
            end
        end,
        fun(Stop) -> 
            case Stop of 
                do_stop -> catch exit(whereis(?MODULE), kill);
                ok -> ok
            end
        end,
        [
            fun test1/0,
            fun test2/0,
            fun test3/0
        ]
    }.


test1() ->
    Reg = #event{class=c, subclass=s, type=t, srv_id=srv},
    Self = self(),
    reg(Reg#event{obj_id=id1, body=#{b1=>1}}),
    reg(Reg#event{obj_id=id2, body=#{b2=>2}}),
    {
        [
            {{srv, <<"id1">>}, [{Self, #{b1:=1}}]}, 
            {{srv, <<"id2">>}, [{Self, #{b2:=2}}]}
        ], 
        [
            {Self, {_, [{srv, <<"id2">>}, {srv, <<"id1">>}]}}
        ]
    } = 
        dump(c, s, t),

    unreg(Reg#event{obj_id=id1}),
    {
        [{{srv, <<"id2">>}, [{Self, #{b2:=2}}]}],
        [{Self, {_, [{srv, <<"id2">>}]}}]
    } = 
        dump(c, s, t),

    unreg(Reg#event{obj_id=id3}),
    unreg(Reg#event{obj_id=id2}),
    {[], []} = dump(c, s, t),
    ok.


test2() ->
    P1 = test_reg(1, b1),
    P2 = test_reg(1, b1),
    P3 = test_reg(1, b1b),
    P4 = test_reg(2, b2),
    P5 = test_reg(3, b3),
    P6 = test_reg(3, b3b),
    P7 = test_reg(<<>>, b7),
    timer:sleep(50),

    Reg = #event{class=c, subclass=s, type=t, srv_id=srv},
    lists:foreach(
        fun(_) ->
            call(Reg#event{obj_id=0}),
            receive 
                {c, _RP1, <<"0">>, RB1} -> 
                    true = lists:member(RB1, [b1, b1b, b2, b3, b3b, b7]);
                O -> 
                    error(O)
                after 100 -> 
                    error(?LINE) 
                
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            call(Reg#event{obj_id=1}),
            receive 
                {c, _RP2, <<"1">>, RB2} -> true = lists:member(RB2, [b1, b1b, b7])
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            call(Reg#event{obj_id=2}),
            receive 
                {c, RP3, <<"2">>, RB2} -> 
                    true = lists:member(RB2, [b2, b7]),
                    true = lists:member(RP3, [P4, P7])
                after 100 -> 
                    error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            call(Reg#event{obj_id=3}),
            receive 
                {c, _RP3, <<"3">>, RB2} -> true = lists:member(RB2, [b3, b3b, b7])
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            call(Reg#event{obj_id=25}),
            receive 
                {c, P7, <<"25">>, b7} -> ok
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    send(Reg#event{obj_id=0}),
    receive {c, P1, <<"0">>, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P2, <<"0">>, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P3, <<"0">>, b1b} -> ok after 100 -> error(?LINE) end,
    receive {c, P4, <<"0">>, b2} -> ok after 100 -> error(?LINE) end,
    receive {c, P5, <<"0">>, b3} -> ok after 100 -> error(?LINE) end,
    receive {c, P6, <<"0">>, b3b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, <<"0">>, b7} -> ok after 100 -> error(?LINE) end,

    send(Reg#event{obj_id=1}),
    receive {c, P1, <<"1">>, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P2, <<"1">>, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P3, <<"1">>, b1b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, <<"1">>, b7} -> ok after 100 -> error(?LINE) end,

    send(Reg#event{obj_id=2}),
    receive {c, P4, <<"2">>, b2} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, <<"2">>, b7} -> ok after 100 -> error(?LINE) end,

    send(Reg#event{obj_id=3}),
    receive {c, P5, <<"3">>, b3} -> ok after 100 -> error(?LINE) end,
    receive {c, P6, <<"3">>, b3b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, <<"3">>, b7} -> ok after 100 -> error(?LINE) end,

    send(Reg#event{obj_id=33}),
    receive {c, P7, <<"33">>, b7} -> ok after 100 -> error(?LINE) end,

    receive _ -> error(?LINE) after 100 -> ok end,

    [P ! stop || P <- [P1, P2, P3, P4, P5, P6, P7]],
    timer:sleep(50),
    {[], []} = dump(c, s, t),
    ok.


test3() ->
    P1 = test_reg(1, b1),
    P2 = test_reg(1, b1),
    P3 = test_reg(1, b1b),
    P4 = test_reg(2, b2),
    P5 = test_reg(3, b3),
    P6 = test_reg(3, b3b),
    P7 = test_reg(<<>>, b7),
    timer:sleep(50),

    {
        [
            {{srv, <<>>}, 
                [{P7, #{b7:=1}}]},
            {{srv, <<"0">>}, 
                [{P1, #{b1:=1}}, {P2, #{b1:=1}}, {P3, #{b1b:=1}}, {P4, #{b2:=1}}, 
                 {P5, #{b3:=1}}, {P6, #{b3b:=1}}, {P7, #{b7:=1}}]},
            {{srv, <<"1">>}, 
                [{P1, #{b1:=1}}, {P2, #{b1:=1}}, {P3, #{b1b:=1}}]},
            {{srv, <<"2">>}, 
                [{P4, #{b2:=1}}]},
            {{srv, <<"3">>}, 
                [{P5, #{b3:=1}}, {P6, #{b3b:=1}}]}
        ],
        [
            {P1, {_, [{srv, <<"0">>}, {srv, <<"1">>}]}},
            {P2, {_, [{srv, <<"0">>}, {srv, <<"1">>}]}},
            {P3, {_, [{srv, <<"0">>}, {srv, <<"1">>}]}},
            {P4, {_, [{srv, <<"0">>}, {srv, <<"2">>}]}},
            {P5, {_, [{srv, <<"0">>}, {srv, <<"3">>}]}},
            {P6, {_, [{srv, <<"0">>}, {srv, <<"3">>}]}},
            {P7, {_, [{srv, <<"0">>}, {srv, <<>>}]}}
        ]
    }
        = dump(c, s, t),

    P1 ! stop,
    P4 ! unreg,
    timer:sleep(100),
    {
        [
            {{srv, <<>>}, 
                [{P7, #{b7:=1}}]},
            {{srv, <<"0">>}, 
                [{P2, #{b1:=1}}, {P3, #{b1b:=1}}, {P4, #{b2:=1}}, 
                 {P5, #{b3:=1}}, {P6, #{b3b:=1}}, {P7, #{b7:=1}}]},
            {{srv, <<"1">>}, 
                [{P2, #{b1:=1}}, {P3, #{b1b:=1}}]},
            {{srv, <<"3">>}, 
                [{P5, #{b3:=1}}, {P6, #{b3b:=1}}]}
        ],
        [
            {P2, {_, [{srv, <<"0">>}, {srv, <<"1">>}]}},
            {P3, {_, [{srv, <<"0">>}, {srv, <<"1">>}]}},
            {P4, {_, [{srv, <<"0">>}]}},
            {P5, {_, [{srv, <<"0">>}, {srv, <<"3">>}]}},
            {P6, {_, [{srv, <<"0">>}, {srv, <<"3">>}]}},
            {P7, {_, [{srv, <<"0">>}, {srv, <<>>}]}}
        ]
    } = 
        dump(c, s, t),

    [P ! stop || P <- [P1, P2, P3, P4, P5, P6, P7]],
    ok.


test_reg(I, B) ->
    Reg = #event{class=c, subclass=s, type=t, srv_id=srv},
    Self = self(),
    spawn(
        fun() -> 
            reg(Reg#event{obj_id=I, body=maps:put(B, 1, #{})}),
            reg(Reg#event{obj_id=0, body=maps:put(B, 1, #{})}),
            test_reg_loop(Self, I)
        end).

test_reg_loop(Pid, I) ->
    receive
        {nkservice_event, Event} -> 
            #event{class= <<"c">>, subclass= <<"s">>, type= <<"t">>, 
                   srv_id=srv, obj_id=Id, body=B} = Event,
            [{B1, 1}] = maps:to_list(B),
            Pid ! {c, self(), Id, B1},
            test_reg_loop(Pid, I);
        stop ->
            ok;
        unreg ->
            unreg(#event{class=c, subclass=s, type=t, srv_id=srv, obj_id=I}),
            test_reg_loop(Pid, I);
        _ ->
            error(?LINE)
    after 10000 ->
        ok
    end.


-endif.
