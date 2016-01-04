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

-module(nkservice_syntax).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([app_syntax/0, app_defaults/0, syntax/0]).
-export([parse_fun_listen/3, get_config/1]).

-include_lib("nkpacket/include/nkpacket.hrl").
-include("nkservice.hrl").
  

%% @private
app_syntax() ->
    #{
        log_path => binary
    }.



%% @private
app_defaults() ->    
    #{
        log_path => <<"log">>
    }.



%% @private
syntax() ->
    #{
        class => any,
        plugins => {list, atom},
        callback => atom,
        log_level => log_level,

        service_idle_timeout => pos_integer,
        service_connect_timeout => nat_integer,
        service_sctp_out_streams => nat_integer,
        service_sctp_in_streams => nat_integer,
        service_no_dns_cache => boolean,

        ?TLS_SYNTAX
    }.



%% @private Useful for nklib_config:parse_config/2
parse_fun_listen(_Key, [{[{_, _, _, _}|_], Opts}|_]=Multi, _Ctx) when is_map(Opts) ->
    {ok, Multi};

parse_fun_listen(_Key, Multi, _Ctx) ->
    case nkpacket:multi_resolve(Multi, #{resolve_type=>listen}) of
        {ok, List} ->
            {ok, List};
        _ ->
            error
    end.



%% @private
get_config(Spec) ->
    Keys = lists:filter(
        fun(Key) ->
            case atom_to_binary(Key, latin1) of 
                <<"service_", _/binary>> -> true;
                <<"tls_", _/binary>> -> true;
                _ -> false
            end
        end,
        maps:keys(syntax())),
    Net1 = maps:with(Keys, Spec),
    Net2 = lists:map(
        fun({Key, Val}) ->
            case atom_to_binary(Key, latin1) of 
                <<"service_", Rest/binary>> -> {binary_to_atom(Rest, latin1), Val};
                _ -> {Key, Val}
            end
        end,
        maps:to_list(Net1)),
    #{net_opts=>Net2}.

