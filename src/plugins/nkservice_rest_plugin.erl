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

%% @doc Default callbacks
-module(nkservice_rest_plugin).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([plugin_deps/0, plugin_config/3, plugin_start/4, plugin_update/5]).
-export_type([id/0, http_method/0, http_path/0, http_req/0, http_reply/0]).

-include_lib("nklib/include/nklib.hrl").
-include("nkservice.hrl").
-include_lib("nkpacket/include/nkpacket.hrl").

-define(LLOG(Type, Txt, Args),lager:Type("NkSERVICE REST "++Txt, Args)).



%% ===================================================================
%% Types
%% ===================================================================


-type id() :: binary().
-type http_method() :: nkservice_rest_http:method().
-type http_path() :: nkservice_rest_http:path().
-type http_req() :: nkservice_rest_http:nkreq_http().
-type http_reply() :: nkservice_rest_http:reply().




%% ===================================================================
%% Plugin Callbacks
%% ===================================================================

%% @doc
plugin_deps() ->
	[].


%% @doc
plugin_config(?PKG_REST, #{id:=Id, config:=Config}=Spec, #{id:=SrvId}) ->
    Syntax = #{
        url => binary,
        opts => nkpacket_syntax:safe_syntax(),
        debug => {list, {atom, [ws, http, nkpacket]}},
        requestCallback => any,
        requestGetBody => boolean,
        requestParseBody => boolean,
        requestMaxBodySize => {integer, 0, 10000000},
        requestGetHeaders => {list, binary},
        requestGetAllHeaders => boolean,
        requestGetQs => boolean,
        requestGetBasicAuthorization => boolean,
        '__mandatory' => [url]
    },
    case nklib_syntax:parse(Config, Syntax) of
        {ok, Parsed, _} ->
            case make_listen(SrvId, Id, Parsed) of
                {ok, _Listeners} ->
                    Spec2 = Spec#{config:=Parsed},
                    Spec3 = lists:foldl(
                        fun(Type, Acc) ->
                            D0 = maps:get(debug_map, Acc, #{}),
                            Acc#{debug_map=>D0#{{nkservice_rest, Id, Type} => true}}
                        end,
                        Spec2,
                        maps:get(debug, Parsed, [])),
                    ReqConfig1 = maps:with([
                        requestGetBody,
                        requestParseBody,
                        requestMaxBodySize,
                        requestGetHeaders,
                        requestGetAllHeaders,
                        requestGetQs,
                        requestGetBasicAuthorization], Parsed),
                    ReqConfig2 = maps:to_list(ReqConfig1),
                    Cache1 = maps:get(cache_map, Spec, #{}),
                    Cache2 = Cache1#{{?PKG_REST, Id, request_config} => ReqConfig2},
                    Spec4 = Spec3#{cache_map => Cache2},
                    {ok, Spec4};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end;

plugin_config(_Class, _Package, _Service) ->
    continue.


%% @doc
plugin_start(?PKG_REST, #{id:=Id, config:=#{url:=_Url}=Config}, Pid, #{id:=SrvId}) ->
    {ok, Listeners} =  make_listen(SrvId, Id, Config),
    insert_listeners(Id, Pid, Listeners);

plugin_start(_Id, _Spec, _Pid, _Service) ->
    continue.


%% @doc
%% Even if we are called only with modified config, we check if the spec is new
plugin_update(?PKG_REST, #{id:=Id, config:=#{url:=_}=NewConfig}, OldSpec, Pid, #{id:=SrvId}) ->
    case OldSpec of
        #{config:=NewConfig} ->
            ok;
        _ ->
            {ok, Listeners} =  make_listen(SrvId, Id, NewConfig),
            insert_listeners(Id, Pid, Listeners)
    end;

plugin_update(_Class, _NewSpec, _OldSpec, _Pid, _Service) ->
    ok.



%% ===================================================================
%% Internal
%% ===================================================================



%% @private
make_listen(SrvId, Id, #{url:=Url}=Entry) ->
    ResolveOpts = #{resolve_type=>listen, protocol=>nkservice_rest_protocol},
    case nkpacket_resolve:resolve(Url, ResolveOpts) of
        {ok, Conns} ->
            Opts1 = maps:get(opts, Entry, #{}),
            Debug = maps:get(debug, Entry, []),
            Opts2 = Opts1#{debug=>lists:member(nkpacket, Debug)},
            make_listen_transps(SrvId, Id, Conns, Opts2, []);
        {error, Error} ->
            {error, Error}
    end.


%% @private
make_listen_transps(_SrvId, _Id, [], _Opts, Acc) ->
    {ok, Acc};

make_listen_transps(SrvId, Id, [Conn|Rest], Opts, Acc) ->
    #nkconn{opts=ConnOpts} = Conn,
    Opts2 = maps:merge(ConnOpts, Opts),
    Opts3 = Opts2#{
        id => Id,
        class => {nkservice_rest, SrvId, Id},
        path => maps:get(path, Opts2, <<"/">>),
        get_headers => [<<"user-agent">>]
    },
    Conn2 = Conn#nkconn{opts=Opts3},
    case nkpacket:get_listener(Conn2) of
        {ok, Id, Spec} ->
            make_listen_transps(SrvId, Id, Rest, Opts, [Spec|Acc]);
        {error, Error} ->
            {error, Error}
    end.


%% @private
insert_listeners(Id, Pid, SpecList) ->
    case nkservice_packages_sup:update_child_multi(Pid, SpecList, #{}) of
        ok ->
            ?LLOG(debug, "started ~s", [Id]),
            ok;
        not_updated ->
            ?LLOG(debug, "didn't upgrade ~s", [Id]),
            ok;
        upgraded ->
            ?LLOG(info, "upgraded ~s", [Id]),
            ok;
        {error, Error} ->
            ?LLOG(notice, "start/update error ~s: ~p", [Id, Error]),
            {error, Error}
    end.
