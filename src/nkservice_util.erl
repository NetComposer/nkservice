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

-export([parse_syntax/3]).
-export([make_id/1, get_callback/1, update_service/2]).
-export([update_uuid/2, make_cache/1]).

-include_lib("nkpacket/include/nkpacket.hrl").



%% ===================================================================
%% Public
%% ===================================================================


parse_syntax(Spec, Syntax, Defaults) ->
    Opts = #{return=>map, defaults=>Defaults},
    case nklib_config:parse_syntax(Spec, Syntax, Opts) of
        {ok, Parsed, _} -> {ok, Parsed};
        {error, Error} -> {error, Error}
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


%% @doc Starts or update the service
%% OldService must contain id, name and uuidm and can contain 
%% cache, plugins and transports
-spec update_service(nkservice:user_spec(), nkservice:service()) ->
    {ok, nkservice:service()}.

update_service(UserSpec, OldService) ->
    try
        Syntax = nkservice_syntax:syntax(), 
        Defaults = nkservice_syntax:defaults(),
        ParseOpts = #{return=>map, defaults=>Defaults},
        case nklib_config:parse_config(UserSpec, Syntax, ParseOpts) of
            {ok, Service2, _} -> ok;
            {error, Error1} -> Service2 = throw(Error1)
        end,
        Plugins2 = maps:get(plugins, Service2),
        CallBack2 = maps:get(callback, Service2, none),
        case expand_plugins(Plugins2, CallBack2) of
            {ok, Plugins3} -> ok;
            {error, Error2} -> Plugins3 = throw(Error2)
        end,
        Service3 = maps:merge(OldService, Service2),
        OldPlugins = maps:get(plugins, OldService, []),
        Service4 = update_service(Plugins3, OldPlugins, UserSpec, Service3),
        {ok, Service4}
    catch
        throw:Throw -> {error, Throw}
    end.



%% @private
update_service([], _OldPlugins, _UserSpec, Service) ->
    Service;

update_service([Plugin|Rest], OldPlugins, UserSpec, Service) ->
    case get_callback(Plugin) of
        {ok, Mod} -> ok;
        error -> Mod = throw({unknown_plugin, Plugin})
    end,
    case nklib_util:apply(Mod, plugin_parse, [UserSpec]) of
        {ok, UserSpec2} -> ok;
        {error, Error1} -> UserSpec2 = throw({plugin_syntax_error, {Plugin, Error1}});
        not_exported -> UserSpec2 = UserSpec
    end,
    Service2 = maps:put(Plugin, UserSpec2, Service),
    case lists:member(Plugin, OldPlugins) of
        false ->
            case nklib_util:apply(Mod, plugin_start, [Service2]) of
                {ok, Service3} -> ok;
                {stop, Error} -> Service3 = throw({plugin_stop, {Plugin, Error}});
                not_exported -> Service3 = Service2
            end;
        true ->
            case nklib_util:apply(Mod, plugin_update, [Service2]) of
                {ok, Service3} -> ok;
                {stop, Error} -> Service3 = throw({plugin_stop, {Plugin, Error}});
                not_exported -> Service3 = Service2
            end
    end,
    case nklib_util:apply(Mod, plugin_cache, [Service3]) of
        UserCache when is_map(UserCache) -> ok;
        not_exported -> UserCache = #{}
    end,
    case nklib_util:apply(Mod, plugin_transports, [Service3]) of
        UserTranspList when is_list(UserTranspList) -> 
            case nkservice_util:parse_transports(UserTranspList) of
                {ok, UserTransps} -> ok;
                error -> UserTransps = throw({invalid_plugin_transport, Plugin})
            end;
        not_exported -> 
            UserTransps = []
    end,
    OldCache = maps:get(cache, Service, #{}),
    OldTransps = maps:get(transps, Service, #{}),
    Service4 = Service3#{
        cache => maps:merge(OldCache, UserCache),
        transps => maps:put(Plugin, UserTransps, OldTransps)
    },
    update_service(Rest, OldPlugins, UserSpec, Service4).
    

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
    BaseSyntax = make_base_syntax(Service),
    % Gather all fun specs from all callbacks modules on all plugins
    Plugins = maps:get(plugins, Service),
    PluginSyntax = plugin_callbacks_syntax([nkservice|Plugins]),
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

