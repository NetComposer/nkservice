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
-module(nkservice_transport_sup).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(supervisor).

-export([get_pid/1, add_transport/2, start_transports/2, start_link/1, init/1]).

-include("nkservice.hrl").

%% @private Gets the service's transport supervisor's pid()
-spec get_pid(nkservice:id()) ->
    pid() | undefined.

get_pid(Id) ->
    nklib_proc:whereis_name({nkservice_transport_sup, Id}).


%% @private Starts a new transport control process under this supervisor
-spec add_transport(nkservice:id(), any()) ->
    {ok, pid()} | {error, term()}.

add_transport(Id, Spec) ->
    SupPid = get_pid(Id),
    {Conn, _Ref} = element(1, Spec),
    case find_started(supervisor:which_children(SupPid), Conn) of
        false ->
            case supervisor:start_child(SupPid, Spec) of
                {ok, Pid} -> {ok, Pid};
                {error, {Error, _}} -> {error, Error};
                {error, Error} -> {error, Error}
            end;
        {true, Pid} ->
            lager:warning("Transport ~p was already started", [Conn]),
            {ok, Pid}
    end.


%% @private
find_started([], _Conn) ->
    false;

find_started([{{Conn, _}, Pid, worker, _}|_], Conn) ->
    {true, Pid};

find_started([_|Rest], Conn) ->
    find_started(Rest, Conn).


%% @private Tries to start all the configured transports for a Server.
-spec start_transports(list(), nkservice:spec()) ->
    ok | {error, Error}
    when Error ::  {could_not_start, {udp|tcp|tls|sctp|ws|wss, term()}}.

start_transports([{Conns, Opts}|Rest], #{id:=Id}=Spec) ->
    Opts1 = maps:merge(Spec, Opts),
    case start_transports(Id, Conns, Opts1) of
        ok ->
            start_transports(Rest, Spec);
        {error, Error} ->
            {error, Error}
    end;

start_transports([], _Spec) ->
    ok.


%% @private
start_transports(Id, [{_Proto, Transp, _Ip, _Port}=Conn|Rest], Opts) ->
    case nkpacket:get_listener(Conn, Opts) of
        {ok, Child} ->
            case add_transport(Id, Child) of
                {ok, _} ->
                    start_transports(Id, Rest, Opts);
                {error, Error} ->
                    {error, {could_not_start, {Transp, Error}}}
            end;
        {error, Error} ->
            {error, {could_not_start, {Transp, Error}}}
    end;

start_transports(_Id, [], _Opts) ->
    ok.



%% @private
-spec start_link(nkservice:id()) -> 
    {ok, pid()} | {error, term()}.

start_link(Id) ->
    ChildSpec = {{one_for_one, 10, 60}, []},
    {ok, Pid} = supervisor:start_link(?MODULE, {Id, ChildSpec}),
    Spec = nkservice_server:get_spec(Id),
    case start_transports(maps:get(transports, Spec, []), Spec) of
        ok ->
            {ok, Pid};
        {error, Error} ->
            {error, Error}
    end.



%% @private
init({Id, ChildSpecs}) ->
    yes = nklib_proc:register_name({?MODULE, Id}, self()),
    {ok, ChildSpecs}.
