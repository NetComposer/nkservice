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

%% @doc HTTP Pool plugin
-module(nkservice_httppool_plugin).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([plugin_deps/0, plugin_api/1, plugin_config/3, plugin_start/4, plugin_update/5]).

-include("nkservice.hrl").

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
plugin_api(?PKG_HTTPPOOL) ->
    #{
        luerl => #{
            request => {nkservice_httppool, luerl_request}
        }
    };

plugin_api(_Class) ->
    #{}.


%% @doc
plugin_config(?PKG_HTTPPOOL, #{config:=Config}=Spec, _Service) ->
    Syntax = #{
        targets => {list, #{
            url => binary,
            opts => nkpacket_syntax:safe_syntax(),
            weight => {integer, 1, 1000},
            pool => {integer, 1, 1000},
            refresh => boolean,
            headers => map,
            '__mandatory' => [url]
        }},
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
plugin_start(?PKG_HTTPPOOL, #{id:=Id, config:=Config}, Pid, Service) ->
    insert(Id, Config, Pid, Service);

plugin_start(_Id, _Spec, _Pid, _Service) ->
    continue.


%% @doc
%% Even if we are called only with modified config, we check if the spec is new
plugin_update(?PKG_HTTPPOOL, #{id:=Id, config:=NewConfig}, OldSpec, Pid, Service) ->
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
    PluginConfig = #{
        id => nklib_util:bjoin([SrvId, Id], $-),
        targets => maps:get(targets, Config),
        debug => maps:get(debug, Config, false),
        resolve_interval => maps:get(resolveInterval, Config, 0)
    },
    Spec = #{
        id => Id,
        start => {nkpacket_httpc_pool, start_link, [PluginConfig]}
    },
    case nkservice_packages_sup:update_child(SupPid, Spec, #{}) of
        {ok, ChildPid} ->
            nklib_proc:put({nkservice_httppool, SrvId, Id}, undefined, ChildPid),
            ?LLOG(debug, "started ~s (~p)", [Id, ChildPid]),
            ok;
        not_updated ->
            ?LLOG(debug, "didn't upgrade ~s", [Id]),
            ok;
        {upgraded, ChildPid} ->
            nklib_proc:put({nkservice_httppool, SrvId, Id}, undefined, ChildPid),
            ?LLOG(info, "upgraded ~s (~p)", [Id, ChildPid]),
            ok;
        {error, Error} ->
            ?LLOG(notice, "start/update error ~s: ~p", [Id, Error]),
            {error, Error}
    end.
