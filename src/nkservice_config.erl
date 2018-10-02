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

-module(nkservice_config).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([config_service/3, get_plugin_mod/1, get_callback_mod/1]).
-export([negated_service/1]).

-define(LLOG(Type, Txt, Args, Service),
    lager:Type("NkSERVICE '~s' "++Txt, [maps:get(id, Service) | Args])).

-export([remove_modules_packages/2]).

%% ===================================================================
%% Public
%% ===================================================================


%% @doc Create or update the configuration for a service
%% - class, name, plugins, meta are copied from Spec, if present, otherwise
%%   took from Service
%% - cache, scripts, callbacks are merged, unless remove:=true in their configs
%% - plugins are merged, the same way

-spec config_service(nkservice:id(), nkservice:spec(), nkservice:service()) ->
    {ok, nkservice:service()} | {error, term()}.

config_service(Id, Spec, Service) ->
    try
        Spec2 = nkservice_syntax:parse(Spec#{id=>Id}),
        Service2 = config_core(Spec2, Service#{id=>Id}),
        {ok, Service2}
    catch
        throw:Throw -> {error, Throw}
    end.


%% @doc 
negated_service(Service) ->
    RemFun = fun(V) -> V#{remove=>true} end,
    maps:map(
        fun
            (Key, Data) when Key==packages; Key==modules; Key==callbacks;
                             Key==cache; Key==secret; Key==debug ->
                maps:map(fun(_Key2, _Data2) -> RemFun(#{}) end, Data);
            (_Key, Data) ->
                Data
        end,
        Service).


%% @private
config_core(#{id:=Id}=Spec, Service) ->
    UUID = case Spec of
        #{uuid:=UserUUID} ->
            case Service of
                #{uuid:=ServiceUUID} when ServiceUUID /= UserUUID ->
                    throw(uuid_cannot_be_updated);
                _ ->
                    UserUUID
            end;
        _ ->
            update_uuid(Id, Spec)
    end,
    General = maps:with([class, name, domain, plugins, debug_actors, meta, parent], Spec),
    Service2 = maps:merge(Service, General#{uuid=>UUID}),
    Defaults = #{
        class => <<>>,
        name => to_bin(Id),
        domain => <<>>,
        plugins => [],
        meta => #{}
    },
    Service3 = maps:merge(Defaults, Service2),
    config_secrets(Spec, Service3).


%% @private
%% New entries are add or updated
%% If remove:=true, it is deleted
config_secrets(Spec, Service) ->
    SpecSecrets1 = maps:get(secret, Spec, []),
    SpecSecrets2 = maps:from_list([
        {Key, Val} || #{key:=Key, value:=Val} <- SpecSecrets1
    ]),
    OldSecrets = maps:get(secret, Service, #{}),
    Secrets1 = maps:merge(OldSecrets, SpecSecrets2),
    ToRemove = [Key || {Key, #{remove:=true}} <- maps:to_list(Secrets1)],
    Secrets2 = maps:without(ToRemove, Secrets1),
    config_modules(Spec, Service#{secret=>Secrets2}).



%% @private
%% All modules described in spec are analyzed and compiled
%% Old ones are left, can be deleted defining them again with remove=true
config_modules(Spec, Service) ->
    SpecModules1 = maps:get(modules, Spec, []),
    SpecModules2 = maps:from_list([{Id, S} || #{id:=Id}=S <- SpecModules1]),
    SpecModuleIds = maps:keys(SpecModules2),
    % We mark all old packages belonging to defined modules as removed
    % temporarily, in case they are not used any more
    Service2 = remove_modules_packages(SpecModuleIds, Service),
    OldModules = maps:get(modules, Service2, #{}),
    Modules1 = maps:merge(OldModules, SpecModules2),
    ToRemove = [Id || {Id, #{remove:=true}} <- maps:to_list(Modules1)],
    Modules2 = maps:without(ToRemove, Modules1),
    NewModules = SpecModuleIds -- ToRemove,
    % Adds compile info in modules (module_packages will be temporary)
    % Stores debug and cache in service
    Modules3 = nkservice_config_luerl:compile_modules(NewModules, Modules2, Service2),
    config_modules_packages(Spec, Service2#{modules=>Modules3}).


%% @private
%% Adds module packages to spec packages
config_modules_packages(Spec, Service) ->
    SpecPackages1 = maps:get(packages, Spec, []),
    Modules1 = maps:get(modules, Service, #{}),
    SpecPackages2 = maps:fold(
        fun(_ModuleId, ModuleSpec, Acc) ->
            case ModuleSpec of
                #{'_module_packages':=ModPackagesSpec} ->
                    Acc ++ maps:values(ModPackagesSpec);
                _ ->
                    Acc
            end
        end,
        SpecPackages1,
        Modules1),
    Spec2 = Spec#{packages=>SpecPackages2},
    % Find duplicated ids
    Spec3 = nkservice_syntax:parse(Spec2),
    % Remove temporary info
    Modules2 = maps:map(
        fun(_, ModuleSpec) ->
            case ModuleSpec of
                #{'_module_packages':=ModPackagesSpec} ->
                    M2 = maps:remove('_module_packages', ModuleSpec),
                    M2#{packages => maps:keys(ModPackagesSpec)};
                _ ->
                    ModuleSpec
            end
        end,
        Modules1),
    config_packages(Spec3, Service#{modules=>Modules2}).


%% @private
%% We merge the new packages with the old ones
config_packages(Spec, Service) ->
    SpecPackages1 = maps:get(packages, Spec, []),
    SpecPackages2 = lists:map(
        fun(#{class:=Class}=PSpec) ->
            case nkservice_util:get_package_plugin(Class) of
                undefined ->
                    throw({unknown_package_class, Class});
                Plugin ->
                    PSpec#{plugin=>Plugin}
            end
        end,
        SpecPackages1),
    SpecPackages3 = maps:from_list([{Id, PSpec} || #{id:=Id}=PSpec <- SpecPackages2]),
    OldPackages = maps:get(packages, Service, #{}),
    Packages1 = maps:merge(OldPackages, SpecPackages3),
    ToRemove = [Id || {Id, #{remove:=true}} <- maps:to_list(Packages1)],
    Packages2 = maps:without(ToRemove, Packages1),
    Plugins1 = maps:get(plugins, Service, []),
    Plugins2 = [Plugin || #{plugin:=Plugin} <- maps:values(Packages2)],
    Plugins3 = expand_plugins(Plugins1++Plugins2),
    Service2 = Service#{
        plugin_ids => Plugins3,             % down to top
        packages => Packages2
    },
    % We call configure only for plugins listen in new Spec and not removed
    NewPackages = maps:keys(Packages2)--ToRemove,
    Service3 = package_configure(NewPackages, Service2),
    #{modules:=Modules1} = Service2,
    Modules2 = add_apis(NewPackages, Modules1, Service3),
    config_hash(Service3#{modules:=Modules2}).


%% @private
config_hash(Service) ->
    Service#{hash=>erlang:phash2(Service)}.


%% Mark all packages belonging to this modules as removed
remove_modules_packages(ModuleIds, Service) ->
    Packages2 = maps:filter(
        fun(_PackageId, Package) ->
            case Package of
                #{module_id:=ModuleId} ->
                    not lists:member(ModuleId, ModuleIds);
                _ ->
                    true
            end
        end,
        maps:get(packages, Service, #{})),
    Service#{packages=>Packages2}.


%% @private
package_configure([], Service) ->
    Service;

package_configure([PackageId|Rest], #{packages:=Packages, plugin_ids:=PluginIds}=Service) ->
    Package = #{class:=Class} = maps:get(PackageId, Packages),
    ?LLOG(debug, "configuring package '~s' (~s)", [PackageId, Class], Service),
    % High to low
    Service3 = package_configure(lists:reverse(PluginIds), Package, Service),
    package_configure(Rest, Service3).


%% @private
package_configure([], _Package, Service) ->
    Service;

package_configure([PluginId|Rest], Package, #{packages:=Packages}=Service) ->
    Mod = get_plugin_mod(PluginId),
    #{class:=Class, id:=PackageId} = Package,
    {Package3, Service3} = case
        nklib_util:apply(Mod, plugin_config, [Class, Package, Service])
    of
        ok ->
            {Package, Service};
        not_exported ->
            {Package, Service};
        continue ->
            {Package, Service};
        {ok, Package2} ->
            {Package2, Service};
        {ok, Package2, Service2} ->
            {Package2, Service2};
        {error, Error} ->
            throw({{PackageId, Error}})
    end,
    Hash = erlang:phash2(maps:with([config, class, debug], Package3)),
    Package4 = Package3#{hash=>Hash},
    Service4 = Service3#{packages:=Packages#{PackageId=>Package4}},
    package_configure(Rest, Package4, Service4).


%% @doc
%% Add apis to module scripts
add_apis([], Modules, _Service) ->
    Modules;

add_apis([PackageId|Rest], Modules, Service) ->
    #{packages:=Packages, plugin_ids:=PluginIds} = Service,
    Package = maps:get(PackageId, Packages),
    % Low to high plugins are applied to add apis and callbacks
    Modules2 = add_apis(PluginIds, Package, Modules, Service),
    add_apis(Rest, Modules2, Service).


%% @private
add_apis([], _Package, Modules, _Service) ->
    Modules;

add_apis([PluginId|Rest], #{module_class:=luerl}=Package, Modules, Service) ->
    #{module_id:=ModuleId, id:=PackageId, class:=Class} = Package,
    Mod = get_plugin_mod(PluginId),
    ModSpec1 = maps:get(ModuleId, Modules),
    ModSpec2 = case nklib_util:apply(Mod, plugin_api, [Class]) of
        #{luerl := APIs} ->
            %% Add APIs to luerl object
            nkservice_config_luerl:add_apis(ModuleId, ModSpec1, PackageId, APIs, Service);
        _ ->
            ModSpec1
    end,
    Modules2 = Modules#{ModuleId:=ModSpec2},
    add_apis(Rest, Package, Modules2, Service);

add_apis([_PluginId|Rest], Package, Modules, Service) ->
    add_apis(Rest, Package, Modules, Service).


%% @private
get_plugin_mod(Plugin) ->
    case get_plugin_mod_check(Plugin) of
        undefined ->
            throw({plugin_unknown, Plugin});
        Mod ->
            Mod
    end.


%% @private
get_plugin_mod_check(Plugin) ->
    Mod = list_to_atom(atom_to_list(Plugin)++"_plugin"),
    case code:ensure_loaded(Mod) of
        {module, _} ->
            Mod;
        {error, nofile} ->
            case code:ensure_loaded(Plugin) of
                {module, _} ->
                    Plugin;
                {error, nofile} ->
                    undefined
            end
    end.


%% @private
get_callback_mod(Plugin) ->
    Mod = list_to_atom(atom_to_list(Plugin)++"_callbacks"),
    case code:ensure_loaded(Mod) of
        {module, _} ->
            Mod;
        {error, nofile} ->
            case code:ensure_loaded(Plugin) of
                {module, _} ->
                    Plugin;
                {error, nofile} ->
                    undefined
            end
    end.


%% @private Expands a list of plugins with their dependencies
%% First in the returned list will be the higher-level plugins, last one
%% will be 'nkservice' usually

-spec expand_plugins([atom()]) ->
    [module()].

expand_plugins(ModuleList) ->
    List1 = add_group_deps([nkservice|ModuleList]),
    List2 = add_all_deps(List1, [], []),
    case nklib_sort:top_sort(List2) of
        {ok, Sorted} ->
            % Optional plugins could still appear in dependencies, and show up here
            Sorted2 = [Plugin || Plugin <- Sorted, get_plugin_mod_check(Plugin) /= undefined],
            Sorted2;
        {error, Error} ->
            throw(Error)
    end.


%% @private
%% All plugins belonging to the same 'group' are added a dependency on the 
%% previous plugin in the same group
add_group_deps(Plugins) ->
    add_group_deps(lists:reverse(Plugins), [], #{}).


%% @private
add_group_deps([], Acc, _Groups) ->
    Acc;

add_group_deps([Plugin|Rest], Acc, Groups) when is_atom(Plugin) ->
    add_group_deps([{Plugin, []}|Rest], Acc, Groups);

add_group_deps([{Plugin, Deps}|Rest], Acc, Groups) ->
    Mod = get_plugin_mod(Plugin),
    Group = case nklib_util:apply(Mod, plugin_group, []) of
        not_exported -> undefined;
        continue -> undefined;
        Group0 -> Group0
    end,
    case Group of
        undefined ->
            add_group_deps(Rest, [{Plugin, Deps}|Acc], Groups);
        _ ->
            Groups2 = maps:put(Group, Plugin, Groups),
            case maps:find(Group, Groups) of
                error ->
                    add_group_deps(Rest, [{Plugin, Deps}|Acc], Groups2);
                {ok, Last} ->
                    add_group_deps(Rest, [{Plugin, [Last|Deps]}|Acc], Groups2)
            end
    end.


%% @private
add_all_deps([], _Optional, Acc) ->
    Acc;

add_all_deps([Plugin|Rest], Optional, Acc) when is_atom(Plugin) ->
    add_all_deps([{Plugin, []}|Rest], Optional, Acc);

add_all_deps([{Plugin, List}|Rest], Optional, Acc) when is_atom(Plugin) ->
    case lists:keyfind(Plugin, 1, Acc) of
        {Plugin, OldList} ->
            List2 = lists:usort(OldList++List),
            Acc2 = lists:keystore(Plugin, 1, Acc, {Plugin, List2}),
            add_all_deps(Rest, Optional, Acc2);
        false ->
            case get_plugin_deps(Plugin, List, Optional) of
                undefined ->
                    add_all_deps(Rest, Optional, Acc);
                {Deps, Optional2} ->
                    add_all_deps(Deps++Rest, Optional2, [{Plugin, Deps}|Acc])
            end
    end;

add_all_deps([Other|_], _Optional, _Acc) ->
    throw({invalid_plugin_name, Other}).


%% @private
get_plugin_deps(Plugin, BaseDeps, Optional) ->
    case get_plugin_mod_check(Plugin) of
        undefined ->
            case lists:member(Plugin, Optional) of
                true ->
                    undefined;
                false ->
                    throw({plugin_unknown, Plugin})
            end;
        Mod ->
            {Deps1, Optional2} = case nklib_util:apply(Mod, plugin_deps, []) of
                List when is_list(List) ->
                    get_plugin_deps_list(List, [], Optional);
                not_exported ->
                    {[], Optional};
                continue ->
                    {[], Optional}
            end,
            Deps2 = lists:usort(BaseDeps ++ [nkservice|Deps1]) -- [Plugin],
            {Deps2, Optional2}
    end.


%% @private
get_plugin_deps_list([], Deps, Optional) ->
    {Deps, Optional};

get_plugin_deps_list([{Plugin, optional}|Rest], Deps, Optional) when is_atom(Plugin) ->
    get_plugin_deps_list(Rest, [Plugin|Deps], [Plugin|Optional]);

get_plugin_deps_list([Plugin|Rest], Deps, Optional) when is_atom(Plugin) ->
    get_plugin_deps_list(Rest, [Plugin|Deps], Optional).


%% @private
update_uuid(Id, Spec) ->
    LogPath = nkservice_app:get(logPath),
    Path = filename:join(LogPath, atom_to_list(Id)++".uuid"),
    case read_uuid(Path) of
        {ok, UUID} ->
            UUID;
        {error, Path} ->
            save_uuid(Path, nklib_util:uuid_4122(), Spec)
    end.


%% @private
read_uuid(Path) ->
    case file:read_file(Path) of
        {ok, Binary} ->
            case binary:split(Binary, <<$,>>) of
                [UUID|_] when byte_size(UUID)==36 -> {ok, UUID};
                _ -> {error, Path}
            end;
        _ ->
            {error, Path}
    end.


%% @private
save_uuid(Path, UUID, Spec) ->
    Content = io_lib:format("~p", [Spec]),
    case file:write_file(Path, Content) of
        ok ->
            UUID;
        Error ->
            lager:warning("NkSERVICE: Could not write file ~s: ~p", [Path, Error]),
            UUID
    end.


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).
