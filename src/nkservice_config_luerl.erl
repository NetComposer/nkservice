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

-module(nkservice_config_luerl).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([compile_modules/3]).
-export([add_apis/5]).
-export([start_package/2, service_table/1]).

-include_lib("nkpacket/include/nkpacket.hrl").
-include_lib("luerl/src/luerl.hrl").


-define(LLOG(Type, Txt, Args, Service),
    lager:Type("NkSERVICE '~s' "++Txt, [maps:get(id, Service) | Args])).


%% ===================================================================
%% Public
%% ===================================================================

%% @doc
compile_modules([], Modules, _Service) ->
    Modules;

compile_modules([ModuleId|Rest], Modules, Service) ->
    ModSpec1 = maps:get(ModuleId, Modules),
    ModSpec2 = case ModSpec1 of
        #{code:=Bin} ->
            compile_module(ModuleId, ModSpec1, Bin, Service);
        #{file:=File} ->
            case file:read_file(File) of
                {ok, Bin} ->
                    compile_module(ModuleId, ModSpec1, Bin, Service);
                {error, Error} ->
                    ?LLOG(warning, "could not read file ~s: ~p", [File, Error], Service),
                    throw({module_read_error, ModuleId})
            end;
        #{url:=_Url} ->
            throw({module_read_error, ModuleId})
    end,
    ?LLOG(debug, "configuring module '~s'", [ModuleId], Service),
    compile_modules(Rest, Modules#{ModuleId=>ModSpec2}, Service).


%% @private
compile_module(ModuleId, ModSpec, Bin, #{id:=SrvId}=Service) ->
    MaxInstances = maps:get(max_instances, ModSpec),
    Cache1 = maps:get(cache, ModSpec, #{}),
    Cache2 = Cache1#{{nkservice_luerl, max_instances, ModuleId} => MaxInstances},
    ModSpec2 = ModSpec#{cache_map => Cache2},
    ModSpec3 = case maps:get(debug, ModSpec, false) of
        true ->
            Debug1 = maps:get(debug_map, ModSpec, #{}),
            Debug2 = Debug1#{{nkservice_luerl, ModuleId} => true},
            ModSpec2#{debug_map=>Debug2};
        false ->
            ModSpec2
    end,
    LuaState1 = nkservice_luerl_lib:init(SrvId, ModuleId),
    Db1 = #{srv=>SrvId, module_id=>ModuleId, packages=>#{}, callbacks=>#{}},
    put(nkservice_config_luerl, Db1),
    try luerl:do(Bin, LuaState1) of
        {_Res, LuaState2} ->
            #{packages:=Packages, callbacks:=CBs} = get(nkservice_config_luerl),
            ?LLOG(debug, "module '~s' added packages '~s'",
                  [ModuleId, nklib_util:bjoin(maps:keys(Packages))], Service),
            ?LLOG(debug, "module '~s' added callbacks '~s'",
                  [ModuleId, nklib_util:bjoin(maps:keys(CBs))], Service),
            % Packages2 = find_callbacks(Packages1, ModuleId, LuaState2),
            % lager:error("NKLOG RES ~p", [_Res]),
            % lager:error("NKLOG RES ~p", [luerl:decode(hd(_Res), LuaState2)]),
            ModSpec3#{
                '_module_packages' => Packages,
                callbacks => CBs,
                lua_state => LuaState2,
                hash => erlang:phash2(Bin)
            }
    catch
        error:{lua_error, Reason, Trace} ->
            throw({lua_error, {Reason, Trace}});
        Class:Error ->
            Trace = erlang:get_stacktrace(),
            throw({error, {Class, {Error, Trace}}})
    end.


%% @private
start_package([Class], St) ->
    start_package([Class, nil], St);

start_package([Class, TableId], St) ->
    try
        DB = case get(nkservice_config_luerl) of
            Db0 when is_map(Db0) ->
                Db0;
            _ ->
                throw("Call to startPackage not allowed")
        end,
        #{
            srv := SrvId,
            module_id := ModuleId,
            packages := Packages1,
            callbacks := CBs1
        } = DB,
        Opts = case luerl:decode(TableId, St) of
            nil ->
                [];
            Opts0 when is_list(Opts0) ->
                Opts0;
            _ ->
                throw("Invalid package specification")
        end,
        Id = nklib_util:get_value(<<"id">>, Opts, <<ModuleId/binary, $-, Class/binary>>),
        {Opts2, CBs2} = extract_callbacks(Opts, CBs1, ModuleId, Class, Id, []),
        Spec1 = #{
            id => Id,
            class => Class,
            module_class => luerl,
            module_id => ModuleId,
            config => maps:without([<<"id">>], Opts2)
        },
        Spec2 = case catch nkservice_syntax:parse(#{id=>SrvId, packages=>[Spec1]}) of
            #{packages:=[Parsed]} ->
                Parsed;
            {syntax_error, Field} ->
                throw(<<"Syntax error: ", Field/binary>>);
            {error, _Error} ->
                throw("Syntax error")
        end,
        Packages2 = Packages1#{Id => Spec2},
        DB2 = DB#{
            packages => Packages2,
            callbacks => CBs2
        },
        % Pass the info to config
        put(nkservice_config_luerl, DB2),
        LuaSpec1 = nklib_util:store_values([
            {id, Id},
            {class, Class},
            {'_nk_type' ,<<"nkservice_package">>}], Opts),
        LuaSpec2 = lists:map(
            fun
                ({Key, {function, Fun}}) -> {Key, Fun};
                ({Key, Val}) -> {Key, Val}
            end,
            LuaSpec1
        ),
        St2 = luerl:set_table(service_table([packages, Id]), LuaSpec2, St),
        {UserPackage, St3} = luerl:get_table1(service_table([packages, Id]), St2),
        {[UserPackage], St3}
    catch
        throw:Throw ->
            luerl_lib:lua_error(Throw, St)
    end;

start_package(_, St) ->
    luerl_lib:lua_error("Invalid package specification", St).


%% @private
extract_callbacks([], CBs, _ModuleId, _Class, _PackageId, Acc) ->
    {maps:from_list(Acc), CBs};

extract_callbacks([{Name, {function, _}}|Rest], CBs, ModuleId, Class, PackageId, Acc) ->
    Val = #{
        class => luerl,
        module_id => ModuleId,
        luerl_fun => service_table([packages, PackageId, Name])
    },
    CBs2 = CBs#{{Class, PackageId, Name} => Val},
    extract_callbacks(Rest, CBs2, ModuleId, Class, PackageId, [{Name, Val}|Acc]);

