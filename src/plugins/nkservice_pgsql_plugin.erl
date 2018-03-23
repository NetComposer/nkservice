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

%% @doc PGSQL Pool plugin
-module(nkservice_pgsql_plugin).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([plugin_deps/0, plugin_api/1, plugin_config/3, plugin_start/4, plugin_update/5]).
-export([conn_resolve/3, conn_start/1, conn_stop/1]).

-include("nkservice.hrl").
-include_lib("nkpacket/include/nkpacket.hrl").

-define(LLOG(Type, Txt, Args),lager:Type("NkSERVICE HTTPPOOL "++Txt, Args)).



%% ===================================================================
%% Types
%% ===================================================================



%% ===================================================================
%% Plugin Callbacks
%% ===================================================================

%% @doc
plugin_deps() ->
	[].

%% @doc
plugin_api(?PKG_PGSQL) ->
    #{
        luerl => #{
            query => {nkservice_pgsql, luerl_query}
        }
    };

plugin_api(_Class) ->
    #{}.


%% @doc
plugin_config(?PKG_PGSQL, #{config:=Config}=Spec, _Service) ->
    Syntax = #{
        targets => {list, #{
            url => binary,
            weight => {integer, 1, 1000},
            pool => {integer, 1, 1000},
            '__mandatory' => [url]
        }},
        database => binary,
        debug => boolean,
        resolveInterval => {integer, 0, none},
        '__mandatory' => [targets]
    },
    case nklib_syntax:parse(Config, Syntax) of
        {ok, Parsed, _} ->
            {ok, Spec#{config:=Parsed}};
        {error, Error} ->
            {error, Error}
    end;

plugin_config(_Class, _Package, _Service) ->
    continue.


%% @doc
plugin_start(?PKG_PGSQL, #{id:=Id, config:=Config}, Pid, Service) ->
    insert(Id, Config, Pid, Service);

plugin_start(_Id, _Spec, _Pid, _Service) ->
    continue.


%% @doc
%% Even if we are called only with modified config, we check if the spec is new
plugin_update(?PKG_PGSQL, #{id:=Id, config:=NewConfig}, OldSpec, Pid, Service) ->
    case OldSpec of
        #{config:=NewConfig} ->
            ok;
        _ ->
            insert(Id, NewConfig, Pid, Service)
    end;

plugin_update(_Class, _NewSpec, _OldSpec, _Pid, _Service) ->
    ok.



%% ===================================================================
%% Internal
%% ===================================================================


%% @private
insert(Id, Config, SupPid, #{id:=SrvId}) ->
    PoolConfig = Config#{
        targets => maps:get(targets, Config),
        debug => maps:get(debug, Config, false),
        resolve_interval => maps:get(resolveInterval, Config, 0),
        conn_resolve_fun => fun ?MODULE:conn_resolve/3,
        conn_start_fun => fun ?MODULE:conn_start/1,
        conn_stop_fun => fun ?MODULE:conn_stop/1
    },
    Spec = #{
        id => Id,
        start => {nkpacket_pool, start_link, [{SrvId, Id}, PoolConfig]}
    },
    case nkservice_packages_sup:update_child(SupPid, Spec, #{}) of
        {ok, ChildPid} ->
            nklib_proc:put({nkservice_pgsql, SrvId, Id}, undefined, ChildPid),
            ?LLOG(debug, "started ~s (~p)", [Id, ChildPid]),
            ok;
        not_updated ->
            ?LLOG(debug, "didn't upgrade ~s", [Id]),
            ok;
        {upgraded, ChildPid} ->
            nklib_proc:put({nkservice_pgsql, SrvId, Id}, undefined, ChildPid),
            ?LLOG(info, "upgraded ~s (~p)", [Id, ChildPid]),
            ok;
        {error, Error} ->
            ?LLOG(notice, "start/update error ~s: ~p", [Id, Error]),
            {error, Error}
    end.

%% @private
conn_resolve(#{url:=Url}, Config, _Pid) ->
    ResOpts = #{schemes=>#{postgresql=>postgresql, tcp=>postgresql}},
    UserOpts = maps:with([database, connect_timeout], Config),
    case nkpacket_resolve:resolve(Url, ResOpts) of
        {ok, List1} ->
            do_conn_resolve(List1, UserOpts, []);
        {error, Error} ->
            {error, Error}
    end.

%% @private
do_conn_resolve([], _UserOpts, Acc) ->
    {ok, lists:reverse(Acc)};

do_conn_resolve([Conn|Rest], UserOpts, Acc) ->
    case Conn of
        #nkconn{protocol=postgresql, transp=Transp, opts=Opts} ->
            Transp2 = case Transp of
                tcp ->
                    tcp;
                undefined ->
                    tcp
            end,
            Opts2 = maps:merge(Opts, UserOpts),
            Conn2 = Conn#nkconn{transp=Transp2, opts=Opts2},
            do_conn_resolve(Rest, UserOpts, [Conn2|Acc]);
        _ ->
            {error, invalid_protocol}
    end.


%% @private
conn_start(#nkconn{transp=_Transp, ip=Ip, port=Port, opts=Opts}) ->
    PgOpts = lists:flatten([
        {host, Ip},
        {port, Port},
        {as_binary, true},
        case Opts of
            #{user:=User} -> {user, User};
            _ -> []
        end,
        case Opts of
            #{password:=Pass} -> {password, Pass};
            _ -> []
        end,
        case Opts of
            #{database:=DB} -> {database, DB};
            _ -> []
        end
    ]),
    case gen_server:start(pgsql_connection, PgOpts, [])  of
        {ok, Pid} ->
            {ok, Pid};
        {error, Error} ->
            {error, Error}
    end.


%% @private
conn_stop(Pid) ->
    pgsql_connection:close({pgsql_connection, Pid}).