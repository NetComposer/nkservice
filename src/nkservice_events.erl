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
-export([send_single/1, send_single/2]).
-export([send_all/1, send_all/2]).
-export([reg/1, reg/2, reg/3, unreg/1, unreg/2]).
-export([start_link/3, get_all/0, remove_all/3, dump/3]).
-export([init/1, terminate/2, code_change/3, handle_call/3, 
         handle_cast/2, handle_info/2]).
% -export([atest/0]).

-include("nkservice.hrl").


%% ===================================================================
%% Types
%% ===================================================================

-type reg_id() :: #reg_id{}.

-type class() :: atom().
-type type() :: atom() | '*'.
-type obj() :: atom() | '*'.
-type srv_id() :: nkservice:id() | '*'.
-type obj_id() :: term().
-type body() :: term().



%% ===================================================================
%% Public
%% ===================================================================


%% @doc
-spec send_single(reg_id()) ->
    ok | not_found.

send_single(RegId) ->
    send_single(RegId, #{}).


%% @doc
-spec send_single(reg_id(), body()) ->
    ok | not_found.

send_single(#reg_id{}=RegId, Body) ->
    #reg_id{class=Class, type=Type, obj=Obj, srv_id=SrvId, obj_id=ObjId} = RegId,
    % In each search, we search for Id and Id=='*'
    case do_send_single(Class, Type, Obj, SrvId, ObjId, Body) of
        not_found ->
            case do_send_single(Class, {Type, '*'}, Obj, SrvId, ObjId, Body) of
                not_found ->
                    do_send_single(Class, {Type, '*'}, {Obj, '*'}, SrvId, ObjId, Body);
                ok ->
                    ok
            end;
        ok ->
            ok
    end.


%% @doc
-spec send_all(reg_id()) ->
    ok | not_found.

send_all(RegId) ->
    send_all(RegId, {}).


%% @doc
-spec send_all(reg_id(), body()) ->
    ok | not_found.

send_all(#reg_id{}=RegId, Body) ->
    #reg_id{class=Class, type=Type, obj=Obj, srv_id=SrvId, obj_id=ObjId} = RegId,
    do_send_all(Class, Type, Obj, SrvId, ObjId, Body),
    do_send_all(Class, {Type, '*'}, Obj, SrvId, ObjId, Body),
    do_send_all( Class, {Type, '*'}, {Obj, '*'}, SrvId, ObjId, Body).


%% @doc
-spec reg(reg_id()) ->
    {ok, pid()}.

reg(RegId) ->
    reg(RegId, #{}, self()).


%% @doc
-spec reg(reg_id(), body()) ->
    {ok, pid()}.

reg(RegId, Body) ->
    reg(RegId, Body, self()).


%% @doc
-spec reg(reg_id(), body(), pid()) ->
    {ok, pid()}.

reg(#reg_id{}=RegId, Body, Pid) ->
    #reg_id{class=Class, type=Type, obj=Obj, srv_id=SrvId, obj_id=ObjId} = RegId,
    Type2 = check_all(Type),
    Obj2 = check_all(Obj),
    ObjId2 = check_all(ObjId),
    Server = start_server(Class, Type2, Obj2),
    gen_server:cast(Server, {reg, SrvId, ObjId2, Body, Pid}),
    {ok, Server}.


%% @doc
-spec unreg(reg_id()) ->
    {ok, pid()}.

unreg(RegId) ->
    unreg(RegId, self()).


%% @doc
-spec unreg(reg_id(), pid()) ->
    ok.

unreg(#reg_id{}=RegId, Pid) ->
    #reg_id{class=Class, type=Type, obj=Obj, srv_id=SrvId, obj_id=ObjId} = RegId,
    Type2 = check_all(Type),
    Obj2 = check_all(Obj),
    ObjId2 = check_all(ObjId),
    Server = start_server(Class, Type2, Obj2),
    gen_server:cast(Server, {unreg, SrvId, ObjId2, Pid}).



%% @private
get_all() ->
    nklib_proc:values(?MODULE).


%% @private
remove_all(Class, Type, Obj) ->
    case find_server(Class, Type, Obj) of
        {ok, Pid} -> gen_server:cast(Pid, remove_all);
        not_found -> not_found
    end.


%% @private
dump(Class, Type, Obj) ->
    case find_server(Class, Type, Obj) of
        {ok, Pid} -> gen_server:call(Pid, dump);
        not_found -> not_found
    end.



%% ===================================================================
%% gen_server
%% ===================================================================

-type key() :: {srv_id(), obj_id()}.

-record(state, {
    class :: atom(),
    type :: atom(),
    obj :: atom(),
    regs = #{} :: #{key() => [{pid(), body()}]},
    pids = #{} :: #{pid() => {reference(), [key()]}}
}).

%% @private
start_link(Class, Type, Obj) -> 
    gen_server:start_link(?MODULE, [Class, Type, Obj], []).
        

%% @private 
-spec init(term()) ->
    {ok, #state{}}.

init([Class, Type, Obj]) ->
    true = nklib_proc:reg({?MODULE, Class, Type, Obj}),
    nklib_proc:put(?MODULE, {Class, Type, Obj}),
    lager:info("Starting events for ~p:~p:~p (~p)", [Class, Type, Obj, self()]),
    {ok, #state{class=Class, type=Type, obj=Obj}}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {reply, term(), #state{}} | {noreply, #state{}} | {stop, normal, ok, #state{}}.

handle_call({send_single, Type, Obj, SrvId, ObjId, Body}, _From, State) ->
    #state{class=Class, regs=Regs} = State,
    RegId = #reg_id{class=Class, type=Type, obj=Obj, srv_id=SrvId, obj_id=ObjId},
    PidTerms = case maps:get({SrvId, ObjId}, Regs, []) of
        [] ->
            maps:get({SrvId, '*'}, Regs, []);
        List ->
            List
    end,
    % lager:error("Event single: ~p:~p:~p:~p (~p:~p): ~p", 
    %             [Class, Type, Obj, Id, State#state.type, State#state.sub,
    %              PidTerms]),
    case PidTerms of
        [] ->
            {reply, not_found, State};
        _ ->
            Pos = nklib_util:l_timestamp() rem length(PidTerms) + 1,
            {Pid, RegBody} = lists:nth(Pos, PidTerms),
            send_event(RegId, Body, Pid, RegBody),
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

handle_cast({send_all, Type, Obj, SrvId, ObjId, Body}, State) ->
    #state{class=Class, regs=Regs} = State,
    RegId = #reg_id{class=Class, type=Type, obj=Obj, srv_id=SrvId, obj_id=ObjId},
    % lager:error("Event all: ~p:~p:~p:~p (~p:~p)", 
    %             [Class, Type, Obj, Id, State#state.type, State#state.sub]),
    PidTerms1 = maps:get({SrvId, ObjId}, Regs, []),
    lists:foreach(
        fun({Pid, RegBody}) -> 
            send_event(RegId, Body, Pid, RegBody) end,
        PidTerms1),
    PidTerms2 = maps:get({SrvId, '*'}, Regs, []) -- PidTerms1,
    lists:foreach(
        fun({Pid, RegBody}) -> 
            send_event(RegId, Body, Pid, RegBody) end,
        PidTerms2),
    PidTerms3 = maps:get({'*', '*'}, Regs, []) -- PidTerms1 -- PidTerms2,
    lists:foreach(
        fun({Pid, RegBody}) -> 
            send_event(RegId, Body, Pid, RegBody) end,
        PidTerms3),
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
check_all(<<"*">>) -> '*';
check_all(Any) -> Any.


%% @private
do_send_single(Class, Type, Obj, SrvId, ObjId, Body) ->
    case Type of
        {TypeC, TypeS} -> ok;
        TypeC -> TypeS = TypeC
    end,
    case Obj of
        {ObjC, ObjS} -> ok;
        ObjC -> ObjS = ObjC
    end,
    case find_server(Class, TypeS, ObjS) of
        {ok, Server} -> 
            gen_server:call(Server, {send_single, TypeC, ObjC, SrvId, ObjId, Body});
        not_found -> 
            not_found
    end.


%% @private
do_send_all(Class, Type, Obj, SrvId, ObjId, Body) ->
    case Type of
        {TypeC, TypeS} -> ok;
        TypeC -> TypeS = TypeC
    end,
    case Obj of
        {ObjC, ObjS} -> ok;
        ObjC -> ObjS = ObjC
    end,
    case find_server(Class, TypeS, ObjS) of
        {ok, Server} -> 
            gen_server:cast(Server, {send_all, TypeC, ObjC, SrvId, ObjId, Body});
        not_found -> 
            ok
    end.


%% @private
find_server(Class, Type, Obj) ->
    case nklib_proc:values({?MODULE, Class, Type, Obj}) of
        [{undefined, Pid}] ->
            {ok, Pid};
        [] ->
            not_found
end.


%% @private
start_server(Class, Type, Obj) ->
    case find_server(Class, Type, Obj) of
        {ok, Pid} ->
            Pid;
        not_found ->
            Spec = {
                {Class, Type, Obj},
                {?MODULE, start_link, [Class, Type, Obj]},
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
send_event(#reg_id{}=RegId, Body, Pid, RegBody) ->
    % lager:info("Sending event ~p:~p:~p:~p to ~p (~p)",
    %            [Class, Type, Obj, Id, Pid, Body]),
    Body2 = case is_map(Body) andalso is_map(RegBody) of
        true -> maps:merge(RegBody, Body);
        false when map_size(Body)==0 -> RegBody;
        false -> RegBody
    end,
    Pid ! {nkservice_event, RegId, Body2}.





%% ===================================================================
%% EUnit tests
%% ===================================================================


% -define(TEST, 1).
% -ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-compile([export_all]).

basic_test_() ->
    {setup, 
        fun() -> 
            ?debugFmt("Starting ~p", [?MODULE]),
            case find_server(c, t, o) of
                not_found ->
                    {ok, _} = gen_server:start(?MODULE, [c, t, o], []),
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
    Reg = #reg_id{class=c, type=t, obj=o, srv_id=srv},
    Self = self(),
    reg(Reg#reg_id{obj_id=id1}, b1),
    reg(Reg#reg_id{obj_id=id2}, b2),
    {
        [
            {{srv, id1}, [{Self, b1}]}, 
            {{srv, id2}, [{Self, b2}]}
        ],
        [{Self, {_, [{srv, id2}, {srv, id1}]}}]
    } = 
        dump(c, t, o),

    unreg(Reg#reg_id{obj_id=id1}),
    {
        [{{srv, id2}, [{Self, b2}]}],
        [{Self, {_, [{srv, id2}]}}]
    } = 
        dump(c, t, o),

    unreg(Reg#reg_id{obj_id=id3}),
    unreg(Reg#reg_id{obj_id=id2}),
    {[], []} = dump(c, t, o),
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

    Reg = #reg_id{class=c, type=t, obj=o, srv_id=srv},
    lists:foreach(
        fun(_) ->
            send_single(Reg#reg_id{obj_id=0}),
            receive 
                {c, _RP1, 0, RB1} -> true = lists:member(RB1, [b1, b1b, b2, b3, b3b, b7]);
                O -> error(O)
                after 100 -> error(?LINE) 
                
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            send_single(Reg#reg_id{obj_id=1}),
            receive 
                {c, _RP2, 1, RB2} -> true = lists:member(RB2, [b1, b1b, b7])
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            send_single(Reg#reg_id{obj_id=2}),
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
            send_single(Reg#reg_id{obj_id=3}),
            receive 
                {c, _RP3, 3, RB2} -> true = lists:member(RB2, [b3, b3b, b7])
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            send_single(Reg#reg_id{obj_id=25}),
            receive 
                {c, P7, 25, b7} -> ok
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    send_all(Reg#reg_id{obj_id=0}),
    receive {c, P1, 0, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P2, 0, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P3, 0, b1b} -> ok after 100 -> error(?LINE) end,
    receive {c, P4, 0, b2} -> ok after 100 -> error(?LINE) end,
    receive {c, P5, 0, b3} -> ok after 100 -> error(?LINE) end,
    receive {c, P6, 0, b3b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 0, b7} -> ok after 100 -> error(?LINE) end,

    send_all(Reg#reg_id{obj_id=1}),
    receive {c, P1, 1, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P2, 1, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P3, 1, b1b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 1, b7} -> ok after 100 -> error(?LINE) end,

    send_all(Reg#reg_id{obj_id=2}),
    receive {c, P4, 2, b2} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 2, b7} -> ok after 100 -> error(?LINE) end,

    send_all(Reg#reg_id{obj_id=3}),
    receive {c, P5, 3, b3} -> ok after 100 -> error(?LINE) end,
    receive {c, P6, 3, b3b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 3, b7} -> ok after 100 -> error(?LINE) end,

    send_all(Reg#reg_id{obj_id=33}),
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
        = dump(c, t, o),

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
        dump(c, t, o),

    [P ! stop || P <- [P1, P2, P3, P4, P5, P6, P7]],
    ok.


test_reg(I, B) ->
    Reg = #reg_id{class=c, type=t, obj=o, srv_id=srv},
    Self = self(),
    spawn(
        fun() -> 
            reg(Reg#reg_id{obj_id=I}, B),
            reg(Reg#reg_id{obj_id=0}, B),
            test_reg_loop(Self, I)
        end).

test_reg_loop(Pid, I) ->
    receive
        {nkservice_event, RegId, Body} -> 
            #reg_id{class=c, type=t, obj=o, srv_id=srv, obj_id=Id} = RegId,
            Pid ! {c, self(), Id, Body},
            test_reg_loop(Pid, I);
        stop ->
            ok;
        unreg ->
            unreg(#reg_id{class=c, type=t, obj=o, srv_id=srv, obj_id=I}),
            test_reg_loop(Pid, I);
        _ ->
            error(?LINE)
    after 10000 ->
        ok
    end.


% -endif.
