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
-export([call/1, call/2]).
-export([start_link/3, get_all/0, remove_all/3, dump/3]).
-export([init/1, terminate/2, code_change/3, handle_call/3, 
         handle_cast/2, handle_info/2]).
% -export([atest/0]).

-include("nkservice.hrl").


%% ===================================================================
%% Types
%% ===================================================================

-type event() :: #event{}.

-type srv_id() :: nkservice:id() | '*'.
-type class() :: term().
-type subclass() :: term() | '*'.
-type type() :: term() | '*'.
-type obj_id() :: term().
-type body() :: term().



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Send to an specific pid() if registered
-spec send(event()) ->
    ok | not_found.

send(#event{}=Event) ->
    % lager:info("EVENT: ~p ~p", [Event, Body]),
    #event{
        class = Class, 
        subclass = Sub, 
        type = Type, 
        srv_id = SrvId, 
        obj_id = ObjId,
        body = Body,
        pid = Pid
    } = Event,
    Class2 = nklib_util:to_binary(Class),
    Sub2 = check_wildcard(Sub),
    Type2 = check_wildcard(Type),
    ObjId2 = check_wildcard(ObjId),
    do_send(Class2, Sub2, Type2, SrvId, ObjId2, Body, Pid),
    do_send(Class2, Sub2, {Type2, '*'}, SrvId, ObjId2, Body, Pid),
    do_send(Class2, {Sub2, '*'}, {Type2, '*'}, SrvId, ObjId2, Body, Pid).


%% @doc
-spec call(event()) ->
    ok | not_found.

