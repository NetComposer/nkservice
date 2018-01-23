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

-export([start_transports/1, start_link/1, init/1]).

-include_lib("nkpacket/include/nkpacket.hrl").
-include("nkservice.hrl").


-define(LLOG(Type, Txt, Args, Service),
    lager:Type("NkSERVICE '~s' "++Txt, [maps:get(id, Service) | Args])).



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts all transports associated to a service.
-spec start_transports(nkservice:service()) ->
    {ok, nkservice:service()} | {error, term()}.

start_transports(Service) ->
    #{listen := Listen} = Service,
    do_start_transports(maps:to_list(Listen), Service).



%% ===================================================================
%% Internal
%% ===================================================================



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


%% @private
-spec do_start_transports([{atom(), list()}], nkservice:service()) ->
    {ok, nkservice:service()} | {error, term()}.

do_start_transports([], Service) ->
    {ok, Service};

do_start_transports([{Plugin, Listen}|Rest], Service) ->
    % lager:error("NKLOG Listen ~p", [Listen]),
    case do_start_transports(Plugin, Listen, Service) of
        {ok, Service2} ->
            do_start_transports(Rest, Service2);
        {error, Error} ->
            {error, Error}
    end.


%% @private
do_start_transports(_Plugin, [], Service) ->
    {ok, Service};

do_start_transports(Plugin, [{TranspId, Conns}|Rest], #{listen_started:=Started}=Service) ->
    case lists:member(TranspId, Started) of
        false ->
            case do_start_conns(TranspId, Conns, Service) of
                ok ->
                    Started2 = nklib_util:store_value(TranspId, Started),
                    Service2 = Service#{listen_started:=Started2},
                    do_start_transports(Plugin, Rest, Service2);
                {error, Error} ->
                    {error, Error}
            end;
        true ->
            ?LLOG(notice, "skipping already started transport ~p (~p)", [TranspId, Plugin], Service),
            do_start_transports(Plugin, Rest, Service)
    end.


do_start_conns(_TranspId, [], _Service) ->
    ok;

do_start_conns(TranspId, [Conn|Rest], Service) ->
    #nkconn{protocol=Protocol, transp=Transp} = Conn,
    ?LLOG(debug, "loading transport ~p", [lager:pr(Conn, ?MODULE)], Service),
    case nkpacket:get_listener(Conn) of
        {ok, TranspId, Spec} ->
            case load_transport(TranspId, Spec, Service) of
                {ok, _Pid} ->
                    do_start_conns(TranspId, Rest, Service);
                {error, Error} ->
                    ?LLOG(warning, "could not start transport ~p: ~p",
                          [lager:pr(Conn, ?MODULE), Error], Service),
                    {error, {could_not_start, {TranspId, Error}}}
            end;
        {error, Error} ->
            {error, {could_not_start, {Protocol, Transp, Error}}}
    end.



%% @private Starts a new transport control process under this supervisor
-spec load_transport(nkpacket:id(), supervisor:child_spec(), nkservice:service()) ->
    {ok, pid()} | {error, term()}.

load_transport(TranspId, Spec, Service) ->
    ?LLOG(info, "starting ~p ~p", [TranspId, Spec], Service),
    SupPid = get_sup_pid(Service),
    case supervisor:start_child(SupPid, Spec) of
        {ok, Pid} ->
            {ok, {Proto, Transp, Ip, Port}} = nkpacket:get_local(Pid),
            ?LLOG(info, "started listener ~p ~p on ~p:~p:~p (~p)",
                  [TranspId, Proto, Transp, Ip, Port, Pid], Service),
            {ok, Pid};
        {error, {already_started, Pid}} ->
            ?LLOG(notice, "skipping already started transport ~p", [TranspId], Service),
            {ok, Pid};
        %{error, {Error, _}} ->
        %    {error, Error};
        {error, Error} ->
            {error, Error}
    end.



%% @private Gets the service's transport supervisor's pid()
-spec get_sup_pid(nkservice:id()) ->
    pid() | undefined.

get_sup_pid(#{id:=SrvId}) ->
    nklib_proc:whereis_name({?MODULE, SrvId}).




