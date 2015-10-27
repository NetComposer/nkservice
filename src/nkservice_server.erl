%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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

-module(nkservice_server).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([start/2, stop/1, get/2, get/3, put/3, put_new/3, del/2]).
-export([get_srv_id/1, get_pid/1]).
-export([call/2, call/3, cast/2, get_spec/1, get_cache/2]).
-export([start_link/1, update/2, send_stop/1, get_all/0, get_all/1]).
-export([pending_msgs/0]).
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2,
         handle_info/2]).

-include("nkservice.hrl").

-type service_select() :: nkservice:id() | nkservice:name().
-type user() :: map().


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts a new service.
-spec start(nkservice:name(), nkservice:spec()) ->
    ok | {error, term()}.

start(Name, Spec) ->
    Id = nkservice:make_id(Name),
    try
        case get_srv_id(Id) of
            {ok, OldId} -> 
                case is_pid(whereis(OldId)) of
                    true -> throw(already_started);
                    false -> ok
                end;
            not_found -> 
                ok
        end,
        Spec1 = case nkservice_util:parse_syntax(Spec) of
            {ok, Parsed} -> Parsed;
            {error, ParseError} -> throw(ParseError)
        end,
        CacheKeys = maps:keys(nkservice_syntax:defaults()),
        ConfigCache = maps:with(CacheKeys, Spec1),
        Spec2 = Spec1#{id=>Id, name=>Name, cache=>ConfigCache},
        % lager:warning("Parsed: ~p", [Parsed2]),
        case nkservice_service_sup:start_service(Spec2) of
            ok ->
                {ok, Id};
            {error, Error} -> 
                {error, Error}
        end
    catch
        throw:Throw -> {error, Throw}
    end.



%% @doc Stops a service
-spec stop(service_select()) ->
    ok | {error, service_not_found}.

stop(Srv) ->
    case get_srv_id(Srv) of
        {ok, Id} ->
            case nkservice_service_sup:stop_service(Id) of
                ok -> 
                    ok;
                error -> 
                    {error, service_not_found}
            end;
        not_found ->
            {error, service_not_found}
    end.



%% @private
-spec update(service_select(), nkservice:spec()) ->
    ok | {error, term()}.

update(Srv, Spec) ->
    case get_srv_id(Srv) of
        {ok, Id} ->
            call(Id, {nkservice_update, Spec}, 30000);
        not_found ->
            {error, service_not_found}
    end.

    

%% @doc Gets the internal name of an existing service
-spec get_srv_id(service_select()) ->
    {ok, nkservice:id(), pid()} | not_found.

get_srv_id(Srv) ->
    case is_atom(Srv) andalso erlang:function_exported(Srv, plugin_start, 1) of
        true ->
            {ok, Srv};
        false ->
            find_name(Srv)
    end.


%% @doc Gets the internal name of an existing service
-spec get_pid(service_select()) ->
    {ok, pid()} | not_running.

get_pid(Srv) ->
    case get_srv_id(Srv) of
        {ok, SrvId} ->
            case whereis(SrvId) of
                Pid when is_pid(Pid) -> Pid;
                _ -> not_running
            end;
        not_found ->
            not_running
    end.


%% @doc Gets a value from service's store
-spec get(service_select(), term()) ->
    term().

get(Srv, Key) ->
    get(Srv, Key, undefined).

%% @doc Gets a value from service's store
-spec get(service_select(), term(), term()) ->
    term().

get(Srv, Key, Default) ->
    case get_srv_id(Srv) of
        {ok, Id} ->
            case catch ets:lookup(Id, Key) of
                [{_, Value}] -> Value;
                [] -> Default;
                _ -> error(service_not_found)
            end;
        not_found ->
            error(service_not_found)
    end.

%% @doc Inserts a value in service's store
-spec put(service_select(), term(), term()) ->
    ok.

put(Srv, Key, Value) ->
    case get_srv_id(Srv) of
        {ok, Id} ->
            case catch ets:insert(Id, {Key, Value}) of
                true -> ok;
                _ -> error(service_not_found)
            end;
        not_found ->
            error(service_not_found)
    end.


%% @doc Deletes a value from service's store
-spec del(service_select(), term()) ->
    ok.

del(Srv, Key) ->
    case get_srv_id(Srv) of
        {ok, Id} ->
            case catch ets:delete(Id, Key) of
                true -> ok;
                _ -> error(service_not_found)
            end;
        not_found ->
            error(service_not_found)
    end.


%% @doc Inserts a value in service's store
-spec put_new(service_select(), term(), term()) ->
    true | false.

put_new(Srv, Key, Value) ->
    case get_srv_id(Srv) of
        {ok, Id} ->
            case catch ets:insert_new(Id, {Key, Value}) of
                true -> true;
                false -> false;
                _ -> error(service_not_found)
            end;
        not_found ->
            error(service_not_found)
    end.


%% @doc Synchronous call to the service's gen_server process
-spec call(service_select(), term()) ->
    term().

