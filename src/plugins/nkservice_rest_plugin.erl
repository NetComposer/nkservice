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
-module(nkservice_rest_plugin).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([plugin_deps/0, plugin_config/3, plugin_start/4, plugin_update/4]).
-export([parse_url/1]).
-export_type([id/0, http_method/0, http_path/0, http_req/0, http_reply/0]).

-include_lib("nklib/include/nklib.hrl").
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
plugin_config(Id, Config, #{id:=SrvId}) ->
    % For debug at nkpacket level, add debug=>true to opts (or in a url)
    % For debug at nkservice_rest level, add nkservice_rest to 'debug' config option in global service
    Syntax = #{
       url => fun ?MODULE:parse_url/1,
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
parse_url({nkservice_rest_conns, Multi}) ->
    {ok, {nkservice_rest_conns, Multi}};

parse_url(<<>>) ->
    {ok, <<>>};

parse_url(Url) ->
    case nkpacket_resolve:resolve(Url, #{resolve_type=>listen, protocol=>nkservice_rest_protocol}) of
        {ok, Conns} ->
            {ok, {nkservice_rest_conns, Conns}};
        {error, Error} ->
            {error, Error}
    end.



%% @private
make_listen(SrvId, Id, #{url:={nkservice_rest_conns, Conns}}=Entry) ->
    Opts = maps:get(opts, Entry, #{}),
    make_listen_transps(SrvId, Id, Conns, Opts, []).


%% @private
make_listen_transps(_SrvId, _Id, [], _Opts, Acc) ->
    {ok, Acc};

make_listen_transps(SrvId, Id, [Conn|Rest], Opts, Acc) ->
    #nkconn{opts=ConnOpts, transp=_Transp} = Conn,
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
