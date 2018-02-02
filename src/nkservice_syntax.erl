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
-export([syntax_scripts/1, syntax_callbacks/1, syntax_duplicated_ids/1]).


-define(LLOG(Type, Txt, Args, Service),
    lager:Type("NkSERVICE '~s' "++Txt, [maps:get(id, Service) | Args])).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc

-spec parse(nkservice:spec()) ->
    {ok, nkservice:spec()} | {error, term()}.

parse(Spec) ->
    case nklib_syntax:parse(Spec, syntax()) of
        {ok, Parsed, Unknown} ->
            case Unknown of
                [] ->
                    ok;
                _ ->
                    ?LLOG(warning, "Unknown keys starting service: ~p",
                        [Unknown], Parsed)
            end,
            {ok, Parsed};
        {error, SyntaxError} ->
            throw(SyntaxError)
    end.


%% @private
syntax() ->
    #{
        id => atom,
        class => binary,
        name => binary,
        plugins => {list, #{
            id => binary,
            class => atom,
            config => map,
            remove => boolean,
            '__mandatory' => [id, class],
            '__defaults' => #{config => #{}}
        }},
        log_level => log_level,
        debug => {list, #{
            key => atom,
            spec => any,
            '__mandatory' => [key],
            '__defaults' => #{spec => #{}}
        }},
        cache => {list, #{
            key => atom,
            value => any,
            remove => boolean
        }},
        scripts => {list, #{
            id => binary,
            class => {atom, [luerl, remove]},
            file => binary,
            url => binary,
            code => binary,
            remove => boolean,
            '__mandatory' => [id, class],
            '__post_check' => fun ?MODULE:syntax_scripts/1
        }},
        callbacks => {list, #{
            id => binary,
            class => {atom, [luerl, http, remove]},
            luerl_id => binary,
            url => binary,
            remove => boolean,
            '__mandatory' => [id, class],
            '__post_check' => fun ?MODULE:syntax_callbacks/1
        }},
        % For debug at nkpacket level, add debug=>true to opts (or in a url)
        % For debug at nkservice_rest level, add nkservice_rest to 'debug' config option in global service
        listen => {list, #{
            id => binary,
            url => fun nkservice_rest_plugin:parse_url/1,
            opts => nkpacket_syntax:safe_syntax(),
            remove => boolean,
            '__mandatory' => [url],
            '__defaults' => #{id => <<"main">>}
        }},
        meta => map,
        '__post_check' => fun ?MODULE:syntax_duplicated_ids/1
    }.


%% @private
syntax_scripts(List) ->
    Map = maps:from_list(List),
    case maps:get(class, Map) of
        luerl ->
            case maps:with([code, file, url], maps:from_list(List)) of
                [] ->
                    {error, {missing_field, url}};
                _ ->
                    ok
            end;
        remove ->
            ok
    end.


%% @private
syntax_callbacks(List) ->
    Map = maps:from_list(List),
    case maps:get(class, Map) of
        luerl ->
            case Map of
                #{luerl_id:=_} ->
                    ok;
                _ ->
                    {error, {missing_field, <<"luerl_id">>}}
            end;
        http ->
            case Map of
                #{url:=_} ->
                    ok;
                _ ->
                    {error, {missing_field, <<"url">>}}
            end;
        remove ->
            ok
    end.


%% @private
syntax_duplicated_ids([]) ->
    ok;

syntax_duplicated_ids([{Key, List}|Rest])
        when Key==plugins; Key==scripts; Key==callbacks ->
    case find_duplicated_ids(List) of
        ok ->
            syntax_duplicated_ids(Rest);
        error ->
            {error, {duplicated_field, nklib_util:bjoin([Key, "id"], <<".">>)}}
    end;

syntax_duplicated_ids([_|Rest]) ->
    syntax_duplicated_ids(Rest).

%% @private
find_duplicated_ids(List) ->
    Ids = [Id || #{id:=Id} <- List],
    case lists:usort(Ids) of
        Ids ->
            ok;
        _ ->
            error
    end.


