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
-module(nkservice_webserver).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([plugin_deps/0, plugin_syntax/0, plugin_listen/2]).

%%-export_type([continue/0]).
%%
%%-type continue() :: continue | {continue, list()}.
%%-type config() :: nkapi:config().


%% ===================================================================
%% Plugin Callbacks
%% ===================================================================

plugin_deps() ->
	[].


plugin_syntax() ->
    nkpacket_util:get_plugin_net_syntax(#{
        webserver_url => fun parse_web_server/3,
        webserver_path => binary
    }).


plugin_listen(Config, #{id:=SrvId}) ->
    {?MODULE, parsed, WebSrv} = maps:get(webserver_url, Config, {?MODULE, parsed, []}),
    get_web_servers(SrvId, WebSrv, Config).



%% ===================================================================
%% Util
%% ===================================================================


%% @private
parse_web_server(_Key, {?MODULE, parsed, Multi}, _Ctx) ->
    {ok, {?MODULE, parsed, Multi}};

parse_web_server(webserver_url, Url, _Ctx) ->
    Opts = #{valid_schemes=>[http, https], resolve_type=>listen},
    case nkpacket:multi_resolve(Url, Opts) of
        {ok, List} -> {ok, {?MODULE, parsed, List}};
        _ -> error
    end.


%% @private
get_web_servers(SrvId, List, Config) ->
    WebPath = case Config of
        #{webserver_path:=UserPath} ->
            UserPath;
        _ ->
            Priv = list_to_binary(code:priv_dir(nkapi)),
            <<Priv/binary, "/www">>
    end,
    NetOpts = nkpacket_util:get_plugin_net_opts(Config),
    WebOpts2 = NetOpts#{
        class => {nkservice_webserver, SrvId},
        http_proto => {static, #{path=>WebPath, index_file=><<"index.html">>}}
    },
    [{Conns, maps:merge(ConnOpts, WebOpts2)} || {Conns, ConnOpts} <- List].

