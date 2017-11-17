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
-export([get_accept/1, get_cowboy_req/1]).
-export([reply_json/2]).
-export([init/4, terminate/3]).
-export_type([method/0, reply/0, code/0, headers/0, body/0, nkreq_http/0, path/0, http_qs/0]).

-define(MAX_BODY, 10000000).


-define(DEBUG(Txt, Args, State),
    case erlang:get(nkservice_rest_debug) of
        true -> ?LLOG(debug, Txt, Args, State);
        _ -> ok
    end).

-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE REST HTTP (~s) "++Txt, [State#nkreq_http.remote|Args])).

-include_lib("nkservice/include/nkservice.hrl").
-include_lib("nkpacket/include/nkpacket.hrl").


%% ===================================================================
%% Types
%% ===================================================================


-type method() :: get | post | head | delete | put | binary().

-type code() :: 100 .. 599.

-type headers() :: #{binary() => iolist()}.

-type body() ::  Body::binary()|map().

-type http_qs() ::
    [{binary(), binary()|true}].

-type path() :: [binary()].

-record(nkreq_http, {
    srv_id :: nkservice:id(),
    id :: nkservice_rest:id(),
    req :: term(),
    method :: method(),
    path :: [binary()],
    remote :: binary()
}).

-type nkreq_http() :: #nkreq_http{}.

-type reply() ::
    {http, code(), headers(), body(), nkreq_http()}.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc
-spec get_srv_id(nkreq_http()) ->
    nkservice:id().

get_srv_id(#nkreq_http{srv_id=SrvId}) ->
    SrvId.


%% @doc
-spec get_body(nkreq_http(), #{max_size=>integer(), parse=>boolean()}) ->
    {ok, binary(), nkreq_http()} | {error, term()}.

get_body(#nkreq_http{req=CowReq}=Req, Opts) ->
    CT = get_ct(Req),
    MaxBody = maps:get(max_size, Opts, 100000),
    case cowboy_req:body_length(CowReq) of
        BL when is_integer(BL), BL =< MaxBody ->
            %% https://ninenines.eu/docs/en/cowboy/2.1/guide/req_body/
            {ok, Body, CowReq2} = cowboy_req:read_body(CowReq, #{length=>infinity}),
            Req2 = Req#nkreq_http{req=CowReq2},
            case maps:get(parse, Opts, false) of
                true ->
                    case CT of
                        <<"application/json">> ->
                            case nklib_json:decode(Body) of
                                error ->
                                    {error, invalid_json};
                                Json ->
                                    {ok, Json, Req2}
                            end;
                        _ ->
                            {ok, Body, Req2}
                    end;
                _ ->
                    {ok, Body, Req2}
            end;
        BL ->
            {error, {body_too_large, BL, MaxBody}}
    end.


%% @doc
-spec get_qs(nkreq_http()) ->
    http_qs().

get_qs(#nkreq_http{req=Req}) ->
    cowboy_req:parse_qs(Req).


%% @doc
-spec get_ct(nkreq_http()) ->
    binary().

get_ct(#nkreq_http{req=Req}) ->
    cowboy_req:header(<<"content-type">>, Req).


%% @doc
-spec get_accept(nkreq_http()) ->
    binary().

get_accept(#nkreq_http{req=Req}) ->
    cowboy_req:parse_header(<<"accept">>, Req).


%% @doc
-spec get_headers(nkreq_http()) ->
    #{binary() => binary()}.

get_headers(#nkreq_http{req=Req}) ->
    cowboy_req:headers(Req).


%% @doc
-spec get_basic_auth(nkreq_http()) ->
    {user, binary(), binary()} | undefined.

get_basic_auth(#nkreq_http{req=Req}) ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
        {basic, User, Pass} ->
            {basic, User, Pass};
        _ ->
            undefined
    end.


%% @doc
-spec get_peer(nkreq_http()) ->
    {inet:ip_address(), inet:port_number()}.

get_peer(#nkreq_http{req=Req}) ->
    {Ip, Port} = cowboy_req:peer(Req),
    {Ip, Port}.


%% @private
get_cowboy_req(#nkreq_http{req=Req}) ->
    Req.



%% @doc
reply_json({ok, Data}, _Req) ->
    Hds = #{<<"Content-Tytpe">> => <<"application/json">>},
    Body = nklib_json:encode(Data),
    {http, 200, Hds, Body};

reply_json({error, Error}, #nkreq_http{srv_id=SrvId}) ->
    Hds = #{<<"Content-Tytpe">> => <<"application/json">>},
    {Code, Txt} = nkservice_util:error(SrvId, Error),
    Body = nklib_json:encode(#{result=>error, data=>#{code=>Code, error=>Txt}}),
    {http, 400, Hds, Body}.



%% ===================================================================
%% Callbacks
%% ===================================================================


%% @private
init(Paths, CowReq, Env, NkPort) ->
    {Ip, Port} = cowboy_req:peer(CowReq),
    Remote = <<
        (nklib_util:to_host(Ip))/binary, ":",
        (to_bin(Port))/binary
    >>,
    Method = case cowboy_req:method(CowReq) of
        <<"GET">> -> get;
        <<"POST">> -> post;
        <<"PUT">> -> put;
        <<"DELETE">> -> delete;
        <<"HEAD">> -> head;
        OtherMethod -> OtherMethod
    end,
    {ok, {nkservice_rest, SrvId, Id}} = nkpacket:get_class(NkPort),
    Req = #nkreq_http{
        srv_id = SrvId,
        id = Id,
        req = CowReq,
        method = Method,
        path = Paths,
        remote = Remote
    },
    set_log(SrvId),
    ?DEBUG("received ~p (~s) from ~s", [Method, Paths, Remote], Req),
    case ?CALL_SRV(SrvId, nkservice_rest_http, [Id, Method, Paths, Req]) of
        {http, Code, Hds, Body} ->
            lager:warning("Returning a REST reply without Req: ~p", [Body]),
            {ok, nkpacket_cowboy:reply(Code, Hds, Body, CowReq), Env};
        {http, Code, Hds, Body, #nkreq_http{req=CowReq2}} ->
            {ok, nkpacket_cowboy:reply(Code, Hds, Body, CowReq2), Env};
        {redirect, Path3} ->
            {redirect, Path3};
        {cowboy_static, Opts} ->
            {cowboy_static, Opts};
        {cowboy_rest, Module, State} ->
            {cowboy_rest, Module, State};
        continue ->
            {ok, nkpacket_cowboy:reply(404, #{},
                                        <<"NkSERVICE REST resource not found">>, CowReq)}
    end.


%% @private
terminate(_Reason, _Req, _Opts) ->
    ok.


%% ===================================================================
%% Internal
%% ===================================================================

%% @private
set_log(SrvId) ->
    Debug = case nkservice_util:get_debug_info(SrvId, nkservice_rest) of
        {true, _} -> true;
        _ -> false
    end,
    put(nkservice_rest_debug, Debug).


%% @private
to_bin(Term) -> nklib_util:to_binary(Term).
