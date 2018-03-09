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

-module(nkservice_syntax).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([parse/1]).
-export([syntax_modules/1, syntax_packages/1, syntax_duplicated_ids/1]).


-define(LLOG(Type, Txt, Args, Service),
    lager:Type("NkSERVICE '~s' "++Txt, [maps:get(id, Service) | Args])).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc
-spec parse(nkservice:spec()) ->
    nkservice:spec().

parse(Spec) ->
    case nklib_syntax:parse(Spec, syntax()) of
        {ok, Parsed, Unknown} ->
            case Unknown of
                [] ->
                    ok;
                _ ->
                    ?LLOG(warning, "Unknown keys in service: ~p",
                          [Unknown], Parsed)
            end,
            Parsed;
        {error, SyntaxError} ->
            throw(SyntaxError)
    end.



%% @private
syntax() ->
    #{
        id => atom,
        class => binary,
        name => binary,
        uuid => binary,
        plugins => {list, atom},
        packages => {list, #{
            id => binary,
            class => binary,
            config => map,
            remove => boolean,
            cache_map => map,                   % Type:term() => any()
            debug_map => map,                   % Type:term() => any()
            module_id => binary,
            module_class => {atom, [luerl]},
            '__defaults' => #{config=>#{}},
            '__post_check' => fun ?MODULE:syntax_packages/1
        }},
        modules => {list, #{
            id => binary,
            class => {atom, [luerl]},
            packages => {list, binary},     % Allowed packages
            file => binary,
            url => binary,
            code => binary,
            max_instances => {integer, 1, 1000000},
            debug => boolean,
            cache_map => map,                   % Type:term() => any()
            debug_map => [boolean,map],         % Type:term() => any()
            remove => boolean,
            reload => boolean,
            '__mandatory' => [id, class],
            '__defaults' => #{packages=>[<<"any">>], max_instances=>100},
            '__post_check' => fun ?MODULE:syntax_modules/1
        }},
        secret => {list, #{
            class => [raw_atom, binary],
            id => binary,
            key => binary,
            value => any,
            remove => boolean,
            '__mandatory' => [key, value],
            '__defaults' => #{class=><<>>, id=><<>>}
        }},
        debug_actors => {list, binary},
        meta => map,
        '__post_check' => fun ?MODULE:syntax_duplicated_ids/1
    }.


%% @private
syntax_modules(List) ->
    #{id:=Id, class:=Class} = Map = maps:from_list(List),
    case Class of
        luerl ->
            case maps:size(maps:with([code, file, url], Map)) of
                0 ->
                    case maps:get(remove, Map, false) of
                        true ->
                            ok;
                        false ->
                            % We must provide one of code, file or url
                            {error, {missing_field, nklib_util:bjoin([Id, url], <<".">>)}}
                    end;
                _ ->
                    ok
            end;
        _ ->
            {error, {invalid_class, nklib_util:bjoin([Id, class], <<".">>)}}
    end.


%% @private
syntax_packages(List) ->
    case maps:from_list(List) of
        #{id:=_, class:=_} ->
            ok;
        #{class:=Class} ->
            {ok, [{id, Class}|List]};
        #{id:=_} ->
            % We will extract the class later, if possible
            ok;
        _ ->
            {error, {missing_field, <<"class">>}}
    end.


%% @private
syntax_duplicated_ids([]) ->
    ok;

syntax_duplicated_ids([{Key, List}|Rest]) when Key==packages; Key==modules ->
    case nklib_util:find_duplicated([Id || #{id:=Id} <- List]) of
        [] ->
            syntax_duplicated_ids(Rest);
        [First|_] ->
            {error, {duplicated_id, nklib_util:bjoin([Key, "id", First], <<".">>)}}
    end;

syntax_duplicated_ids([_|Rest]) ->
    syntax_duplicated_ids(Rest).


