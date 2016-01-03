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
-export([start_link/1, stop_all/1]).
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
-spec start_link(nkservice:service()) ->
    {ok, pid()} | {error, term()}.

start_link(#{id:=Id}=Service) ->
    gen_server:start_link({local, Id}, ?MODULE, Service, []).



%% @private
-spec stop_all(pid()) ->
    ok.

stop_all(Pid) ->
    nklib_util:call(Pid, nkservice_stop_all, 30000).


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
init(#{id:=Id, name:=Name}=Service) ->
    process_flag(trap_exit, true),          % Allow receiving terminate/2
    case nkservice_srv_listen_sup:update_transports(Service) of
        {ok, Listen} ->
            Service2 = Service#{listen_ids=>Listen},
            nkservice_util:make_cache(Service2),
            Class = maps:get(class, Service, undefined),
            nklib_proc:put(?MODULE, {Id, Class}),   
            nklib_proc:put({?MODULE, Name}, Id),   
            io:format("Service: ~p\n", [Service2]),
            {ok, Service2};
        {error, Error} ->
            {stop, {transport_error, Error}}
    end.


%% @private
-spec handle_call(term(), {pid(), term()}, nkservice:service()) ->
    term().

handle_call({nkservice_update, UserSpec}, _From, Service) ->
    case nkservice_util:config_service(UserSpec, Service) of
        {ok, Service2} ->
            case nkservice_srv_listen_sup:update_transports(Service2) of
                {ok, Listen} ->
                    Service3 = Service2#{listen_ids=>Listen},
                    nkservice_util:make_cache(Service3),
                    {Added, Removed} = get_diffs(Service3, Service),
                    lager:info("Added config: ~p", [Added]),
                    lager:info("Removed config: ~p", [Removed]),
                    {reply, ok, Service3};
                {error, Error} ->
                    {reply, {error, Error}, Service}
            end;
        {error, Error} ->
            {reply, {error, Error}, Service}
    end;

handle_call(nkservice_stop_all, _From, Service) ->
    #{plugins:=Plugins} = Service,
    Service2 = nkservice_util:stop_plugins(Plugins, Service),
    {reply, ok, Service2};

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

terminate(Reason, #{id:=Id, name:=Name, plugins:=Plugins}=Service) ->  
    _Service2 = nkservice_util:stop_plugins(Plugins, Service),
    lager:debug("Service ~s (~p) has terminated (~p)", [Name, Id, Reason]).
    


%% ===================================================================
%% Internal
%% ===================================================================


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



