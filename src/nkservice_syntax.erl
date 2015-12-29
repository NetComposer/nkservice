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

-export([app_syntax/0, app_defaults/0, syntax/0, defaults/0]).
-export([packet_keys/0]).

-include_lib("nkpacket/include/nkpacket.hrl").
  

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
        packet_idle_timeout => pos_integer,
        packet_connect_timeout => nat_integer,
        packet_sctp_out_streams => nat_integer,
        packet_sctp_in_streams => nat_integer,
        packet_no_dns_cache => boolean,
        ?TLS_SYNTAX
    }.



%% @private
defaults() ->    
    #{
        log_level => notice,
        plugins => []
    }.


packet_keys() ->
    lists:filter(
        fun(Key) ->
            case atom_to_binary(Key, latin1) of 
                <<"packet_", _/binary>> -> true;
                <<"tls_", _/binary>> -> true;
                _ -> false
            end
        end,
        maps:keys(syntax())).


% packet_keys() ->
%     lists:filtermap(
%         fun(Key) ->
%             case atom_to_binary(Key, latin1) of 
%                 <<"packet_", Rest/binary>> -> {true, binary_to_atom(Rest, latin1)};
%                 <<"tls_", _/binary>> -> true;
%                 _ -> false
%             end
%         end,
%         maps:keys(syntax())).




