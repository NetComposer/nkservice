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
-export([plugin_deps/0, plugin_syntax/0, plugin_listen/2]).


-include_lib("nklib/include/nklib.hrl").

-define(LLOG(Type, Txt, Args),lager:Type("NkSERVICE REST "++Txt, Args)).


%% ===================================================================
%% Plugin Callbacks
%% ===================================================================

plugin_deps() ->
	[].


plugin_syntax() ->
    % For debug at nkpacket level, add debug=>true to opts (or in a url)
    % For debug at nkservice_rest level, add nkservice_rest to 'debug' config option in global service
    #{
        nkservice_rest => {list,
           #{
               id => binary,
               url => fun nkservice_rest_util:parse_url/1,
               opts => nkpacket_syntax:safe_syntax(),
               '__mandatory' => [id, url]
           }}
    }.


plugin_listen(Config, #{id:=SrvId}) ->
    Endpoints = maps:get(nkservice_rest, Config, []),
    lager:notice("NKLOG REST LISTEN ~p", [Endpoints]),
    Listen = nkservice_rest_util:make_listen(SrvId, Endpoints),
    lists:flatten(maps:values(Listen)).

