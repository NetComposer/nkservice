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

-module(nkservice_httppool).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([request/6, luerl_request/3]).

%% ===================================================================
%% Types
%% ===================================================================

-type method() :: get | post | put | delete | head | patch.
-type path() :: binary().
-type body() :: iolist().

-type request_opts() ::
    #{
        headers => [{binary(), binary()}],
        timeout => integer()
    }.


%% ===================================================================
%% API
%% ===================================================================

%% @doc Signs a request (anyone can decrypt it)
-spec request(nkservice:id(), nkservice:package_id(), method(), path(),
              body(), request_opts()) ->
    {ok, Status::100..599, Headers::[{binary(), binary()}], Body::binary()} |
    {error, term()}.

request(SrvId, PackageId, Method, Path, Body, Opts) ->
    Key = {nkservice_httppool, SrvId, nklib_util:to_binary(PackageId)},
    case nklib_proc:values(Key) of
        [{_, Pid}|_] ->
            nkpacket_httpc_pool:request(Pid, Method, Path, Body, Opts);
        [] ->
            {error, no_connection}
    end.





%% ===================================================================
%% Luerl API
%% ===================================================================

%% @doc
luerl_request(SrvId, PackageId, [Method, Path, _Hds, Body]) ->
    Opts = #{
        headers => [],
        timeout => 5000
    },
    case request(SrvId, PackageId, Method, Path, Body, Opts) of
        {ok, Status, RepHds, RepBody} ->
            [Status, RepHds, RepBody];
        {error, Error} ->
            {Code, Txt} = nkservice_error:error(SrvId, Error),
            [nil, Code, Txt]
    end.

