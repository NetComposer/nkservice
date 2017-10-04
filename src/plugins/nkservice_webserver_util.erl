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
-module(nkservice_webserver_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([parse_web_server/1, get_web_servers/4]).


%% ===================================================================
%% Webserver & rest
%% ===================================================================


%% @private
parse_web_server({parsed_urls, Multi}) ->
    {ok, {parsed_urls, Multi}};

parse_web_server(Url) ->
    % TODO

    Opts = #{valid_schemes=>[http, https], resolve_type=>listen},
    case nkpacket:multi_resolve(Url, Opts) of
        {ok, List} -> {ok, {parsed_urls, List}};
        _ -> error
    end.


%% @private
get_web_servers(SrvId, List, Path, Config) ->
    NetOpts = nkpacket_util:get_plugin_net_opts(Config),
    PacketDebug = case Config of
        #{debug:=DebugList} when is_list(DebugList) ->
            lists:member(nkpacket, DebugList);
        _ ->
            false
    end,
    WebOpts2 = NetOpts#{
        class => {nkservice_webserver, SrvId},
        http_proto => {static, #{path=>Path, index_file=><<"index.html">>}},
        debug => PacketDebug
    },
    [{Conns, maps:merge(ConnOpts, WebOpts2)} || {Conns, ConnOpts} <- List].
