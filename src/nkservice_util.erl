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

-module(nkservice_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([http/3, http_upload/7, http_download/6]).
-export([call/2, call/3]).
-export([parse_syntax/3, parse_transports/1]).
-export([get_core_listeners/2, make_id/1, update_uuid/2]).
-export([error_code/2]).

-include_lib("nkpacket/include/nkpacket.hrl").


-define(API_TIMEOUT, 30).

-define(CONNECT_TIMEOUT, 5000).
-define(RECV_TIMEOUT, 3000).


%% ===================================================================
%% Public
%% ===================================================================


%% @private
http(Method, Url, Opts) ->
    Headers1 = maps:get(headers, Opts, []),
    {Headers2, Body2} = case Opts of
        #{body:=Body} when is_map(Body) ->
            {
                [{<<"Content-Type">>, <<"application/json">>}|Headers1],
                nklib_json:encode(Body)

            };
        #{body:=Body} ->
            {
                [{<<"Content-Type">>, <<"application/octet-stream">>}|Headers1],
                nklib_util:to_binary(Body)                
            };
        _ ->
            {[{<<"Content-Length">>, <<"0">>}|Headers1], <<>>}
    end,
    Headers3 = case Opts of
        #{user:=User, pass:=Pass} ->
            Auth = base64:encode(list_to_binary([User, ":", Pass])),
            [{<<"Authorization">>, <<"Basic ", Auth/binary>>}|Headers2];
        _ ->
            Headers2
    end,
    Ciphers = ssl:cipher_suites(),
    % Hackney fails with its default set of ciphers
    % See hackney.ssl#44
    HttpOpts = [
        {connect_timeout, ?CONNECT_TIMEOUT},
        {recv_timeout, ?RECV_TIMEOUT},
        insecure,
        with_body,
        {ssl_options, [{ciphers, Ciphers}]}
    ],
    Start = nklib_util:l_timestamp(),
    case hackney:request(Method, Url, Headers3, Body2, HttpOpts) of
        {ok, 200, Headers, RespBody} ->
            Time = nklib_util:l_timestamp() - Start,
            {ok, Headers, RespBody, Time div 1000};
        {ok, Code, Headers, RespBody} ->
            {error, {http_code, Code, Headers, RespBody}};
        {error, Error} ->
            {error, Error}
    end.


%% @doc
http_upload(Url, User, Pass, Class, ObjId, Name, Body) ->
    Id = nkservice_api_server_http:filename_encode(Class, ObjId, Name),
    <<"/", Base/binary>> = nklib_parse:path(Url),
    Url2 = list_to_binary([Base, "/upload/", Id]),
    Opts = #{
        user => nklib_util:to_binary(User),
        pass => nklib_util:to_binary(Pass),
        body => Body
    },
    http(post, Url2, Opts).


%% @doc
http_download(Url, User, Pass, Class, ObjId, Name) ->
    Id = nkservice_api_server_http:filename_encode(Class, ObjId, Name),
    <<"/", Base/binary>> = nklib_parse:path(Url),
    Url2 = list_to_binary([Base, "/download/", Id]),
    Opts = #{
        user => nklib_util:to_binary(User),
        pass => nklib_util:to_binary(Pass)
    },
    http(get, Url2, Opts).


%% @doc Safe call (no exceptions)
call(Dest, Msg) ->
    call(Dest, Msg, 5000).


%% @doc Safe call (no exceptions)
call(Dest, Msg, Timeout) ->
    case nklib_util:call(Dest, Msg, Timeout) of
        {error, {exit, {{timeout, _Fun}, _Stack}}} ->
            {error, timeout};
        {error, {exit, {{noproc, _Fun}, _Stack}}} ->
            {error, process_not_found};
        Other ->
            Other
    end.



parse_syntax(Spec, Syntax, Defaults) ->
    Opts = #{return=>map, defaults=>Defaults},
    case nklib_config:parse_config(Spec, Syntax, Opts) of
        {ok, Parsed, Other} -> {ok, maps:merge(Other, Parsed)};
        {error, Error} -> {error, Error}
    end.


%% @private
parse_transports([{[{_, _, _, _}|_], Opts}|_]=Transps) when is_map(Opts) ->
    {ok, Transps};

