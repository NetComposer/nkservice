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

%% @doc Backend module for luerl supporting Lager operations
-module(nkservice_luerl_lib).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([init/2, sample/0]).
-export([debug/2, info/2, notice/2, warning/2, error/2]).
-export([encode/2, decode/2]).

-include_lib("luerl/src/luerl.hrl").


%% Luerl functions

%% luerl_emul:init/0
%% -----------------
%%
%%  - Initializes the state record
%%  - Calls to luerl_lib_basic:install/1 to create _G, and
%%      it is inserted directly in the record ('g' field)
%%  - Calls luerl_lib_package:install/1
%%      - Creates global 'require' (it was not inserted in _G before)
%%      - Allocates a table with config, loaded, preload, etc. (most are arrays)
%%      - Set it accessible as 'package' at _G
%%      - Set is accessible as 'package.loaded.package'
%%  - It does the same for bit32, io, math, os, string, table, debug
%%  - Sets _G accessible as '_G' and also as 'package.loaded._G'
%%  - The final situation is:
%%      - A table {tref, 0} is inserted as 'g' field in record an also
%%        associated with path [], [_G] and [package, loaded, _G]
%%        (and [_G, package, loaded, _G])
%%      - A number of functions are inserted in this table (print, etc.)
%%      - A table is created for 'package' and inserted in _G as [_G, package]
%%        and [_G, package, loaded] (you can omit _G in paths)
%%      - A number of tables are created for other packages (math, etc.)
%%        and inserted in _G and package.loaded
%%
%%
%% luerl_emul:set_global_key/3 && set_global_name/3
%% ------------------------------------------------
%%
%%  - adds a key (for example a binary, a {function, fun/2} or an allocated
%%    table #tref{}) to table _G (tref 0)
%%  - see sample bellow
%%
%%
%%  luerl_emul:get_global_key/2 && get_global_name/2
%%  -----------------------------------------------
%%  - see sample bellow
%%
%%
%% luerl_emul:alloc_table/2
%% ------------------------
%%
%%  - creates a new table and inserts it in state, returns internal #tref{}
%%  - entries must be [{binary()|float(), InternalValue}]
%%    InternalValue can be {function fun/2}, binaries, float, etc, and also
%%    previously allocated tables (#trefs{}).
%%    For arrays, allocate a table like [{1.0, ...}]
%%  - you then need to insert the table in _G or some other place
%%    (or several at the same time)
%%
%%
%% luerl:function_list/2 && luerl_emul:get_table_keys/2
%% ----------------------------------------------------
%% - Gets to what a path is pointing to
%%     - for example, for [] is _G ({tref, 0}
%%     - for 'package' is {tref, 4}
%%     - for 'print' is a {function, fun/2}
%%       (same _G.print, package.loaded._G.print, _G.package.loaded._G.print)
%%     - for 'package.config' is a binary (see luerl_lib_package:config())
%%  - See test bellow
%%
%%
%% luerl:function_list/2 && luerl_emul:get_table_keys/2
%% ----------------------------------------------------
%% - Gets to what a path is pointing to, using a internal representation
%% - See test bellow
%%
%%
%%  luerl:encode/2
%%  --------------
%%
%%  - Encodes and Erlang term into internal representation.
%%  - State is not changed, unless we are encoding a table (or array: [{1.0, _}...]),
%%    that is first 'allocated' in the state
%%  - Encoded values:
%%      - nil, false, true, binary(), float(), {function fun/1,2}, #tref{}
%%
%%
%%  luerl:decode/2
%%  --------------
%%
%%  - Decodes an internal term
%%  - Decoded values:
%%      - nil, false, true, binary(), float(), {function fun/1,2}
%%      - [{decoded(), decoded()}...] (keys are float for arrays)




%% ===================================================================
%% Public
%% ===================================================================


%% @doc
init(SrvId, ModuleId) ->
    St0 = luerl:init(),
    % Must be internal representation
    St1 = add_core_funs(SrvId, ModuleId, St0),
    Packages = #{
        <<"log">> => [
            {<<"debug">>, {function, fun ?MODULE:debug/2}},
            {<<"info">>, {function, fun ?MODULE:info/2}},
            {<<"notice">>, {function, fun ?MODULE:notice/2}},
            {<<"warning">>, {function, fun ?MODULE:warning/2}},
            {<<"error">>, {function, fun ?MODULE:error/2}}
        ],
        <<"json">> => [
            {<<"decode">>, {function, fun ?MODULE:decode/2}},
            {<<"encode">>, {function, fun ?MODULE:encode/2}},
            {<<"encodePretty">>, {function, fun ?MODULE:encode/2}}
        ]
    },
    load_packages(maps:to_list(Packages), St1).


%% @doc
add_core_funs(SrvId, ModuleId, St) ->
    ServiceTable = [
        {<<"srv">>, SrvId},
        {<<"module_id">>, ModuleId},
        {<<"callbacks">>, []},
        {<<"packages">>, []}
    ],
    St2 = luerl:set_table(service_table([]), ServiceTable, St),
    St3 = luerl_emul:set_global_key(<<"startPackage">>, {function, fun nkservice_config_luerl:start_package/2}, St2),
    St3.


%% @doc
load_packages([], St0) ->
    St0;

load_packages([{Key, Table}|Rest], St0) ->
    {Table2, St2} = luerl_emul:alloc_table(Table, St0), % {tref, X}
    St3 = luerl_emul:set_global_key(Key, Table2, St2),
    St4 = luerl_emul:set_table_keys([<<"package">>, <<"loaded">>, Key], Table2, St3),
    {Table2, _} = luerl_emul:get_table_keys([Key], St4),
    {Table2, _} = luerl_emul:get_table_keys([<<"package">>, <<"loaded">>, Key], St4),
    load_packages(Rest, St4).


%% ===================================================================
%% Core
%% ===================================================================

%% @private
service_table(List) ->
    nkservice_config_luerl:service_table(List).


%% ===================================================================
%% Debug Package
%% ===================================================================


debug([Bin], State) when is_binary(Bin) ->
    {Prefix, State2} = log_prefix(State),
    lager:debug(<<Prefix/binary, Bin/binary>>),
    {[], State2}.

info([Bin], State) when is_binary(Bin) ->
    {Prefix, State2} = log_prefix(State),
    lager:info(<<Prefix/binary, Bin/binary>>),
    {[], State2}.

notice([Bin], State) when is_binary(Bin) ->
    {Prefix, State2} = log_prefix(State),
    lager:notice(<<Prefix/binary, Bin/binary>>),
    {[], State2}.

warning([Bin], State) when is_binary(Bin) ->
    {Prefix, State2} = log_prefix(State),
    lager:warning(<<Prefix/binary, Bin/binary>>),
    {[], State2}.

error([Bin], State) when is_binary(Bin) ->
    {Prefix, State2} = log_prefix(State),
    lager:error(<<Prefix/binary, Bin/binary>>),
    {[], State2}.


%% @private
log_prefix(State) ->
    {SrvId, State2} = luerl:get_table(service_table([srv]), State),
    {ModuleId, State3} = luerl:get_table(service_table([module_id]), State2),
    Prefix = list_to_binary([
        "NkSERVICE LUERL '", to_bin(SrvId), "' module '", to_bin(ModuleId), "' "
    ]),
    {Prefix, State3}.


%% ===================================================================
%% JSON Package
%% ===================================================================

%% @doc
encode([T, Opts], St) ->
    Opts2 = luerl:decode(Opts, St),
    Pretty = nklib_util:get_value(<<"pretty">>, Opts2, false),
    encode(luerl:decode(T, St), Pretty, St);

encode([T], St) ->
    encode(luerl:decode(T, St), false, St).


%% @private
encode(Term, Pretty, St) ->
    try encode_value(Term) of
        Encoded ->
            case
                case Pretty of
                    true ->
                        nklib_json:encode_pretty(Encoded);
                    false ->
                        nklib_json:encode(Encoded)
                end
            of
                error ->
                    {[nil], St};
                Result ->
                    {[Result], St}
            end
        catch
            _:_ ->
                {[nil], St}
    end.


%% @private
encode_value([{1, _}|_]=Array) ->
    encode_array(Array, 1, []);

encode_value(V) when is_list(V) ->
    encode_object(V, []);

encode_value(V) ->
    V.


%% @private
encode_array([], _Pos, Acc) ->
    lists:reverse(Acc);

encode_array([{Pos, V}|Rest], Pos, Acc) ->
    encode_array(Rest, Pos+1, [encode_value(V)|Acc]);

encode_array(_, _Pos, _Acc) ->
    throw(error).


%% @private
encode_object([], Acc) ->
    {lists:reverse(Acc)};

encode_object([{K, V}|Rest], Acc) ->
    encode_object(Rest, [{K, encode_value(V)}|Acc]).


%% @private
decode([Bin], St) when is_binary(Bin) ->
    case nklib_json:decode(Bin) of
        error ->
            {[nil], St};
        Result1 ->
            {Result2, St2} = luerl:encode(Result1, St),
            {[Result2], St2}
    end.



%% ===================================================================
%% Sample
%% ===================================================================


%% Sample
sample() ->
    St0 = luerl:init(),

    {#tref{i=0}, St0} = luerl:function_list([], St0),
    {#tref{i=0}, St0} = luerl_emul:get_table_keys([], St0),

    {{tref, 2}, _} = luerl_emul:get_table_keys([<<"package">>, <<"loaded">>], St0),

    {{tref, 4}, _} = luerl_emul:get_global_name(package, St0),
    {{tref, 4}, _} = luerl_emul:get_global_key(<<"package">>, St0),

    {{tref, 7}, _} = luerl_emul:get_table_keys([<<"math">>], St0),
    {{tref, 7}, _} = luerl_emul:get_table_keys([<<"_G">>, <<"math">>], St0),
    {{tref, 7}, _} = luerl_emul:get_table_keys([<<"package">>, <<"loaded">>, <<"math">>], St0),
    {{tref, 7}, _} = luerl_emul:get_table_key({tref, 2}, <<"math">>, St0),
    {{function, _}, _} = luerl_emul:get_table_key({tref, 7}, <<"abs">>, St0),

    StA = luerl_emul:set_global_name(my_global, <<"hi">>, St0),
    {<<"hi">>, _} = luerl_emul:get_global_key(<<"my_global">>, StA),

    % Creates a new table, not yet inserted in global or any other place
    Table = [{<<"a">>, 1.0}, {<<"b">>, 2.0}],
    {#tref{i=13},St1} = luerl_emul:alloc_table(Table, St0),
    {#tref{i=0}, St1} = luerl_emul:get_table_keys([], St1),

    % Encode
    Name = [<<"package">>,<<"loaded">>,<<"kv">>],
    {Name,St1} = luerl:encode_list([package, loaded, kv], St1),
    {#tref{}, _StX} = luerl:encode([{a, 1}], St1),

    {nil, St1} = luerl_emul:get_table_keys(Name, St1),      % not yet loaded
    St2 = luerl_emul:set_table_keys(Name, #tref{i=13}, St1),
    {#tref{i=13}, St2} = luerl_emul:get_table_keys(Name, St2),
    [{<<"a">>, 1.0}|_] = luerl:decode(#tref{i=13}, St2),
    ok.


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).
