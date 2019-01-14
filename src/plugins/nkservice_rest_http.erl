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
-export([reply_json/2, reply_json/3]).
-export([init/2, terminate/3]).
-export_type([method/0, reply/0, code/0, header/0, body/0, state/0, path/0, http_qs/0]).

-define(MAX_BODY, 52428800).


-define(DEBUG(Txt, Args, State),
    case erlang:get(nkservice_rest_debug) of
        true -> ?LLOG(debug, Txt, Args, State);
        _ -> ok
    end).

-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE REST HTTP (~s) "++Txt, [State#req.remote|Args])).

-include_lib("nkservice/include/nkservice.hrl").

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
    srv_id :: nkservice:id(),
    id :: nkservice_rest:id(),
    req :: term(),
    method :: method(),
    path :: [binary()],
    remote :: binary()
}).

-type req() :: #req{}.

-type reply() ::
    {http, code(), [header()], body(), state(), req()}.


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
    {ok, binary()} | {error, term()}.

get_body(#req{req=Req}=State, Opts) ->
    CT = get_ct(State),
    MaxBody = maps:get(max_size, Opts, ?MAX_BODY),
    case cowboy_req:body_length(Req) of
        BL when is_integer(BL), BL =< MaxBody ->
            %% https://ninenines.eu/docs/en/cowboy/1.0/guide/req_body/
            %{ok, Body, Req2} = cowboy_req:body(Req, [{length, infinity}]),
            Length = nkservice_app:get(body_length),
            ReadLength = nkservice_app:get(body_read_length),
            ReadTimeout = nkservice_app:get(body_read_timeout),
            {ok, Body, Req2} = read_body_in_chunks(Req, [{length, Length}, {read_length, ReadLength}, {read_timeout, ReadTimeout}]),
            case maps:get(parse, Opts, false) of
                true ->
                    case CT of
                        <<"application/json">> ->
                            case nklib_json:decode(Body) of
                                error ->
                                    {error, invalid_json};
                                Json ->
                                    {ok, Json, State#req{req=Req2}}
                            end;
                        _ ->
                            {ok, Body, State#req{req=Req2}}
                    end;
                _ ->
                    {ok, Body, State#req{req=Req2}}
            end;
        BL ->
            {error, {body_too_large, BL, MaxBody}}
    end.


%% @private
read_body_in_chunks(Req, Opts) ->
    read_body_in_chunks(<<>>, Opts, Req).

read_body_in_chunks(Data1, Opts, Req) ->
    case cowboy_req:body(Req, Opts) of
        {ok, Data2, Req2} ->
            {ok, <<Data1/binary, Data2/binary>>, Req2};
        {more, Data2, Req2} ->
            read_body_in_chunks(<<Data1/binary, Data2/binary>>, Opts, Req2)
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
-spec get_accept(req()) ->
    binary().

get_accept(#req{req=Req}) ->
    cowboy_req:parse_header(<<"accept">>, Req).


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


%% @private
get_cowboy_req(#req{req=Req}) ->
    Req.



%% @doc
reply_json({ok, Data}, Req) ->
    Hds = [{<<"Content-Type">>, <<"application/json">>}],
    Body = nklib_json:encode(Data),
    {http, 200, Hds, Body, Req};

reply_json({error, Error}, #req{srv_id=SrvId}=Req) ->
    Hds = [{<<"Content-Type">>, <<"application/json">>}],
    {Code, Txt} = nkservice_util:error(SrvId, Error),
    Body = nklib_json:encode(#{result=>error, data=>#{code=>Code, error=>Txt}}),
    {http, 400, Hds, Body, Req}.


%% @doc
reply_json({ok, Data}, Hds, Req) ->
    Hds2 = [{<<"Content-Type">>, <<"application/json">>} | Hds],
    Body = nklib_json:encode(Data),
    {http, 200, Hds2, Body, Req};

reply_json({error, Error}, Hds, #req{srv_id=SrvId}=Req) ->
    Hds2 = [{<<"Content-Type">>, <<"application/json">>} | Hds],
    {Code, Txt} = nkservice_util:error(SrvId, Error),
    Body = nklib_json:encode(#{result=>error, data=>#{code=>Code, error=>Txt}}),
    {http, 400, Hds2, Body, Req}.


%% ===================================================================
%% Callbacks
%% ===================================================================


%% @private
init(HttpReq, [{srv_id, SrvId}, {id, Id}]) ->
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
        <<"OPTIONS">> -> options;
        <<"HEAD">> -> head;
        OtherMethod -> OtherMethod
    end,
    Path = case cowboy_req:path_info(HttpReq) of
        [<<>>|Rest] -> Rest;
        Rest -> Rest
    end,
    Req = #req{
        srv_id = SrvId,
        id = Id,
        req = HttpReq,
        method = Method,
        path = Path,
        remote = Remote
    },
    set_log(SrvId),
    ?DEBUG("received ~p (~p) from ~s", [Method, Path, Remote], Req),
    case ?CALL_SRV(SrvId, nkservice_rest_http, [Id, Method, Path, Req]) of
        {http, Code, Hds, Body, #req{req=HttpReq2}} ->
            {ok, cowboy_req:reply(Code, Hds, Body, HttpReq2), []};
        {http, Code, Hds, Body} ->
            ?LLOG(warning,"unupdated nkservice_rest_http callback: ~p ~p ~p ~p", [SrvId, Id, Method, Path], Req),
            {ok, cowboy_req:reply(Code, Hds, Body, HttpReq), []};
        {redirect, Path2} ->
            Url = <<(cowboy_req:url(HttpReq))/binary, (to_bin(Path2))/binary>>,
            HttpReq2 = cowboy_req:set_resp_header(<<"location">>, Url, HttpReq),
            {ok, cowboy_req:reply(301, [], <<>>, HttpReq2), []};
        continue ->
            {ok, cowboy_req:reply(404, [], <<"Resource not found">>, HttpReq), []}
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
