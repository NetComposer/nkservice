%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc
-module(nkservice_rest_http).
-export([get_body/2, get_qs/1, get_ct/1, get_basic_auth/1, get_peer/1]).
-export([init/2, terminate/3]).
-export_type([method/0, code/0, header/0, body/0, state/0, path/0, http_qs/0]).

-define(MAX_BODY, 10000000).

%%-include("nkapi.hrl").
%%-include_lib("nkservice/include/nkservice.hrl").


-define(DEBUG(Txt, Args, State),
    case erlang:get(nkapi_server_debug) of
        true -> ?LLOG(debug, Txt, Args, State);
        _ -> ok
    end).

-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkAPI API Server HTTP (~s) "++Txt,
        [State#state.remote|Args])).



%% ===================================================================
%% Types
%% ===================================================================


-type method() :: get | post | head | delete | put.

-type code() :: 100 .. 599.

-type header() :: [{binary(), binary()}].

-type body() ::  Body::binary()|map().

-type state() :: map().

-type http_qs() ::
    [{binary(), binary()|true}].

-type path() :: [binary()].

-record(state, {
    srv_id :: nkapi:id(),
    req :: term(),
    method :: binary(),
    path :: [binary()],
    remote :: binary(),
    user_state :: nkapi:user_state()
}).

-type req() :: #state{}.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc
-spec get_body(req(), #{max_size=>integer(), parse=>boolean()}) ->
    binary() | map().

get_body(#state{req=Req}, Opts) ->
    CT = get_ct(Req),
    MaxBody = maps:get(max_size, Opts, 100000),
    case cowboy_req:body_length(Req) of
        BL when is_integer(BL), BL =< MaxBody ->
            {ok, Body, _} = cowboy_req:body(Req),
            case maps:get(parse, Opts, false) of
                true ->
                    case CT of
                        <<"application/json">> ->
                            case nklib_json:decode(Body) of
                                error ->
                                    throw({400, [], <<"Invalid json">>});
                                Json ->
                                    Json
                            end;
                        _ ->
                            Body
                    end;
                _ ->
                    Body
            end;
        _ ->
            throw({400, [], <<"Body too large">>})
    end.


%% @doc
-spec get_qs(req()) ->
    http_qs().

get_qs(#state{req=Req}) ->
    cowboy_req:parse_qs(Req).


%% @doc
-spec get_ct(req()) ->
    binary().

get_ct(#state{req=Req}) ->
    cowboy_req:header(<<"content-type">>, Req).


%% @doc
-spec get_basic_auth(req()) ->
    {user, binary(), binary()} | undefined.

get_basic_auth(#state{req=Req}) ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
        {basic, User, Pass} ->
            {basic, User, Pass};
        _ ->
            undefined
    end.


%% @doc
-spec get_peer(req()) ->
    {inet:ip_address(), inet:port_number()}.

get_peer(#state{req=Req}) ->
    {Ip, Port} = cowboy_req:peer(Req),
    {Ip, Port}.




%% ===================================================================
%% Callbacks
%% ===================================================================


%% @private
init(Req, [{srv_id, SrvId}]) ->
    {Ip, Port} = cowboy_req:peer(Req),
    Remote = <<
        (nklib_util:to_host(Ip))/binary, ":",
        (to_bin(Port))/binary
    >>,
    Method = cowboy_req:method(Req),
    Path = case cowboy_req:path_info(Req) of
        [<<>>|Rest] -> Rest;
        Rest -> Rest
    end,
    State = #state{
        srv_id = SrvId,
        req = Req,
        method = Method,
        path = Path,
        remote = Remote,
        user_state = #{}
    },
    set_log(State),
    ?DEBUG("received ~p (~p) from ~s", [Method, Path, Remote], State),
    {http, Code, Hds, Body, State} = handle(nkservice_rest_http, [Method, Path], State),
    {ok, cowboy_req:reply(Code, Hds, Body, Req), []}.


%% @private
terminate(_Reason, _Req, _Opts) ->
    ok.


%% ===================================================================
%% Internal
%% ===================================================================


%% @private
set_log(#state{srv_id=SrvId}=State) ->
    Debug = case nkservice_util:get_debug_info(SrvId, nkservice_rest) of
        {true, _} -> true;
        _ -> false
    end,
    % lager:error("DEBUG: ~p", [Debug]),
    put(nkservice_rest_debug, Debug),
    State.


%% @private
handle(Fun, Args, State) ->
    nklib_gen_server:handle_any(Fun, Args++[State], State, #state.srv_id, #state.user_state).

%% @private
to_bin(Term) -> nklib_util:to_binary(Term).
