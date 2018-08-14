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

%% @doc
-module(nkservice_rest_http).
-export([get_body/2, get_headers/1, get_qs/1, get_basic_auth/1]).
-export([stream_start/3, stream_body/2, stream_stop/1]).
-export([get_accept/1]).
-export([reply_json/2, make_req_ext/2, reply_req_ext/2]).
-export([init/4, terminate/3]).
-export_type([method/0, reply/0, code/0, headers/0, body/0, req/0, path/0, http_qs/0]).

-define(MAX_BODY, 10000000).


-define(DEBUG(Txt, Args, State),
    case erlang:get(nkservice_rest_debug) of
        true -> ?LLOG(debug, Txt, Args, State);
        _ -> ok
    end).

-define(LLOG(Type, Txt, Args, Req),
    lager:Type("NkSERVICE REST HTTP (~s:~s ~s) "++Txt,
               [maps:get(srv, Req), maps:get(plugin_id, Req), maps:get(peer, Req)|Args])).

-include_lib("nkservice/include/nkservice.hrl").
-include_lib("nkpacket/include/nkpacket.hrl").


%% ===================================================================
%% Types
%% ===================================================================


-type method() :: binary().         %% <<"GET">> ...

-type code() :: 100 .. 599.

-type headers() :: #{binary() => iolist()}.

-type body() ::  Body::binary()|map().

-type http_qs() ::
    [{binary(), binary()|true}].

-type path() :: [binary()].

-type req() ::
    #{
        srv => nkservice:id(),
        plugin_id => nkservice:module_id(),
        method => method(),
        path => [binary()],
        peer => binary(),
        content_type => binary(),
        cowboy_req => term()
    }.


-type reply() ::
    {http, code(), headers(), body(), req()}.


%% ===================================================================
%% Public
%% ===================================================================


