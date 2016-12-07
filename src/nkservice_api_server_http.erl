%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Carlos Gonzalez Florido.  All Rights Reserved.
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

-module(nkservice_api_server_http).
-export([filename_encode/3, filename_decode/1]).
-export([init/2, terminate/3]).

-define(MAX_BODY, 100000).
-define(MAX_ACK_TIME, 180).

-include("nkservice.hrl").



%% ===================================================================
%% Public
%% ===================================================================


%% @private
-spec filename_encode(Module::atom(), Id::term(), Name::term()) ->
    binary().

filename_encode(Module, ObjId, Name) ->
    Term1 = term_to_binary({Module, ObjId, Name}),
    Term2 = base64:encode(Term1),
    Term3 = http_uri:encode(binary_to_list(Term2)),
    list_to_binary(Term3).


%% @private
-spec filename_decode(binary()|string()) ->
    {Module::atom(), Id::term(), Name::term()}.

filename_decode(Term) ->
    try
        Uri = http_uri:decode(nklib_util:to_list(Term)),
        BinTerm = base64:decode(Uri),
        {Module, Id, Name} = binary_to_term(BinTerm),
        {Module, Id, Name}
    catch
        error:_ -> error
    end.


%% ===================================================================
%% Incoming
%% ===================================================================

%% @private
incoming(SrvId, <<"POST">>, [], _CT, Msg, Req, State) when is_map(Msg) ->
    case Msg of
        #{<<"class">> := Class, <<"cmd">> := Cmd} ->
            #{srv_id:=SrvId, user:=User, session_id:=SessId} = State,
            TId = erlang:phash2(make_ref()),
            ApiReq = #api_req{
                srv_id = SrvId,
                class = Class,
                subclass = maps:get(<<"subclass">>, Msg, <<"core">>),
                cmd = Cmd,
                tid = TId,
                data = maps:get(<<"data">>, Msg, #{}), 
                user_id = User,
                session_id = SessId
            },
            case nkservice_api_lib:process_req(ApiReq, State) of
                {ok, Reply, _State2} when is_map(Reply); is_list(Reply) ->
                    send_msg_ok(SrvId, Reply, Req);
                {ack, _State2} ->
                    #{session_id:=SessId} = State,
                    nkservice_api_server:do_register_http(SessId),
                    ack_wait(SrvId, TId, Req);
                {error, Error, _State2} ->
                    send_msg_error(SrvId, Error, Req)
            end;
        _ ->
            throw(cowboy_req:reply(400, [], <<"Invalid Command">>, Req))
    end;

incoming(SrvId, <<"GET">>, [<<"download">>, File], _CT, _Body, Req, State) ->
    case filename_decode(File) of
        {Mod, ObjId, Name} ->
            case handle(api_server_http_download, [Mod, ObjId, Name], State) of
                {ok, CT2, Bin, _State2} when is_binary(Bin) ->
                    Hds = [{<<"content-type">>, CT2}],
                    cowboy_req:reply(200, Hds, Bin, Req);
                {error, Error, _State2} ->
                    send_http_error(SrvId, Error, Req)
            end;
        error ->
            cowboy_req:reply(400, [], <<"Invalid file name">>, Req)
    end;

incoming(SrvId, <<"POST">>, [<<"upload">>, File], CT, Body, Req, State) ->
    case filename_decode(File) of
        {Mod, ObjId, Name} ->
            case handle(api_server_http_upload, [Mod, ObjId, Name, CT, Body], State) of
                {ok, _State2} ->
                    cowboy_req:reply(200, [], <<>>, Req);
                {error, Error, _State2} ->
                    send_http_error(SrvId, Error, Req)
            end;
        error ->
            cowboy_req:reply(400, [], <<"Invalid file name">>, Req)
    end;

incoming(_SrvId, <<"GET">>, Path, _CT, _Body, Req, State) ->
    {ok, Code, Hds, Body2} = handle(api_server_http_get, [Path], State),        
    cowboy_req:reply(Code, Hds, Body2, Req);

incoming(_SrvId, <<"POST">>, Path, CT, Body, Req, State) ->
    {ok, Code, Hds, Body2} = handle(api_server_http_post, [Path, CT, Body], State),
    cowboy_req:reply(Code, Hds, Body2, Req);

incoming(_SrvId, Method, Path, CT, Body, Req, _State) ->
    lager:notice("Unhandled request: ~s, ~s, ~s, ~s", [Method, Path, CT, Body]),
    cowboy_req:reply(404, [], <<"Unhandled Request">>, Req).


