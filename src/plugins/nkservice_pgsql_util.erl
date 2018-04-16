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

-module(nkservice_pgsql_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([actor_persistence_package_id/1, fields/1, quote/1, quote_double/1]).


%% ===================================================================
%% Public
%% ===================================================================

%% @private
actor_persistence_package_id(SrvId) ->
    nkservice_util:get_cache(SrvId, {nkservice_pgsql, any, actor_persistence}).


%% @private
fields(List) ->
    List2 = [quote(F) || F <- List],
    nklib_util:bjoin(List2, $,).


%% @private
quote(Field) when is_binary(Field) -> [$', Field, $'];
quote(Field) when is_list(Field) -> [$', Field, $'];
quote(Field) when is_integer(Field); is_float(Field) -> to_bin(Field);
quote(true) -> <<"TRUE">>;
quote(false) -> <<"FALSE">>;
quote(Field) when is_atom(Field) -> quote(atom_to_binary(Field, utf8));
quote(Field) when is_map(Field) -> [$', nklib_json:encode(Field), $'].


%% @private
quote_double(Field) when is_binary(Field) -> [$", Field, $"];
quote_double(Field) when is_list(Field) -> [$", Field, $"];
quote_double(Field) when is_integer(Field); is_float(Field) -> to_bin(Field);
quote_double(true) -> <<"TRUE">>;
quote_double(false) -> <<"FALSE">>;
quote_double(Field) when is_atom(Field) -> quote_double(atom_to_binary(Field, utf8));
quote_double(Field) when is_map(Field) -> [$', nklib_json:encode(Field), $'].


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).




