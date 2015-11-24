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

-module(nkservice_cache).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([get_plugins/1, make_cache/1]).

-include("nkservice.hrl").


%% ===================================================================
%% Private
%% ===================================================================


%% @private
-spec get_plugins([module()|{module(), [module()]}]) ->
    {ok, [module()]} | {error, term()}.

get_plugins(ModuleList) ->
    try
        List2 = lists:map(
            fun(Term) ->
                case Term of
                    {Name, all} -> {Name, nklib_util:keys(ModuleList)};
                    Other -> Other
                end
            end,
            ModuleList),
        List3 = get_plugins(List2, []),
        case nklib_sort:top_sort(List3) of
            {ok, List} -> {ok, List};
            {error, Error} -> {error, Error}
        end
    catch
        throw:Throw -> {error, Throw}
    end.


%% @private
get_plugins([], Acc) ->
    Acc;

get_plugins([Name|Rest], Acc) when is_atom(Name) ->
    get_plugins([{Name, []}|Rest], Acc);

get_plugins([{Name, List}|Rest], Acc) when is_atom(Name), is_list(List) ->
    case lists:keymember(Name, 1, Acc) of
        true ->
            get_plugins(Rest, Acc);
        false ->
            Deps = get_plugin_deps(Name, List),
            get_plugins(Deps++Rest, [{Name, Deps}|Acc])
    end;

get_plugins([Other|_], _Acc) ->
    throw({invalid_plugin_name, Other}).


%% @private
get_plugin_deps(Name, BaseDeps) ->
    case code:ensure_loaded(Name) of
        {module, Name} -> 
            ok;
        _ -> 
            throw({invalid_plugin_module, Name})
    end,
    case nklib_util:apply(Name, plugin_deps, []) of
        not_exported ->
            lists:usort(BaseDeps) -- [Name];
        Deps when is_list(Deps) ->
            lists:usort(BaseDeps ++ Deps) -- [Name];
        Other ->
            lager:warning("Plugin ~p invalid deps(): ~p", [Name, Other]),
            throw({invalid_plugin_deps, Name})
    end.


%% @private
make_cache(#{id:=Id, name:=Name}=SrvSpec) ->
    try
        {ok, UUID} = update_uuid(Id, Name),
        Plugins = maps:get(plugins, SrvSpec, []),
        BaseSpec = #{
            class => maps:get(class, SrvSpec, undefined),
            name => Name,
            plugins => Plugins,
            uuid => UUID,
            callback => maps:get(callback, SrvSpec, undefined),
            timestamp => nklib_util:l_timestamp(),
            spec => maps:remove(cache, SrvSpec)
        },
        BaseSyntax = make_base_syntax(BaseSpec, maps:get(cache, SrvSpec, #{})),
        % Gather all fun specs from all _callbacks modules on all plugins
        PluginSyntax = plugin_callbacks_syntax([nkservice|Plugins]),
        FullSyntax = PluginSyntax ++ BaseSyntax,
        {ok, Tree} = nklib_code:compile(Id, FullSyntax),
        LogPath = nkservice_app:get(log_path),
        ok = nklib_code:write(Id, Tree, LogPath)
    catch
        throw:Throw -> {error, Throw}
    end.


%% @private Generates a ready-to-compile config getter functions
%% with a function for each member of the map, plus defauls and configs
make_base_syntax(Spec, Cache) ->
    Base = maps:from_list(
	    [
	        {nklib_util:to_atom("cache_"++nklib_util:to_list(Key)), Value} ||
	        {Key, Value} <- maps:to_list(Cache)
	    ]),
    Spec2 = maps:merge(Spec, Base),
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
        Spec2).



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


plugin_callbacks_syntax([{Fun, 2}|Rest], Mod, Map) 
        when Fun==service_init; Fun==service_terminate ->
    case maps:find({Fun, 2}, Map) of
        error ->
            Pos = 1,
            Value = nklib_code:call_expr(Mod, Fun, 2, Pos);
        {ok, {Syntax, Pos0}} ->
            Pos = Pos0+1,
            Value = nklib_code:case_expr_ok(Mod, Fun, Pos, [Syntax])
    end,
    Map1 = maps:put({Fun, 2}, {Value, Pos}, Map),
    plugin_callbacks_syntax(Rest, Mod, Map1);

%% @private
plugin_callbacks_syntax([{Fun, Arity}|Rest], Mod, Map) ->
    case maps:find({Fun, Arity}, Map) of
        error ->
            Pos = 1,
            Value = nklib_code:call_expr(Mod, Fun, Arity, Pos);
        {ok, {Syntax, Pos0}} ->
            Pos = Pos0+1,
            Value = nklib_code:case_expr(Mod, Fun, Arity, Pos, [Syntax])
    end,
    Map1 = maps:put({Fun, Arity}, {Value, Pos}, Map),
    plugin_callbacks_syntax(Rest, Mod, Map1);

plugin_callbacks_syntax([], _, Map) ->
    Map.


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
    {ok, UUID}.


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

