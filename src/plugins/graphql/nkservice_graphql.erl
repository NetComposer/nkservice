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
%%
%% When creating the schema:
%% - create description modules with behaviour nkservice_graphql_schema'
%% - add modules to callback nkservice_graphql_all_modules
%%
%% Query processing:
%%
%% - nkservice_graphql_query:execute/4 is called to find who is in charge of the query
%% - for 'node' queries, nkservice_graphql_obj:object_query/3 find the object details
%% - since the schema says that 'node' queries return an abstract type,
%%   nkservice_graphql_type:execute/1 is called to find the type
%% - nkservice_graphql_obj:execute/4 is called to extract each field


-module(nkservice_graphql).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([load_schema/1, request/3, make_error/2, mapping_rules/0]).
-export_type([object/0, error/0]).

-define(LLOG(Type, Txt, Args), lager:Type("NkSERVICE GraphQL "++Txt, Args)).


%% ===================================================================
%% Types
%% @see nkservice_graphql_schema
%%
%% ===================================================================

-type object() ::
    term().


-type error() ::
    #{reason=>binary(), message=>binary()} | nkservice:msg().


%% ===================================================================
%% API
%% ===================================================================


%% @doc Generates an loads a new schema
%% Srv must be the 'main' domain (only one domain can be loaded)
load_schema(SrvId) ->
    ok = graphql_schema:reset(),
    Mapping = mapping_rules(),
    Schema = nkservice_graphql_schema:make_schema(SrvId),
    % io:format("Schema: ~s\n", [Schema]),
    LogPath = nkservice_app:get(logPath),
    file:write_file(filename:join(LogPath, "schema.txt"), Schema),
    ok = graphql:load_schema(Mapping, Schema),
    ok = setup_root(),
    ok = graphql:validate_schema(),
    ok.


%% @private
mapping_rules() ->
    #{
        scalars => #{
            default => nkservice_graphql_scalar
        },
        enums => #{
            default => graphql_enum_coerce
        },
        interfaces => #{
            default => nkservice_graphql_type
        },
        unions => #{
            default => nkservice_graphql_type
        },
        objects => #{
            'Query' => nkservice_graphql_query,
            'Mutation' => nkservice_graphql_mutation,
            default => nkservice_graphql_execute
        }
    }.


%% @private
setup_root() ->
    Root = {
        root,
        #{
            query => 'Query',
            mutation => 'Mutation',
            interfaces => ['Node']
        }
    },
    ok = graphql:insert_schema_definition(Root),
    ok.



%% @doc Launches a request
request(SrvId, Str, Meta) when is_list(Str) ->
    request(SrvId, list_to_binary(Str), Meta);

request(SrvId, Str, Meta) when is_binary(Str) ->
    Meta2 = Meta#{
        start => nklib_util:m_timestamp(),
        srv => SrvId
    },
    case gather(#{<<"query">>=>Str, <<"vaiables">>=>null}, #{}) of
        {ok, Decoded} ->
            case run_request(Decoded#{nkmeta=>Meta2}) of
                {ok, Data} ->
                    {ok, Data};
                {error, Error} ->
                    {error, make_error(SrvId, Error)}
            end;
        {error, Error} ->
            {error, make_error(SrvId, Error)}
    end.


%% @private
run_request(#{document:=Doc}=Ctx) ->
    case graphql:parse(Doc) of
        {ok, AST} ->
            run_preprocess(Ctx#{document:=AST});
        {error, Reason} ->
            {error, Reason}
    end.


%% @private
run_preprocess(#{document:=AST}=ReqCtx) ->
    try
        Elaborated = graphql:elaborate(AST),
        {ok, #{
                fun_env := FunEnv,
                ast := AST2
            }
        } = graphql:type_check(Elaborated),
        ok = graphql:validate(AST2),
        run_execute(ReqCtx#{document := AST2, fun_env => FunEnv})
    catch
        throw:{error, Map} ->
            {error, Map};
        throw:Err ->
            {error, Err}
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
    Coerced = graphql:type_check_params(FunEnv, OpName, Vars), % <1>
    Ctx = #{
        params => Coerced,
        operation_name => OpName,
        nkmeta => NkMeta
    },
    Res = graphql:execute(Ctx, AST),
    case Res of
        #{errors:=[Error1|_]} ->
            {error, Error1};
        #{data:=Data} ->
            {ok, Data}
    end.



%% @private
gather(Body, Params) ->
    QueryDocument = document([Params, Body]),
    case variables([Params, Body]) of
        {ok, Vars} ->
            Operation = operation_name([Params, Body]),
            {ok, #{ document => QueryDocument,
                    vars => Vars,
                    operation_name => Operation}};
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


make_error(SrvId, Error) ->
    lager:warning("NKLOG GraphQL error: ~p", [Error]),
    do_make_error(SrvId, Error).


%% @private
do_make_error(SrvId, #{key:={resolver_error, {resolver_error, _}=Key}}=Error) ->
    do_make_error(SrvId, Error#{key:=Key});

do_make_error(SrvId, #{key:={resolver_error, {resolver_crash, _}=Key}}=Error) ->
    do_make_error(SrvId, Error#{key:=Key});

do_make_error(SrvId, #{key:=Key, message:=Msg, path:=Path}) ->
    Path2 = list_to_binary([<<" (">>, nklib_util:bjoin(Path, $.), <<" )">>]),
    case Key of
        {resolver_error, #{reason:=ErrReason, message:=ErrMsg}} ->
            {ErrReason, <<ErrMsg/binary, Path2/binary>>};
        {resolver_error, Error} ->
            case nkservice_msg:is_msg(SrvId, Error) of
                {true, ErrReason, ErrMsg} ->
                    {ErrReason, <<ErrMsg/binary, Path2/binary>>};
                false ->
                    {to_bin(Error), <<Msg/binary, Path2/binary>>}
            end;
        {resolver_crash, ErrReason} ->
            ?LLOG(warning, "resolver crash: ~p", [ErrReason]),
            {<<"internal_error">>, <<Msg/binary, Path2/binary>>};
        {unknown_argument, Arg} ->
            {<<"unknown_argument">>, <<"Unknown argument '", Arg/binary, "'", Path2/binary>>};
        {operation_not_found, _} ->
            {<<"operation_not_found">>, <<Msg/binary, Path2/binary>>};
        {excess_fields_in_object, Map} ->
            {<<"excess_fields_in_object">>, nklib_json:encode(Map)};
        ErrReason when is_atom(ErrReason) ->
            % Happens for unknown_field, ...
            {to_bin(ErrReason), <<Msg/binary, Path2/binary>>};
        Other ->
            lager:error("NKLOG Unexpected GRAPHQL Error ~p", [Key]),
            {Other, <<Msg/binary, Path2/binary>>}
    end;

do_make_error(SrvId, {resolver_error, Error}) ->
    case nkservice_msg:is_msg(SrvId, Error) of
        {true, ErrReason, ErrMsg} ->
            {ErrReason, ErrMsg};
        false ->
            {to_bin(Error), <<>>}
    end;

do_make_error(_SrvId, {parser_error, {Line, graphql_parser, Pos}}) ->
    {<<"parser_error">>, list_to_binary([to_bin(Line), <<": ">>, Pos])};

do_make_error(_SrvId, Error) ->
    lager:error("NKLOG Unexpected GRAPHQL Error2 ~p", [Error]),
    {to_bin(Error), <<>>}.



%% @private
to_bin(T) when is_binary(T)-> T;
to_bin(T) -> nklib_util:to_binary(T).