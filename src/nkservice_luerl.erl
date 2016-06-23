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

-module(nkservice_luerl).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([start_link/4, get_all/0]).
-export([call/3, get_table/2, set_table/3, kv_get/2]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).


%% ===================================================================
%% Types
%% ===================================================================

%% Path to locate tables and functions
-type name() :: [atom()].


%% Allowed erlang types
%% - integers will be converted to floats
%% - true, false and nil will be converted to them
%% - other atoms will be converted to binaries
-type erl_type() ::
    erl_basic() | erl_table().

-type erl_basic() ::
    integer() | float() | binary() | atom().

-type erl_table() :: [{erl_type(), erl_type()}].


%% Returned lua types
-type lua_type() ::
    lua_basic() | lua_table() |
    {function, fun(([lua_type()]) -> [lua_type()])}.

-type lua_basic() ::
    float() | binary() | true | false | nil.

-type lua_table() :: [{lua_type(), lua_type()}].


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts a LUERL server is we find any matching functions
-spec start_link(nkservice:id(), [atom()], name(), lua_table()) -> 
    {ok, Funs::[atom()], pid()} | false.

start_link(SrvId, Funs, Name, Table) 
        when is_list(Name) andalso (is_list(Table) orelse is_map(Table)) ->
    case erlang:function_exported(SrvId, lua_funs, 0) of
        true ->
            LuaFuns = nkservice_srv:get_item(SrvId, lua_funs),
            case 
                lists:takewhile(
                    fun(Fun) -> lists:member(Fun, LuaFuns) end,
                    Funs)
            of
                [] ->
                    false;
                Funs2 ->
                    {ok, Pid} = 
                        gen_server:start_link(?MODULE, [SrvId, Name, Table], []),
                    {ok, Funs2, Pid}
            end;
        false ->
            false
    end.


%% @doc Calls a LUA function inside the state
-spec call(pid(), [atom()], [erl_type()]) ->
    {ok, [lua_type()]} | {error, term()}.

call(Pid, Fun, Args) ->
    gen_server:call(Pid, {call, Fun, Args}).


%% @doc Gets a table inside the state
%% Can return a table, a value, a function, etc.
-spec get_table(pid(), name()) ->
    {ok, lua_type()} | {error, term()}.

get_table(Pid, Name) when is_list(Name) ->
    nklib_util:call(Pid, {get_table, Name}).


%% @doc Gets a table inside the state
%% Can return a table, a value, a function, etc.
-spec set_table(pid(), name(), lua_type()) ->
    {ok, lua_type()} | {error, term()}.

set_table(Pid, Name, Val) when is_list(Name) ->
    nklib_util:call(Pid, {set_table, Name, Val}).



%% @doc Gets a value from KV (using nkservice_luerl_kv/2) but decoding it
%% using the stored context
%% You can get:
%% - a float, binary, 'true', 'false', 'nil'
%% - a table (a list of [{term(), term()}])
%% - a function ({function, Fun}). Fun has full context, and has arity 1
%%   you can call it as Fun([Args])
-spec kv_get(pid(), lua_type()) ->
    {ok, lua_type()} | {ok, undefined} | {error, term()}.

kv_get(Pid, Key) ->
    nklib_util:call(Pid, {kv_get, Key}).


get_all() ->
    nklib_proc:values(?MODULE).



% ===================================================================
%% gen_server behaviour
%% ===================================================================

-record(state, {
    srv_id :: nkservice:id(),
    luerl :: term()
}).


%% @private
-spec init(term()) ->
    {ok, tuple()} | {ok, tuple(), timeout()|hibernate} |
    {stop, term()} | ignore.

init([SrvId, Name, Table]) ->
    nklib_proc:put(?MODULE, {SrvId, Name}),
    Luerl1 = binary_to_term(nkservice_srv:get_item(SrvId, lua_state)),
    Table2 = case is_map(Table) of
        true -> maps:to_list(Table);
        false -> Table
    end,
    Luerl2 = luerl:set_table(Name, Table2, Luerl1),
    %% We put the srv_id in the process dictionary so that we have
    %% it when calling erlang functions (for example in nkservice_luerl_kv)
    put(srv_id, SrvId),
    {ok, #state{srv_id=SrvId, luerl=Luerl2}}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}} | {reply, term(), #state{}} |
    {stop, Reason::term(), #state{}} | {stop, Reason::term(), Reply::term(), #state{}}.

handle_call({call, Fun, Args}, _From, #state{luerl=Luerl}=State) ->
    try luerl:call_function(Fun, Args, Luerl) of
        {Val, Luerl2} ->
            {reply, {ok, Val}, State#state{luerl=Luerl2}}
    catch
        Class:Error ->
            Reply = {error, {Class, {Error, erlang:get_stacktrace()}}},
            {reply, Reply, State}
    end;

handle_call({get_table, Name}, _From, #state{luerl=Luerl}=State) ->
    try luerl:get_table(Name, Luerl) of
        {Val, _} ->
            {reply, {ok, Val}, State}
    catch
        Class:Error ->
            Reply = {error, {Class, {Error, erlang:get_stacktrace()}}},
            {reply, Reply, State}
    end;

handle_call({set_table, Name, Value}, _From, #state{luerl=Luerl}=State) ->
    try luerl:set_table(Name, Value, Luerl) of
        Luerl2 ->
            {reply, ok, State#state{luerl=Luerl2}}
    catch
        Class:Error ->
            Reply = {error, {Class, {Error, erlang:get_stacktrace()}}},
            {reply, Reply, State}
    end;

handle_call({kv_get, Key}, _From, #state{srv_id=SrvId, luerl=Luerl}=State) ->
    case nkservice_luerl_kv:erl_get(SrvId, Key) of
        {ok, undefined} ->
            {reply, {ok, undefined}, State};
        {ok, Val} ->
            lager:error("Val: ~p", [Val]),
            try luerl:decode(Val, Luerl) of
                ErlVal ->
                    {reply, {ok, ErlVal}, State}
            catch
                Class:Error ->
                    Reply = {error, {Class, {Error, erlang:get_stacktrace()}}},
                    {reply, Reply, State}
            end
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

