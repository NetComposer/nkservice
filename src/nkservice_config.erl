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

-export([config_service/2, make_cache/1]).
-export([start_plugin/3, stop_plugin/3, update_plugin/3]).

-include_lib("nkpacket/include/nkpacket.hrl").


-define(LLOG(Type, Txt, Args, Service),
    lager:Type("NkSERVICE '~s' "++Txt, [maps:get(id, Service) | Args])).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Create or update the configuration for a service
%% - class, name, log_level, debug are copied from Spec, if present, otherwise
%%   took from Service
%% - cache, scripts, callbacks are merged, unless remove:=true in their configs
%% - plugins are merged, the same way

-spec config_service(nkservice:spec(), nkservice:service()) ->
    {ok, nkservice:service()}.

config_service(Spec, #{id:=Id}=Service) ->
    try
        Spec2 = case nkservice_syntax:parse(Spec#{id=>Id}) of
            {ok, Parsed} ->
                Parsed;
            {error, SyntaxError} ->
                throw(SyntaxError)
        end,
        Spec3 = update_listen(Spec2),
        % nkservice_srv:put(Id, nkservice_debug, Debug),
        %% Keys class, name, log_level, if present, are updated on service
        Global = maps:with([class, name, log_level], Spec3),
        Service2 = maps:merge(Service, Global),
        Defaults = #{
            class => <<>>,
            name => to_bin(Id),
            log_level => notice
        },
        Service3 = maps:merge(Defaults, Service2),
        Service4 = update_cache(Spec3, Service3),
        Service5 = update_debug(Spec3, Service4),
        Service6 = update_plugins(Spec3, Service5),
        Service7 = update_scripts(Spec3, Service6),
        Service8 = update_callbacks(Spec3, Service7),
        {ok, Service8}
    catch
        throw:Throw -> {error, Throw}
    end.


%% @private
update_listen(#{listen:=Listen}=Spec) ->
    Rest = lists:map(
        fun(#{id:=Id}=L1) ->
            L2 = maps:with([remove], L1),
            L2#{
                id => <<"nkservice_listen_", Id/binary>>,
                class => nkservice_rest,
                config => maps:with([url, opts], L1)
             }
        end,
        Listen),
    Plugins1 = maps:get(plugins, Spec, []),
    Plugins2 = Rest ++ Plugins1,
    Spec#{plugins=>Plugins2};

update_listen(Spec) ->
    Spec.



%% @private
update_plugins(#{plugins:=Plugins}, Service) ->
    OldPlugins = maps:get(plugins, Service, #{}),
    NewPlugins1 = maps:from_list([{Id, Spec} || #{id:=Id}=Spec <- Plugins]),
    NewPlugins2 = maps:merge(OldPlugins, NewPlugins1),
    ToRemove = [Id || #{id:=Id, remove:=true} <- Plugins],
    PluginList1 = maps:to_list(maps:without(ToRemove, NewPlugins2)),
    Modules1 = [Class || {_, #{class:=Class}} <- PluginList1],
    Modules2 = expand_plugins(Modules1),
    Service2 = Service#{
        plugin_modules => Modules2,           % down to top
        plugins => NewPlugins2                % keep removed configs to stop them
    },
    % We call configure only for plugins listen in new Spec and not removed
    configure_plugins(maps:keys(NewPlugins1)--ToRemove, Service2);

update_plugins(_Spec, Service) ->
    Service.



%% @private
%% New entries are add or updated
%% If value is 'null' are deleted
update_cache(#{cache:=Cache}, Service) ->
    OldCache = maps:get(cache, Service, #{}),
    NewCache = maps:from_list([{Key, Val} || #{key:=Key, value:=Val} <- Cache]),
    Cache1 = maps:merge(OldCache, NewCache),
    ToRemove = [Key || #{key:=Key, remove:=true} <- Cache],
    Cache2 = maps:without(ToRemove, Cache1),
    Service#{cache=>Cache2};

update_cache(_Spec, Service) ->
    Service.


%% @private
update_debug(#{debug:=Debug}, Service) ->
    Debug2 = [{Key, Spec} || #{key:=Key, spec:=Spec} <- Debug],
    Service#{debug=>Debug2};

update_debug(_Spec, Service) ->
    maps:merge(#{debug=>[]}, Service).


%% @private
update_scripts(#{scripts:=Scripts}, Service) ->
    OldScripts = maps:get(scripts, Service, #{}),
    SpecScripts = maps:from_list([maps:take(id, Spec) || Spec <- Scripts]),
    NewScripts1 = maps:merge(OldScripts, SpecScripts),
    ToRemove = [Id || #{id:=Id, remove:=true} <- Scripts],
    NewScripts2 = maps:without(ToRemove, NewScripts1),
    Service2 = Service#{scripts=>NewScripts2},
    load_scripts(NewScripts2, Service2);

update_scripts(_Spec, Service) ->
    Service.


%% @private
update_callbacks(#{callbacks:=Callbacks}, Service) ->
    OldCallbacks = maps:get(callbacks, Service, #{}),
    SpecCallbacks = maps:from_list([maps:take(id, Spec) || Spec <- Callbacks]),
    NewCallbacks1 = maps:merge(OldCallbacks, SpecCallbacks),
    ToRemove = [Id || #{id:=Id, remove:=true} <- Callbacks],
    NewCallbacks2 = maps:without(ToRemove, NewCallbacks1),
    Service#{callbacks=>NewCallbacks2};

update_callbacks(_Spec, Service) ->
    Service.


%% @private
configure_plugins([], Service) ->
    Service;

configure_plugins([PluginId|Rest], #{plugins:=Config}=Service) ->
    #{class:=Class} = PluginSpec = maps:get(PluginId, Config),
    Mod = get_plugin(Class),
    PluginConfig = maps:get(config, PluginSpec, #{}),
    ?LLOG(notice, "configuring plugin ~s (~s)", [PluginId, Class], Service),
    Service2 = case
        nklib_util:apply(Mod, plugin_config, [PluginId, PluginConfig, Service])
    of
        ok ->
            Service;
        not_exported ->
            Service;
        continue ->
            Service;
        {ok, NewPluginConfig} ->
            PluginSpec2 = PluginSpec#{config=>NewPluginConfig},
            Config2 = Config#{PluginId=>PluginSpec2},
            Service#{plugins:=Config2};
        {ok, NewPluginConfig, NewService} ->
            PluginSpec2 = PluginSpec#{config=>NewPluginConfig},
            Config2 = Config#{PluginId=>PluginSpec2},
            NewService#{plugins:=Config2};
        {error, Error2} ->
            throw({{PluginId, Error2}})
    end,
    configure_plugins(Rest, Service2).


%% @private
start_plugin(PluginId, Pid, #{plugins:=Config}=Service) ->
    #{class:=Class} = PluginSpec = maps:get(PluginId, Config, #{}),
    PluginConfig = maps:get(config, PluginSpec, #{}),
    ?LLOG(info, "starting plugin ~s (~s)", [PluginId, Class], Service),
    Mod = get_plugin(Class),
    case nklib_util:apply(Mod, plugin_start, [PluginId, PluginConfig, Pid, Service]) of
        ok ->
            ok;
        not_exported ->
            ok;
        continue ->
            ok;
        {error, Error} ->
            {error, Error}
    end.


%% @private
stop_plugin(Plugin, Pid, #{plugins:=Config}=Service) ->
    #{class:=Class} = PluginSpec = maps:get(Plugin, Config, #{}),
    PluginConfig = maps:get(config, PluginSpec, #{}),
    ?LLOG(info, "stopping plugin ~s (~s)", [Plugin, Class], Service),
    Mod = get_plugin(Class),
    case nklib_util:apply(Mod, plugin_stop, [Plugin, PluginConfig, Pid, Service]) of
        ok ->
            ok;
        not_exported ->
            ok;
        continue ->
            ok;
        {error, Error} ->
            ?LLOG(warning, "error stopping plugin ~p", [Plugin], Service),
            {error, Error}
    end.


%% @private
update_plugin(Plugin, Pid, #{plugins:=Config}=Service) ->
    #{class:=Class} = PluginSpec = maps:get(Plugin, Config, #{}),
    PluginConfig = maps:get(config, PluginSpec, #{}),
    ?LLOG(info, "updating plugin ~s (~s)", [Plugin, Class], Service),
    Mod = get_plugin(Class),
    case nklib_util:apply(Mod, plugin_update, [Plugin, PluginConfig, Pid, Service]) of
        ok ->
            ok;
        not_exported ->
            ok;
        continue ->
            ok;
        {error, Error} ->
            {error, Error}
    end.


%% @private
get_plugin(Class) ->
    Mod = list_to_atom(atom_to_list(Class)++"_plugin"),
    case code:ensure_loaded(Mod) of
        {module, _} ->
            Mod;
        {error, nofile} ->
            case code:ensure_loaded(Class) of
                {module, _} ->
                    Class;
                {error, nofile} ->
                    throw({unknown_plugin, Class})
            end
    end.


%% @private
get_callback(Class) ->
    Mod = list_to_atom(atom_to_list(Class)++"_callbacks"),
    case code:ensure_loaded(Mod) of
        {module, _} ->
            Mod;
        {error, nofile} ->
            case code:ensure_loaded(Class) of
                {module, _} ->
                    Class;
                {error, nofile} ->
                    throw({unknown_plugin, Class})
            end
    end.


%% @private Expands a list of plugins with its found dependencies
%% First in the returned list will be the higher-level plugins, last one
%% will be 'nkservice' usually

-spec expand_plugins([atom()]) ->
    [module()].

expand_plugins(ModuleList) ->
    List1 = add_group_deps([nkservice|ModuleList]),
    List2 = add_all_deps(List1, []),
    case nklib_sort:top_sort(List2) of
        {ok, Sorted} ->
            Sorted;
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
    Mod = get_callback(Plugin),
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
add_all_deps([], Acc) ->
    Acc;

add_all_deps([Plugin|Rest], Acc) when is_atom(Plugin) ->
    add_all_deps([{Plugin, []}|Rest], Acc);

add_all_deps([{Plugin, List}|Rest], Acc) when is_atom(Plugin) ->
    case lists:keyfind(Plugin, 1, Acc) of
        {Plugin, OldList} ->
            List2 = lists:usort(OldList++List),
            Acc2 = lists:keystore(Plugin, 1, Acc, {Plugin, List2}),
            add_all_deps(Rest, Acc2);
        false ->
            Deps = get_plugin_deps(Plugin, List),
            add_all_deps(Deps++Rest, [{Plugin, Deps}|Acc])
    end;

add_all_deps([Other|_], _Acc) ->
    throw({invalid_plugin_name, Other}).


%% @private
get_plugin_deps(Plugin, BaseDeps) ->
    Mod = get_plugin(Plugin),
    Deps = case nklib_util:apply(Mod, plugin_deps, []) of
        List when is_list(List) ->
            List;
        not_exported ->
            [];
        continue ->
            []
    end,
    lists:usort(BaseDeps ++ [nkservice|Deps]) -- [Plugin].


%% @private
load_scripts([], Service) ->
    Service;

load_scripts([#{id:=Id}=Spec|Rest], Service) ->
    Service2 = case Spec of
        #{code:=Bin} ->
            set_luerl_start(Bin, Service);
        #{file:=File} ->
            case file:read_file(File) of
                {ok, Bin} ->
                    set_luerl_start(Bin, Service);
                {error, Error} ->
                    ?LLOG(warning, "could not read file ~s: ~p", [File, Error], Service),
                    throw({script_read_error, Id})
            end;
        #{url:=_Url} ->
            throw({script_read_error, Id})
    end,
    load_scripts(Rest, Service2).


%%
%%%% @private
%%set_luerl(#{config:=Config}=Service) ->
%%    case Config of
%%        #{lua_script:=Script} ->
%%            case file:read_file(Script) of
%%                {ok, Bin} ->
%%                    set_luerl_start(Bin, Service);
%%                {error, _} ->
%%                    Script2 = case Script of
%%                        <<"/", R/binary>> -> R;
%%                        _ -> Script
%%                    end,
%%                    Base = code:priv_dir(nkservice) ++ "/scripts",
%%                    Script3 = filename:join(Base, Script2),
%%                    case file:read_file(Script3) of
%%                        {ok, Bin} ->
%%                            set_luerl_start(Bin, Service);
%%                        {error, Error} ->
%%                            lager:warning("Could not read file ~s", [Script3]),
%%                            throw({script_read_error, Error, Script3})
%%                    end
%%            end;
%%        _ ->
%%            Service
%%    end.


%% @private
set_luerl_start(Script, #{lua_modules:=Modules}=Service) ->
    State1 = luerl:init(),
    State2 = lists:foldl(
        fun({NS, Mod}, Acc) ->
            luerl:load_module([package, loaded, '_G', NS], Mod, Acc)
        end, 
        State1, 
        Modules),
    try luerl:do(Script, State2) of
        {_, State3} ->
            {[Funs1], _} = luerl:do(lua_get_funs(), State3),
            [_|Funs2] = binary:split(Funs1, <<".">>, [global]),
            Funs3 = Funs2 -- lua_sys_funs(),
            Funs4 = [binary_to_atom(F, latin1) || F <- Funs3],
            BinState = term_to_binary(State3),
            Service#{lua_funs=>Funs4, lua_state=>BinState}

            % io:format("R2A: ~p\n", [State2#luerl.g]),
            % io:format("R2: ~p\n", [luerl_emul:get_table_keys({tref, 4}, State2)]),
            % io:format("R2: ~p\n", [luerl:get_table1([<<"package">>], State2)]),
            % io:format("R2: ~p\n", [lager:pr(State2, ?MODULE)]),
            % lager:warning("R3: ~p", [luerl:decode_list(R, State2)]),
    catch 
        error:{lua_error, Reason, _} ->
            throw({lua_error, Reason})
    end.


lua_get_funs() -> 
    <<"
        funs = ''
        for k,v in pairs(package.loaded._G) do 
            if type(v) == 'function' then funs = funs .. '.' .. k end
        end
        return funs
    ">>.

lua_sys_funs() ->
    [
        <<"assert">>, <<"collectgarbage">>, <<"dofile">>, <<"eprint">>, 
        <<"error">>, <<"getmetatable">>, <<"ipairs">>, <<"load">>, <<"loadfile">>, 
        <<"loadstring">>, <<"next">>, <<"pairs">>, <<"pcall">>, <<"print">>, 
        <<"rawequal">>, <<"rawget">>, <<"rawlen">>, <<"rawset">>, <<"require">>, 
        <<"select">>, <<"setmetatable">>, <<"tonumber">>, <<"tostring">>, <<"type">>, 
        <<"unpack">>
    ].


%% @doc Generates and compiles in-memory cache module
make_cache(#{id:=Id}=Service) ->
    Service2 = Service#{timestamp => nklib_util:m_timestamp()},
    BaseKeys = [
        id, class, name, plugin_modules, plugins, uuid, log_level, timestamp,
        debug, cache, listen, meta
    ],
    Spec1 = maps:with(BaseKeys, Service2),
    Spec2 = lists:foldl(
        fun({K, V}, Acc) ->
            K2 = <<"service_cache_", (to_bin(K))/binary>>,
            Acc#{binary_to_atom(K2, utf8) => V}
        end,
        Spec1,
        maps:to_list(maps:get(cache, Service, #{}))),
    Spec3 = lists:foldl(
        fun({K, V}, Acc) ->
            K2 = <<"service_callback_", (to_bin(K))/binary>>,
            Acc#{binary_to_atom(K2, utf8) => V}
        end,
        Spec2,
        maps:to_list(maps:get(callbacks, Service, #{}))),
    Spec4 = lists:foldl(
        fun({K, V}, Acc) ->
            K2 = <<"service_script_", (to_bin(K))/binary>>,
            Acc#{binary_to_atom(K2, utf8) => V}
        end,
        Spec3,
        maps:to_list(maps:get(scripts, Service, #{}))),
    BaseSyntax = make_base_syntax(Spec4#{spec=>Spec1}),
    % Gather all fun specs from all callbacks modules on all plugins
    PluginList = maps:get(plugin_modules, Service2),
    PluginSyntax = plugin_callbacks_syntax(PluginList),
    FullSyntax = PluginSyntax ++ BaseSyntax,
    {ok, Tree} = nklib_code:compile(Id, FullSyntax),
    LogPath = nkservice_app:get(log_path),
    ok = nklib_code:write(Id, Tree, LogPath).


%% @private Generates a ready-to-compile config getter functions
%% with a function for each member of the map, plus defaults and configs
make_base_syntax(Service) ->
    maps:fold(
        fun(Key, Value, Acc) ->
            [nklib_code:getter(Key, Value)|Acc]
        end,
        [],
        Service).



%% @private Generates the ready-to-compile syntax of the generated callback module
%% taking all plugins' callback functions
plugin_callbacks_syntax(Plugins) ->
    plugin_callbacks_syntax(Plugins, #{}).


%% @private
plugin_callbacks_syntax([Plugin|Rest], Map) ->
    Mod = get_callback(Plugin),
    case nklib_code:get_funs(Mod) of
        error ->
            plugin_callbacks_syntax(Rest, Map);
        List ->
            Map1 = plugin_callbacks_syntax(List, Mod, Map),
            plugin_callbacks_syntax(Rest, Map1)
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
                        "tini_"++_ -> case_expr_ok;         % Fun is ".._init"
                        "etanimret_"++_ -> case_expr_ok;    % Fun is ".._terminate"
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
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).
