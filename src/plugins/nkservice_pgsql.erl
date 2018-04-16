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

-export([query/3, get_connection/2, do_query/2, release_connection/3, stop_connection/1]).
-export([luerl_query/3]).


%% ===================================================================
%% Types
%% ===================================================================


-type op() ::
    {Op::term(), list(), RecordMeta::map()}.


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
    {ok, [op()], Meta::map()} |
    {error, {pgsql_error, pgsql_error()}|term()}.

query(SrvId, PackageId, Query) ->
    PackageId2 = to_bin(PackageId),
    case get_connection(SrvId, PackageId2) of
        {ok, Pid} ->
            try
                do_query(Pid, Query)
            after
                 release_connection(SrvId, PackageId2, Pid)
            end;
        {error, Error} ->
            {error, Error}
    end.


%% @doc
get_connection(SrvId, PackageId) ->
    case nkpacket_pool:get_exclusive_pid({SrvId, PackageId}) of
        {ok, Pid, _Meta} ->
            {ok, Pid};
        {error, Error} ->
            {error, Error}
    end.


%% @doc
release_connection(SrvId, PackageId, Pid) ->
    nkpacket_pool:release_exclusive_pid({SrvId, PackageId}, Pid).


%% @doc
stop_connection(Pid) ->
    nkservice_pgsql_plugin:conn_stop(Pid).




%% @doc
-spec do_query(pid(), binary()) ->
    {error, {pgsql_error, pgsql_error()}|term()}.

do_query(Pid, Query) ->
    Start = nklib_util:m_timestamp(),
    Opts = [{return_descriptions, true}],
    case pgsql_connection:simple_query(Query, Opts, {pgsql_connection, Pid}) of
        {error, {pgsql_error, List}} ->
            {error, {pgsql_error, maps:from_list(List)}};
        {error, Error} ->
            lager:error("PGSQL UNEXPECTED ERR ~p", [Error]),
            {error, Error};
        % If it is a transaction, first error that happens will abort, and it
        % will appear first in the list of errors (no more error can be on the list)
        % If it is not a transaction, the result will be error only if the last
        % sentence is an error
        [{error, {pgsql_error, List}}|_] ->
            % lager:error("NKLOG ERROR OTHER ~p", [Rest]),
            {error, {pgsql_error, maps:from_list(List)}};
        [{error, Error}|_] ->
            lager:error("PGSQL UNEXPECTED ERR2 ~p", [Error]),
            {error, Error};
        Data ->
            Time = nklib_util:m_timestamp() - Start,
            {ok, parse_results(Data, []), #{time=>Time}}
    end.


%% @private
parse_results([], [Acc]) ->
    [Acc];

parse_results([], Acc) ->
    lists:reverse(Acc);

parse_results([{Op, Desc, List}|Rest], Acc) ->
    Desc2 = [{N, F} || {_, N, _, _, _, _, _, F} <- Desc],
    parse_results(Rest, [{Op, List, #{fields=>Desc2}}|Acc]);

parse_results([{Op, List}|Rest], Acc) ->
    parse_results(Rest, [{Op, List, #{}}|Acc]);

parse_results(Other, Acc) ->
    parse_results([Other], Acc).





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


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).