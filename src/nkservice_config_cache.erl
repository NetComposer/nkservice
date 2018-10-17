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

-module(nkservice_config_cache).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([make_cache/1, get_full_service/1]).

% -include_lib("nkpacket/include/nkpacket.hrl").


-define(LLOG(Type, Txt, Args, Service),
    lager:Type("NkSERVICE '~s' "++Txt, [maps:get(id, Service) | Args])).

-include("nkservice.hrl").

%% ===================================================================
%% Public
%% ===================================================================



%% @doc Generates and compiles in-memory cache module
%% Functions will include:
%% - service() with (mostly) the full service specification
%% - direct access to id, class, name, etc. (See FunKeys)
%% - special entries service_cache, service_debug, service_secret,
%%   service_module_core y service_module_callback
%% - callbacks of all plugins' callback modules

make_cache(#{id:=Id}=Service) ->
    % Remove chunks of code
    SafeModules = maps:map(
        fun(_, V) -> V#{lua_state:=<<>>} end,
        maps:get(modules, Service, #{})),
    % Secret values are not stored in 'service' key in order to avoid saving
    % it to disk, and making it 'public'
    SafeSecrets = maps:map(
        fun(_, _V) -> <<>> end,
        maps:get(secret, Service, #{})),
    Service2 = Service#{
        timestamp =>  nklib_date:epoch(msecs),
        modules => SafeModules,
        secret => SafeSecrets
    },
    FunKeys = [
        id, class, name, domain, uuid, hash, timestamp,
        plugins, plugin_ids, packages, modules, meta, parent
    ],
    Spec1 = maps:map(
        fun(_K, V) -> {single, V} end,
        maps:with(FunKeys, Service2)),
    {Cache, ServiceCache} = get_cache(Service),
    {Debug, ServiceDebug} = get_debug(Service),
    {Callbacks, ServiceCBs} = get_callbacks(Service),
    Code = maps:fold(
        fun(I, #{lua_state:=St}, Acc) -> [{[I], term_to_binary(St)}|Acc] end,
        [],
        maps:get(modules, Service, #{})),
    Secrets = maps:fold(
        fun(SecretId, V, Acc) -> [{[SecretId], V}|Acc] end,
        [],
        maps:get(secret, Service, #{})),
    CacheSpec2 = Spec1#{
        service => {single, Service2},
        cache => {single, Cache},
        debug => {single, Debug},
        callbacks => {single, Callbacks},
        service_cache => {multi, 1, ServiceCache, none},
        service_debug => {multi, 1, ServiceDebug, undefined},
        service_secret => {multi, 1, Secrets, none},
        service_module_code => {multi, 1, Code, none},
        service_callback => {multi, 3, ServiceCBs, undefined}
    },
    BaseSyntax = make_base_syntax(CacheSpec2),
    % Gather all fun specs from all callbacks modules on all plugins
    PluginList = maps:get(plugin_ids, Service),
    PluginSyntax = plugin_callbacks_syntax(PluginList),
    FullSyntax = PluginSyntax ++ BaseSyntax,
    ?LLOG(info, "starting module compilation...", [], Service),
    {ok, Tree} = nklib_code:compile(Id, FullSyntax),
    % Expansion functions are also removed from saved version in log
    % See nkservice:spec_with_secrets/1
    Tree2 = lists:filtermap(fun(T) -> filter_for_disk(T) end, Tree),
    LogPath = nkservice_app:get(logPath),
    ?LLOG(info, "saving to disk...", [], Service),
    ok = nklib_code:write(Id, Tree2, LogPath),
    ?LLOG(info, "compilation completed", [], Service),
    ok.



%% @private
%% Cache functions are service_cache(Class, PackageId, Type)
get_cache(Service) ->
    % lager:error("SRV: ~p\n", [Service]),
    Cache1 = maps:fold(
        fun(_PackageId, Package, Acc) ->
            Acc ++ maps:to_list(maps:get(cache_map, Package, #{}))
        end,
        [],
        maps:get(packages, Service, #{})),
    Cache2 = maps:fold(
        fun(_ModuleId, Module, Acc) ->
            % io:format("MODULES: ~p ~p ~p\n", [_ModuleId, maps:get(cache_map, Module, #{}), Module]),


            Acc ++ maps:to_list(maps:get(cache_map, Module, #{}))
        end,
        Cache1,
        maps:get(modules, Service, #{})),
    ServiceCache = [{[Type], Val} || {Type, Val} <- Cache2],
    {maps:from_list(Cache2), ServiceCache}.



%% @private
get_callbacks(Service) ->
    CBs = maps:fold(
        fun(_ModuleId, Module, Acc) ->
            Acc ++ maps:to_list(maps:get(callbacks, Module, #{}))
        end,
        [],
        maps:get(modules, Service, #{})),
    ServiceCBs = [{[Class, PackageId, Name], Val}
                    || {{Class, PackageId, Name}, Val} <- CBs],
    {maps:from_list(CBs), ServiceCBs}.


%% @private
get_debug(Service) ->
    Debug1 = maps:fold(
        fun(_PackageId, Package, Acc) ->
            Acc ++ maps:to_list(maps:get(debug_map, Package, #{}))
        end,
        [],
        maps:get(packages, Service, #{})),
    Debug2 = maps:fold(
        fun(_ModuleId, Module, Acc) ->
            Acc ++ maps:to_list(maps:get(debug_map, Module, #{}))
        end,
        Debug1,
        maps:get(modules, Service, #{})),
    Debug3 = lists:foldl(
        fun(Key, Acc) ->
            Key2 = case Key of
                <<"all">> ->
                    <<"all">>;
                _ ->
                    case binary:split(Key, <<":">>) of
                        [Class, Type] ->
                            {Class, Type};
                        [Class] ->
                            {Class, <<"all">>}
                    end
            end,
            Acc ++ [{{nkservice_actor, Key2, debug}, true}] end,
        Debug2,
        maps:get(debug_actors, Service, [])),
    ServiceDebug = [{[Type], Val} || {Type, Val} <- Debug3],
    {maps:from_list(Debug3), ServiceDebug}.



%% @private Re-generates service with secrets
get_full_service(SrvId) ->
    Service = ?CALL_SRV(SrvId, service),
    Secrets = maps:map(
        fun(SId, <<>>) -> ?CALL_SRV(SrvId, service_secret, [SId]) end,
        maps:get(secret, Service, #{})),
    Modules = maps:map(
        fun(ModuleId, Spec) ->
            Code = ?CALL_SRV(SrvId, service_module_code, [ModuleId]),
            Spec#{lua_state:=binary_to_term(Code)}
        end,
        maps:get(modules, Service, #{})),
    Service#{secret=>Secrets, modules=>Modules}.



%% @private Generates a ready-to-compile config getter functions
%% with a function for each member of the map, plus defaults and configs
make_base_syntax(Spec) ->
    maps:fold(
        fun
            (Key, {multi, Arity, [], _Default}, Acc) ->
                % If empty, we ensure the function is created
                [nklib_code:getter_args(to_atom(Key), Arity, [], undefined)|Acc];
            (Key, {multi, Arity, Values, Default}, Acc) ->
                % If Default=none, not catch-all clause will be added
                [nklib_code:getter_args(to_atom(Key), Arity, Values, Default)|Acc];
            (Key, {single, Value}, Acc) ->
                [nklib_code:getter(to_atom(Key), Value)|Acc]
        end,
        [],
        Spec).


%% @private Generates the ready-to-compile syntax of the generated callback module
%% taking all plugins' callback functions
plugin_callbacks_syntax(Plugins) ->
    plugin_callbacks_syntax(Plugins, #{}).


%% @private
plugin_callbacks_syntax([Plugin|Rest], Map) ->
    case nkservice_config:get_callback_mod(Plugin) of
        undefined ->
            plugin_callbacks_syntax(Rest, Map);
        Mod ->
            case nklib_code:get_funs(Mod) of
                error ->
                    plugin_callbacks_syntax(Rest, Map);
                List ->
                    Map1 = plugin_callbacks_syntax(List, Mod, Map),
                    plugin_callbacks_syntax(Rest, Map1)
            end
    end;

plugin_callbacks_syntax([], Map) ->
    maps:fold(
        fun({Fun, Arity}, {Value, Pos}, Acc) ->
            [nklib_code:fun_expr(Fun, Arity, Pos, [Value])|Acc]
        end,
        [],
        Map).


%% @private
plugin_callbacks_syntax([{Fun, Arity}|Rest], Mod, Map) ->
    FunStr = atom_to_list(Fun),
    case FunStr of
        "plugin_" ++ _ ->
            plugin_callbacks_syntax(Rest, Mod, Map);
        _ ->
            case maps:find({Fun, Arity}, Map) of
                error ->
                    Pos = 1,
                    Value = nklib_code:call_expr(Mod, Fun, Arity, Pos);
                {ok, {Syntax, Pos0}} ->
                    Case = case Arity==2 andalso lists:reverse(FunStr) of
                        % "tini_"++_ -> case_expr_ok;         % Fun is ".._init"
                        % "etanimret_"++_ -> case_expr_ok;    % Fun is ".._terminate"
                        _ -> case_expr
                    end,
                    Pos = Pos0+1,
                    Value = nklib_code:Case(Mod, Fun, Arity, Pos, [Syntax])
            end,
            Map1 = maps:put({Fun, Arity}, {Value, Pos}, Map),
            plugin_callbacks_syntax(Rest, Mod, Map1)
    end;

plugin_callbacks_syntax([], _, Map) ->
    Map.


%% @private
filter_for_disk({tree, function, _, {func, {tree, atom, _, Name}, _}}) ->
    case atom_to_binary(Name, utf8) of
        <<"secret">> ->
            false;
        <<"service_secret">> ->
            false;
        <<"service_module_code">> ->
            false;
        _ ->
            true
    end;

filter_for_disk(_) ->
    true.


%% @private
%%to_atom(Key) when is_atom(Key) -> Key;
%%to_atom(Key) -> binary_to_atom(to_bin(Key), utf8).
to_atom(Key) -> nklib_util:make_atom(?MODULE, Key).


%%%% @private
%%to_bin(Term) when is_binary(Term) -> Term;
%%to_bin(Term) -> nklib_util:to_binary(Term).

