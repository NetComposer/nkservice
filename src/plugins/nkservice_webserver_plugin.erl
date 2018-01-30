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
-export([plugin_deps/0, plugin_config/2, plugin_start/3]).
-export([parse_url/1]).

-include_lib("nkpacket/include/nkpacket.hrl").


%% ===================================================================
%% Plugin Callbacks
%% ===================================================================

plugin_deps() ->
	[].


plugin_config(Config, #{id:=SrvId}) ->
    Syntax = #{
        servers => {list, #{
            id => binary,
            url => fun ?MODULE:parse_url/1,
            file_path => binary,
            opts => nkpacket_syntax:safe_syntax(),
            '__mandatory' => [id, url]
        }}
    },
    case nklib_syntax:parse(Config, Syntax) of
        {ok, #{servers:=Servers}, _} ->
            case make_listen(SrvId, Servers, []) of
                {ok, Listeners} ->
                    {ok, Config#{listeners=>Listeners}};
                {error, Error} ->
                    {error, Error}
            end;
        {ok, _, _} ->
            ok;
        {error, Error} ->
            {error, Error}
    end.


plugin_start(#{listeners:=Listeners}, Pid, #{id:=_SrvId}) ->
    insert_listeners(Listeners, Pid);

plugin_start(_Config, _Pid, _Service) ->
    ok.





%% ===================================================================
%% Internal
%% ===================================================================



%% @private
parse_url({nkservice_webserver_conns, Conns}) ->
    {ok, {nkservice_webserver_conns, Conns}};

parse_url(Url) ->
    % Use protocol for transports and ports
    case nkpacket_resolve:resolve(Url, #{resolve_type=>listen, protocol=>nkservice_webserver_protocol}) of
        {ok, Conns} ->
            {ok, {nkservice_webserver_conns, Conns}};
        {error, Error} ->
            {error, Error}
    end.


%% @private
make_listen(_SrvId, [], Acc) ->
    {ok, Acc};

make_listen(SrvId, [#{id:=Id, url:={nkservice_webserver_conns, Conns}}=Entry|Rest], Acc) ->
    Opts = maps:get(opts, Entry, #{}),
    Path = case Entry of
        #{file_path:=FilePath} ->
            FilePath;
        _ ->
            Priv = list_to_binary(code:priv_dir(nkservice)),
            <<Priv/binary, "/www">>
    end,
    Acc2 = make_listen_transps(SrvId, Id, Conns, Opts, Path, Acc),
    make_listen(SrvId, Rest, Acc2).


%% @private
make_listen_transps(_SrvId, _Id, [], _Opts, _Path, Acc) ->
    Acc;

make_listen_transps(SrvId, Id, [Conn|Rest], Opts, Path, Acc) ->
    #nkconn{opts=ConnOpts} = Conn,
    Opts2 = maps:merge(ConnOpts, Opts),
    Opts3 = Opts2#{
        id => Id,
        class => {nkservice_webserver, SrvId, Id},
        user_state => #{file_path=>Path, index_file=><<"index.html">>}
    },
    Conn2 = Conn#nkconn{protocol=nkservice_webserver_protocol, opts=Opts3},
    lager:error("NKLOG CONNS ~p", [Conn2]),
    case nkpacket:get_listener(Conn2) of
        {ok, Id, Spec} ->
            make_listen_transps(SrvId, Id, Rest, Opts, Path, [{Id, Spec}|Acc]);
        {error, Error} ->
            {error, Error}
    end.


%% @private
insert_listeners([], _Pid) ->
    ok;

insert_listeners([{Id, Spec}|Rest], Pid) ->
    Hash = erlang:phash2(Spec),
    case supervisor:start_child(Pid, Spec#{id:={Id, Hash}}) of
        {ok, _} ->
            lager:warning("Started listener ~s", [Id]),
            insert_listeners(Rest, Pid);
        {error, Error} ->
            {error, Error}
    end.

