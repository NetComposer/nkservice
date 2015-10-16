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
    case supervisor:start_child(get_pid(Id), Spec) of
        {ok, Pid} -> {ok, Pid};
        {error, {Error, _}} -> {error, Error};
        {error, Error} -> {error, Error}
    end.


%% @private Tries to start all the configured transports for a Server.
-spec start_transports(list(), nkservice:spec()) ->
    ok | {error, Error}
    when Error ::  {could_not_start, {udp|tcp|tls|sctp|ws|wss, term()}}.

start_transports([{{Proto, Ip, Port}, Opts}|Rest], #{id:=Id}=Spec) ->
    Opts1 = maps:merge(Spec, Opts),
    case nksip_transport:start_transport(Id, Proto, Ip, Port, Opts1) of
        {ok, _} -> 
            start_transports(Rest, Spec);
        {error, Error} -> 
            {error, {could_not_start, {Proto, Error}}}
    end;

start_transports([], _Spec) ->
    ok.


%% @private
-spec start_link(nkservice:id()) -> 
    {ok, pid()} | {error, term()}.

start_link(Id) ->
    ChildSpec = {{one_for_one, 10, 60}, []},
    {ok, Pid} = supervisor:start_link(?MODULE, {Id, ChildSpec}),
    Spec = nkservice_server:get_spec(Id),
    Transports = maps:get(transports, Spec, #{}),
    case start_transports(maps:to_list(Transports), Spec) of
        ok ->
            {ok, Pid};
        {error, Error} ->
            {error, Error}
    end.



%% @private
init({Id, ChildSpecs}) ->
    yes = nklib_proc:register_name({?MODULE, Id}, self()),
    {ok, ChildSpecs}.
