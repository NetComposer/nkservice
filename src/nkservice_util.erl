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

-export([register_package_class/2, register_package_class/3,
         get_package_class_module/1, get_package_class_meta/1]).
-export([get_cache/4, get_debug/4, get_secret/2, get_callback/4]).
-export([name/1]).
-export([get_srv_secret/2, set_srv_secret/3]).
-export([get_config/2]).
-export([luerl_api/6]).
-export([register_for_changes/1, notify_updated_service/1]).
-export([get_net_ticktime/0, set_net_ticktime/2]).
-export([call_services/2, add_external_host/1]).


-include("nkservice.hrl").
-include_lib("nkpacket/include/nkpacket.hrl").


-define(API_TIMEOUT, 30).


%% ===================================================================
%% Types
%% ===================================================================

-type register_opts() ::
    #{
        unique => boolean()
    }.



%% ===================================================================
%% Public
%% ===================================================================


%% @doc
-spec register_package_class(nkservice:package_class(), module()) ->
    ok.

register_package_class(Class, Module) ->
    register_package_class(Class, Module, #{}).


%% @doc
-spec register_package_class(nkservice:package_class(), module(), register_opts()) ->
    ok.

register_package_class(Class, Module, Opts) when is_atom(Module), is_map(Opts) ->
    nklib_types:register_type(nkservice_package_class, to_bin(Class), Module, Opts).


%% @doc
-spec get_package_class_module(nkservice:package_class()) ->
    module() | undefined.

get_package_class_module(Class) ->
    nklib_types:get_module(nkservice_package_class, to_bin(Class)).


%% @doc
-spec get_package_class_meta(nkservice:package_class()) ->
    module() | undefined.

get_package_class_meta(Class) ->
    nklib_types:get_meta(nkservice_package_class, to_bin(Class)).


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
-spec get_cache(nkservice:id(), term(), term(), term()) ->
    term() | undefined.

get_cache(SrvId, Group, Id, Key) when is_atom(SrvId) ->
    ?CALL_SRV(SrvId, service_cache, [{Group, Id, Key}]).


%% @doc Gets a debug entry
-spec get_debug(nkservice:id(), term(), term(), term()) ->
    term() | undefined.

get_debug(SrvId, Group, Id, Class) when is_atom(SrvId) ->
    ?CALL_SRV(SrvId, service_debug, [{Group, Id, Class}]).


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


%% @doc Gets service config for a package
get_config(SrvId, PackageId) ->
    Packages = ?CALL_SRV(SrvId, packages),
    case maps:find(PackageId, Packages) of
        {ok, Package} ->
            maps:get(config, Package, #{});
        error ->
            undefined
    end.



%% @doc
luerl_api(SrvId, PackageId, Mod, Fun, Args, St) ->
    try
        Res = case apply(Mod, Fun, [SrvId, PackageId, Args]) of
            {error, Error} ->
                {Code, Txt} = nkservice_msg:msg(SrvId, Error),
                [nil, Code, Txt];
            Other when is_list(Other) ->
                Other
        end,
        {Res, St}
    catch
        Class:CError:Trace ->
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


%% @doc Calls a fun if defined in all service callbacks
%% If it returns 'continue' it will jump to next service

-spec call_services(atom(), list()) ->
    {ok, nkservice:id(), term()} | no_services.

call_services(Fun, Args) ->
    Services = [SrvId || {SrvId, _Name, _Class, _Hash, _Pid} <- nkservice_srv:get_all()],
    call_services(Services, Fun, Args).


%% @private
call_services([], _Fun, _Args) ->
    no_services;


call_services([SrvId|Rest], Fun, Args) ->
    Pid = whereis(SrvId),
    case is_pid(Pid) andalso erlang:function_exported(SrvId, Fun, length(Args)) of
        true ->
            case apply(SrvId, Fun, Args) of
                continue ->
                    call_services(Rest, Fun, Args);
                Data ->
                    {ok, SrvId, Data}
            end;
        false ->
            call_services(Rest, Fun, Args)
    end.




%% @doc Addes external configuration for transports
add_external_host(Config) ->
    Config2 = case nkservice_app:get(externalHost) of
        undefined ->
            Config;
        Host ->
            Config#{external_host => Host}
    end,
    Config3 = case nkservice_app:get(externalPort) of
        undefined ->
            Config2;
        Port ->
            Config2#{external_port => Port}
    end,
    Config4 = case nkservice_app:get(externalPath) of
        undefined ->
            Config3;
        Path ->
            Config3#{external_path => Path}
    end,
    Config4.





%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).



