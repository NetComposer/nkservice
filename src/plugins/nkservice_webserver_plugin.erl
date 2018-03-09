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
-module(nkservice_webserver_plugin).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([plugin_deps/0, plugin_config/3, plugin_start/4, plugin_update/5]).

-include("nkservice.hrl").
-include_lib("nkpacket/include/nkpacket.hrl").


-define(LLOG(Type, Txt, Args), lager:Type("NkSERVICE WEBSERVER "++Txt, Args)).


%% ===================================================================
%% Plugin Callbacks
%% ===================================================================

%% @doc
plugin_deps() ->
	[].


%% @doc
plugin_config(?PKG_WEBSERVER, #{id:=Id, config:=Config}=Spec, #{id:=SrvId}) ->
    Syntax = #{
        url => binary,
        file_path => binary,
        debug => boolean,
        opts => nkpacket_syntax:safe_syntax(),
        '__mandatory' => [url]
    },
    case nklib_syntax:parse(Config, Syntax) of
        {ok, Parsed, _} ->
            case make_listen(SrvId, Id, Parsed) of
                {ok, _Listeners} ->
                    {ok, Spec#{config:=Parsed}};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end;

plugin_config(_Class, _Package, _Service) ->
    continue.


%% @doc
plugin_start(?PKG_WEBSERVER, #{id:=Id, config:=#{url:=_Url}=Config}, Pid, #{id:=SrvId}) ->
    {ok, Listeners} =  make_listen(SrvId, Id, Config),
    insert_listeners(Id, Pid, Listeners);

plugin_start(_Class, _Spec, _Pid, _Service) ->
    ok.


%% @doc
%% Even if we are called only with modified config, we check if the spec is new
plugin_update(?PKG_WEBSERVER, #{id:=Id, config:=#{url:=_Url}=NewConfig}, OldSpec, Pid, #{id:=SrvId}) ->
    case OldSpec of
        #{config:=NewConfig} ->
            ok;
        _ ->
            {ok, Listeners} =  make_listen(SrvId, Id, NewConfig),
            insert_listeners(Id, Pid, Listeners)
    end;

plugin_update(_Class, _NewSpec, _OldSPec, _Pid, _Service) ->
    ok.




%% ===================================================================
%% Internal
%% ===================================================================


%% @private
make_listen(SrvId, Id, #{url:=Url}=Entry) ->
    ResolveOpts = #{resolve_type=>listen, protocol=>nkservice_webserver_protocol},
    case nkpacket_resolve:resolve(Url, ResolveOpts) of
        {ok, Conns} ->
            Opts1 = maps:get(opts, Entry, #{}),
            Debug = maps:get(debug, Entry, false),
            Opts2 = Opts1#{debug=>Debug},
            Path = case Entry of
                #{file_path:=FilePath} ->
                    FilePath;
                _ ->
                    Priv = list_to_binary(code:priv_dir(nkservice)),
                    <<Priv/binary, "/www">>
            end,
            make_listen_transps(SrvId, Id, Conns, Opts2, Path, []);
        {error, Error} ->
            {error, Error}
    end.


%% @private
make_listen_transps(_SrvId, _Id, [], _Opts, _Path, Acc) ->
    {ok, Acc};

make_listen_transps(SrvId, Id, [Conn|Rest], Opts, Path, Acc) ->
    #nkconn{opts=ConnOpts} = Conn,
    Opts2 = maps:merge(ConnOpts, Opts),
    Opts3 = Opts2#{
        id => Id,
        class => {nkservice_webserver, SrvId, Id},
        user_state => #{file_path=>Path, index_file=><<"index.html">>}
    },
    Conn2 = Conn#nkconn{protocol=nkservice_webserver_protocol, opts=Opts3},
    case nkpacket:get_listener(Conn2) of
        {ok, Id, Spec} ->
            make_listen_transps(SrvId, Id, Rest, Opts, Path, [Spec|Acc]);
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
