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

%% @doc Plugin implementation
-module(nkservice_jose_plugin).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([plugin_deps/0, plugin_api/1, plugin_config/3]).


-define(LLOG(Type, Txt, Args),lager:Type("NkSERVICE JOSE "++Txt, Args)).

-include("nkservice.hrl").


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
plugin_api(?PKG_JOSE) ->
    #{
        luerl => #{
            sign => {nkservice_jose, luerl_sign},
            verify => {nkservice_jose, luerl_verify}
        }
    };

plugin_api(_Class) ->
    #{}.


%% @doc
plugin_config(?PKG_JOSE, #{id:=Id, config:=Config}=Spec, Service) ->
    % You can specify a key in 'secret_key'
    % By default it will look for "jose_secret"
    % It will generate it if not present
    Default = <<"jose_secret">>,
    Syntax = #{
        secret_key => binary,
        '__defaults' => #{secret_key => Default}
    },
    case nklib_syntax:parse(Config, Syntax) of
        {ok, Parsed, _} ->
            Service2 = case nkservice_util:get_srv_secret(Id, Service) of
                undefined ->
                    Bin = crypto:strong_rand_bytes(32),
                    nkservice_util:set_srv_secret(Default, Bin, Service);
                _ ->
                    Service
            end,
            {ok, Spec#{config:=Parsed}, Service2};
        {error, Error} ->
            {error, Error}
    end;

plugin_config(_Class, _Package, _Service) ->
    continue.


