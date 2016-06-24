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
-export([send_single/4, send_single/5, send_all/4, send_all/5, reg/5, unreg/4]).
-export([start_link/3, get_all/0, remove_all/3, dump/3]).
-export([init/1, terminate/2, code_change/3, handle_call/3, 
         handle_cast/2, handle_info/2]).
% -export([atest/0]).


%% ===================================================================
%% Types
%% ===================================================================

-type class() :: atom().
-type type() :: atom() | '*'.
-type sub() :: atom() | '*'.
-type obj_id() :: term().
-type body() :: term().



%% ===================================================================
%% Public
%% ===================================================================


%% @doc
-spec send_single(class(), type(), sub(), obj_id()) ->
    ok | not_found.

send_single(Class, Type, Sub, Id) ->
    send_single(Class, Type, Sub, Id, #{}).


%% @doc
-spec send_single(class(), type(), sub(), obj_id(), body()) ->
    ok | not_found.

send_single(Class, Type, Sub, Id, Body) ->
    % In each search, we search for Id and Id=='*'
    case do_send_single(Class, Type, Sub, Id, Body) of
        not_found ->
            case do_send_single(Class, Type, '*', Id, Body) of
                not_found ->
                    do_send_single(Class, '*', '*', Id, Body);
                ok ->
                    ok
            end;
        ok ->
            ok
    end.


%% @doc
-spec send_all(class(), type(), sub(), obj_id()) ->
    ok | not_found.

send_all(Class, Type, Sub, Id) ->
    send_all(Class, Type, Sub, Id, #{}).


%% @doc
-spec send_all(class(), type(), sub(), obj_id(), body()) ->
    ok.

send_all(Class, Type, Sub, Id, Body) ->
    do_send_all(Class, Type, Sub, Id, Body),
    do_send_all(Class, Type, '*', Id, Body),
    do_send_all(Class, '*', '*', Id, Body).

%% @doc
-spec reg(class(), type(), sub(), obj_id(), body()) ->
    ok.

reg(Class, Type, Sub, Id, Body) ->
    Server = start_server(Class, Type, Sub),
    gen_server:cast(Server, {reg, Id, Body, self()}).


%% @doc
-spec unreg(class(), type(), sub(), obj_id()) ->
    ok.

unreg(Class, Type, Sub, Id) ->
    Server = start_server(Class, Type, Sub),
    gen_server:cast(Server, {unreg, Id, self()}).


%% @private
get_all() ->
    nklib_proc:values(?MODULE).


%% @private
remove_all(Class, Type, Sub) ->
    case find_server(Class, Type, Sub) of
        {ok, Pid} -> gen_server:cast(Pid, remove_all);
        not_found -> not_found
    end.


%% @private
dump(Class, Type, Sub) ->
    case find_server(Class, Type, Sub) of
        {ok, Pid} -> gen_server:call(Pid, dump);
        not_found -> not_found
    end.



%% ===================================================================
%% gen_server
%% ===================================================================


-record(state, {
    class :: atom(),
    type :: atom(),
    sub :: atom(),
    regs = #{} :: #{obj_id() => [{pid(), term()}]},
    pids = #{} :: #{pid() => {reference(), [obj_id()]}}
}).

%% @private
start_link(Class, Type, Sub) -> 
    gen_server:start_link(?MODULE, [Class, Type, Sub], []).
        

%% @private 
-spec init(term()) ->
    {ok, #state{}}.

init([Class, Type, Sub]) ->
    true = nklib_proc:reg({?MODULE, Class, Type, Sub}),
    nklib_proc:put(?MODULE, {Class, Type, Sub}),
    lager:info("Starting events for ~p:~p:~p (~p)", [Class, Type, Sub, self()]),
    {ok, #state{class=Class, type=Type, sub=Sub}}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {reply, term(), #state{}} | {noreply, #state{}} | {stop, normal, ok, #state{}}.

handle_call({send_single, Type, Sub, Id, Body}, _From, State) ->
    #state{class=Class, regs=Regs} = State,
    % lager:error("Event single: ~p:~p:~p:~p (~p:~p)", 
    %             [Class, Type, Sub, Id, State#state.type, State#state.sub]),
    PidTerms = case maps:get(Id, Regs, []) of
        [] ->
            maps:get('*', Regs, []);
        List ->
            List
    end,
    case PidTerms of
        [] ->
            {reply, not_found, State};
        _ ->
            Pos = nklib_util:l_timestamp() rem length(PidTerms) + 1,
            {Pid, RegBody} = lists:nth(Pos, PidTerms),
            send_event(Class, Type, Sub, Id, Body, Pid, RegBody),
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

handle_cast({send_all, Type, Sub, Id, Body}, #state{class=Class, regs=Regs}=State) ->
    % lager:error("Event all: ~p:~p:~p:~p (~p:~p)", 
    %             [Class, Type, Sub, Id, State#state.type, State#state.sub]),
    PidTerms1 = maps:get(Id, Regs, []),
    lists:foreach(
        fun({Pid, RegBody}) -> 
            send_event(Class, Type, Sub, Id, Body, Pid, RegBody) end,
        PidTerms1),
    PidTerms2 = maps:get('*', Regs, []) -- PidTerms1,
    lists:foreach(
        fun({Pid, RegBody}) -> 
            send_event(Class, Type, Sub, Id, Body, Pid, RegBody) end,
        PidTerms2),
    {noreply, State};

handle_cast({reg, Id, Body, Pid}, #state{regs=Regs, pids=Pids}=State) ->
    {Regs2, Pids2} = do_reg(Id, Body, Pid, Regs, Pids),
    {noreply, State#state{regs=Regs2, pids=Pids2}};

handle_cast({unreg, Id, Pid}, #state{regs=Regs, pids=Pids}=State) ->
    {Regs2, Pids2} = do_unreg([Id], Pid, Regs, Pids),
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
        {ok, {Mon, Ids}} ->
            {Regs2, Pids2} = do_unreg(Ids, Pid, Regs, Pids),
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
do_send_single(Class, Type, Sub, Id, Body) ->
    case find_server(Class, Type, Sub) of
        {ok, Server} -> 
            gen_server:call(Server, {send_single, Type, Sub, Id, Body});
        not_found -> 
            not_found
    end.


%% @private
do_send_all(Class, Type, Sub, Id, Body) ->
    case find_server(Class, Type, Sub) of
        {ok, Server} -> 
            gen_server:cast(Server, {send_all, Type, Sub, Id, Body});
        not_found -> 
            ok
    end.


%% @private
find_server(Class, Type, Sub) ->
    case nklib_proc:values({?MODULE, Class, Type, Sub}) of
        [{undefined, Pid}] ->
            {ok, Pid};
        [] ->
            not_found
end.


%% @private
start_server(Class, Type, Sub) ->
    case find_server(Class, Type, Sub) of
        {ok, Pid} ->
            Pid;
        not_found ->
            Spec = {
                {Class, Type, Sub},
                {?MODULE, start_link, [Class, Type, Sub]},
                permanent,
                5000,
                worker,
                [?MODULE]
            },
            {ok, Pid} = supervisor:start_child(nkservice_events_sup, Spec),
            Pid
    end.


%% @private
do_reg(Id, Body, Pid, Regs, Pids) ->
    Regs2 = case maps:find(Id, Regs) of
        {ok, PidTerms} ->
            maps:put(Id, lists:keystore(Pid, 1, PidTerms, {Pid, Body}), Regs);
        error ->
            maps:put(Id, [{Pid, Body}], Regs)
    end,
    Pids2 = case maps:find(Pid, Pids) of
        {ok, {Mon, Ids}} ->
            maps:put(Pid, {Mon, nklib_util:store_value(Id, Ids)}, Pids);
        error ->
            Mon = monitor(process, Pid),
            maps:put(Pid, {Mon, [Id]}, Pids)
    end,
    {Regs2, Pids2}.




%% @private
do_unreg([], _Pid, Regs, Pids) ->
    {Regs, Pids};

do_unreg([Id|Rest], Pid, Regs, Pids) ->
    Regs2 = case maps:find(Id, Regs) of
        {ok, PidTerms} ->
            case lists:keydelete(Pid, 1, PidTerms) of
                [] ->
                    maps:remove(Id, Regs);
                PidTerms2 ->
                    maps:put(Id, PidTerms2, Regs)
            end;
        error ->
            Regs
    end,
    Pids2 = case maps:find(Pid, Pids) of
        {ok, {Mon, Ids}} ->
            case Ids -- [Id] of
                [] ->
                    demonitor(Mon),
                    maps:remove(Pid, Pids);
                Ids2 ->
                    maps:put(Pid, {Mon, Ids2}, Pids)
            end;
        error ->
            Pids
    end,
    do_unreg(Rest, Pid, Regs2, Pids2).


%% @private
send_event(Class, Type, Sub, Id, Body, Pid, RegBody) ->
    % lager:info("Sending event ~p:~p:~p:~p to ~p (~p)",
    %            [Class, Type, Sub, Id, Pid, Body]),
    Body2 = case is_map(Body) andalso is_map(RegBody) of
        true -> maps:merge(RegBody, Body);
        false when map_size(Body)==0 -> RegBody;
        false -> RegBody
    end,
    Pid ! {nkservice_event, Class, Type, Sub, Id, Body2}.





%% ===================================================================
%% EUnit tests
%% ===================================================================


-define(TEST, 1).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

basic_test_() ->
    {setup, 
        fun() -> 
            ?debugFmt("Starting ~p", [?MODULE]),
            case find_server(c, t, s) of
                not_found ->
                    {ok, _} = gen_server:start(?MODULE, [c, t, s], []),
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
    Self = self(),
    reg(c, t, s, id1, b1),
    reg(c, t, s, id2, b2),
    {
        [
            {id1, [{Self, b1}]}, 
            {id2, [{Self, b2}]}
        ],
        [{Self, {_, [id2, id1]}}]
    } = 
        dump(c, t, s),

    unreg(c, t, s, id1),
    {
        [{id2, [{Self, b2}]}],
        [{Self, {_, [id2]}}]
    } = 
        dump(c, t, s),

    unreg(c, t, s, id3),
    unreg(c, t, s, id2),
    {[], []} = dump(c, t, s),
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

    lists:foreach(
        fun(_) ->
            send_single(c, t, s, 0),
            receive 
                {c, _RP1, 0, RB1} -> true = lists:member(RB1, [b1, b1b, b2, b3, b3b, b7])
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            send_single(c, t, s, 1),
            receive 
                {c, _RP2, 1, RB2} -> true = lists:member(RB2, [b1, b1b, b7])
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            send_single(c, t, s, 2),
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
            send_single(c, t, s, 3),
            receive 
                {c, _RP3, 3, RB2} -> true = lists:member(RB2, [b3, b3b, b7])
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    lists:foreach(
        fun(_) ->
            send_single(c, t, s, 25),
            receive 
                {c, P7, 25, b7} -> ok
                after 100 -> error(?LINE) 
            end
        end,
        lists:seq(1, 100)),

    send_all(c, t, s, 0),
    receive {c, P1, 0, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P2, 0, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P3, 0, b1b} -> ok after 100 -> error(?LINE) end,
    receive {c, P4, 0, b2} -> ok after 100 -> error(?LINE) end,
    receive {c, P5, 0, b3} -> ok after 100 -> error(?LINE) end,
    receive {c, P6, 0, b3b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 0, b7} -> ok after 100 -> error(?LINE) end,

    send_all(c, t, s, 1),
    receive {c, P1, 1, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P2, 1, b1} -> ok after 100 -> error(?LINE) end,
    receive {c, P3, 1, b1b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 1, b7} -> ok after 100 -> error(?LINE) end,

    send_all(c, t, s, 2),
    receive {c, P4, 2, b2} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 2, b7} -> ok after 100 -> error(?LINE) end,

    send_all(c, t, s, 3),
    receive {c, P5, 3, b3} -> ok after 100 -> error(?LINE) end,
    receive {c, P6, 3, b3b} -> ok after 100 -> error(?LINE) end,
    receive {c, P7, 3, b7} -> ok after 100 -> error(?LINE) end,

    send_all(c, t, s, 33),
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
            {0, [{P1, b1}, {P2, b1}, {P3, b1b}, {P4, b2}, {P5, b3}, {P6, b3b}, {P7, b7}]},
            {1, [{P1, b1}, {P2, b1}, {P3, b1b}]},
            {2, [{P4, b2}]},
            {3, [{P5, b3}, {P6, b3b}]},
            {'*', [{P7, b7}]}
        ],
        [
            {P1, {_, [0,1]}},
            {P2, {_, [0,1]}},
            {P3, {_, [0,1]}},
            {P4, {_, [0,2]}},
            {P5, {_, [0,3]}},
            {P6, {_, [0,3]}},
            {P7, {_, [0,'*']}}
        ]
    }
        = dump(c, t, s),

    P1 ! stop,
    P4 ! unreg,
    timer:sleep(100),
    {
        [
            {0, [{P2, b1}, {P3, b1b}, {P4, b2}, {P5, b3}, {P6, b3b}, {P7, b7}]},
            {1, [{P2, b1}, {P3, b1b}]},
            {3, [{P5, b3}, {P6, b3b}]},
            {'*', [{P7, b7}]}
        ],
        [
            {P2, {_, [0,1]}},
            {P3, {_, [0,1]}},
            {P4, {_, [0]}},
            {P5, {_, [0,3]}},
            {P6, {_, [0,3]}},
            {P7, {_, [0,'*']}}
        ]
    } = 
        dump(c, t, s),

    [P ! stop || P <- [P1, P2, P3, P4, P5, P6, P7]],
    ok.


test_reg(I, B) ->
    Self = self(),
    spawn(
        fun() -> 
            reg(c, t, s, I, B),
            reg(c, t, s, 0, B),
            test_reg_loop(Self, I)
        end).

test_reg_loop(Pid, I) ->
    receive
        {nkservice_event, c, t, s, Id, Body} -> 
            Pid ! {c, self(), Id, Body},
            test_reg_loop(Pid, I);
        stop ->
            ok;
        unreg ->
            unreg(c, t, s, I),
            test_reg_loop(Pid, I);
        _ ->
            error(?LINE)
    after 10000 ->
        ok
    end.


-endif.
