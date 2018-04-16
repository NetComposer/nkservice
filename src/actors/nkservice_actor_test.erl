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

-module(nkservice_actor_test).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([start/0, stop/0]).
-export([s1/0, s2/0]).
-export([actor_delete/1, actor_link_event/4]).

-define(SRV, test).
-compile(nowarn_unused_function).

-include("nkservice.hrl").

-dialyzer({nowarn_function, start/0}).


start() ->
    Spec = #{
        name => my_name,
        plugins => [?MODULE],
        debug_actors => all
    },
    nkservice:start(?SRV, Spec).


stop() ->
    nkservice:stop(?SRV).



s1() ->
    nkservice_actor_srv:start(#{srv=>?SRV, class=><<"k1">>}, #{}).

s2() ->
    nkservice_actor_srv:start(#{srv=>?SRV, class=><<"k1">>}, #{config=>#{permanent=>true}}).




actor_delete(State) ->
    {ok, State}.

actor_link_event(Link, Opts, Event, State) ->
    lager:notice("Link Event ~p ~p ~p", [Link, Opts, Event]),
    {ok, State}.