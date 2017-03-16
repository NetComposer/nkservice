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

-module(nkservice_syntax).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([app_syntax/0, app_defaults/0, syntax/0]).
-export([parse_fun_listen/3]).

-include_lib("nklib/include/nklib.hrl").
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
        debug => fun parse_debug/1,
        log_level => log_level     %% TO REMOVE
    }.



%% @private Useful for nklib_config:parse_config/2
%% @TODO: anybody is using this?
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
parse_debug(Term) when is_list(Term) ->
    do_parse_debug(Term, []);

parse_debug(Term) ->
    parse_debug([Term]).


%% @private
do_parse_debug([], Acc) ->
    {ok, Acc};

do_parse_debug([{Mod, Data}|Rest], Acc) ->
    Mod2 = nklib_util:to_atom(Mod),
    do_parse_debug(Rest, [{Mod2, Data}|Acc]);


    % case code:ensure_loaded(Mod2) of
    %     {module, Mod2} ->
    %         do_parse_debug(Rest, [{Mod, Data}|Acc]);
    %     _ ->
    %         lager:warning("Module ~p could not be loaded", [Mod2]),
    %         error
    % end;

do_parse_debug([Mod|Rest], Acc) ->
    do_parse_debug([{Mod, []}|Rest], Acc).

