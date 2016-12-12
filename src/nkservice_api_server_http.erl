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


-define(DEBUG(Txt, Args, State),
    case erlang:get(nkservice_api_server_debug) of
        true -> ?LLOG(debug, Txt, Args, State);
        _ -> ok
    end).

-define(LLOG(Type, Txt, Args, State),
    lager:Type("NkSERVICE API Server HTTP (~s, ~s) "++Txt, 
               [State#state.user, State#state.id|Args])).




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


-record(state, {
    id :: binary(),
    srv_id :: nkservice:id(),
    session_type :: atom(),
    remote :: binary(),
    user :: binary(),
    user_state :: map(),
    req :: term(),
    method :: binary(),
    path :: [binary()],
    ct :: binary(),
    body :: binary() | map()
}).


%% @private
incoming(post, [], #state{user = <<>>}) ->
    throw(forbidden);

incoming(post, [], #state{body=#{<<"class">>:=Class, <<"cmd">>:=Cmd}=Body}=State) ->
    #state{srv_id=SrvId, user=User, id=SessId, user_state=UserState} = State,
    TId = erlang:phash2(make_ref()),
    ApiReq = #api_req{
        srv_id = SrvId,
        class = Class,
        subclass = maps:get(<<"subclass">>, Body, <<>>),
        cmd = Cmd,
        tid = TId,
        data = maps:get(<<"data">>, Body, #{}), 
        user_id = User,
        session_id = SessId
    },
    case nkservice_api_lib:process_req(ApiReq, UserState) of
        {ok, Reply, UserState2} ->
            {ok, Reply, State#state{user_state=UserState2}};
        {ack, UserState2} ->
            nkservice_api_server:do_register_http(SessId),
            ack_wait(TId, State#state{user_state=UserState2});
        {error, Error, UserState2} ->
            {error, Error, State#state{user_state=UserState2}}
    end;

incoming(post, [<<"upload">>, _], #state{user = <<>>}) ->
    throw(forbidden);

incoming(post, [<<"upload">>, File], #state{user=User, ct=CT, body=Body}=State) ->
    case filename_decode(File) of
        {Mod, ObjId, Name} ->
            ?DEBUG("decoded upload ~s:~s:~s", [Mod, ObjId, Name], State),
            Args = [User, Mod, ObjId, Name, CT, Body],
            case handle(api_server_http_upload, Args, State) of
                {ok, State2} ->
                    {http, 200, [], <<>>, State2};
                {error, Error, _State2} ->
                    throw(Error)
            end;
        error ->
            throw(invalid_file_name)
    end;

incoming(get, [<<"download">>, _], #state{user = <<>>}) ->
    throw(forbidden);

incoming(get, [<<"download">>, File], #state{user=User}=State) ->
    case filename_decode(File) of
        {Mod, ObjId, Name} ->
            ?DEBUG("decoded download ~s:~s:~s", [Mod, ObjId, Name], State),
            case handle(api_server_http_download, [User, Mod, ObjId, Name], State) of
                {ok, CT2, Bin, State2} ->
                    Hds = [{<<"content-type">>, CT2}],
                    {http, 200, Hds, Bin, State2};
                {error, Error, _State2} ->
                    throw(Error)
            end;
        error ->
            throw(invalid_file_name)
    end;

incoming(get, Path, #state{user=User, req=Req}=State) ->
    handle(api_server_http_get, [User, Path, Req], State);

incoming(post, Path, #state{user=User, ct=CT, body=Body, req=Req}=State) ->
    handle(api_server_http_post, [User, Path, CT, Body, Req], State).


%% @private
ack_wait(TId, State) ->
    receive
        {'$gen_cast', {nkservice_reply_ok, TId, Reply}} ->
            send_msg_ok(Reply, State);
        {'$gen_cast', {nkservice_reply_error, TId, Error}} ->
            send_msg_error(Error, State)
    after 
        1000*?MAX_ACK_TIME -> 
            send_msg_error(timeout, State)
    end.



%% ===================================================================
%% Callbacks
%% ===================================================================


%% @private
init(Req, [{srv_id, SrvId}]) ->
    {Ip, Port} = cowboy_req:peer(Req),
    Transp = tls,
    Remote = <<
        (nklib_util:to_binary(Transp))/binary, ":",
        (nklib_util:to_host(Ip))/binary, ":",
        (nklib_util:to_binary(Port))/binary
    >>,
    SessId = nklib_util:luid(),
    Method = case cowboy_req:method(Req) of
        <<"POST">> -> post;
        <<"GET">> -> get;
        _ -> throw(invalid_method)
    end,
    Path = cowboy_req:path_info(Req),
    UserState = #{srv_id=>SrvId, id=>SessId, remote=>Remote},
    State1 = #state{
        id = SessId,
        srv_id = SrvId, 
        session_type = ?MODULE,
        remote = Remote,
        user = <<>>,
        user_state = UserState,
        req = Req,
        method = Method,
        path = Path,
        ct = cowboy_req:header(<<"content-type">>, Req)
    },
    set_log(State1),
    ?DEBUG("received ~p (~p) from ~s", [Method, Path, Remote], State1),
    try
        State2 = auth(State1),
        State3 = get_body(State2),
        case incoming(Method, Path, State3) of
            {ok, Reply, State4} ->
                send_msg_ok(Reply, State4);
            {error, Error, State4} ->
                send_msg_error(Error, State4);
            {http, Code, Hds, Body, State4} ->
                http_reply(Code, Hds, Body, State4)
        end
    catch
        throw:TError ->
            {http, TCode, THds, TBody, TState} = http_error(TError, State1),
            http_reply(TCode, THds, TBody, TState)
    end.


%% @private
terminate(_Reason, _Req, _Opts) ->
    ok.


%% ===================================================================
%% Internal
%% ===================================================================


%% @private
set_log(#state{srv_id=SrvId}=State) ->
    Debug = case nkservice_util:get_debug_info(SrvId, nkservice_api_server) of
        {true, _} -> true;
        _ -> false
    end,
    % lager:error("DEBUG: ~p", [Debug]),
    put(nkservice_api_server_debug, Debug),
    State.


%% @private
auth(#state{req=Req, remote=Remote}=State) ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
        {basic, User, Pass} ->
            Data = #{module=>?MODULE, user=>User, password=>Pass, meta=>#{}},
            % We do the same as nkservice_api:cmd(user, login, _),
            case handle(api_server_login, [Data], State) of
                {true, User2, _Meta, State2} ->
                    State3 = State2#state{user=User2},
                    ?LLOG(info, "user authenticated (~s)", [Remote], State3),
                    State3;
                {false, _State2} ->
                    ?LLOG(info, "user forbidden (~s)", [Remote], State),
                    throw(forbidden)
            end;
        _Other ->
            State
    end.


%% @private
get_body(#state{ct=CT, req=Req}=State) ->
    case cowboy_req:body_length(Req) of
        BL when is_integer(BL), BL =< ?MAX_BODY ->
            {ok, Body, _} = cowboy_req:body(Req),
            case CT of
                <<"application/json">> ->
                    case nklib_json:decode(Body) of
                        error ->
                            throw(invalid_json);
                        Json ->
                            State#state{body=Json}
                    end;
                _ ->
                    State#state{body=Body}
            end;
        _ ->
            throw(body_too_large)
    end.


%% @private
send_msg_ok(Reply, State) ->
    Msg1 = #{result=>ok},
    Msg2 = case Reply of
        #{} when map_size(Reply)==0 -> Msg1;
        #{} -> Msg1#{data=>Reply};
        List when is_list(List) -> Msg1#{data=>Reply}
    end,
    http_reply(200, [], Msg2, State).


%% @private
send_msg_error(Error, #state{srv_id=SrvId}=State) ->
    {Code, Text} = nkservice_util:error_code(SrvId, Error),
    Msg = #{
        result => error,
        data => #{ 
            code => Code,
            error => Text
        }
    },
    http_reply(200, [], Msg, State).


%% @private
http_reply(Code, Hds, Body, #state{req=Req}) ->
    {Hds2, Body2} = case is_map(Body) of
        true -> 
            {
                [{<<"content-type">>, <<"application/json">>}|Hds],
                nklib_json:encode(Body)
            };
        false -> 
            {
                Hds,
                nklib_util:to_binary(Body)
            }
    end,
    {ok, cowboy_req:reply(Code, Hds2, Body2, Req), []}.



%% @private
http_error(Error, #state{srv_id=SrvId}=State) ->
    case Error of
        unauthorized ->
            ?LLOG(info, "missing authorization", [], State),
            Hds0 = [{<<"www-authenticate">>, <<"Basic realm=\"netcomposer\"">>}],
            {http, 401, Hds0, <<>>, State};
        invalid_request ->
            {http, 400, [], <<"Invalid Request">>, State};
        invalid_json ->
            {http, 400, [], <<"Invalid JSON">>, State};
        forbidden ->
            {http, 403, [], <<"Forbidden">>, State};
        invalid_file_name ->
            {http, 400, [], <<"Invalid file name">>, State};
        body_too_large ->
            {http, 400, [], <<"Body Too Large">>, State};
        _ ->
            {_Code, Text} = nkservice_util:error_code(SrvId, Error),
            {http, 400, [], Text, State}
    end.


%% @private
handle(Fun, Args, State) ->
    nklib_gen_server:handle_any(Fun, Args, State, #state.srv_id, #state.user_state).