%% @doc
-spec get_body(req(), #{max_size=>integer(), parse=>boolean()}) ->
    {ok, binary(), req()} | {error, term()}.

get_body(#{content_type:=CT, cowboy_req:=CowReq}=Req, Opts) ->
    MaxBody = maps:get(max_size, Opts, 100000),
    case cowboy_req:body_length(CowReq) of
        BL when is_integer(BL), BL =< MaxBody ->
            %% https://ninenines.eu/docs/en/cowboy/2.1/guide/req_body/
            {ok, Body, CowReq2} = cowboy_req:read_body(CowReq, #{length=>infinity}),
            Req2 = Req#{cowboy_req:=CowReq2},
            case maps:get(parse, Opts, false) of
                true ->
                    case CT of
                        <<"application/json", _/binary>> when is_binary(Body) ->
                            case catch nklib_json:decode(Body) of
                                {'EXIT', _} ->
                                    {error, invalid_json};
                                Json ->
                                    {ok, Json, Req2}
                            end;
                        <<"application/json", _/binary>> ->
                            {error, invalid_json};
                        _ when is_binary(CT) ->
                            case binary:split(CT, <<"yaml">>) of
                                [_, _] when is_binary(Body) ->
                                    case catch nklib_yaml:decode(Body) of
                                        {'EXIT', _} ->
                                            {error, invalid_yaml};
                                        Yaml ->
                                            {ok, Yaml, Req2}
                                    end;
                                [_, _] ->
                                    {error, invalid_yaml};
                                _ ->
                                    {ok, Body, Req2}
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


-spec get_headers(req()) ->
    headers().

get_headers(#{cowboy_req:=CowReq}) ->
    cowboy_req:headers(CowReq).


%% @doc
-spec get_qs(req()) ->
    http_qs().

get_qs(#{cowboy_req:=CowReq}) ->
    cowboy_req:parse_qs(CowReq).


%% @doc
-spec get_accept(req()) ->
    binary().

get_accept(#{cowboy_req:=CowReq}) ->
    cowboy_req:parse_header(<<"accept">>, CowReq).


%% @doc
-spec get_basic_auth(req()) ->
    {ok, binary(), binary()} | undefined.

get_basic_auth(#{cowboy_req:=CowReq}) ->
    case cowboy_req:parse_header(<<"authorization">>, CowReq) of
        {basic, User, Pass} ->
            {ok, User, Pass};
        _ ->
            undefined
    end.


%% @private
make_req_ext(PackageId, #{srv:=SrvId, content_type:=CT}=Req) ->
    Config = nkservice_util:get_cache(SrvId, ?PKG_REST, PackageId, request_config),
    Map1 = maps:with([srv, plugin_id, method, path, peer], Req),
    Map2 = Map1#{contentType => CT},
    make_req_ext(Config, Config, Map2, Req).


%% @private
make_req_ext([], _Spec, Info, Req) ->
    {ok, Info, Req};

make_req_ext([{requestGetBody, true}|Rest], Config, Info, Req) ->
    Max = nklib_util:get_value(requestMaxBodySize, Config, 10000000),
    Parse = nklib_util:get_value(requestParseBody, Config, false),
    case get_body(Req, #{max_size=>Max, parse=>Parse}) of
        {ok, Body, Req2} ->
            Info2  = Info#{body=>Body},
            make_req_ext(Rest, Config, Info2, Req2);
        {error, Error} ->
            {error, Error}
    end;

make_req_ext([{requestGetHeaders, Hds}|Rest], Config, Info, Req) ->
    Hds2 = [{Hd, cowboy_req:header(Hd, Req)} || Hd <- Hds],
    Info2 = Info#{headers => Hds2},
    make_req_ext(Rest, Config, Info2, Req);

make_req_ext([{requestGetAllHeaders, true}|Rest], Config, Info, Req) ->
    Info2 = Info#{allHeaders => get_headers(Req)},
    make_req_ext(Rest, Config, Info2, Req);

make_req_ext([{requestGetQs, true}|Rest], Config, Info, Req) ->
    Info2 = Info#{qs => maps:from_list(get_qs(Req))},
    make_req_ext(Rest, Config, Info2, Req);

make_req_ext([{requestGetBasicAuthorization, true}|Rest], Config, Info, Req) ->
    Info2 = case get_basic_auth(Req) of
        {ok, User, Pass} ->
            Info#{user => User, pass => Pass};
        undefined ->
            Info#{user => <<>>}
    end,
    make_req_ext(Rest, Config, Info2, Req);

make_req_ext([_|Rest], Config, Info, Req) ->
    make_req_ext(Rest, Config, Info, Req).


%% @doc
reply_req_ext(Reply, Req) ->
    Syntax = #{
        code => {integer, 200, 599},
        body => binary,
        headers => map,
        redirect => binary
    },
    case nklib_syntax:parse(Reply, Syntax) of
        {ok, Parsed, _} ->
            do_reply_req_ext(Parsed, Req);
        {error, Error} ->
            ?LLOG(notice, "invalid reply from script ~p: ~p", [Reply, Error], Req),
            {http, 500, [], "Reply response error", Req}
    end.


%% @doc
do_reply_req_ext(#{redirect:=Redirect}, _Req) ->
    {redirect, Redirect};

do_reply_req_ext(#{code:=Code}=Luerl, Req) ->
    Headers1 = maps:fold(
        fun(K, V, Acc) -> [{to_bin(K), to_bin(V)}|Acc] end,
        [],
        maps:get(headers, Luerl, #{})),
    Body = maps:get(body, Luerl, <<>>),
    {http, Code, Headers1, Body, Req}.


%% @doc Streamed responses
%% First, call this function
%% Then call stream_body/2 for each chunk, and finish with {stop, Req}

stream_start(Code, Hds, #{cowboy_req:=CowReq}=Req) ->
    CowReq2 = nkpacket_cowboy:stream_reply(Code, Hds, CowReq),
    Req#{cowboy_req:=CowReq2}.


%% @doc
stream_body(Body, #{cowboy_req:=CowReq}) ->
    ok = nkpacket_cowboy:stream_body(Body, nofin, CowReq).


%% @doc
stream_stop(#{cowboy_req:=CowReq}) ->
    ok = nkpacket_cowboy:stream_body(<<>>, fin, CowReq).


%% @doc
reply_json({ok, Data}, _Req) ->
    Hds = #{<<"Content-Tytpe">> => <<"application/json">>},
    Body = nklib_json:encode(Data),
    {http, 200, Hds, Body};

reply_json({error, Error}, #{srv:=SrvId}) ->
    Hds = #{<<"Content-Tytpe">> => <<"application/json">>},
    {Code, Txt} = nkservice_msg:msg(SrvId, Error),
    Body = nklib_json:encode(#{result=>error, data=>#{code=>Code, error=>Txt}}),
    {http, 200, Hds, Body}.


%% ===================================================================
%% Callbacks
%% ===================================================================


%% @private
%% Called from nkpacket_transport_http:cowboy_init/5
init(Paths, CowReq, Env, NkPort) ->
    Start = nklib_util:l_timestamp(),
    {Ip, Port} = cowboy_req:peer(CowReq),
    Peer = <<
        (nklib_util:to_host(Ip))/binary, ":",
        (to_bin(Port))/binary
    >>,
    {ok, {nkservice_rest, SrvId, Id}} = nkpacket:get_class(NkPort),
    Method = cowboy_req:method(CowReq),
    Req = #{
        srv => SrvId,
        plugin_id => Id,
        method => Method,
        path => Paths,
        peer => Peer,
        content_type => cowboy_req:header(<<"content-type">>, CowReq),
        cowboy_req => CowReq
    },
    set_debug(Req),
    ?DEBUG("received '~p' (~s) from ~s", [Method, Paths, Peer], Req),
    Res = ?CALL_SRV(SrvId, nkservice_rest_http, [Id, Method, Paths, Req]),
    ?DEBUG("request processing time: ~pusecs", [nklib_util:l_timestamp()-Start], Req),
    case Res of
        {http, Code, Hds, Body, #{cowboy_req:=CowReq2}} ->
            ?DEBUG("replying '~p' (~p) ~s", [Code, Hds, Body], Req),
            {ok, nkpacket_cowboy:reply(Code, Hds, Body, CowReq2), Env};
        {stop, #{cowboy_req:=CowReq2}} ->
            ?DEBUG("replying stream stop", [], Req),
            {ok, CowReq2, Env};
        {redirect, Path3} ->
            {redirect, Path3};
        {cowboy_static, Opts} ->
            ?DEBUG("replying cowboy_static (~p)", [Opts], Req),
            {cowboy_static, Opts};
        {cowboy_rest, Module, State} ->
            ?DEBUG("replying cowboy_rest '~p'", [Module], Req),
            {cowboy_rest, Module, State};
        continue ->
            ?DEBUG("replying 'continue'", [], Req),
            Reply = nkpacket_cowboy:reply(404, #{},
                        <<"NkSERVICE REST resource not found">>, CowReq),
            {ok, Reply, Env}
    end.


%% @private
terminate(_Reason, _Req, _Opts) ->
    ok.


%% ===================================================================
%% Internal
%% ===================================================================

%% @private
set_debug(#{srv:=SrvId, plugin_id:=Id}=Req) ->
    Debug = nkservice_util:get_debug(SrvId, nkservice_rest, Id, http) == true,
    put(nkservice_rest_debug, Debug),
    ?DEBUG("debug mode activated", [], Req).


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).
