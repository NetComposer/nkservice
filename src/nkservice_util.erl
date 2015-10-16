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

-export([parse_syntax/1, parse_syntax/2, parse_syntax/3]).
-export([defaults/0, syntax/0]).
-export([safe_call/3]).




%% ===================================================================
%% Public
%% ===================================================================




%% @private
-spec parse_syntax(map()|list()) ->
    {ok, map()} | {error, term()}.

parse_syntax(Data) ->
    parse_syntax(Data, syntax(), defaults()).


%% @private
-spec parse_syntax(map()|list(), map()|list()) ->
    {ok, map()} | {error, term()}.

parse_syntax(Data, Syntax) ->
    parse_syntax(Data, Syntax, []).


%% @private
-spec parse_syntax(map()|list(), map()|list(), map()|list()) ->
    {ok, map()} | {error, term()}.

parse_syntax(Data, Syntax, Defaults) ->
    ParseOpts = #{return=>map, defaults=>Defaults},
    case nklib_config:parse_config(Data, Syntax, ParseOpts) of
        {ok, Parsed, Other} ->
            {ok, maps:merge(Other, Parsed)};
        {error, Error} ->
            {error, Error}
    end.



%% @private
-spec safe_call(module(), atom(), list()) ->
    term() | not_exported | error.

safe_call(Module, Fun, Args) ->
    try
        case erlang:function_exported(Module, Fun, length(Args)) of
            false ->
                not_exported;
            true ->
                apply(Module, Fun, Args)
        end
    catch
        C:E ->
            Trace = erlang:get_stacktrace(),
            lager:warning("Exception calling ~p:~p: ~p:~p\n~p",
                          [Module, Fun, C, E, Trace]),
            error
    end.



syntax() ->
    #{
        id => atom,
        name => any,
        class => atom,
        plugins => {list, atom},
        callback => atom,
        log_level => log_level,
        transports => fun parse_transports/3,
        packet_udp_timeout => {integer, 5, none},
        packet_tcp_timeout => {integer, 5, none},
        packet_sctp_timeout => {integer, 5, none},
        packet_ws_timeout => {integer, 5, none},
        packet_max_connections => {integer, 1, 1000000},
        packet_certfile => path,
        packet_keyfile => path,
        packet_local_host => [{enum, [auto]}, host],
        packet_local_host6 => [{enum, [auto]}, host6]
    }.


defaults() ->
    #{
        log_level => notice,
        packet_udp_timeout => 30,                  % (secs) 30 secs
        packet_tcp_timeout => 180,                 % (secs) 3 min
        packet_sctp_timeout => 180,                % (secs) 3 min
        packet_ws_timeout => 180,                  % (secs) 3 min
        packet_max_connections => 1024,            % Per transport and Service
        packet_local_host => auto,
        packet_local_host6 => auto
    }.


%% @private
parse_transports(_, Spec, _) when is_list(Spec); is_map(Spec) ->
    try
        do_parse_transports(nklib_util:to_list(Spec), #{})
    catch
        throw:Throw -> {error, Throw}
    end;

parse_transports(_, _List, _) ->
    error.


%% @private
do_parse_transports([], Map) ->
    {ok, Map};

do_parse_transports([Transport|Rest], Map) ->
    case Transport of
        {{Proto, Ip, Port}, Opts}  when is_list(Opts); is_map(Opts) -> ok;
        {Proto, Ip, Port, Opts} when is_list(Opts); is_map(Opts) -> ok;
        {Proto, Ip, Port} -> Opts = #{};
        {Proto, Ip} -> Port = any, Opts = #{};
        Proto -> Ip = all, Port = any, Opts = #{}
    end,
    case 
        (Proto==udp orelse Proto==tcp orelse 
         Proto==tls orelse Proto==sctp orelse
         Proto==ws  orelse Proto==wss)
    of
        true -> ok;
        false -> throw({invalid_transport, Transport})
    end,
    Ip1 = case Ip of
        all ->
            {0,0,0,0};
        all6 ->
            {0,0,0,0,0,0,0,0};
        _ when is_tuple(Ip) ->
            case catch inet_parse:ntoa(Ip) of
                {error, _} -> throw({invalid_transport, Transport});
                {'EXIT', _} -> throw({invalid_transport, Transport});
                _ -> Ip
            end;
        _ ->
            case catch nklib_util:to_ip(Ip) of
                {ok, PIp} -> PIp;
                _ -> throw({invalid_transport, Transport})
            end
    end,
    Port1 = case Port of
        any -> 0;
        _ when is_integer(Port), Port >= 0 -> Port;
        _ -> throw({invalid_transport, Transport})
    end,
    Opts1 = nklib_util:to_map(Opts),
    do_parse_transports(Rest, maps:put({Proto, Ip1, Port1}, Opts1, Map)).






% %% @private
% -spec update_spec(#{spec=>map(), cache=>map(), transports=>map()},
%                  nkservice:spec()) ->
%     nkservice:spec().

% update_spec(Update, ServiceSpec) when is_map(Update), is_map(ServiceSpec) ->
%     OldCache = maps:get(cache, ServiceSpec, #{}),
%     NewCache = case Update of
%         #{cache:=Cache} when is_map(Cache) ->
%             maps:merge(OldCache, Cache);
%         _ ->
%             OldCache
%     end,
%     OldTransports = maps:get(transports, ServiceSpec, #{}),
%     NewTransports = case Update of
%         #{transports:=Transports} when is_map(Transports) ->
%             maps:merge(OldTransports, Transports);
%         _ ->
%             OldTransports
%     end,
%     ServiceSpec1 = case Update of
%         #{spec:=Config} when is_map(Config) ->
%             maps:merge(ServiceSpec, Config);
%         _ ->
%             ServiceSpec
%     end,
%     ServiceSpec1#{
%         cache => NewCache, 
%         transports => NewTransports
%     }.

    

% %% @private
% -spec remove_spec(#{spec=>[term()], cache=>[term()], transports=>[term()]},
%                  nkservice:spec()) ->
%     nkservice:spec().

% remove_spec(Update, ServiceSpec) when is_map(Update), is_map(ServiceSpec) ->
%     lager:warning("REM: ~p", [Update]),
%     io:format("S: ~p\n", [ServiceSpec]),

%     OldCache = maps:get(cache, ServiceSpec, #{}),
%     NewCache = case Update of
%         #{cache:=Cache} when is_list(Cache) ->
%             maps:without(Cache, OldCache);
%         _ ->
%             OldCache
%     end,
%     OldTransports = maps:get(transports, ServiceSpec, #{}),
%     NewTransports = case Update of
%         #{transports:=Transports} when is_list(Transports) ->
%             maps:without(Transports, OldTransports);
%         _ ->
%             OldTransports
%     end,
%     ServiceSpec1 = ServiceSpec#{
%         cache => NewCache, 
%         transports => NewTransports
%     },
%     case Update of
%         #{spec:=Config} when is_list(Config) ->
%             maps:without(Config, ServiceSpec1);
%         _ ->
%             ServiceSpec1
%     end.