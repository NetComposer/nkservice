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

-module(nkservice_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([parse_syntax/3, parse_transports/1]).
-export([make_id/1, get_callback/1, config_service/2]).
-export([update_uuid/2, make_cache/1]).

-include_lib("nkpacket/include/nkpacket.hrl").



%% ===================================================================
%% Public
%% ===================================================================


parse_syntax(Spec, Syntax, Defaults) ->
    Opts = #{return=>map, defaults=>Defaults},
    case nklib_config:parse_config(Spec, Syntax, Opts) of
        {ok, Parsed, _Other} -> {ok, Parsed};
        {error, Error} -> {error, Error}
    end.


%% @private
parse_transports([{[{_, _, _, _}|_], Opts}|_]=Transps) when is_map(Opts) ->
    {ok, Transps};

parse_transports(Spec) ->
    case nkpacket:multi_resolve(Spec, #{resolve_type=>listen}) of
        {ok, List} ->
            {ok, List};
        _ ->
            error
    end.


%% ===================================================================
%% Private
%% ===================================================================



%% @doc Generates the service id from any name
-spec make_id(nkservice:name()) ->
    nkservice:id().

make_id(Name) ->
    list_to_atom(
        string:to_lower(
            case binary_to_list(nklib_util:hash36(Name)) of
                [F|Rest] when F>=$0, F=<$9 -> [$A+F-$0|Rest];
                Other -> Other
            end)).


get_callback(Plugin) ->
    Mod = list_to_atom(atom_to_list(Plugin)++"_callbacks"),
    case code:ensure_loaded(Mod) of
        {module, _} ->
            {ok, Mod};
        error ->
            case code:ensure_loaded(Plugin) of
                {module, _} ->
                    {ok, Plugin};
                error ->
                    error
            end
    end.


%% @doc Starts or update the configuration for the service
%% OldService must contain id, name and uuid, and can contain 
%% cache, plugins and transports
-spec config_service(nkservice:user_spec(), nkservice:service()) ->
    {ok, nkservice:service()}.

config_service(UserSpec, OldService) ->
    try
        Syntax = nkservice_syntax:syntax(), 
        Defaults = nkservice_syntax:defaults(),
        ParseOpts = #{return=>map, defaults=>Defaults},
        Service1 = case nklib_config:parse_config(UserSpec, Syntax, ParseOpts) of
            {ok, Data2, _} -> Data2;
            {error, Error1} -> throw(Error1)
        end,
        Service2 = maps:merge(OldService, Service1),
        lager:warning("S2: ~p", [Service2]),
        Plugins = maps:get(plugins, Service2),
        CallBack = maps:get(callback, Service2, none),
        DownToTop = case expand_plugins(Plugins, CallBack) of
            {ok, Expanded} -> Expanded;
            {error, Error2} -> throw(Error2)
        end,
        OldPlugins = maps:get(plugins, OldService, []),
        TopToDown = lists:reverse(DownToTop),
        {UserSpec3, Service3} = config_plugins(TopToDown, UserSpec, Service2),
        Service4 = start_plugins(DownToTop, OldPlugins, UserSpec3, Service3),
        ToStop = lists:reverse(OldPlugins -- DownToTop),
        Service5 = stop_plugins(ToStop, Service4),
        NetOpts = nkservice_syntax:get_net_opts(UserSpec),
        {ok, Service5#{plugins=>DownToTop, net_opts=>NetOpts}}
    catch
        throw:Throw -> {error, Throw}
    end.


%% @private
config_plugins([], UserSpec, Service) ->
    {UserSpec, Service};

config_plugins([Plugin|Rest], UserSpec, Service) ->
    lager:warning("Config Plugin: ~p", [Plugin]),
    Mod = get_mod(Plugin),
    % If we use a key that is exactly the name of the plugin, it overrides any
    % other plugin configuration (used by high level plugins)
    PluginSpec1 = case maps:find(Plugin, UserSpec) of
        {ok, Find1} when is_map(Find1) -> Find1;
        _ -> UserSpec
    end,
    PluginSpec2 = case nklib_util:apply(Mod, plugin_parse, [PluginSpec1, Service]) of
        not_exported -> PluginSpec1;
        {ok, Apply1} -> Apply1;
        {error, Error1} -> throw({plugin_syntax_error, {Plugin, Error1}})
    end,
    UserSpec2 = maps:merge(UserSpec, PluginSpec2),
    UserCache = case nklib_util:apply(Mod, plugin_cache, [PluginSpec2, Service]) of
        not_exported -> #{};
        Apply2 when is_map(Apply2) -> Apply2
    end,
    UserListen = case nklib_util:apply(Mod, plugin_listen, [PluginSpec2, Service]) of
        not_exported -> 
            [];
        Apply3 ->
            case parse_transports(Apply3) of
                {ok, Parse1} -> Parse1;
                error -> throw({invalid_plugin_listen, Plugin})
            end
    end,
    OldCache = maps:get(cache, Service, #{}),
    OldListen = maps:get(listen, Service, #{}),
    Service2 = Service#{
        cache => maps:merge(OldCache, UserCache),
        listen => maps:put(Plugin, UserListen, OldListen)
    },
    config_plugins(Rest, UserSpec2, Service2).


%% @private
start_plugins([], _OldPlugins, _UserSpec, Service) ->
    Service;

start_plugins([Plugin|Rest], OldPlugins, UserSpec, Service) ->
    lager:warning("Start Plugin: ~p", [Plugin]),
    Mod = get_mod(Plugin),
    Service2 = case lists:member(Plugin, OldPlugins) of
        false ->
            case nklib_util:apply(Mod, plugin_start, [UserSpec, Service]) of
                {ok, Apply} -> Apply;
                {stop, Error} -> throw({plugin_stop, {Plugin, Error}});
                not_exported -> Service
            end;
        true ->
            case nklib_util:apply(Mod, plugin_update, [UserSpec, Service]) of
                {ok, Apply} -> Apply;
                {stop, Error} -> throw({plugin_stop, {Plugin, Error}});
                not_exported -> Service
            end
    end,
    start_plugins(Rest, OldPlugins, UserSpec, Service2).
    

%% @private
stop_plugins([], Service) ->
    Service;

stop_plugins([Plugin|Rest], Service) ->
    lager:warning("Stop Plugin: ~p", [Plugin]),
    Mod = get_mod(Plugin),
    case nklib_util:apply(Mod, plugin_stop, [Service]) of
        {ok, Service2} -> ok;
        _ -> Service2 = Service
    end,
    stop_plugins(Rest, Service2).


%% @private
get_mod(Plugin) ->
    case get_callback(Plugin) of
        {ok, Callback} -> Callback;
        error -> throw({unknown_plugin, Plugin})
    end.


%% @private
-spec expand_plugins([module()], module()|none) ->
    {ok, [module()]} | {error, term()}.

expand_plugins(ModuleList, CallBack) ->
    try
        List2 = case CallBack of
            none -> ModuleList;
            _ -> [{CallBack, ModuleList}|ModuleList]
        end,
        List3 = do_expand_plugins(List2, []),
        case nklib_sort:top_sort(List3) of
            {ok, List} -> {ok, List};
            {error, Error} -> {error, Error}
        end
    catch
        throw:Throw -> {error, Throw}
    end.


%% @private
do_expand_plugins([], Acc) ->
    Acc;

do_expand_plugins([Name|Rest], Acc) when is_atom(Name) ->
    do_expand_plugins([{Name, []}|Rest], Acc);

do_expand_plugins([{Name, List}|Rest], Acc) when is_atom(Name), is_list(List) ->
    case lists:keymember(Name, 1, Acc) of
        true ->
            do_expand_plugins(Rest, Acc);
        false ->
            Deps = get_plugin_deps(Name, List),
            do_expand_plugins(Deps++Rest, [{Name, Deps}|Acc])
    end;

do_expand_plugins([Other|_], _Acc) ->
    throw({invalid_plugin_name, Other}).


%% @private
get_plugin_deps(Name, BaseDeps) ->
    Deps = case get_callback(Name) of
        {ok, Mod} ->
            case nklib_util:apply(Mod, plugin_deps, []) of
                List when is_list(List) ->
                    nklib_util:store_value(nkservice, List);
                not_exported ->
                    [nkservice]
            end;
        error ->
            throw({unknown_plugin, Name})
    end,
    lists:usort(BaseDeps ++ Deps) -- [Name].


%% @private
update_uuid(Id, Name) ->
    LogPath = nkservice_app:get(log_path),
    Path = filename:join(LogPath, atom_to_list(Id)++".uuid"),
    case read_uuid(Path) of
        {ok, UUID} ->
            ok;
        {error, Path} ->
            UUID = nklib_util:uuid_4122(),
            save_uuid(Path, Name, UUID)
    end,
    UUID.


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
save_uuid(Path, Name, UUID) ->
    Content = [UUID, $,, nklib_util:to_binary(Name)],
    case file:write_file(Path, Content) of
        ok ->
            ok;
        Error ->
            lager:warning("Could not write file ~s: ~p", [Path, Error]),
            ok
    end.


%% @doc Generates and compiles in-memory cache module
make_cache(#{id:=Id}=Service) ->
    Service2 = maps:remove(cache, Service),
    Service3 = Service2#{timestamp => nklib_util:l_timestamp()},
    BaseSyntax = make_base_syntax(Service3),
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
    Cache = maps:get(cache, Service, #{}),
    Base = maps:from_list(
        [
            {nklib_util:to_atom("cache_"++nklib_util:to_list(Key)), Value} ||
            {Key, Value} <- maps:to_list(Cache)
        ]),
    Spec = maps:merge(Service, Base),
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
        Spec).



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
    case maps:find({Fun, Arity}, Map) of
        error ->
            Pos = 1,
            Value = nklib_code:call_expr(Mod, Fun, Arity, Pos);
        {ok, {Syntax, Pos0}} ->
            Case = case Arity==2 andalso lists:reverse(atom_to_list(Fun)) of
                "tini_"++_ -> case_expr_ok;         % Fun is ".._init"
                "etanimret_"++_ -> case_expr_ok;    % Fun is ".._terminate"
                _ -> case_expr
            end,
            Pos = Pos0+1,
            Value = nklib_code:Case(Mod, Fun, Arity, Pos, [Syntax])
    end,
    Map1 = maps:put({Fun, Arity}, {Value, Pos}, Map),
    plugin_callbacks_syntax(Rest, Mod, Map1);

plugin_callbacks_syntax([], _, Map) ->
    Map.


