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

%% @private
-module(nkservice_srv_listen_sup).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(supervisor).

-export([start_link/1, init/1]).

-include_lib("nkpacket/include/nkpacket.hrl").
-include("nkservice.hrl").


-define(LLOG(Type, Txt, Args, Service),
    lager:Type("NkSERVICE '~s' "++Txt, [maps:get(id, Service) | Args])).



%% ===================================================================
%% Public
%% ===================================================================


%% @private
-spec start_link(nkservice:service()) -> 
    {ok, pid()} | {error, term()}.

start_link(Id) ->
    SrvSpec = ?CALL_SRV(Id, spec),
    Listen1 = maps:get(listen, SrvSpec, []),
    Listen2 = make_listen(Id, Listen1),
    Childs = lists:map(
        fun(Spec) ->
            {ok, _, ListenSpec} = nkpacket:get_listener(Spec),
            ListenSpec
        end,
        Listen2),
    ChildSpec = {{one_for_one, 10, 60}, Childs},
    supervisor:start_link(?MODULE, {Id, ChildSpec}).


%% @private
init({Id, ChildSpecs}) ->
    yes = nklib_proc:register_name({?MODULE, Id}, self()),
    {ok, ChildSpecs}.



%% @doc
make_listen(SrvId, Endpoints) ->
    make_listen(SrvId, Endpoints, []).


%% @private
make_listen(_SrvId, [], Acc) ->
    Acc;
make_listen(SrvId, [#{id:=Id, url:={nkservice_rest_conns, Conns}}=Entry|Rest], Acc) ->
    Opts = maps:get(opts, Entry, #{}),
    Transps = make_listen_transps(SrvId, Id, Conns, Opts, []),
    make_listen(SrvId, Rest, [Transps|Acc]).


%% @private
make_listen_transps(_SrvId, _Id, [], _Opts, Acc) ->
    lists:reverse(Acc);

make_listen_transps(SrvId, Id, [Conn|Rest], Opts, Acc) ->
    #nkconn{opts=ConnOpts, transp=_Transp} = Conn,
    Opts2 = maps:merge(ConnOpts, Opts),
    Opts3 = Opts2#{
        class => {nkservice_rest, SrvId, Id},
        path => maps:get(path, Opts2, <<"/">>),
        get_headers => [<<"user-agent">>]
    },
    Conn2 = Conn#nkconn{opts=Opts3},
    make_listen_transps(SrvId, Id, Rest, Opts, [Conn2|Acc]).