parse_transports(Spec) ->
    case nkpacket:multi_resolve(Spec, #{resolve_type=>listen}) of
        {ok, List} ->
            {ok, List};
        _ ->
            error
    end.


%% @private
get_core_listeners(SrvId, Config) ->
    {multi, WebSrv} = maps:get(web_server, Config, {multi, []}),
    WebSrvs = get_web_servers(SrvId, WebSrv, Config),
    {multi, ApiSrv} = maps:get(api_server, Config, {multi, []}),
    ApiSrvs1 = get_api_webs(SrvId, ApiSrv, []),
    ApiSrvs2 = get_api_sockets(SrvId, ApiSrv, Config, []),
    WebSrvs ++ ApiSrvs1 ++ ApiSrvs2.


%% @doc Generates the service id from any name
-spec make_id(nkservice:name()) ->
    nkservice:id().

make_id(Name) ->
    list_to_atom(
        string:to_lower(
            case binary_to_list(nklib_util:hash36(Name)) of
                [F|Rest] when F>=$0, F=<$9 -> [$A+F-$0|Rest];
                Other -> Other
            end)).





%% @private
update_uuid(Id, Name) ->
    LogPath = nkservice_app:get(log_path),
    Path = filename:join(LogPath, atom_to_list(Id)++".uuid"),
    case read_uuid(Path) of
        {ok, UUID} ->
            ok;
        {error, Path} ->
            UUID = nklib_util:uuid_4122(),
            save_uuid(Path, Name, UUID)
    end,
    UUID.


%% @private
read_uuid(Path) ->
    case file:read_file(Path) of
        {ok, Binary} ->
            case binary:split(Binary, <<$,>>) of
                [UUID|_] when byte_size(UUID)==36 -> {ok, UUID};
                _ -> {error, Path}
            end;
        _ -> 
            {error, Path}
    end.


%% @private
save_uuid(Path, Name, UUID) ->
    Content = [UUID, $,, nklib_util:to_binary(Name)],
    case file:write_file(Path, Content) of
        ok ->
            ok;
        Error ->
            lager:warning("Could not write file ~s: ~p", [Path, Error]),
            ok
    end.


%% @private
-spec error_code(nkservice:id(), nkservice:error()) ->
    {integer(), binary()}.

error_code(SrvId, Error) ->
    case SrvId:error_code(Error) of
        {Code, Text} when is_binary(Text) ->
            {Code, Text};
        {Code, Text} when is_list(Text) ->
            {Code, list_to_binary(Text)};
        {Code, Fmt, List} ->
            case catch io_lib:format(nklib_util:to_list(Fmt), List) of
                {'EXIT', _} ->
                    {0, <<"Invalid format: ", (nklib_util:to_binary(Fmt))/binary>>};
                Val ->
                    {Code, list_to_binary(Val)}
            end
    end.












%% ===================================================================
%% internal
%% ===================================================================



%% @private
get_web_servers(SrvId, List, Config) ->
    WebPath = case Config of
        #{web_server_path:=UserPath} -> 
            UserPath;
        _ ->
            Priv = list_to_binary(code:priv_dir(nkservice)),
            <<Priv/binary, "/www">>
    end,
    WebOpts2 = #{
        class => {nkservice_web_server, SrvId},
        http_proto => {static, #{path=>WebPath, index_file=><<"index.html">>}}
    },
    [{Conns, maps:merge(ConnOpts, WebOpts2)} || {Conns, ConnOpts} <- List].



%% @private
get_api_webs(_SrvId, [], Acc) ->
    Acc;

get_api_webs(SrvId, [{List, Opts}|Rest], Acc) ->
    List2 = [
        {nkpacket_protocol_http, Proto, Ip, Port}
        ||
        {nkservice_api_server, Proto, Ip, Port} <- List, 
        Proto==http orelse Proto==https
    ],
    Path = nklib_util:to_list(maps:get(path, Opts, <<"/rpc">>)),
    CowPath = Path ++ "/[...]",
    Routes = [{'_', [{CowPath, nkservice_api_server_http, [{srv_id, SrvId}]}]}],
    Opts2 = #{
        class => {nkservice_api_server, SrvId},
        http_proto => {dispatch, #{routes => Routes}}
    },
    get_api_webs(SrvId, Rest, [{List2, Opts2}|Acc]).


%% @private
get_api_sockets(_SrvId,[], _Config, Acc) ->
    Acc;

get_api_sockets(SrvId, [{List, Opts}|Rest], Config, Acc) ->
    List2 = [
        {nkservice_api_server, Proto, Ip, Port}
        ||
        {nkservice_api_server, Proto, Ip, Port} <- List, 
        Proto==ws orelse Proto==wss orelse Proto==tcp orelse Proto==tls
    ],
    Timeout = maps:get(api_server_tiemout, Config, 180),
    Opts2 = #{
        class => {nkservice_api_server, SrvId},
        get_headers => [<<"user-agent">>],
        idle_timeout => 1000 * Timeout
    },
    get_api_sockets(SrvId, Rest, Config, [{List2, maps:merge(Opts, Opts2)}|Acc]).






