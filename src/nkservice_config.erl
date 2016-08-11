%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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

-export([config_service/2, stop_plugins/2, make_cache/1]).

-include_lib("nkpacket/include/nkpacket.hrl").




%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts or update the configuration for the service
%% OldService must contain id, name and uuid, and can contain 
%% cache, plugins and transports
-spec config_service(nkservice:user_spec(), nkservice:service()) ->
    {ok, nkservice:service()}.

config_service(Config, Service) ->
    try
        Syntax = nkservice_syntax:syntax(), 
        Config2 = case nkservice_util:parse_syntax(Config, Syntax, #{}) of
            {ok, Parsed} -> Parsed;
            {error, Error1} -> throw(Error1)
        end,
        GlobalKeys = [class, plugins, callback, log_level],
        % Extract global key values from Config, if present
        Service2 = maps:with(GlobalKeys, Config2),
        % Global keys are first-level keys on Service map
        Service3 = maps:merge(Service, Service2),
        Plugins = maps:get(plugins, Service3, []),
        CallBack = maps:get(callback, Service3, none),
        DownToTop = case expand_plugins([nkservice|Plugins], CallBack) of
            {ok, Expanded} -> Expanded;
            {error, Error2} -> throw(Error2)
        end,
        OldPlugins = maps:get(plugins, Service, []),
        ToStop = lists:reverse(OldPlugins -- DownToTop),
        % Stop old services no longer present
        Service4 = stop_plugins(ToStop, Service3),
        OldConfig = maps:get(config, Service4, #{}),
        UserConfig1 = maps:without(GlobalKeys, Config2),
        UserConfig2 = maps:merge(OldConfig, UserConfig1),
        % Options not in global keys go to 'config' key
        Service5 = Service4#{plugins=>DownToTop, config=>UserConfig2},
        TopToDown = lists:reverse(DownToTop),
        Service6 = config_plugins(TopToDown, Service5),
        Service7 = start_plugins(DownToTop, OldPlugins, Service6),
        Defaults = #{log_level=>notice, listen_ids=>#{}},
        Service8 = maps:merge(Defaults, Service7),
        Service9 = set_luerl(Service8),
        {ok, Service9}
    catch
        throw:Throw -> {error, Throw}
    end.



%% @private
config_plugins([], Service) ->
    Service;

config_plugins([Plugin|Rest], #{config:=Config}=Service) ->
    % lager:warning("Config Plugin: ~p", [Plugin]),
    Mod = get_mod(Plugin),
    Config2 = case nklib_util:apply(Mod, plugin_syntax, []) of
        not_exported -> 
            Config;
        Syntax when is_map(Syntax), map_size(Syntax)==0 ->
            Config;
        Syntax when is_map(Syntax) ->
            Defaults = case nklib_util:apply(Mod, plugin_defaults, []) of
                not_exported -> #{};
                Apply1 when is_map(Apply1) -> Apply1
            end,
            case nkservice_util:parse_syntax(Config, Syntax, Defaults) of
                {ok, Parsed1} -> Parsed1;
                {error, Error1} -> throw({{Plugin, Error1}})
            end
    end,
    Service2 = Service#{config:=Config2},
    Service3 = case nklib_util:apply(Mod, plugin_config, [Config2, Service2]) of
        not_exported -> 
            Service2;
        {ok, ApplyConfig} ->
            Service2#{config:=ApplyConfig};
        {ok, ApplyConfig, ApplyCache} ->
            Key = list_to_atom("config_"++atom_to_list(Plugin)),
            maps:put(Key, ApplyCache, Service2#{config:=ApplyConfig});
        {error, Error2} ->
            throw({{Plugin, Error2}})
    end,
    #{config:=Config3} = Service3,
    Service4 = case nklib_util:apply(Mod, plugin_listen, [Config3, Service3]) of
        not_exported -> 
            Service3;
        Apply3 ->
            case nkservice_util:parse_transports(Apply3) of
                {ok, Parsed2} -> 
                    OldListen = maps:get(listen, Service, #{}),
                    Listen = maps:put(Plugin, Parsed2, OldListen),
                    Service3#{listen=>Listen};
                error -> 
                    throw({invalid_plugin_listen, Plugin})
            end
    end,
    #{config:=Config4} = Service4,
    Service5 = case nklib_util:apply(Mod, plugin_lua_modules, [Config4, Service4]) of
        not_exported -> 
            Service4;
        LuaModules1 when is_list(LuaModules1) ->
            OldModules = maps:get(lua_modules, Service, []),
            LuaModules2 = OldModules ++ LuaModules1,
            Service4#{lua_modules=>lists:usort(LuaModules2)}
    end,
    config_plugins(Rest, Service5).


%% @private
start_plugins([], _OldPlugins, Service) ->
    Service;

start_plugins([Plugin|Rest], OldPlugins, #{config:=Config}=Service) ->
    Mod = get_mod(Plugin),
    Service2 = case lists:member(Plugin, OldPlugins) of
        false ->
            % lager:warning("Start Plugin: ~p", [Plugin]),
            case nklib_util:apply(Mod, plugin_start, [Config, Service]) of
                {ok, Config2} -> Service#{config:=Config2};
                {stop, Error} -> throw({plugin_stop, {Plugin, Error}});
                not_exported -> Service
            end;
        true ->
            % lager:warning("Update Plugin: ~p", [Plugin]),
            case nklib_util:apply(Mod, plugin_update, [Config, Service]) of
                {ok, Config2} -> Service#{config:=Config2};
                {stop, Error} -> throw({plugin_stop, {Plugin, Error}});
                not_exported -> Service
            end
    end,
    start_plugins(Rest, OldPlugins, Service2).
    

%% @private
stop_plugins([], Service) ->
    Service;

stop_plugins([Plugin|Rest], Service) ->
    % lager:warning("Stop Plugin: ~p", [Plugin]),
    #{config:=Config, listen:=Listen, listen_ids:=ListenIds} = Service,
    Listen2 = maps:remove(Plugin, Listen),
    case maps:find(Plugin, ListenIds) of
        {ok, PluginIds} ->
            lists:foreach(
                fun(ListenId) -> nkpacket:stop_listener(ListenId) end, PluginIds);
        error -> 
            ok
    end,
    ListenIds2 = maps:remove(Plugin, ListenIds),
    Mod = get_mod(Plugin),
    Service2 = case nklib_util:apply(Mod, plugin_stop, [Config, Service]) of
        {ok, Config2} -> Service#{config:=Config2};
        not_exported -> Service
    end,
    Key = list_to_atom("config_"++atom_to_list(Plugin)),
    Service3 = maps:remove(Key, Service2),
    stop_plugins(Rest, Service3#{listen=>Listen2, listen_ids=>ListenIds2}).


%% @private
get_mod(Plugin) ->
    case get_callback(Plugin) of
        {ok, Callback} -> Callback;
        error -> throw({unknown_plugin, Plugin})
    end.


%% @private
get_callback(Plugin) ->
    Mod = list_to_atom(atom_to_list(Plugin)++"_callbacks"),
    case code:ensure_loaded(Mod) of
        {module, _} ->
            {ok, Mod};
        {error, nofile} ->
            case code:ensure_loaded(Plugin) of
                {module, _} ->
                    {ok, Plugin};
                {error, nofile} ->
                    error
            end
    end.


%% @private
-spec expand_plugins([module()], module()|none) ->
    {ok, [module()]} | {error, term()}.

expand_plugins(ModuleList, CallBack) ->
    try
        List1 = case CallBack of
            none -> ModuleList;
            _ -> [{CallBack, ModuleList}|ModuleList]
        end,
        List2 = add_group_deps(List1),
        List3 = add_all_deps(List2, []),
        case nklib_sort:top_sort(List3) of
            {ok, Sorted} -> {ok, Sorted};
            {error, Error} -> {error, Error}
        end
    catch
        throw:Throw -> {error, Throw}
    end.


%% @private
%% All plugins belonging to the same 'group' are added a dependency on the 
%% previous plugin in the same group
add_group_deps(Plugins) ->
    add_group_deps(lists:reverse(Plugins), [], #{}).


%% @private
add_group_deps([], Acc, _Groups) ->
    Acc;

add_group_deps([Name|Rest], Acc, Groups) when is_atom(Name) ->
    add_group_deps([{Name, []}|Rest], Acc, Groups);

add_group_deps([{Name, Deps}|Rest], Acc, Groups) ->
    Group = case get_callback(Name) of
        {ok, Mod} ->
            case nklib_util:apply(Mod, plugin_group, []) of
                not_exported -> undefined;
                Group0 -> Group0
            end;
        error ->
            throw({unknown_plugin, Name})
    end,
    case Group of
        undefined ->
            add_group_deps(Rest, [{Name, Deps}|Acc], Groups);
        _ ->
            Groups2 = maps:put(Group, Name, Groups),
            case maps:find(Group, Groups) of
                error ->
                    add_group_deps(Rest, [{Name, Deps}|Acc], Groups2);
                {ok, Last} ->
                    add_group_deps(Rest, [{Name, [Last|Deps]}|Acc], Groups2)
            end
    end.


%% @private
add_all_deps([], Acc) ->
    Acc;

add_all_deps([Name|Rest], Acc) when is_atom(Name) ->
    add_all_deps([{Name, []}|Rest], Acc);

add_all_deps([{Name, List}|Rest], Acc) when is_atom(Name) ->
    case lists:keyfind(Name, 1, Acc) of
        {Name, OldList} ->
            List2 = lists:usort(OldList++List),
            Acc2 = lists:keystore(Name, 1, Acc, {Name, List2}),
            add_all_deps(Rest, Acc2);
        false ->
            Deps = get_plugin_deps(Name, List),
            add_all_deps(Deps++Rest, [{Name, Deps}|Acc])
    end;

add_all_deps([Other|_], _Acc) ->
    throw({invalid_plugin_name, Other}).


%% @private
get_plugin_deps(Name, BaseDeps) ->
    Deps = case get_callback(Name) of
        {ok, Mod} ->
            case nklib_util:apply(Mod, plugin_deps, []) of
                List when is_list(List) ->
                    List;
                not_exported ->
                    []
            end;
        error ->
            throw({unknown_plugin, Name})
    end,
    lists:usort(BaseDeps ++ [nkservice|Deps]) -- [Name].


%% @private
set_luerl(#{config:=Config}=Service) ->
    case Config of
        #{lua_script:=Script} ->
            case file:read_file(Script) of
                {ok, Bin} ->
                    set_luerl_start(Bin, Service);
                {error, _} ->
                    Script2 = case Script of
                        <<"/", R/binary>> -> R;
                        _ -> Script
                    end,
                    Base = code:priv_dir(nkservice) ++ "/scripts",
                    Script3 = filename:join(Base, Script2),
                    case file:read_file(Script3) of
                        {ok, Bin} ->
                            set_luerl_start(Bin, Service);
                        {error, Error} ->
                            lager:warning("Could not read file ~s", [Script3]),
                            throw({script_read_error, Error, Script3})
                    end
            end;
        _ ->
            Service
    end.


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
    Service2 = Service#{timestamp => nklib_util:l_timestamp()},
    BaseSyntax = make_base_syntax(Service2),
    % Gather all fun specs from all callbacks modules on all plugins
    Plugins = maps:get(plugins, Service),
    PluginSyntax = plugin_callbacks_syntax(Plugins),
    FullSyntax = PluginSyntax ++ BaseSyntax,
    {ok, Tree} = nklib_code:compile(Id, FullSyntax),
    LogPath = nkservice_app:get(log_path),
    ok = nklib_code:write(Id, Tree, LogPath).


%% @private Generates a ready-to-compile config getter functions
%% with a function for each member of the map, plus defauls and configs
make_base_syntax(Service) ->
    maps:fold(
        fun(Key, Value, Acc) -> 
            % Maps not yet suported in 17 (supported in 18)
            Value1 = case is_map(Value) of
                true -> {map, term_to_binary(Value)};
                false -> Value
            end,
            [nklib_code:getter(Key, Value1)|Acc] 
        end,
        [],
        Service).



%% @private Generates the ready-to-compile syntax of the generated callback module
%% taking all plugins' callback functions
plugin_callbacks_syntax(Plugins) ->
    plugin_callbacks_syntax(Plugins, #{}).


%% @private
plugin_callbacks_syntax([Name|Rest], Map) ->
    Mod = list_to_atom(atom_to_list(Name)++"_callbacks"),
    code:ensure_loaded(Mod),
    case nklib_code:get_funs(Mod) of
        error ->
            code:ensure_loaded(Name),
            case nklib_code:get_funs(Name) of
                error ->
                    plugin_callbacks_syntax(Rest, Map);
                List ->
                    Map1 = plugin_callbacks_syntax(List, Name, Map),
                    plugin_callbacks_syntax(Rest, Map1)
            end;
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


