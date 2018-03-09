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

-module(nkservice_error).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([is_error/2, error/2]).

-include("nkservice.hrl").
-include_lib("nkpacket/include/nkpacket.hrl").


%% ===================================================================
%% Public
%% ===================================================================


%% @private
-spec is_error(nkservice:id(), nkservice:error()) ->
    {true, term(), term()} | false.

is_error(SrvId, Error) ->
    case ?CALL_SRV(SrvId, error, [SrvId, Error]) of
        {ErrCode, Fmt, List} when is_list(Fmt), is_list(List) ->
            {true, get_error_code(ErrCode), get_error_fmt(Fmt, List)};
        {Fmt, List} when is_list(Fmt), is_list(List) ->
            {true, get_error_code(Error), get_error_fmt(Fmt, List)};
        {ErrCode, ErrReason} when is_list(ErrReason); is_binary(ErrReason) ->
            {true, get_error_code(ErrCode), to_bin(ErrReason)};
        ErrReason when is_list(ErrReason) ->
            {true, get_error_code(Error), to_bin(ErrReason)};
        _ ->
            false
    end.


%% @private
-spec error(nkservice:id(), nkservice:error()) ->
    {binary(), binary()}.

error(SrvId, Error) ->
    case is_error(SrvId, Error) of
        {true, Code, Reason} ->
            {Code, Reason};
        false ->
            % This error is not in any table, but it can be an already processed one
            case Error of
                {ErrCode, ErrReason} when is_binary(ErrCode), is_binary(ErrReason) ->
                    {ErrCode, ErrReason};
                {ErrCode, _} when is_atom(ErrCode) ->
                    lager:notice("NkSERVICE unknown error: ~p", [Error]),
                    {to_bin(ErrCode), to_bin(ErrCode)};
                Other ->
                    Ref = erlang:phash2(make_ref()) rem 10000,
                    lager:notice("NkSERVICE internal error (~p): ~p", [Ref, Other]),
                    {<<"internal_error">>, get_error_fmt("Internal error (~p)", [Ref])}
            end
    end.


%% @private
get_error_code(Term) when is_atom(Term); is_binary(Term); is_list(Term) ->
    to_bin(Term);

get_error_code(Tuple) when is_tuple(Tuple) ->
    get_error_code(element(1, Tuple));

get_error_code(Error) ->
    lager:notice("Invalid format in API reason: ~p", [Error]),
    <<"internal_error">>.


%% @private
get_error_fmt(Fmt, List) ->
    case catch io_lib:format(Fmt, List) of
        {'EXIT', _} ->
            lager:notice("Invalid format API reason: ~p, ~p", [Fmt, List]),
            <<>>;
        Val ->
            list_to_binary(Val)
    end.



%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).
