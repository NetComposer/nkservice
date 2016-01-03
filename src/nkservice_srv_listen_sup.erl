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
        listen := Listen, 
        listen_ids := ListenIds, 
        config_nkservice := Config
    } = Service,
    #config{net_opts=Opts} = Config,
    start_transports1(Id, maps:to_list(Listen), maps:from_list(Opts), ListenIds).


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
-spec start_transports1(nkservice:id(), list(), map(), map()) ->
    {ok, map()} | {error, term()}.

start_transports1(Id, [{Plugin, Listen}|Rest], NetOpts, Started) ->
    case start_transports2(Id, Plugin, Listen, NetOpts, Started) of
        {ok, Started2} ->
            start_transports1(Id, Rest, NetOpts, Started2);
        {error, Error} ->
            {error, Error}
    end;

start_transports1(_Id, [], _NetOpts, Started) ->
    {ok, Started}.



%% @private Tries to start all the configured transports for a Server.
-spec start_transports2(nkservice:id(), atom(), list(), map(), map()) ->
    {ok, map()} | {error, term()}.

start_transports2(Id, Plugin, [{Conns, Opts}|Rest], NetOpts, Started) ->
    % Options that can be configured globally
    Opts2 = maps:merge(NetOpts, Opts),
    case start_transports3(Id, Plugin, Conns, Opts2, Started) of
        {ok, Started2} ->
            start_transports2(Id, Plugin, Rest, NetOpts, Started2);
        {error, Error} ->
            {error, Error}
    end;

start_transports2(_Id, _Plugin, [], _NetOpts, Started) ->
    {ok, Started}.


%% @private
start_transports3(Id, Plugin, [Conn|Rest], Opts, Started) ->
    {_Proto, Transp, _Ip, _Port} = Conn,
    case nkpacket:get_listener(Conn, Opts) of
        {ok, Child} ->
            case add_transport(Id, Child) of
                {ok, ListenId} ->
                    ListenIds = maps:get(Plugin, Started, []),
                    Started2 = maps:put(Plugin, [ListenId|ListenIds], Started),
                    start_transports3(Id, Plugin, Rest, Opts, Started2);
                {error, Error} ->
                    {error, {could_not_start, {Transp, Error}}}
            end;
        {error, Error} ->
            {error, {could_not_start, {Transp, Error}}}
    end;

start_transports3(_Id, _Plugin, [], _Opts, Started) ->
    {ok, Started}.


%% @private Starts a new transport control process under this supervisor
-spec add_transport(nkservice:id(), any()) ->
    {ok, nkpacket:listen_id()} | {error, term()}.

add_transport(SrvId, Spec) ->
    SupPid = get_pid(SrvId),
    {TranspId, _Ref} = element(1, Spec),
    case find_started(supervisor:which_children(SupPid), TranspId) of
        false ->
            case supervisor:start_child(SupPid, Spec) of
                {ok, Pid} ->
                    {registered_name, ListenId} = process_info(Pid, registered_name),
                    {ok, {Proto, Transp, Ip, Port}} = nkpacket:get_local(Pid),
                    lager:info("Service ~s (~p) started listener on ~p:~p:~p (~p)", 
                               [SrvId:name(), SrvId, Transp, Ip, Port, Proto]),
                    {ok, ListenId};
                {error, {Error, _}} -> 
                    {error, Error};
                {error, Error} -> 
                    {error, Error}
            end;
        {true, Pid} ->
            lager:info("Skipping started transport ~p", [TranspId]),
            {registered_name, ListenId} = process_info(Pid, registered_name),
            {ok, ListenId}
    end.


%% @private
find_started([], _Conn) ->
    false;

find_started([{{Conn, _}, Pid, worker, _}|_], Conn) ->
    {true, Pid};

find_started([_|Rest], Conn) ->
    find_started(Rest, Conn).


%% @private Gets the service's transport supervisor's pid()
-spec get_pid(nkservice:id()) ->
    pid() | undefined.

get_pid(SrvId) ->
    nklib_proc:whereis_name({nkservice_srv_listen_sup, SrvId}).



