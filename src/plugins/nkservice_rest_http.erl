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
-export([get_srv_id/1, get_body/2, get_qs/1, get_ct/1, get_basic_auth/1, get_headers/1, get_peer/1]).
-export([reply_json/3]).
-export([init/2, terminate/3]).
-export_type([method/0, reply/0, code/0, header/0, body/0, state/0, path/0, http_qs/0]).

-define(MAX_BODY, 10000000).


-define(DEBUG(Txt, Args, State),
    case erlang:get(nkservice_rest_debug) of
        true -> ?LLOG(debug, Txt, Args, State);
        _ -> ok
    end).

-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE REST HTTP (~s) "++Txt, [State#req.remote|Args])).



%% ===================================================================
%% Types
%% ===================================================================


-type method() :: get | post | head | delete | put | binary().

-type code() :: 100 .. 599.

-type header() :: [{binary(), binary()}].

-type body() ::  Body::binary()|map().

-type state() :: map().

-type http_qs() ::
    [{binary(), binary()|true}].

-type path() :: [binary()].

-record(req, {
    srv_id :: nkapi:id(),
    req :: term(),
    method :: binary(),
    path :: [binary()],
    remote :: binary()
}).

-type req() :: #req{}.

-type reply() ::
    {http, code(), [header()], body(), state()}.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc
-spec get_srv_id(req()) ->
    nkservice:id().

get_srv_id(#req{srv_id=SrvId}) ->
    SrvId.


%% @doc
-spec get_body(req(), #{max_size=>integer(), parse=>boolean()}) ->
    binary() | map().

get_body(#req{req=Req}=State, Opts) ->
    CT = get_ct(State),
    MaxBody = maps:get(max_size, Opts, 100000),
    case cowboy_req:body_length(Req) of
        BL when is_integer(BL), BL =< MaxBody ->
            %% https://ninenines.eu/docs/en/cowboy/1.0/guide/req_body/
            {ok, Body, _} = cowboy_req:body(Req, [{length, infinity}]),
            case maps:get(parse, Opts, false) of
                true ->
                    case CT of
                        <<"application/json">> ->
                            case nklib_json:decode(Body) of
                                error ->
                                    {error, invalid_json};
                                Json ->
                                    {ok, Json}
                            end;
                        _ ->
                            {ok, Body}
                    end;
                _ ->
                    {ok, Body}
            end;
        BL ->
            {error, {body_too_large, BL, MaxBody}}
    end.


%% @doc
-spec get_qs(req()) ->
    http_qs().

get_qs(#req{req=Req}) ->
    cowboy_req:parse_qs(Req).


%% @doc
-spec get_ct(req()) ->
    binary().

get_ct(#req{req=Req}) ->
    cowboy_req:header(<<"content-type">>, Req).


%% @doc
-spec get_headers(req()) ->
    [{binary(), binary()}].

get_headers(#req{req=Req}) ->
    cowboy_req:headers(Req).


%% @doc
-spec get_basic_auth(req()) ->
    {user, binary(), binary()} | undefined.

get_basic_auth(#req{req=Req}) ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
        {basic, User, Pass} ->
            {basic, User, Pass};
        _ ->
            undefined
    end.


%% @doc
-spec get_peer(req()) ->
    {inet:ip_address(), inet:port_number()}.

get_peer(#req{req=Req}) ->
    {Ip, Port} = cowboy_req:peer(Req),
    {Ip, Port}.


%% @doc
reply_json({ok, Data}, _Req, State) ->
    Hds = [{<<"Content-Tytpe">>, <<"application/json">>}],
    Body = nklib_json:encode(Data),
    {http, 200, Hds, Body, State};

reply_json({error, Error}, #req{srv_id=SrvId}, State) ->
    Hds = [{<<"Content-Tytpe">>, <<"application/json">>}],
    {Code, Txt} = nkservice_util:error(SrvId, Error),
    Body = nklib_json:encode(#{result=>error, data=>#{code=>Code, error=>Txt}}),
    {http, 400, Hds, Body, State}.



%% ===================================================================
%% Callbacks
%% ===================================================================


%% @private
init(HttpReq, [{srv_id, SrvId}]) ->
    {Ip, Port} = cowboy_req:peer(HttpReq),
    Remote = <<
        (nklib_util:to_host(Ip))/binary, ":",
        (to_bin(Port))/binary
    >>,
    Method = case cowboy_req:method(HttpReq) of
        <<"GET">> -> get;
        <<"POST">> -> post;
        <<"PUT">> -> put;
        <<"DELETE">> -> delete;
        <<"HEAD">> -> head;
        OtherMethod -> OtherMethod
    end,
    Path = case cowboy_req:path_info(HttpReq) of
        [<<>>|Rest] -> Rest;
        Rest -> Rest
    end,
    Req = #req{
        srv_id = SrvId,
        req = HttpReq,
        method = Method,
        path = Path,
        remote = Remote
    },
    UserState = #{},
    set_log(Req),
    ?DEBUG("received ~p (~p) from ~s", [Method, Path, Remote], Req),
    {http, Code, Hds, Body, _UserState2} = SrvId:nkservice_rest_http(Method, Path, Req, UserState),
    {ok, cowboy_req:reply(Code, Hds, Body, HttpReq), []}.


%% @private
terminate(_Reason, _Req, _Opts) ->
    ok.


%% ===================================================================
%% Internal
%% ===================================================================


%% @private
set_log(#req{srv_id=SrvId}=Req) ->
    Debug = case nkservice_util:get_debug_info(SrvId, nkservice_rest) of
        {true, _} -> true;
        _ -> false
    end,
    % lager:error("DEBUG: ~p", [Debug]),
    put(nkservice_rest_debug, Debug),
    Req.



%% @private
to_bin(Term) -> nklib_util:to_binary(Term).
