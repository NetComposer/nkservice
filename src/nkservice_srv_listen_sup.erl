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

%% @private
-module(nkservice_srv_listen_sup).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(supervisor).

-export([update_transports/1, start_link/1, init/1]).

-include_lib("nkpacket/include/nkpacket.hrl").
-include("nkservice.hrl").


%% @doc Starts all transports associated to a service.
%% If a transport already exists, it is skipped 
-spec update_transports(nkservice:service()) ->
    {ok, #{Plugin::atom() => [nkpacket:listen_id()]}} | {error, term()}.

update_transports(Service) ->
    #{
        id := Id, 
        name := Name,
        listen := Listen, 
        listen_ids := ListenIds
    } = Service,
    start_transports1(Id, Name, maps:to_list(Listen), ListenIds).


%% @private
-spec start_link(nkservice:service()) -> 
    {ok, pid()} | {error, term()}.

start_link(#{id:=Id}) ->
    ChildSpec = {{one_for_one, 10, 60}, []},
    supervisor:start_link(?MODULE, {Id, ChildSpec}).


%% @private
init({Id, ChildSpecs}) ->
    yes = nklib_proc:register_name({?MODULE, Id}, self()),
    {ok, ChildSpecs}.


%% @private Tries to start all the configured transports for a Server.
-spec start_transports1(nkservice:id(), binary(), list(), map()) ->
    {ok, map()} | {error, term()}.

start_transports1(Id, Name, [{Plugin, Listen}|Rest], Started) ->
    case start_transports2(Id, Name, Plugin, Listen, Started) of
        {ok, Started2} ->
            start_transports1(Id, Name, Rest, Started2);
        {error, Error} ->
            {error, Error}
    end;

start_transports1(_Id, _Name, [], Started) ->
    {ok, Started}.



%% @private Tries to start all the configured transports for a Server.
-spec start_transports2(nkservice:id(), binary(), atom(), list(),  map()) ->
    {ok, map()} | {error, term()}.

start_transports2(Id, Name, Plugin, [{Conns, Opts}|Rest], Started) ->
    % Options that can be configured globally
    case start_transports3(Id, Name, Plugin, Conns, Opts, Started) of
        {ok, Started2} ->
            start_transports2(Id, Name, Plugin, Rest, Started2);
        {error, Error} ->
            {error, Error}
    end;

start_transports2(_Id, _Name, _Plugin, [], Started) ->
    {ok, Started}.


%% @private
start_transports3(Id, Name, Plugin, [Conn|Rest], Opts, Started) ->
    {_Proto, Transp, _Ip, _Port} = Conn,
    case nkpacket:get_listener(Conn, Opts) of
        {ok, Child} ->
            case add_transport(Id, Name, Child) of
                {ok, ListenId} ->
                    ListenIds1 = maps:get(Plugin, Started, []),
                    ListenIds2 = nklib_util:store_value(ListenId, ListenIds1),
                    Started2 = maps:put(Plugin, ListenIds2, Started),
                    start_transports3(Id, Name, Plugin, Rest, Opts, Started2);
                {error, Error} ->
                    {error, {could_not_start, {Transp, Error}}}
            end;
        {error, Error} ->
            {error, {could_not_start, {Transp, Error}}}
    end;

start_transports3(_Id, _Name, _Plugin, [], _Opts, Started) ->
    {ok, Started}.


%% @private Starts a new transport control process under this supervisor
-spec add_transport(nkservice:id(), binary(), any()) ->
    {ok, nkpacket:listen_id()} | {error, term()}.

add_transport(SrvId, Name, Spec) ->
    {Conn, _Ref} = element(1, Spec),
    {_, _, [NkPort]} = element(2, Spec),
    TranspId = nkpacket_util:get_id(NkPort),
    SupPid = get_pid(SrvId),
    case find_started(supervisor:which_children(SupPid), TranspId) of
        false ->
            Spec2 = setelement(1, Spec, {Conn, TranspId}),
            case supervisor:start_child(SupPid, Spec2) of
                {ok, Pid} ->
                    {registered_name, ListenId} = process_info(Pid, registered_name),
                    {ok, {Proto, Transp, Ip, Port}} = nkpacket:get_local(Pid),
                    lager:info("Service '~s' started listener on ~p:~p:~p (~p)",
                               [Name, Transp, Ip, Port, Proto]),
                    {ok, ListenId};
                {error, {Error, _}} ->
                    {error, Error};
                {error, Error} ->
                    {error, Error}
            end;
        {true, Conn, Pid} ->
            lager:info("Skipping started transport ~p (~p)", [Conn, TranspId]),
            {registered_name, ListenId} = process_info(Pid, registered_name),
            {ok, ListenId}
    end.

%% @private
find_started([], _TranspId) ->
    false;

find_started([{{Conn, TranspId}, Pid, worker, _}|_], TranspId) when is_pid(Pid) ->
    {true, Conn, Pid};

find_started([_|Rest], TranspId) ->
    find_started(Rest, TranspId).


%% @private Gets the service's transport supervisor's pid()
-spec get_pid(nkservice:id()) ->
    pid() | undefined.

get_pid(SrvId) ->
    nklib_proc:whereis_name({?MODULE, SrvId}).




