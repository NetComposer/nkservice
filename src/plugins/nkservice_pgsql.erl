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

-module(nkservice_pgsql).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([query/3, luerl_query/3]).


%% ===================================================================
%% Types
%% ===================================================================

-type pgsql_error() ::
    #{
        code => binary(),
        message => binary(),
        severity => binary()
    }.

%% ===================================================================
%% API
%% ===================================================================

%% @doc



-spec query(nkservice:id(), nkservice:package_id(), binary()) ->
    {error, {pgsql_error, pgsql_error()}|term()}.

    
query(SrvId, PackageId, Query) ->
    case nkpacket_pool:get_exclusive_pid({SrvId, PackageId}) of
        {ok, Pid} ->
            try
                Start = nklib_util:m_timestamp(),
                Opts = [{return_descriptions, true}],
                case pgsql_connection:simple_query(Query, Opts, {pgsql_connection, Pid}) of
                    {error, {pgsql_error, List}} ->
                        {error, {pgsql_error, maps:from_list(List)}};
                    {{Op, Result}, Desc, List} ->
                        Time = nklib_util:m_timestamp() - Start,
                        Desc2 = [{N, F} || {_, N, _, _, _, _, _, F} <- Desc],
                        {ok, List, #{op=>Op, result=>Result, fields=>Desc2, time=>Time}};
                    {{Op, Result}, List} ->
                        Time = nklib_util:m_timestamp() - Start,
                        {ok, List, #{op=>Op, result=>Result, time=>Time}}
                end
            after
                 nkpacket_pool:release_exclusive_pid({SrvId, PackageId}, Pid)
            end;
        {error, Error} ->
            {error, Error}
    end.




%% ===================================================================
%% Luerl API
%% ===================================================================

%% @doc
luerl_query(SrvId, PackageId, [Query]) ->
    case query(SrvId, PackageId, Query) of
        {ok, List, _Meta} ->
            [parse_rows(List)];
        {error, {pgsql_error, Error}} ->
            [nil, pgsql_error, Error];
        {error, Error} ->
            {error, Error}
    end.


parse_rows(Rows) ->
    lists:map(
        fun(Row) ->
            lists:map(
                fun
                    ({{_Y, _M, _D}=Date, {H, M, S1}}) ->
                        S2 = round(S1 * 1000),
                        Secs = S2 div 1000,
                        Msecs = S2 - (Secs * 1000),
                        Unix1 = nklib_util:gmt_to_timestamp({Date, {H, M, Secs}}),
                        Unix2 = Unix1 * 1000 + Msecs,
                        Unix2;
                    (Term) when is_binary(Term); is_integer(Term); is_float(Term) ->
                        Term;
                    (Other) ->
                        nklib_util:to_binary(Other)
                end,
                tuple_to_list(Row))
        end,
        Rows).