call(Event) ->
    call(Event, #{}).


%% @doc
-spec call(event(), body()) ->
    ok | not_found.

call(#event{}=Event, Body) ->
    #event{
        class = Class, 
        subclass = Sub, 
        type = Type, 
        srv_id = SrvId, 
        obj_id = ObjId
    } = Event,
    Class2 = nklib_util:to_binary(Class),
    Sub2 = check_wildcard(Sub),
    Type2 = check_wildcard(Type),
    ObjId2 = check_wildcard(ObjId),
    % In each search, we search for Id and Id=='*'
    case do_call(Class2, Sub2, Type2, SrvId, ObjId2, Body) of
        not_found ->
            case do_call(Class2, Sub2, {Type2, '*'}, SrvId, ObjId2, Body) of
                not_found ->
                    do_call(Class2, {Sub2, '*'}, {Type2, '*'}, SrvId, ObjId2, Body);
                ok ->
                    ok
            end;
        ok ->
            ok
    end.


%% @doc
%% body and pid are not used for registration index
-spec reg(event()) ->
    {ok, pid()}.

reg(#event{}=Event) ->
    #event{
        class = Class, 
        subclass = Sub, 
        type = Type, 
        srv_id = SrvId, 
        obj_id = ObjId,
        body = Body,
        pid = Pid
    } = Event,
    Pid2 = case Pid of
        undefined -> self();
        _ -> Pid
    end,
    Class2 = nklib_util:to_binary(Class),
    Sub2 = check_wildcard(Sub),
    Type2 = check_wildcard(Type),
    ObjId2 = check_wildcard(ObjId),
    Server = start_server(Class2, Sub2, Type2),
    gen_server:cast(Server, {reg, SrvId, ObjId2, Body, Pid2}),
    {ok, Server}.


%% @doc
-spec unreg(event()) ->
    ok.

unreg(#event{}=Event) ->
    #event{
        class = Class, 
        subclass = Sub, 
        type = Type, 
        srv_id = SrvId, 
        obj_id = ObjId,
        pid  =  Pid
    } = Event,
    Pid2 = case Pid of
        undefined -> self();
        _ -> Pid
    end,
    Class2 = nklib_util:to_binary(Class),
    Sub2 = check_wildcard(Sub),
    Type2 = check_wildcard(Type),
    ObjId2 = check_wildcard(ObjId),
    Server = start_server(Class2, Sub2, Type2),
    gen_server:cast(Server, {unreg, SrvId, ObjId2, Pid2}).



%% @private
get_all() ->
    nklib_proc:values(?MODULE).


%% @private
remove_all(Class, Sub, Type) ->
    case find_server(Class, Sub, Type) of
        {ok, Pid} -> gen_server:cast(Pid, remove_all);
        not_found -> not_found
    end.


%% @private
dump(Class, Sub, Type) ->
    case find_server(Class, Sub, Type) of
        {ok, Pid} -> gen_server:call(Pid, dump);
        not_found -> not_found
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
    lager:info("Starting events for ~p:~p:~p (~p)", [Class, Sub, Type, self()]),
    {ok, #state{class=Class, sub=Sub, type=Type}}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {reply, term(), #state{}} | {noreply, #state{}} | {stop, normal, ok, #state{}}.

handle_call({call, Sub, Type, SrvId, ObjId, Body}, _From, State) ->
    #state{class=Class, regs=Regs} = State,
    Event = #event{class=Class, subclass=Sub, type=Type, srv_id=SrvId, obj_id=ObjId},
    PidTerms = case maps:get({SrvId, ObjId}, Regs, []) of
        [] ->
            maps:get({SrvId, '*'}, Regs, []);
        List ->
            List
    end,
    % lager:error("Event single: ~p:~p:~p:~p (~p:~p): ~p", 
    %             [Class, Sub, Type, ObjId, State#state.sub, State#state.type,
    %              PidTerms]),
    case PidTerms of
        [] ->
            {reply, not_found, State};
        _ ->
            Pos = nklib_util:l_timestamp() rem length(PidTerms) + 1,
            {Pid, RegBody} = lists:nth(Pos, PidTerms),
            send_events([{Pid, RegBody}], Event, Body, all),
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

handle_cast({send, Sub, Type, SrvId, ObjId, Body, PidSpec}, State) ->
    #state{class=Class, regs=Regs} = State,
    Event = #event{class=Class, subclass=Sub, type=Type, srv_id=SrvId, obj_id=ObjId},
    PidTerms1 = maps:get({SrvId, ObjId}, Regs, []),
    PidTerms2 = maps:get({SrvId, '*'}, Regs, []) -- PidTerms1,
    PidTerms3 = maps:get({'*', '*'}, Regs, []) -- PidTerms1 -- PidTerms2,
    % lager:error("Event all: ~p (~p:~p): ~p,~p,~p", 
    %             [lager:pr(Event, ?MODULE), State#state.sub, State#state.type,
    %             PidTerms1, PidTerms2, PidTerms3]),
    send_events(PidTerms1, Event, Body, PidSpec),
    send_events(PidTerms2, Event, Body, PidSpec),
    send_events(PidTerms3, Event, Body, PidSpec),
    {noreply, State};

handle_cast({reg, SrvId, ObjId, Body, Pid}, #state{regs=Regs, pids=Pids}=State) ->
    {Regs2, Pids2} = do_reg(SrvId, ObjId, Body, Pid, Regs, Pids),
    {noreply, State#state{regs=Regs2, pids=Pids2}};

handle_cast({unreg, SrvId, ObjId, Pid}, #state{regs=Regs, pids=Pids}=State) ->
    {Regs2, Pids2} = do_unreg([{SrvId, ObjId}], Pid, Regs, Pids),
    {noreply, State#state{regs=Regs2, pids=Pids2}};

handle_cast(remove_all, #state{pids=Pids}=State) ->
    lists:foreach(fun({_Pid, {Mon, _}}) -> demonitor(Mon) end, maps:to_list(Pids)),
    {noreply, State#state{regs=#{}, pids=#{}}};

handle_cast(Msg, State) ->
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}}.

handle_info({'DOWN', Mon, process, Pid, _Reason}, #state{regs=Regs, pids=Pids}=State) ->
    case maps:find(Pid, Pids) of
        {ok, {Mon, Keys}} ->
            {Regs2, Pids2} = do_unreg(Keys, Pid, Regs, Pids),
            {noreply, State#state{regs=Regs2, pids=Pids2}};
        error ->
            lager:warning("Module ~p received unexpected down: ~p", [?MODULE, Pid]),
            {noreply, State}
    end;

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

terminate(_Reason, _State) ->  
    ok.



%% ===================================================================
%% Private
%% ===================================================================

%% @private
check_wildcard('*') -> '*';
check_wildcard(<<"*">>) -> '*';
check_wildcard(Any) -> nklib_util:to_binary(Any).


%% @private
do_call(Class, Sub, Type, SrvId, ObjId, Body) ->
    case Sub of
        {SubC, SubS} -> ok;
        SubC -> SubS = SubC
    end,
    case Type of
        {TypeC, TypeS} -> ok;
        TypeC -> TypeS = TypeC
    end,
    case find_server(Class, SubS, TypeS) of
        {ok, Server} -> 
            gen_server:call(Server, {call, SubC, TypeC, SrvId, ObjId, Body});
        not_found -> 
            not_found
    end.


%% @private
do_send(Class, Sub, Type, SrvId, ObjId, Body, Pid) ->
    case Sub of
        {SubC, SubS} -> ok;
        SubC -> SubS = SubC
    end,
    case Type of
        {TypeC, TypeS} -> ok;
        TypeC -> TypeS = TypeC
    end,
    case find_server(Class, SubS, TypeS) of
        {ok, Server} -> 
            gen_server:cast(Server, {send, SubC, TypeC, SrvId, ObjId, Body, Pid});
        not_found -> 
            ok
    end.


%% @private
find_server(Class, Sub, Type) ->
    case nklib_proc:values({?MODULE, Class, Sub, Type}) of
        [{undefined, Pid}] ->
            {ok, Pid};
        [] ->
            not_found
end.


%% @private
start_server(Class, Sub, Type) ->
    case find_server(Class, Sub, Type) of
        {ok, Pid} ->
            Pid;
        not_found ->
            Spec = {
                {Class, Sub, Type},
                {?MODULE, start_link, [Class, Sub, Type]},
                permanent,
                5000,
                worker,
                [?MODULE]
            },
            {ok, Pid} = supervisor:start_child(nkservice_events_sup, Spec),
            Pid
    end.


%% @private
do_reg(SrvId, ObjId, Body, Pid, Regs, Pids) ->
    Key = {SrvId, ObjId},
    Regs2 = case maps:find(Key, Regs) of
        {ok, PidTerms} ->
            maps:put(Key, lists:keystore(Pid, 1, PidTerms, {Pid, Body}), Regs);
        error ->
            maps:put(Key, [{Pid, Body}], Regs)
    end,
    Pids2 = case maps:find(Pid, Pids) of
        {ok, {Mon, Keys}} ->
            maps:put(Pid, {Mon, nklib_util:store_value(Key, Keys)}, Pids);
        error ->
            Mon = monitor(process, Pid),
            maps:put(Pid, {Mon, [Key]}, Pids)
    end,
    {Regs2, Pids2}.


%% @private
do_unreg([], _Pid, Regs, Pids) ->
    {Regs, Pids};

do_unreg([Key|Rest], Pid, Regs, Pids) ->
    Regs2 = case maps:find(Key, Regs) of
        {ok, PidTerms} ->
            case lists:keydelete(Pid, 1, PidTerms) of
                [] ->
                    maps:remove(Key, Regs);
                PidTerms2 ->
                    maps:put(Key, PidTerms2, Regs)
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
    do_unreg(Rest, Pid, Regs2, Pids2).



%% @private
send_events([], _Event, _Body, _PidSpec) ->
    ok;

send_events([{Pid, _}|Rest], Event, Body, PidS) when is_pid(PidS), Pid/=PidS ->
    send_events(Rest, Event, Body, PidS);

send_events([{Pid, RegBody}|Rest], #event{}=Event, Body, PidS) ->
    % lager:info("Sending event ~p to ~p (~p)", 
    %            [lager:pr(Event, ?MODULE), Pid, Body]),
    Body2 = case {is_map(Body), is_map(RegBody)} of
        {true, true} -> maps:merge(RegBody, Body);
        {true, false} -> Body;
        {false, true} -> RegBody;
        {false, false} -> Body
    end,
    Pid ! {nkservice_event, Event, Body2},
    send_events(Rest, Event, Body, PidS).





%% ===================================================================
%% EUnit tests
%% ===================================================================


% -define(TEST, 1).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-compile([export_all]).

basic_test_() ->
    {setup, 
        fun() -> 
            ?debugFmt("Starting ~p", [?MODULE]),
            case find_server(c, s, t) of
                not_found ->
                    {ok, _} = gen_server:start(?MODULE, [c, s, t], []),
                    do_stop;
                _ -> 
                    ok
            end
        end,
        fun(Stop) -> 
            case Stop of 
                do_stop -> exit(whereis(?MODULE), kill);
                ok -> ok
            end
        end,
        [
            fun test1/0,
            fun test2/0,
            fun test3/0
        ]
    }.

% -compile([export_all]).

test1() ->
    Reg = #event{class=c, subclass=s, type=t, srv_id=srv},
    Self = self(),
    reg(Reg#event{obj_id=id1, body=b1}),
    reg(Reg#event{obj_id=id2, body=b2}),
    {
        [
            {{srv, id1}, [{Self, b1}]}, 
            {{srv, id2}, [{Self, b2}]}
        ],
        [{Self, {_, [{srv, id2}, {srv, id1}]}}]
    } = 
        dump(c, s, t),

    unreg(Reg#event{obj_id=id1}),
    {
        [{{srv, id2}, [{Self, b2}]}],
        [{Self, {_, [{srv, id2}]}}]
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
    P7 = test_reg('*', b7),
    timer:sleep(50),

    Reg = #event{class=c, subclass=s, type=t, srv_id=srv},
    lists:foreach(
        fun(_) ->
            call(Reg#event{obj_id=0}),
            receive 
                {c, _RP1, 0, RB1} -> true = lists:member(RB1, [b1, b1b, b2, b3, b3b, b7]);
                O -> error(O)
                after 100 -> error(?LINE) 
                
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            call(Reg#event{obj_id=1}),
            receive 
                {c, _RP2, 1, RB2} -> true = lists:member(RB2, [b1, b1b, b7])
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            call(Reg#event{obj_id=2}),
            receive 
                {c, RP3, 2, RB2} -> 
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
                {c, _RP3, 3, RB2} -> true = lists:member(RB2, [b3, b3b, b7])
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            call(Reg#event{obj_id=25}),
            receive 
                {c, P7, 25, b7} -> ok
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    send(Reg#event{obj_id=0}),
    receive {c, P1, 0, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P2, 0, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P3, 0, b1b} -> ok after 100 -> error(?LINE) end,
    receive {c, P4, 0, b2} -> ok after 100 -> error(?LINE) end,
    receive {c, P5, 0, b3} -> ok after 100 -> error(?LINE) end,
    receive {c, P6, 0, b3b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 0, b7} -> ok after 100 -> error(?LINE) end,

    send(Reg#event{obj_id=1}),
    receive {c, P1, 1, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P2, 1, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P3, 1, b1b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 1, b7} -> ok after 100 -> error(?LINE) end,

    send(Reg#event{obj_id=2}),
    receive {c, P4, 2, b2} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 2, b7} -> ok after 100 -> error(?LINE) end,

    send(Reg#event{obj_id=3}),
    receive {c, P5, 3, b3} -> ok after 100 -> error(?LINE) end,
    receive {c, P6, 3, b3b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 3, b7} -> ok after 100 -> error(?LINE) end,

    send(Reg#event{obj_id=33}),
    receive {c, P7, 33, b7} -> ok after 100 -> error(?LINE) end,

    receive _ -> error(?LINE) after 100 -> ok end,

    [P ! stop || P <- [P1, P2, P3, P4, P5, P6, P7]],
    ok.


test3() ->
    P1 = test_reg(1, b1),
    P2 = test_reg(1, b1),
    P3 = test_reg(1, b1b),
    P4 = test_reg(2, b2),
    P5 = test_reg(3, b3),
    P6 = test_reg(3, b3b),
    P7 = test_reg('*', b7),
    timer:sleep(50),

    {
        [
            {{srv, 0}, 
                [{P1, b1}, {P2, b1}, {P3, b1b}, {P4, b2}, {P5, b3}, {P6, b3b}, {P7, b7}]},
            {{srv, 1}, [{P1, b1}, {P2, b1}, {P3, b1b}]},
            {{srv, 2}, [{P4, b2}]},
            {{srv, 3}, [{P5, b3}, {P6, b3b}]},
            {{srv, '*'}, [{P7, b7}]}
        ],
        [
            {P1, {_, [{srv, 0}, {srv, 1}]}},
            {P2, {_, [{srv, 0}, {srv, 1}]}},
            {P3, {_, [{srv, 0}, {srv, 1}]}},
            {P4, {_, [{srv, 0}, {srv, 2}]}},
            {P5, {_, [{srv, 0}, {srv, 3}]}},
            {P6, {_, [{srv, 0}, {srv, 3}]}},
            {P7, {_, [{srv, 0}, {srv, '*'}]}}
        ]
    }
        = dump(c, s, t),

    P1 ! stop,
    P4 ! unreg,
    timer:sleep(100),
    {
        [
            {{srv, 0}, [{P2, b1}, {P3, b1b}, {P4, b2}, {P5, b3}, {P6, b3b}, {P7, b7}]},
            {{srv, 1}, [{P2, b1}, {P3, b1b}]},
            {{srv, 3}, [{P5, b3}, {P6, b3b}]},
            {{srv, '*'}, [{P7, b7}]}
        ],
        [
            {P2, {_, [{srv, 0}, {srv, 1}]}},
            {P3, {_, [{srv, 0}, {srv, 1}]}},
            {P4, {_, [{srv, 0}]}},
            {P5, {_, [{srv, 0}, {srv, 3}]}},
            {P6, {_, [{srv, 0}, {srv, 3}]}},
            {P7, {_, [{srv, 0}, {srv, '*'}]}}
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
            reg(Reg#event{obj_id=I, body=B}),
            reg(Reg#event{obj_id=0, body=B}),
            test_reg_loop(Self, I)
        end).

test_reg_loop(Pid, I) ->
    receive
        {nkservice_event, Event, Body} -> 
            #event{class=c, subclass=s, type=t, srv_id=srv, obj_id=Id} = Event,
            Pid ! {c, self(), Id, Body},
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
