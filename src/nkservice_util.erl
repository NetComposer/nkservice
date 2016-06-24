%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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

-export([parse_syntax/3, parse_transports/1]).
-export([get_core_listeners/2, make_id/1, update_uuid/2]).

-include_lib("nkpacket/include/nkpacket.hrl").


-define(API_TIMEOUT, 30).



%% ===================================================================
%% Public
%% ===================================================================


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
    Web1 = maps:get(web_server, Config, []),
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
    Web2 = [{Conns, maps:merge(ConnOpts, WebOpts2)} || {Conns, ConnOpts} <- Web1],
    Api1 = maps:get(api_server, Config, []),
    ApiTimeout = maps:get(api_server_timeout, Config, ?API_TIMEOUT),
    ApiOpts = #{
        class => {nkservice_api_server, SrvId},
        get_headers => [<<"user-agent">>],
        idle_timeout => 1000 * ApiTimeout
    },
    Api2 = [{Conns, maps:merge(ConnOpts, ApiOpts)} || {Conns, ConnOpts} <- Api1],
    Web2 ++ Api2.


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



