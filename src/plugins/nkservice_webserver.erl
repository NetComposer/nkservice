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


%% ===================================================================
%% Plugin Callbacks
%% ===================================================================

plugin_deps() ->
	[].


%% TODO: use nkpacket:parse_urls/3
plugin_syntax() ->
    % For debug, add {nkservice_webserver, [nkpacket]} to 'debug' option
    nkpacket_util:get_plugin_net_syntax(#{
        webserver_url => fun nkservice_webserver_util:parse_web_server/1,
        webserver_path => binary
    }).


plugin_listen(Config, #{id:=SrvId}=Srv) ->
    {parsed_urls, WebSrv} = maps:get(webserver_url, Config, {parsed_urls, []}),
    Debug = nklib_util:get_value(nkservice_webserver, maps:get(debug, Srv, [])),
    Path = case Config of
        #{webserver_path:=UserPath} ->
            UserPath;
        _ ->
            Priv = list_to_binary(code:priv_dir(nkservice)),
            <<Priv/binary, "/www">>
    end,
    nkservice_webserver_util:get_web_servers(SrvId, WebSrv, Path, Config#{debug=>Debug}).


