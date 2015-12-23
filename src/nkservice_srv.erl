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

-module(nkservice_srv).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([find_name/1, get_srv_id/1, get_from_mod/2]).
-export([start_link/2, stop/1]).
-export([pending_msgs/0]).
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2,
         handle_info/2]).

-include("nkservice.hrl").

-type service_select() :: nkservice:id() | nkservice:name().


%% ===================================================================
%% Public
%% ===================================================================

%% @private Finds a service's id from its name
-spec find_name(nkservice:name()) ->
    {ok, nkservice:id()} | not_found.

find_name(Name) ->
    case nklib_proc:values({?MODULE, Name}) of
        [] -> not_found;
        [{Id, _Pid}|_] -> {ok, Id}
    end.


%% @doc Gets the internal name of an existing service
-spec get_srv_id(service_select()) ->
    {ok, nkservice:id(), pid()} | not_found.

get_srv_id(Srv) ->
    case 
        is_atom(Srv) andalso erlang:function_exported(Srv, service_init, 2) 
    of
        true ->
            {ok, Srv};
        false ->
            find_name(Srv)
    end.


%% @doc Gets current service configuration
-spec get_from_mod(service_select(), atom()) ->
    term().

get_from_mod(Srv, Field) ->
    case get_srv_id(Srv) of
        {ok, Id} -> 
            case Id:Field() of
                {map, Bin} -> binary_to_term(Bin);
                Other -> Other
            end;
        not_found ->
            error({service_not_found, Srv})
    end.




%% ===================================================================
%% Private
%% ===================================================================


%% @private
-spec start_link(nkservice:user_spec(), nkservice:service()) ->
    {ok, pid()} | {error, term()}.