call(Srv, Term) ->
    call(Srv, Term, 5000).


%% @doc Synchronous call to the service's gen_server process with a timeout
-spec call(service_select(), term(), pos_integer()|infinity|default) ->
    term().

call(Srv, Term, Time) ->
    case get_srv_id(Srv) of
        {ok, Id} -> 
            gen_server:call(Id, Term, Time);
        not_found -> 
            error(service_not_found)
    end.


%% @doc Asynchronous call to the service's gen_server process
-spec cast(service_select(), term()) ->
    term().

cast(Srv, Term) ->
    case get_srv_id(Srv) of
        {ok, Id} -> 
            gen_server:cast(Id, Term);
        not_found -> 
            error(service_not_found)
    end.


%% @doc Gets current service configuration
-spec get_spec(service_select()) ->
    nkservice:spec().

get_spec(Srv) ->
    get_cache(Srv, spec).


%% ===================================================================
%% Private
%% ===================================================================


%% @private
-spec start_link(nkservice:spec()) ->
    {ok, pid()} | {error, term()}.

start_link(#{id:=Id}=Spec) ->
    gen_server:start_link({local, Id}, ?MODULE, Spec, []).



%% @private
-spec send_stop(pid()) ->
    ok.

send_stop(Pid) ->
    gen_server:cast(Pid, '$nkservice_stop').


%% @doc Gets all started services
-spec get_all() ->
    [{nkservice:id(), nkservice:name(), nkservice:class(), pid()}].

get_all() ->
    [{Id, Id:name(), Class, Pid} || 
     {{Id, Class}, Pid}<- nklib_proc:values(?MODULE)].


%% @doc Gets all started services
-spec get_all(nkservice:class()) ->
    [{nkservice:id(), nkservice:name(), pid()}].

get_all(Class) ->
    [{Id, Name, Pid} || {Id, Name, C, Pid} <- get_all(), C==Class].


%% @private
-spec find_name(nkservice:name()) ->

    {ok, nkservice:id()} | not_found.

find_name(Name) ->
    case nklib_proc:values({?MODULE, Name}) of
        [] -> not_found;
        [{Id, _Pid}|_] -> {ok, Id}
    end.


%% @doc Gets current service configuration
-spec get_cache(service_select(), atom()) ->
    term().

get_cache(Srv, Field) ->
    case get_srv_id(Srv) of
        {ok, Id} -> 
            case Id:Field() of
                {map, Bin} -> binary_to_term(Bin);
                Other -> Other
            end;
        not_found ->
            error(service_not_found)
    end.


%% @private
pending_msgs() ->
    lists:map(
        fun({_Id, Name, _Class, Pid}) ->
            {_, Len} = erlang:process_info(Pid, message_queue_len),
            {Name, Len}
        end,
        get_all()).



%% ===================================================================
%% gen_server
%% ===================================================================


-record(state, {
    id :: nkservice:id(),
    user = #{} :: user()
}).

-define(P1, #state.id).
-define(P2, #state.user).


%% @private
init(#{id:=Id, name:=Name}=Spec) ->
    process_flag(trap_exit, true),          % Allow receiving terminate/2
    Class = maps:get(class, Spec, undefined),
    nklib_proc:put(?MODULE, {Id, Class}),   
    nklib_proc:put({?MODULE, Name}, Id),   
    case do_start(Spec) of
        {ok, Spec2} ->
            case Id:init(Spec2, #{id=>Id}) of
                {ok, User} -> {ok, #state{id=Id, user=User}};
                {ok, User, Timeout} -> {ok, #state{id=Id, user=User}, Timeout};
                {stop, Reason} -> {stop, Reason}
            end;
        {error, Error} ->
            {stop, Error}
    end.


%% @private
-spec handle_call(term(), nklib_util:gen_server_from(), #state{}) ->
    nklib_util:gen_server_call(#state{}).

handle_call({nkservice_update, Spec}, _From, #state{id=Id}=State) ->
    {reply, do_update(Spec#{id=>Id}), State};

handle_call(state, _From, State) ->
    {reply, State, State};

handle_call(Msg, From, State) ->
    nklib_gen_server:handle_call(Msg, From, State, ?P1, ?P2).


%% @private
-spec handle_cast(term(), #state{}) ->
    nklib_util:gen_server_cast(#state{}).

handle_cast('$nkservice_stop', State) ->
    {stop, normal, State};

handle_cast(Msg, State) ->
    nklib_gen_server:handle_cast(Msg, State, ?P1, ?P2).


%% @private
-spec handle_info(term(), #state{}) ->
    nklib_util:gen_server_info(#state{}).

handle_info(Msg, State) ->
    nklib_gen_server:handle_info(Msg, State, ?P1, ?P2).
    

%% @private
-spec code_change(term(), #state{}, term()) ->
    {ok, #state{}} | {error, term()}.

code_change(OldVsn, State, Extra) ->
    nklib_gen_server:code_change(OldVsn, State, Extra, ?P1, ?P2).


%% @private
-spec terminate(term(), #state{}) ->
    nklib_util:gen_server_terminate().

terminate(Reason, #state{id=Id}=State) ->  
	Plugins = lists:reverse(Id:plugins()),
    lager:debug("Service terminated (~p): ~p", [Reason, Plugins]),
    do_stop_plugins(Plugins, get_spec(Id)),
    catch nklib_gen_server:terminate(Reason, State, ?P1, ?P2).
    


%% ===================================================================
%% Internal
%% ===================================================================


%% @private
do_start(Spec) ->
    Plugins1 = maps:get(plugins, Spec, []),
    Plugins2 = case Spec of
        #{callback:=CallBack} -> [{CallBack, all}|Plugins1];
        _ -> Plugins1
    end,
    case nkservice_cache:get_plugins(Plugins2) of
        {ok, Plugins3} ->
            Spec1 = Spec#{plugins=>Plugins3},
            case do_start_plugins(Plugins3, Spec1) of
                {ok, Spec2} ->
                    case nkservice_cache:make_cache(Spec2) of
                        ok -> 
                            {ok, Spec2};
                        {error, Error} -> 
                            {error, Error}
                    end;
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.

      
%% @private
do_start_plugins([], Spec) ->
    {ok, Spec};

do_start_plugins([Plugin|Rest], Spec) ->
    lager:debug("Service ~p starting plugin ~p", [maps:get(id, Spec), Plugin]),
    code:ensure_loaded(Plugin),
    case nkservice_util:safe_call(Plugin, plugin_start, [Spec]) of
        not_exported ->
            do_start_plugins(Rest, Spec);
        {ok, Spec1} ->
            do_start_plugins(Rest, Spec1);
        {stop, Reason} ->
            {error, {could_not_start_plugin, {Plugin, Reason}}};
        _ ->
            {error, {could_not_start_plugin, Plugin}}
    end.


%% @private
do_stop_plugins([], Spec) ->
    {ok, Spec};

do_stop_plugins([Plugin|Rest], Spec) ->
    lager:debug("Service ~p stopping plugin ~p", [maps:get(id, Spec), Plugin]),
    case nkservice_util:safe_call(Plugin, plugin_stop, [Spec]) of
    	{ok, Spec1} ->
    		do_stop_plugins(Rest, Spec1);
    	_ ->
    		do_stop_plugins(Rest, Spec)
    end.


%% @private
do_update(#{id:=Id}=Spec) ->
    try
        OldSpec = get_spec(Id),
        Syntax = nkservice_syntax:syntax(),
        % We don't use OldSpec as a default, since values not in syntax()
        % would be taken from OldSpec insted than from Spec
        Spec1 = case nkservice_util:parse_syntax(Spec, Syntax) of
            {ok, Parsed} -> Parsed;
            {error, ParseError} -> throw(ParseError)
        end,
        Spec2 = maps:merge(OldSpec, Spec1),
        OldPlugins = Id:plugins(),
        NewPlugins1 = maps:get(plugins, Spec2),
        NewPlugins2 = case Spec2 of
            #{callback:=CallBack} -> 
                [{CallBack, all}|NewPlugins1];
            _ ->
                NewPlugins1
        end,
        ToStart = case nkservice_cache:get_plugins(NewPlugins2) of
            {ok, AllPlugins} -> AllPlugins;
            {error, GetError} -> throw(GetError)
        end,
        ToStop = lists:reverse(OldPlugins--ToStart),
        lager:info("Server ~p plugins to stop: ~p, start: ~p", 
                   [Id, ToStop, ToStart]),
        CacheKeys = maps:keys(nkservice_syntax:defaults()),
        Spec3 = Spec2#{
            plugins => ToStart,
            cache => maps:with(CacheKeys, Spec2)
        },
        {ok, Spec4} = do_stop_plugins(ToStop, Spec3),
        case do_start_plugins(ToStart, Spec4) of
            {ok, Spec5} ->
                {Added, Removed} = get_diffs(Spec5, OldSpec),
                lager:info("Added config: ~p", [Added]),
                lager:info("Removed config: ~p", [Removed]),
                nkservice_cache:make_cache(Spec5);
            {error, StartError} ->
                {error, StartError}
        end
    catch
        throw:Throw -> {error, Throw}
    end.


%% private
get_diffs(Map1, Map2) ->
    Add = get_diffs(nklib_util:to_list(Map1), Map2, []),
    Rem = get_diffs(nklib_util:to_list(Map2), Map1, []),
    {maps:from_list(Add), maps:from_list(Rem)}.


%% private
get_diffs([], _, Acc) ->
    Acc;

get_diffs([{cache, _}|Rest], Map, Acc) ->
    get_diffs(Rest, Map, Acc);

get_diffs([{Key, Val}|Rest], Map, Acc) ->
    Acc1 = case maps:find(Key, Map) of
        {ok, Val} -> Acc;
        _ -> [{Key, Val}|Acc]
    end,
    get_diffs(Rest, Map, Acc1).



