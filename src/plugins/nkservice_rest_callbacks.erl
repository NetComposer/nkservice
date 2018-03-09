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

%% @doc Default callbacks
-module(nkservice_rest_callbacks).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([nkservice_rest_init/3, nkservice_rest_frame/4,
         nkservice_rest_handle_call/4, nkservice_rest_handle_cast/3,
         nkservice_rest_handle_info/3, nkservice_rest_terminate/3]).
-export([nkservice_rest_http/4]).

-include("nkservice.hrl").
-include_lib("nklib/include/nklib.hrl").


-define(DEBUG(Txt, Args),
    case erlang:get(nkservice_rest_debug) of
        true -> ?LLOG(debug, Txt, Args);
        _ -> ok
    end).


-define(LLOG(Type, Txt, Args),lager:Type("NkSERVICE REST "++Txt, Args)).


%% ===================================================================
%% REST Callbacks
%% ===================================================================

-type state() :: nkapi_server:user_state().
-type continue() :: nkservice_callbacks:continue().
-type id() :: nkservice:module_id().
-type http_method() :: nkservice_rest_http:method().
-type http_path() :: nkservice_rest_http:path().
-type http_req() :: nkservice_rest_http:req().
-type http_reply() :: nkservice_rest_http:http_reply().
-type nkport() :: nkpacket:nkport().


%% @doc called when a new http request has been received
-spec nkservice_rest_http(id(), http_method(), http_path(), http_req()) ->
    http_reply() |
    {redirect, Path::binary(), http_req()} |
    {cowboy_static, cowboy_static:opts()} |
    {cowboy_rest, Callback::module(), State::term()}.

nkservice_rest_http(Id, Method, Path, #{srv_id:=SrvId}=Req) ->
    case nkservice_util:get_callback(SrvId, ?PKG_REST, Id, requestCallback) of
        #{class:=luerl, luerl_fun:=_}=CB ->
            case nkservice_luerl_instance:spawn_callback_spec(SrvId, CB) of
                {ok, Pid} ->
                    process_luerl_req(Id, CB, Pid, Req);
                {error, too_many_instances} ->
                    {http, 429, [], <<"NkSERVICE: Too many requests">>, Req}
            end;
        _ ->
            % There is no callback defined
            #{peer:=Peer} = Req,
            ?LLOG(debug, "path not found (~p, ~s): ~p from ~s", [Id, Method, Path, Peer]),
            {http, 404, [], <<"NkSERVICE: Path Not Found">>, Req}
    end.


%% @doc Called when a new connection starts
-spec nkservice_rest_init(id(), nkport(), state()) ->
    {ok, state()} | {stop, term()}.

nkservice_rest_init(_Id, _NkPort, State) ->
    {ok, State}.


%% @doc Called when a new connection starts
-spec nkservice_rest_frame(id(), {text, binary()}|{binary, binary()}, nkport(), state()) ->
    {ok, state()} | {reply, Msg, state()}
        when Msg :: {text, iolist()} | {binary, iolist()} | {json, term()}.

nkservice_rest_frame(_Id, _Frame, _NkPort, State) ->
    ?LLOG(notice, "unhandled data ~p", [_Frame]),
    {ok, State}.


%% @doc Called when the process receives a handle_call/3.
-spec nkservice_rest_handle_call(id(), term(), {pid(), reference()}, state()) ->
    {ok, state()} | continue().

nkservice_rest_handle_call(_Id, Msg, _From, State) ->
    ?LLOG(error, "unexpected call ~p", [Msg]),
    {ok, State}.


%% @doc Called when the process receives a handle_cast/3.
-spec nkservice_rest_handle_cast(id(), term(), state()) ->
    {ok, state()} | continue().

nkservice_rest_handle_cast(_Id, Msg, State) ->
    ?LLOG(error, "unexpected cast ~p", [Msg]),
    {ok, State}.


%% @doc Called when the process receives a handle_info/3.
-spec nkservice_rest_handle_info(id(), term(), state()) ->
    {ok, state()} | continue().

nkservice_rest_handle_info(_Id, Msg, State) ->
    ?LLOG(error, "unexpected cast ~p", [Msg]),
    {ok, State}.


%% @doc Called when a service is stopped
-spec nkservice_rest_terminate(id(), term(), state()) ->
    {ok, state()}.

nkservice_rest_terminate(_Id, _Reason, State) ->
    {ok, State}.


%% ===================================================================
%% Internal
%% ===================================================================

process_luerl_req(PackageId, CBSpec, Pid, Req) ->
    Start = nklib_util:l_timestamp(),
    case nkservice_rest_http:make_req_ext(PackageId, Req) of
        {ok, ReqInfo, Req2} ->
            ?DEBUG("script spawn time: ~pusecs", [nklib_util:l_timestamp() - Start]),
            ?DEBUG("calling info: ~p", [ReqInfo]),
            case
                nkservice_luerl_instance:call_callback(Pid, CBSpec, [ReqInfo])
            of
                {ok, [Reply]} ->
                    nkservice_rest_http:reply_req_ext(Reply, Req2);
                {ok, Other} ->
                    ?LLOG(notice, "invalid reply from script ~s: ~p", [PackageId, Other]),
                    {http, 500, [], "NkSERVICE: Reply response error", Req2};
                {error, Error} ->
                    ?LLOG(notice, "invalid reply from script ~s: ~p", [PackageId, Error]),
                    {http, 500, [], "NkSERVICE: Reply response error", Req2}
            end;
        {error, Error} ->
            ?LLOG(notice, "invalid reply from script ~s: ~p", [PackageId, Error]),
            {http, 500, [], "NkSERVICE: Reply response error", Req}
    end.
