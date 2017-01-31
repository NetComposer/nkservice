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

%% @private Supervisor for user-related (not NkService) processes
-module(nkservice_srv_user_sup).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(supervisor).

-export([start_link/1, init/1, start_proc/4, start_child/2]).

-include_lib("nkpacket/include/nkpacket.hrl").
-include("nkservice.hrl").


%% @private
-spec start_link(nkservice:id()) -> 
    {ok, pid()} | {error, term()}.

start_link(SrvId) ->
    Childs = nkservice_srv:get(SrvId, {?MODULE, childs}, []),
    ChildSpec = {{one_for_one, 10, 60}, Childs},
    supervisor:start_link(?MODULE, {SrvId, ChildSpec}).


%% @private
init({Id, ChildSpecs}) ->
    yes = nklib_proc:register_name({?MODULE, Id}, self()),
    {ok, ChildSpecs}.


%% @private Starts a new child under this supervisor
-spec start_proc(nkservice:id(), term(), module(), list()) ->
    {ok, pid()} | {error, term()}.

start_proc(SrvId, Name, Module, Args) ->
    Spec = {
        Name, 
        {Module, start_link, Args},
        transient,
        5000,
        worker,
        [Module]
    },
    start_child(SrvId, Spec).


%% @private Starts a new child under this supervisor
-spec start_child(nkservice:id(), any()) ->
    {ok, pid()} | {error, term()}.

start_child(SrvId, Spec) ->
    SupPid = get_pid(SrvId),
    case supervisor:start_child(SupPid, Spec) of
        {ok, Pid} ->
            Name = element(1, Spec),
            Specs1 = nkservice_srv:get(SrvId, {?MODULE, childs}, []),
            Specs2 = lists:keystore(Name, 1, Specs1, Spec),
            nkservice_srv:put(SrvId, {?MODULE, childs}, Specs2),
            {ok, Pid};
        {error, {Error, _}} -> 
            {error, Error};
        {error, Error} -> 
            {error, Error}
    end.


%% @private Gets the service's transport supervisor's pid()
-spec get_pid(nkservice:id()) ->
    pid() | undefined.

get_pid(SrvId) ->
    nklib_proc:whereis_name({?MODULE, SrvId}).


