%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Carlos Gonzalez Florido.  All Rights Reserved.
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
-export([plugin_deps/0, plugin_config/3, plugin_start/4, plugin_update/4]).
-export([parse_url/1]).

-include_lib("nkpacket/include/nkpacket.hrl").

-define(LLOG(Type, Txt, Args), lager:Type("NkSERVICE Webserver "++Txt, Args)).


%% ===================================================================
%% Plugin Callbacks
%% ===================================================================

%% @doc
plugin_deps() ->
	[].


%% @doc
plugin_config(Id, Config, #{id:=SrvId}) ->
    Syntax = #{
        url => fun ?MODULE:parse_url/1,     % Use <<>> to remove the id
        file_path => binary,
        opts => nkpacket_syntax:safe_syntax(),
        '__mandatory' => [url]
    },
    case nklib_syntax:parse(Config, Syntax) of
        {ok, Parsed, _} ->
            case make_listen(SrvId, Id, Parsed) of
                {ok, Listeners} ->
                    {ok, Config#{listeners=>Listeners}};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc
plugin_start(Id, #{listeners:=Listeners}, Pid, #{id:=_SrvId}) ->
    insert_listeners(Id, Pid, Listeners);

plugin_start(_Id, _Config, _Pid, _Service) ->
    ok.


%% @doc
plugin_update(Id, #{listeners:=Listeners}, Pid, #{id:=_SrvId}) ->
    insert_listeners(Id, Pid, Listeners);

plugin_update(_Id, _Config, _Pid, _Service) ->
    ok.




%% ===================================================================
%% Internal
%% ===================================================================



%% @private
parse_url({nkservice_webserver_conns, Conns}) ->
    {ok, {nkservice_webserver_conns, Conns}};

parse_url(<<>>) ->
    {ok, <<>>};

parse_url(Url) ->
    Opts = #{resolve_type=>listen, protocol=>nkservice_webserver_protocol},
    case nkpacket_resolve:resolve(Url, Opts) of
        {ok, Conns} ->
            {ok, {nkservice_webserver_conns, Conns}};
        {error, Error} ->
            {error, Error}
    end.


%% @private
make_listen(SrvId, Id, #{url:={nkservice_webserver_conns, Conns}}=Entry) ->
    Opts = maps:get(opts, Entry, #{}),
    Path = case Entry of
        #{file_path:=FilePath} ->
            FilePath;
        _ ->
            Priv = list_to_binary(code:priv_dir(nkservice)),
            <<Priv/binary, "/www">>
    end,
    make_listen_transps(SrvId, Id, Conns, Opts, Path, []).


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
%%insert_listeners([{Id, <<>>}|Rest], Pid) ->
%%    Childs = nkservice_srv_plugins_sup:get_childs(Pid),
%%    lists:foreach(
%%        fun({ChildId, _, _, _}) ->
%%            case element(1, ChildId) of
%%                Id ->
%%                    ?LLOG(info, "stopping ~s", [Id]),
%%                    nkservice_srv_plugins_sup:remove_child(Pid, ChildId);
%%                _ ->
%%                    ok
%%            end
%%        end,
%%        Childs),
%%    insert_listeners(Rest, Pid);

insert_listeners(Id, Pid, SpecList) ->
    case nkservice_srv_plugins_sup:update_child_multi(Pid, SpecList, #{}) of
        ok ->
            ?LLOG(info, "started ~s", [Id]),
            ok;
        not_updated ->
            ?LLOG(info, "didn't upgrade ~s", [Id]),
            ok;
        upgraded ->
            ?LLOG(info, "upgraded ~s", [Id]),
            ok;
        {error, Error} ->
            ?LLOG(warning, "start/update error ~s: ~p", [Id, Error]),
            {error, Error}
    end.
