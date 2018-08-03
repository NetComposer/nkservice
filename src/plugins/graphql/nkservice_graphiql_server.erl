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

%% @doc NkDomain GraphQL main module
-module(nkservice_graphiql_server).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([http/3]).




%%====================================================================
%% GraphQL
%%====================================================================

%% @private
http(<<"GET">>, [], Req) ->
    http(<<"GET">>, [<<"index.html">>], Req);

http(<<"GET">>, [<<"index.html">>], Req) ->
    Path = filename:join(code:priv_dir(nkdomain), "graphiql/index.html"),
    {ok, File} = file:read_file(Path),
    {http, 200, content_type(Path), File, Req};

http(<<"GET">>, [<<"assets">>, Name], Req) ->
    Path = filename:join([code:priv_dir(nkdomain), "graphiql/assets", Name]),
    % content_type(Path),
    {ok, File} = file:read_file(Path),
    {http, 200, content_type(Path), File, Req};

http(<<"POST">>, [], #{srv:=SrvId}=Req) ->
    NkMeta = #{
        start => nklib_util:m_timestamp(),
        srv => SrvId
    },
    case gather(Req) of
        {ok, Decoded, Req2} ->
            Reply = run_request(Decoded#{nkmeta=>NkMeta}),
            http_reply(SrvId, Reply, Req2);
        {error, Reason} ->
            http_reply(SrvId, {error, Reason}, Req)
    end.


%% @private
http_reply(_SrvId, {ok, Data}, Req) ->
    Body = nklib_json:encode_pretty(Data#{success=>true}),
    {http, 200, [], Body, Req};

http_reply(SrvId, {error, {error, Error}}, Req) ->
    http_reply(SrvId, {error, Error}, Req);

http_reply(SrvId, {error, Error}, Req) ->
    lager:error("NKLOG GRAPHIQL ERROR ~p", [Error]),
    {Code, Msg} = nkservice_graphql:make_error(SrvId, Error),
    Body1 = #{success=>false, error=>#{code=>Code, message=>Msg}},
    Body2 = nklib_json:encode_pretty(Body1),
    {http, 400, [], Body2, Req}.



%% @private
content_type(Path) ->
    {A, B, _C} = cow_mimetypes:all(nklib_util:to_binary(Path)),
    [{<<"content-type">>, <<A/binary, $/, B/binary, ";charset=utf-8">>}].


%% @private
run_request(#{ document := undefined }) ->
    {error, no_query_supplied};

run_request(#{document:=Doc} = ReqCtx) ->
    case graphql:parse(Doc) of
        {ok, AST} ->
            run_preprocess(ReqCtx#{document := AST});
        {error, Reason} ->
            {error, Reason}
    end.


%% @private
run_preprocess(#{document:=AST}=ReqCtx) ->
    try
        Elaborated = graphql:elaborate(AST),
        {ok, #{
            fun_env := FunEnv,
            ast := AST2 }} = graphql:type_check(Elaborated),
        ok = graphql:validate(AST2),
        run_execute(ReqCtx#{document := AST2, fun_env => FunEnv})
    catch
        throw:Error ->
            {error, Error}
    end.


%% @private
run_execute(ReqCtx) ->
    #{
        document := AST,
        fun_env := FunEnv,
        vars := Vars,
        operation_name := OpName,
        nkmeta := NkMeta
    } = ReqCtx,
    Coerced = graphql:type_check_params(FunEnv, OpName, Vars),
    Ctx = #{
        params => Coerced,
        operation_name => OpName,
        nkmeta => NkMeta
    },
    Res = graphql:execute(Ctx, AST),
    case Res of
        #{errors:=[Error1|_]} ->
            {error, Error1};
        #{data:=_}=Data->
            {ok, Data}
    end.


%% @private
gather(#{cowboy_req:=CowReq1}=Req) ->
    {ok, Body, CowReq2} = cowboy_req:read_body(CowReq1),
    Bindings = cowboy_req:bindings(CowReq2),
    % Params = maps:from_list(Bindings),
    case catch nklib_json:decode(Body) of
        JSON when is_map(JSON) ->
            gather(JSON, Bindings, Req#{cowboy_req:=CowReq2});
        _ ->
            {error, invalid_json_body}
    end.


%% @private
gather(Body, Params, Req) ->
    QueryDocument = document([Params, Body]),
    case variables([Params, Body]) of
        {ok, Vars} ->
            Operation = operation_name([Params, Body]),
            Data = #{
                document => QueryDocument,
                vars => Vars,
                operation_name => Operation
            },
            {ok, Data, Req};
        {error, Reason} ->
            {error, Reason}
    end.


%% @private
document([#{ <<"query">> := Q }|_]) -> Q;
document([_|Next]) -> document(Next);
document([]) -> undefined.


%% @private
variables([#{ <<"variables">> := Vars} | _]) ->
    if
        is_binary(Vars) ->
            case catch nklib_json:decode(Vars) of
                null ->
                    {ok, #{}};
                JSON when is_map(JSON) ->
                    {ok, JSON};
                _ ->
                    {error, invalid_json}
            end;
        is_map(Vars) ->
            {ok, Vars};
        Vars == null ->
            {ok, #{}}
    end;
variables([_ | Next]) ->
    variables(Next);
variables([]) ->
    {ok, #{}}.


%% @private
operation_name([#{ <<"operationName">> := OpName } | _]) ->
    OpName;
operation_name([_ | Next]) ->
    operation_name(Next);
operation_name([]) ->
    undefined.



%%%% Ground types
%%fixup(Term) when is_number(Term) -> Term;
%%fixup(Term) when is_atom(Term) -> Term;
%%fixup(Term) when is_binary(Term) -> Term;
%%%% Compound types
%%fixup(Term) when is_list(Term) ->
%%    [fixup(T) || T <- Term];
%%fixup(Term) when is_map(Term) ->
%%    KVs = maps:to_list(Term),
%%    maps:from_list([{fixup_key(K), fixup(V)} || {K, V} <- KVs]);
%%fixup(Term) ->
%%    %% Every other term is transformed into a binary value
%%    iolist_to_binary(
%%        io_lib:format("~p", [Term])).
%%
%%fixup_key(Term) ->
%%    case fixup(Term) of
%%        T when is_binary(T) ->
%%            T;
%%        T ->
%%            iolist_to_binary(io_lib:format("~p", [T]))
%%    end.



%%err(Code, Msg, Req) ->
%%    %% lager:notice("NKLOG GRAPHI ERROR ~p ~p", [Code, Msg]),
%%    Formatted = iolist_to_binary(io_lib:format("~p", [Msg])),
%%    Err = #{
%%        type => error,
%%         message => Formatted
%%    },
%%    Body = nklib_json:encode_pretty(#{errors => [Err]}),
%%    {http, Code, [], Body, Req}.