extract_callbacks([{Name, Value}|Rest], CBs, ModuleId, Class, PackageId, Acc) ->
    extract_callbacks(Rest, CBs, ModuleId, Class, PackageId, [{Name, Value}|Acc]).


%% @doc Adds a set of functions to a table
add_apis(ModuleId, ModSpec, PackageId, APIs, #{id:=SrvId}=Service) ->
    #{lua_state:=St1} = ModSpec,
    St2 = maps:fold(
        fun(Name, {Mod, Fun}, Acc) ->
            Value = fun(Args, St) ->
                nkservice_util:luerl_api(SrvId, PackageId, Mod, Fun, Args, St)
            end,
            ?LLOG(debug, "function API '~s' added to script '~s' (~s)",
                  [Name, ModuleId, PackageId], Service),
            luerl:set_table(service_table([packages, PackageId, Name]), Value, Acc)
        end,
        St1,
        APIs),
    ModSpec#{lua_state:=St2}.

%% @doc
service_table(List) ->
    [<<"Service">> | [to_bin(T) || T<-List]].



%%lua_get_funs() ->
%%    <<"
%%        tables = ''
%%        for k,v in pairs(package.loaded._G) do
%%            if type(v) == 'table' then tables = tables .. '.' .. k end
%%        end
%%        funs = ''
%%        for k,v in pairs(package.loaded._G) do
%%            --- if type(v) == 'function' then funs = funs .. '.' .. k end
%%            funs = funs .. '.' .. k
%%        end
%%        return tables, funs
%%    ">>.


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).


%%<<"
%%function dumpTable(o)
%%    if type(o) == 'table' then
%%        local s = '{ '
%%        for k,v in pairs(o) do
%%            if type(k) ~= 'number' then k = '\"'..k..'\"' end
%%            s = s .. '['..k..'] = ' .. dumpTable(v) .. ','
%%        end
%%        return s .. '} '
%%    else
%%        return tostring(o)
%%    end
%%end
%%">>
