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

%% @doc
%% When an http listener is configured for api_server, and a request arrives,
%% init/2 is called
%% - if the header "authorization" is present, api_server_login is called,
%%   and the 'user' field is populated if valid
%% - if the body is present, and size is correct, is captured and the if JSON, decoded
%% - incoming/3 is called
%%
%% By default:
%% - If an authenticated POST is received for "/", is is managed as an API call
%% - If an authenticated POST to /upload/name 
%% - Otherwhise, api_server_http_get or api_server_http_post are invoked



-module(nkservice_api_server_http).
-export([get_body/2, get_qs/1, get_ct/1, get_user/1]).
-export([init/2, terminate/3]).
-export_type([reply/0, http_method/0, http_error/0, http_qs/0]).

-define(MAX_BODY, 10000000).
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
%% Types
%% ===================================================================


-record(state, {
    id :: binary(),
    srv_id :: nkservice:id(),
    session_type :: atom(),
    remote :: binary(),
    user :: binary(),
    user_meta = #{} :: map(),
    user_state :: map(),
    req :: term(),
    method :: binary(),
    path :: [binary()],
    ct :: binary()
}).


-type http_method() :: get | post | head | delete | put.


-type http_error() ::
    unauthorized |
    invalid_request |
    invalid_json |
    forbidden |
    not_found |
    body_too_large.


-type state() :: map().

-type reply() ::
    {ok, Reply::map(), state()} |
    {error, nkservice:error(), state()} |
    {http_ok, state()} |
    {http_error, http_error(), state()} |
    {http, Code::integer(), Hds::[{binary(), binary()}], Body::binary()|map(), state()} |
    {rpc, state()}.


-type http_qs() ::
    [{binary(), binary()|true}].

-type req() :: #state{}.



%% ===================================================================
%% Public
%% ===================================================================

%% @doc
-spec get_body(req(), #{max_size=>integer(), parse=>boolean()}) ->
    binary() | map().

get_body(#state{ct=CT, req=Req}, Opts) ->
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
                                    throw(invalid_json);
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
            throw(body_too_large)
    end.


%% @doc
-spec get_qs(req()) ->
    http_qs().

get_qs(#state{req=Req}) ->
    cowboy_req:parse_qs(Req).


%% @doc
-spec get_ct(req()) ->
    binary().

get_ct(#state{ct=CT}) ->
    CT.


%% @doc
-spec get_user(req()) ->
    {binary(), map()}.

get_user(#state{user=User, user_meta=Meta}) ->
    {User, Meta}.



%% ===================================================================
%% Callbacks
%% ===================================================================


%% @private
init(Req, [{srv_id, SrvId}]) ->
    {Ip, Port} = cowboy_req:peer(Req),
    Remote = <<
        (nklib_util:to_host(Ip))/binary, ":",
        (nklib_util:to_binary(Port))/binary
    >>,
    SessId = nklib_util:luid(),
    Method = case cowboy_req:method(Req) of
        <<"POST">> -> post;
        <<"GET">> -> get;
        <<"HEAD">> -> head;
        <<"DELETE">> -> delete;
        <<"PUT">> -> put;
        _ -> throw(invalid_method)
    end,
    Path = case cowboy_req:path_info(Req) of
        [<<>>|Rest] -> Rest;
        Rest -> Rest
    end,
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
        {User, State2} = auth(State1),
        Reply = handle(api_server_http, [Method, Path, State2], State2),
        process(Reply)
    catch
        throw:TError ->
            send_http_error(TError, State1)
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
                {true, User2, Meta, State2} ->
                    State3 = State2#state{user=User2, user_meta=Meta},
                    ?LLOG(info, "user authenticated (~s)", [Remote], State3),
                    {User2, State3};
                {false, _State2} ->
                    ?LLOG(info, "user forbidden (~s)", [Remote], State),
                    throw(forbidden)
            end;
        _Other ->
            {<<>>, State}
    end.

%% @private
process({ok, Reply, State}) ->
    send_msg_ok(Reply, State);

process({error, Error, State}) ->
    send_msg_error(Error, State);

process({http_ok, State}) ->
    send_http_reply(200, [], <<>>, State);

process({http_error, Error, State}) ->
    send_http_error(Error, State);

process({http, Code, Hds, Body, State}) ->
    send_http_reply(Code, Hds, Body, State);

process({rpc, State}) ->
    #state{srv_id=SrvId, user=User, id=SessId, user_state=UserState} = State,
    case get_body(State, 100000) of
        #{<<"class">>:=Class, <<"cmd">>:=Cmd} = Body ->
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
                    send_msg_ok(Reply, State#state{user_state=UserState2});
                {ack, UserState2} ->
                    nkservice_api_server:do_register_http(SessId),
                    ack_wait(TId, State#state{user_state=UserState2});
                {error, Error, UserState2} ->
                    send_msg_error(Error, State#state{user_state=UserState2})
            end;
        _ ->
            send_http_error(invalid_request, State)
    end.


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


%% @private
send_msg_ok(Reply, State) ->
    Msg1 = #{result=>ok},
    Msg2 = case Reply of
        #{} when map_size(Reply)==0 -> Msg1;
        #{} -> Msg1#{data=>Reply};
        List when is_list(List) -> Msg1#{data=>Reply}
    end,
    send_http_reply(200, [], Msg2, State).


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
    send_http_reply(200, [], Msg, State).


%% @private
send_http_reply(Code, Hds, Body, #state{req=Req}) ->
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
send_http_error(Error, #state{srv_id=SrvId}=State) ->
    {Code, Hds, Body} = case Error of
        unauthorized ->
            ?LLOG(info, "missing authorization", [], State),
            Hds0 = [{<<"www-authenticate">>, <<"Basic realm=\"netcomposer\"">>}],
            {401, Hds0, <<>>};
        invalid_request ->
            {400, [], <<"Invalid Request">>};
        {invalid_request, Msg} ->
            {400, [], Msg};
        internal_error ->
            {500, [], <<"Internal Error">>};
        {internal_error, Msg} ->
            {500, [], Msg};
        invalid_json ->
            {400, [], <<"Invalid JSON">>};
        forbidden ->
            {403, [], <<"Forbidden">>};
        not_found ->
            {404, [], <<"Not found">>};
        body_too_large ->
            {400, [], <<"Body Too Large">>};
        _ ->
            {_Code, Text} = nkservice_util:error_code(SrvId, Error),
            {400, [], Text}
    end,
    send_http_reply(Code, Hds, Body, State).



%% @private
handle(Fun, Args, State) ->
    nklib_gen_server:handle_any(Fun, Args, State, #state.srv_id, #state.user_state).


