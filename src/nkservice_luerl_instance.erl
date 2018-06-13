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

-module(nkservice_luerl_instance).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([start_link/4, start/4, get_pid/3, get_instances/2, get_num_instances/2, get_all/0]).
-export([spawn_callback_spec/2, call_callback/3, spawn_clean_spec/3]).
-export([call/3, call/4, call_syntax/4, get_table/2, set_table/3]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).

-include("nkservice.hrl").


-define(DEBUG(Txt, Args, State),
    case erlang:get(nkservice_luerl_debug) of
        true -> ?LLOG(debug, Txt, Args, State);
        _ -> ok
    end).

-define(LLOG(Type, Txt, Args, Req),
    lager:Type("NkSERVICE LUERL (~s:~s) (~p) "++Txt,
        [State#state.srv, State#state.module_id, State#state.instance|Args])).



%% ===================================================================
%% Types
%% ===================================================================

-type call_id() :: {nkservice:id(), nkservice:module_id(), instance()} | pid().

-type instance() :: atom() | binary() | reference().

%% Path to locate tables and functions
-type table_name() :: [atom()|binary()].


%% Allowed erlang types
%% - integers will be converted to floats
%% - true, false and nil will be converted to them
%% - other atoms will be converted to binaries
-type erl_type() ::
    erl_basic() | erl_table().

-type erl_basic() ::
    integer() | float() | binary() | atom().

-type erl_table() :: [{erl_type(), erl_type()}] | #{erl_type() => erl_type()}.


%% Returned lua types
-type lua_type() ::
    lua_basic() | lua_table() |
    {function, fun(([lua_type()]) -> [lua_type()])}.

-type lua_basic() ::
    float() | binary() | true | false | nil.

-type lua_table() :: [{lua_type(), lua_type()}].


-type start_opts() ::
    #{
        lua_state => term(),
        monitor => pid()
    }.


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts a LUERL server is we find any matching functions
-spec start_link(nkservice:id(), nkservice:module_id(), instance(), start_opts()) ->
    {ok, pid()}.

start_link(SrvId, ModuleId, Instance, Opts) ->
    gen_server:start_link(?MODULE, [SrvId, ModuleId, Instance, Opts], []).


%% @doc Starts a LUERL server is we find any matching functions
-spec start(nkservice:id(), nkservice:module_id(), instance(), start_opts()) ->
    {ok, pid()}.

start(SrvId, ModuleId, Instance, Opts) ->
    gen_server:start(?MODULE, [SrvId, ModuleId, Instance, Opts], []).


%% @doc Calls a LUA function inside the state
-spec call(call_id(), [atom()|binary()], [erl_type()]) ->
    {ok, [lua_type()]} | {error, term()}.

call(Id, Fun, Args) ->
    call(Id, Fun, Args, 5000).


%% @doc Calls a LUA function inside the state
-spec call(call_id(), [atom()|binary()], [erl_type()], timeout()) ->
    {ok, [lua_type()]} | {error, term()}.

call(Id, Fun, Args, Timeout) ->
    nklib_util:call(get_pid(Id), {call, Fun, Args}, Timeout).


%% @doc Calls a LUA function inside the state with a syntax
-spec call_syntax(call_id(), table_name(), [erl_type()], nklib_syntax:syntax()) ->
    {ok, [lua_type()]} | {error, term()}.

call_syntax(Id, Fun, Args, Syntax) ->
    case call(Id, Fun, Args) of
        {ok, [Reply]} ->
            case nklib_syntax:parse(Reply, Syntax) of
                {ok, Parsed, Unknown} ->
                    {ok, Parsed, Unknown};
                {error, Error} ->
                    {error, Error}
            end;
        {ok, Other} ->
            {error, {invalid_response, Other}};
        {error, Error} ->
            {error, Error}
    end.



%% @doc Gets a table inside the state
%% Can return a table, a value, a function, etc.
-spec get_table(call_id(), table_name()) ->
    {ok, lua_type()} | {error, term()}.

get_table(Id, Name) when is_list(Name) ->
    nklib_util:call(get_pid(Id), {get_table, Name}).


%% @doc Gets a table inside the state
%% Can return a table, a value, a function, etc.
-spec set_table(call_id(), table_name(), lua_type()) ->
    {ok, lua_type()} | {error, term()}.

set_table(Id, Name, Val) when is_list(Name) ->
    nklib_util:call(get_pid(Id), {set_table, Name, Val}).


%% @doc Finds if there is a Luerl callback, and in this case
%% checks max instances and spawns a new instance
spawn_callback_spec(SrvId, CB) ->
    #{class:=luerl, module_id:=ModuleId, luerl_fun:=_} = CB,
    Max = nkservice_util:get_cache(SrvId, nkservice_luerl, ModuleId, max_instances),
    case get_num_instances(SrvId, ModuleId) >= Max of
        true ->
            {error, too_many_instances};
        false ->
            Ref = make_ref(),
            nkservice_luerl_instance:start_link(SrvId, ModuleId, Ref, #{})
    end.


%% @doc Calls a LUA function inside the state with a syntax
-spec call_callback(call_id(), map()|#{luerl_fun=>table_name()}, [erl_type()]) ->
    {ok, [lua_type()]} | {error, term()}.

call_callback(Id, #{luerl_fun:=Fun}, Args) ->
    call(Id, Fun, Args).


%% @doc Generates a child spec for a new instance
spawn_clean_spec(SrvId, ModuleId, Opts) ->
    Ref = make_ref(),
    Child = #{
        id => Ref,
        start => {nkservice_luerl_instance, start_link, [SrvId, ModuleId, Ref, Opts]},
        restart => temporary,
        shutdown => 30000
    },
    {ok, Child}.


%% @private Get Pid
get_pid({Id, ModuleId, Instance}) ->
    get_pid(Id, ModuleId, Instance);
get_pid(Pid) when is_pid(Pid) ->
    Pid.


%% @doc
-spec get_pid(nkservice:id(), nkservice:module_id(), instance()) ->
    pid() | undefined.

get_pid(Id, ModuleId, Instance) ->
    case nklib_proc:values({?MODULE, Id, to_bin(ModuleId), Instance}) of
        [{_, Pid}] ->
            Pid;
        [] ->
            undefined
    end.


%% @doc
-spec get_instances(nkservice:id(), nkservice:module_id()) ->
    [{instance(), pid()}].

get_instances(Id, ModuleId) ->
    nklib_proc:values({?MODULE, Id, to_bin(ModuleId)}).


%% @doc
-spec get_num_instances(nkservice:id(), nkservice:module_id()) ->
    integer().

get_num_instances(Id, ModuleId) ->
    nklib_counters:value({?MODULE, Id, to_bin(ModuleId)}).


%% @doc
-spec get_all() ->
    [{nkservice:id(), nkservice:module_id(), instance(), pid()}].

get_all() ->
    [
        {SrvId, ModuleId, Instance, Pid}
        || {{SrvId, ModuleId, Instance}, Pid} <- nklib_proc:values(?MODULE)
    ].



% ===================================================================
%% gen_server behaviour
%% ===================================================================

-record(state, {
    srv :: nkservice:id(),
    module_id :: nkservice:module_id(),
    instance :: instance(),
    monitor :: reference(),
    luerl :: term()
}).


%% @private
-spec init(term()) ->
    {ok, tuple()} | {ok, tuple(), timeout()|hibernate} |
    {stop, term()} | ignore.

init([SrvId, ModuleId, Instance, Opts]) ->
    LuaState = case Opts of
        #{lua_state:=LuaState0} ->
            LuaState0;
        _ ->
            BinState = ?CALL_SRV(SrvId, service_module_code, [ModuleId]),
            erlang:binary_to_term(BinState)
    end,

    put(srv, SrvId),
    nklib_counters:incr({?MODULE, SrvId, ModuleId}),
    case is_reference(Instance) of
        false ->
            true = nklib_proc:reg({?MODULE, SrvId, ModuleId, Instance});
        true ->
            ok
    end,
    nklib_proc:put({?MODULE, SrvId, ModuleId}, Instance),   % all instances of a module
    nklib_proc:put(?MODULE, {SrvId, ModuleId, Instance}),   % of all modules
    Mon = case Opts of
        #{monitor:=Pid} when is_pid(Pid) ->
            monitor(process, Pid);
        _ ->
            undefined
    end,
    State = #state{
        srv = SrvId,
        module_id = ModuleId,
        instance = Instance,
        monitor = Mon,
        luerl = LuaState
    },
    set_debug(State),
    ?DEBUG("instance started (~p)", [self()], State),
    {ok, State}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}} | {reply, term(), #state{}} |
    {stop, Reason::term(), #state{}} | {stop, Reason::term(), Reply::term(), #state{}}.

handle_call({call, Fun, Args}, _From, #state{luerl=LuaState1}=State) ->
    Start = nklib_util:l_timestamp(),
    try luerl:call_function(Fun, Args, LuaState1) of
        {Res, LuaState2} ->
            Time = nklib_util:l_timestamp() - Start,
            ?DEBUG("call time: ~pusecs", [Time], State),
            {reply, {ok, Res}, State#state{luerl=LuaState2}}
    catch
        error:{lua_error, Reason, _} ->
            {reply, {error, {lua_error, Reason}}, State};
        error:Error ->
            Trace = erlang:get_stacktrace(),
            {reply, {error, {lua_error, {Error, Trace}}}, State}
    end;

handle_call({get_table, Name}, _From, #state{luerl=LuaState1}=State) ->
    try luerl:get_table(Name, LuaState1) of
        {Val, LuaState2} ->
            {reply, {ok, Val}, State#state{luerl=LuaState2}}
    catch
        error:{lua_error, Reason, _} ->
            {reply, {error, {lua_error, Reason}}, State};
        error:Error ->
            Trace = erlang:get_stacktrace(),
            {reply, {error, {lua_error, {Error, Trace}}}, State}
    end;

handle_call({set_table, Name, Value}, _From, #state{luerl=LuaState1}=State) ->
    try luerl:set_table(Name, Value, LuaState1) of
        LuaState2 ->
            {reply, ok, State#state{luerl=LuaState2}}
    catch
        error:{lua_error, Reason, _} ->
            {reply, {error, {lua_error, Reason}}, State};
        error:Error ->
            Trace = erlang:get_stacktrace(),
            {reply, {error, {lua_error, {Error, Trace}}}, State}
    end;

handle_call(Msg, _From, State) ->
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_cast(Msg, State) -> 
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_info({'DOWN', Ref, process, _Pid, _Reason}, #state{monitor=Ref}=State) ->
    ?DEBUG("master process is down: ~p", [_Reason], State),
    {stop, normal, State};

handle_info(Info, State) ->
    lager:warning("Module ~p received unexpected info: ~p (~p)", [?MODULE, Info, State]),
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
    


% ===================================================================
%% Internal
%% ===================================================================

%% @private
set_debug(#state{srv=SrvId, module_id=Id}=State) ->
    Debug = nkservice_util:get_debug(SrvId, nkservice_luerl, Id, debug) == true,
    put(nkservice_luerl_debug, Debug),
    ?DEBUG("debug mode activated", [], State).



%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).