start_link(UserSpec, #{id:=Id}=Service) ->
    gen_server:start_link({local, Id}, ?MODULE, {UserSpec, Service}, []).



%% @private
-spec stop(pid()) ->
    ok.

stop(Pid) ->
    gen_server:cast(Pid, nkservice_stop).


%% @private
pending_msgs() ->
    lists:map(
        fun({_Id, Name, _Class, Pid}) ->
            {_, Len} = erlang:process_info(Pid, message_queue_len),
            {Name, Len}
        end,
        nkservice:get_all()).



%% ===================================================================
%% gen_server
%% ===================================================================


%% @private
init({UserSpec, #{id:=Id, name:=Name}=Service}) ->
    process_flag(trap_exit, true),          % Allow receiving terminate/2
    case do_start(UserSpec, Service) of
        {ok, Service2} ->
            Class = maps:get(class, Service2, undefined),
            nklib_proc:put(?MODULE, {Id, Class}),   
            nklib_proc:put({?MODULE, Name}, Id),   
            lager:notice("Service ~s (~p) has started (~p)", [Name, Id, self()]),
            {ok, Service2};
        {error, Error} ->
            {stop, Error}
    end.


%% @private
-spec handle_call(term(), {pid(), term()}, nkservice:service()) ->
    term().

handle_call({nkservice_update, UserSpec}, _From, Service) ->
    {reply, do_update(UserSpec, Service)};

handle_call(nkservice_state, _From, Service) ->
    {reply, Service, Service};

handle_call(Msg, From, #{id:=Id}=Service) ->
    Id:service_handle_call(Msg, From, Service).


%% @private
-spec handle_cast(term(), nkservice:service()) ->
    term().

handle_cast(nkservice_stop, State)->
    {stop, normal, State};

handle_cast(Msg, #{id:=Id}=Service) ->
    Id:service_handle_cast(Msg, Service).


%% @private
-spec handle_info(term(), nkservice:service()) ->
    nklib_util:gen_server_info(nkservice:service()).

handle_info(Msg, #{id:=Id}=Service) ->
    Id:service_handle_info(Msg, Service).
    

%% @private
-spec code_change(term(), nkservice:service(), term()) ->
    {ok, nkservice:service()} | {error, term()}.

code_change(OldVsn, #{id:=Id}=Service, Extra) ->
    Id:service_code_change(OldVsn, Service, Extra).


%% @private
-spec terminate(term(), nkservice:service()) ->
    nklib_util:gen_server_terminate().

terminate(Reason, #{id:=Id, name:=Name}=Service) ->  
	Plugins = lists:reverse(Id:plugins()),
    do_stop_plugins(Plugins, Service),
    lager:debug("Service ~s (~p) has terminated (~p)", [Name, Id, Reason]).
    


%% ===================================================================
%% Internal
%% ===================================================================


%% @private
do_start(UserSpec, Service) ->
    try
        Plugins1 = maps:get(plugins, Service),
        CallBack = maps:get(callback, Service, none),
        Plugins3 = case nkservice_cache:get_plugins(Plugins1, CallBack) of
            {ok, AllPlugins} -> 
                AllPlugins;
            {error, PlugError} -> 
                throw(PlugError)
        end,
        % ok = do_init_plugins(lists:reverse(Plugins3)),
        Service2 = do_start_plugins(Plugins3, UserSpec, Service, []),
        case nkservice_cache:make_cache(Service2) of
            ok -> 
                {ok, Service2};
            {error, Error} -> 
                throw(Error)
        end
    catch
        throw:Throw -> {error, Throw}
    end.

      
% %% @private
% do_init_plugins([]) ->
%     ok;

% do_init_plugins([Plugin|Rest]) ->
%     case nklib_util:apply(Plugin, plugin_init, []) of
%         not_exported ->
%             do_init_plugins(Rest);
%         ok ->
%             do_init_plugins(Rest);
%         {error, Error} ->
%             throw({plugin_init_error, {Plugin, Error}});
%         Other ->
%             lager:warning("Invalid response from ~p:plugin_init/1: ~p", [Plugin, Other]),
%             throw({invalid_plugin, {Plugin, invalid_init}})
%     end.


%% @private
%% Plugins should update only 'cache', 'transports' and they own key
do_start_plugins([], _UserSpec, Service, _Started) ->
    Service;

do_start_plugins([Plugin|Rest], UserSpec, Service, Started) ->
    #{id:=Id, name:=Name} = Service,
    lager:debug("Service ~s (~p) starting plugin ~p", [Name, Id, Plugin]),
    Data = nkservice_app:get({plugin, Plugin}),
    Callback = maps:get(callback, Data, Plugin),
    code:ensure_loaded(Callback),
    case nklib_util:apply(Plugin, plugin_init, [UserSpec, Service]) of
        not_exported ->
            do_start_plugins(Rest, UserSpec, Service, [Plugin|Started]);
        {ok, Service2} ->
            do_start_plugins(Rest, UserSpec, Service2, [Plugin|Started]);
        {stop, Reason} ->
            _Spec2 = do_stop_plugins(Started, Service),
            throw({could_not_start_plugin, {Plugin, Reason}})
    end.


%% @private
do_stop_plugins([], Service) ->
    Service;

do_stop_plugins([Plugin|Rest], #{id:=Id, name:=Name}=Service) ->
    lager:debug("Service ~s (~p) stopping plugin ~p", [Name, Id, Plugin]),
    case nklib_util:apply(Plugin, plugin_stop, [Service]) of
    	{ok, Service2} ->
    		do_stop_plugins(Rest, Service2);
    	_ ->
    		do_stop_plugins(Rest, Service)
    end.


%% @private
do_update(UserSpec, #{id:=Id}=Spec) ->
    try
        OldSpec = nkservice:get_spec(Id),
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
        Spec4 = do_stop_plugins(ToStop, Spec3),
        Spec5 = do_syntax(ToStart, Spec4),
        Spec6 = do_start_plugins(ToStart, Spec5, []),
        case Spec6 of
            #{transports:=Transports} ->
                case 
                    nkservice_transp_sup:start_transports(Transports, Spec6) 
                of
                    ok -> 
                        ok;
                    {error, Error} ->
                        throw(Error)
                end;
            _ ->
                ok
        end,
        {Added, Removed} = get_diffs(Spec6, OldSpec),
        lager:info("Added config: ~p", [Added]),
        lager:info("Removed config: ~p", [Removed]),
        nkservice_cache:make_cache(Spec6)
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