%% @private
ack_wait(SrvId, TId, Req) ->
    receive
        {'$gen_cast', {nkservice_reply_ok, TId, Reply}} ->
            send_msg_ok(SrvId, Reply, Req);
        {'$gen_cast', {nkservice_reply_error, TId, Error}} ->
            send_msg_error(SrvId, Error, Req)
    after 
        1000*?MAX_ACK_TIME -> 
            send_msg_error(SrvId, timeout, Req)
    end.



%% ===================================================================
%% Callbacks
%% ===================================================================


%% @private
init(Req, [{srv_id, SrvId}]) ->
    try
        State = auth(SrvId, Req),
        Method = cowboy_req:method(Req),
        PathInfo = cowboy_req:path_info(Req),
        CT = cowboy_req:header(<<"content-type">>, Req),
        Body = get_body(CT, Req),
        Req2 = incoming(SrvId, Method, PathInfo, CT, Body, Req, State),
        {ok, Req2, []}
    catch
        throw:ReqF -> 
            {ok, ReqF, []}
    end.


%% @private
terminate(_Reason, _Req, _Opts) ->
    ok.


%% ===================================================================
%% Internal
%% ===================================================================


%% @private
auth(SrvId, Req) ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
        {basic, User, Pass} ->
            Data = #{user=>User, password=>Pass, meta=>#{}},
            SessId = nklib_util:luid(),
            {Ip, Port} = cowboy_req:peer(Req),
            Transp = tls,
            Remote = <<
                (nklib_util:to_binary(Transp))/binary, ":",
                (nklib_util:to_host(Ip))/binary, ":",
                (nklib_util:to_binary(Port))/binary
            >>,
            State = #{
                srv_id => SrvId, 
                session_type => ?MODULE,
                session_id => SessId,
                remote => Remote
            },
            case handle(api_server_login, [Data], State) of
                {true, User2, _Meta, State2} ->
                    State2#{user=>User2};
                {false, _State2} ->
                    lager:warning("HTTP RPC forbidden"),
                    throw(cowboy_req:reply(403, [], <<>>, Req))
            end;
        _Other ->
            lager:warning("RPC not authorized: ~p", [_Other]),
            Hds = [{<<"www-authenticate">>, <<"Basic realm=\"netcomposer\"">>}],
            throw(cowboy_req:reply(401, Hds, <<>>, Req))
    end.


%% @private
get_body(CT, Req) ->
    case cowboy_req:body_length(Req) of
        BL when is_integer(BL), BL =< ?MAX_BODY ->
            {ok, Body, _} = cowboy_req:body(Req),
            case CT of
                <<"application/json">> ->
                    case nklib_json:decode(Body) of
                        error ->
                            Req2 = cowboy_req:reply(400, [], <<"Invalid Json">>, Req),
                            throw(Req2);
                        Json ->
                            Json
                    end;
                _ ->
                    Body
            end;
        _ ->
            Req2 = cowboy_req:reply(400, [], <<"Body Too Large">>, Req),
            throw(Req2)
    end.


%% @private
send_msg_ok(_SrvId, Data, Req) ->
    Msg1 = #{result=>ok},
    Msg2 = case Data of
        #{} when map_size(Data)==0 -> Msg1;
        #{} -> Msg1#{data=>Data};
        List when is_list(List) -> Msg1#{data=>Data}
    end,
    send_http_msg(Msg2, Req).


%% @private
send_msg_error(SrvId, Error, Req) ->
    {Code, Text} = nkservice_util:error_code(SrvId, Error),
    Msg = #{
        result => error,
        data => #{ 
            code => Code,
            error => Text
        }
    },
    send_http_msg(Msg, Req).


%% @private
send_http_msg(Resp, Req) ->
    Hds = [{<<"content-type">>, <<"application/json">>}],
    Resp2 = nklib_json:encode(Resp),
    cowboy_req:reply(200, Hds, Resp2, Req).


%% @private
send_http_error(SrvId, Error, Req) ->
    case Error of
        not_found ->
            cowboy_req:reply(404, [], <<"Not found">>, Req);
        forbidden ->
            cowboy_req:reply(403, [], <<"Forbidden">>, Req);
        _ ->
            {_Code, Text} = nkservice_util:error_code(SrvId, Error),
            cowboy_req:reply(400, [], Text, Req)
    end.

%% @private
handle(Fun, Args, #{srv_id:=SrvId}=State) ->
    apply(SrvId, Fun, Args++[State]).


