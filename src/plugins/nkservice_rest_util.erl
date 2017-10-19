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

%% @doc Default callbacks
-module(nkservice_rest_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([parse_rest_url/1, make_listen/2, parse_rest_server/1, get_rest_http/3, get_rest_ws/3]).

-include_lib("nklib/include/nklib.hrl").


%% ===================================================================
%% Util
%% ===================================================================


%% @private
parse_rest_url({?MODULE, urls, Multi}) ->
    {ok, {?MODULE, urls, Multi}};

parse_rest_url(Url) ->
    case nkpacket:multi_resolve(Url, #{resolve_type=>listen, protocol=>nkservice_rest_protocol}) of
        {ok, Multi} ->
            {ok, {?MODULE, urls, Multi}};
        {error, Error} ->
            {error, Error}
    end.


%% @doc
make_listen(SrvId, Endpoints) ->
    make_listen(SrvId, Endpoints, #{}).


%% @private
make_listen(_SrvId, [], Acc) ->
    Acc;
make_listen(SrvId, [#{id:=Id, url:={?MODULE, urls, Multi}}=Entry|Rest], Acc) ->
     Transps = make_listen_transps(SrvId, Id, Multi, maps:get(opts, Entry, #{}), []),
    make_listen(SrvId, Rest, Acc#{Id => Transps}).


%% @private
make_listen_transps(_SrvId, _Id, [], _Opts, Acc) ->
    lists:reverse(Acc);

make_listen_transps(SrvId, Id, [{Transps, TranspOpts}|Rest], Opts, Acc) ->
    Opts2 = maps:merge(TranspOpts, Opts),
    Acc2 = lists:foldl(
        fun({nkservice_rest_protocol, Proto, Ip, Port}, Acc0) ->
            Opts3 = if
                Proto==http; Proto==https ->
                    Path1 = nklib_util:to_list(maps:get(path, Opts2, <<>>)),
                    Path2 = case lists:reverse(Path1) of
                        [$/|R] -> lists:reverse(R);
                        _ -> Path1
                    end,
                    CowPath = Path2 ++ "/[...]",
                    CowInit = [{srv_id, SrvId}, {id, Id}],
                    Routes = [{'_', [{CowPath, nkservice_rest_http, CowInit}]}],
                    Opts2#{
                        class => {nkservice_rest_http, SrvId, Id},
                        http_proto => {dispatch, #{routes => Routes}},
                        path => nklib_util:to_binary(Path1)
                    };
                Proto==ws; Proto==wss ->
                    Opts2#{
                        path => maps:get(path, Opts, <<"/">>),
                        class => {nkservice_rest, SrvId, Id},
                        get_headers => [<<"user-agent">>]
                    }
            end,
            [{[{nkpacket_protocol_http, Proto, Ip, Port}], Opts3}|Acc0]
        end,
        Acc,
        Transps),
    make_listen_transps(SrvId, Id, Rest, Opts, Acc2).





%% @private
parse_rest_server({parsed_urls, Multi}) ->
    {ok, {parsed_urls, Multi}};

parse_rest_server(Url) ->
    case nklib_parse:uris(Url) of
        error ->
            error;
        List ->
            case do_parse_rest(List, []) of
                error ->
                    error;
                List2 ->
                    case nkpacket:multi_resolve(List2, #{resolve_type=>listen}) of
                        {ok, List3} ->
                            {ok, {parsed_urls, List3}};
                        _ ->
                            error
                    end
            end
    end.



%% @private
do_parse_rest([], Acc) ->
    lists:reverse(Acc);

do_parse_rest([#uri{scheme=nkservice_rest}=Uri|Rest], Acc) ->
    do_parse_rest(Rest, [Uri|Acc]);

do_parse_rest([#uri{scheme=Sc, ext_opts=Opts}=Uri|Rest], Acc)
        when Sc==http; Sc==https; Sc==ws; Sc==wss  ->
    Uri2 = Uri#uri{scheme=nkservice_rest, opts=[{<<"transport">>, Sc}|Opts]},
    do_parse_rest(Rest, [Uri2|Acc]);

do_parse_rest(_D, _Acc) ->
    error.



%% @private
get_rest_http(SrvId, ApiSrv, Config) ->
    get_rest_http(SrvId, ApiSrv, Config, []).


%% @private
get_rest_http(_SrvId, [], _Config, Acc) ->
    Acc;

get_rest_http(SrvId, [{List, Opts}|Rest], Config, Acc) ->
    List2 = [
        {nkpacket_protocol_http, Proto, Ip, Port}
        ||  {nkservice_rest_protocol, Proto, Ip, Port} <- List, Proto==http orelse Proto==https
    ],
    Acc2 = case List2 of
        [] ->
            Acc;
        _ ->
            Path1 = nklib_util:to_list(maps:get(path, Opts, <<>>)),
            Path2 = case lists:reverse(Path1) of
                [$/|R] -> lists:reverse(R);
                _ -> Path1
            end,
            CowPath = Path2 ++ "/[...]",
            CowInit = [{srv_id, SrvId}],
            Routes = [{'_', [{CowPath, nkservice_rest_http, CowInit}]}],
            NetOpts = nkpacket_util:get_plugin_net_opts(Config),
            PacketDebug = case Config of
                #{debug:=DebugList} when is_list(DebugList) ->
                    lists:member(nkpacket, DebugList);
                _ ->
                    false
            end,
            Opts2 = NetOpts#{
                class => {nkservice_rest_http, SrvId},
                http_proto => {dispatch, #{routes => Routes}},
                path => nklib_util:to_binary(Path1),
                debug => PacketDebug
            },
            [{List2, Opts2}|Acc]
    end,
    get_rest_http(SrvId, Rest, Config, Acc2).



%% @private
get_rest_ws(SrvId, ApiSrv, Config) ->
    get_rest_ws(SrvId, ApiSrv, Config, []).


%% @private
get_rest_ws(_SrvId, [], _Config, Acc) ->
    Acc;

get_rest_ws(SrvId, [{List, Opts}|Rest], Config, Acc) ->
    List2 = [
        {nkservice_rest_protocol, Proto, Ip, Port}
        || {nkservice_rest_protocol, Proto, Ip, Port}
            <- List, Proto==ws orelse Proto==wss orelse Proto==tcp orelse Proto==tls
    ],
    Acc2 = case List2 of
        [] ->
            Acc;
        _ ->
            Timeout = maps:get(rest_server_timeout, Config, 180),
            NetOpts = nkpacket_util:get_plugin_net_opts(Config),
            PacketDebug = case Config of
                #{debug:=DebugList} when is_list(DebugList) ->
                    lists:member(nkpacket, DebugList);
                _ ->
                    false
            end,
            Opts2 = NetOpts#{
                path => maps:get(path, Opts, <<"/">>),
                class => {nkservice_rest, SrvId},
                get_headers => [<<"user-agent">>],
                idle_timeout => 1000 * Timeout,
                debug => PacketDebug
            },
            [{List2, maps:merge(Opts, Opts2)}|Acc]
    end,
    get_rest_ws(SrvId, Rest, Config, Acc2).
