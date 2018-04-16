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

-module(nkservice_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([register_package/2, get_package_plugin/1]).
-export([get_cache/2, get_debug/2, get_secret/2, get_callback/4]).
-export([name/1]).
-export([get_srv_secret/2, set_srv_secret/3]).
-export([luerl_api/6]).
-export([register_for_changes/1, notify_updated_service/1]).
-export([get_net_ticktime/0, set_net_ticktime/2]).

-include("nkservice.hrl").
-include_lib("nkpacket/include/nkpacket.hrl").


-define(API_TIMEOUT, 30).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc
-spec register_package(nkservice:package_class(), module()) ->
    ok.

register_package(Class, Package) when is_atom(Package) ->
    nklib_types:register_type(nkservice_package, to_bin(Class), Package).


%% @doc
-spec get_package_plugin(nkservice:package_class()) ->
    module() | undefined.

get_package_plugin(Class) ->
    nklib_types:get_module(nkservice_package, to_bin(Class)).


%% @doc Registers a pid to receive changes in service config
-spec register_for_changes(nkservice:id()) ->
    ok.

register_for_changes(SrvId) ->
    nklib_proc:put({notify_updated_service, SrvId}).


%% @doc 
-spec notify_updated_service(nkservice:id()) ->
    ok.

notify_updated_service(SrvId) ->
    lists:foreach(
        fun({_, Pid}) -> Pid ! {nkservice_updated, SrvId} end,
        nklib_proc:values({notify_updated_service, SrvId})).


%% @private
name(Name) ->
    nklib_parse:normalize(Name, #{space=>$_, allowed=>[$+, $-, $., $_]}).


%% @doc Gets a cache entry
-spec get_cache(nkservice:id(), term()) ->
    term() | undefined.

get_cache(SrvId, Id) when is_atom(SrvId) ->
    ?CALL_SRV(SrvId, service_cache, [Id]).


%% @doc Gets a debug entry
-spec get_debug(nkservice:id(), term()) ->
    term() | undefined.

get_debug(SrvId, Id) when is_atom(SrvId) ->
    ?CALL_SRV(SrvId, service_debug, [Id]).


%% @doc Gets a secret entry
-spec get_secret(nkservice:id(), term()) ->
    term() | undefined.

get_secret(SrvId, Id) when is_atom(SrvId) ->
    ?CALL_SRV(SrvId, service_secret, [Id]).


%% @doc Gets a callback entry
-spec get_callback(nkservice:id(), binary()|atom(), binary(), binary()|atom()) ->
    term() | undefined.

get_callback(SrvId, Class, Id, CB) when is_atom(SrvId) ->
    ?CALL_SRV(SrvId, service_callback, [to_bin(Class), to_bin(Id), to_bin(CB)]).


%% @doc Gets a cache, secret or debug entry from service config
-spec get_srv_secret(term(), nkservice:service()) ->
    term() | undefined.

get_srv_secret(Id, Service) ->
    Secrets = maps:get(secret, Service, #{}),
    maps:get(Id, Secrets, undefined).


%% @doc Sets a secret
-spec set_srv_secret(term(), term(), nkservice:service()) ->
    nkservice:service().

set_srv_secret(Id, Value, Service) ->
    Secrets = maps:get(secret, Service, #{}),
    Service#{secret=>Secrets#{Id => Value}}.


%% @doc
luerl_api(SrvId, PackageId, Mod, Fun, Args, St) ->
    try
        Res = case apply(Mod, Fun, [SrvId, PackageId, Args]) of
            {error, Error} ->
                {Code, Txt} = nkservice_error:error(SrvId, Error),
                [nil, Code, Txt];
            Other when is_list(Other) ->
                Other
        end,
        {Res, St}
    catch
        Class:CError  ->
            Trace = erlang:get_stacktrace(),
            lager:notice("NkSERVICE LUERL ~s (~s, ~s:~s(~p)) API Error ~p:~p ~p",
                         [SrvId, PackageId, Mod, Fun, Args, Class, CError, Trace]),
            {[nil], St}
    end.


%% @private
get_net_ticktime() ->
    rpc:multicall(net_kernel, get_net_ticktime, []).


%% @private
set_net_ticktime(Time, Period) ->
    rpc:multicall(net_kernel, set_net_ticktime, [Time, Period]).


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).


