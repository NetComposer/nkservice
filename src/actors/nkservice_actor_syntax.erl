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

%% @doc Actor Syntax
-module(nkservice_actor_syntax).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([parse/1, parse/2]).
-export([syntax/0, meta_syntax/0]).
-export([syntax_parse_fun/2]).

-include("nkservice_actor.hrl").


%% ===================================================================
%% Syntax
%% ===================================================================

%% @doc
parse(ActorMap) ->
    parse(ActorMap, syntax()).


%% @doc
parse(ActorMap, Syntax) ->
    case nklib_syntax:parse(ActorMap, Syntax, #{}) of
        {ok, ActorMap2, []} ->
            #{
                domain := Domain,
                group := Group,
                vsn := Vsn,
                resource := Res,
                name := Name,
                data := Data,
                metadata := Meta
            } = ActorMap2,
            Actor = #actor{
                id = #actor_id{
                    uid = maps:get(uid, ActorMap2, undefined),
                    domain = Domain,
                    group = Group,
                    vsn = Vsn,
                    resource = Res,
                    name = Name
                },
                data = Data,
                metadata = Meta,
                hash = maps:get(hash, ActorMap2, undefined)
            },
            {ok, Actor};
        {ok, _, [Field|_]} ->
            {error, {field_unknown, Field}};
        {error, Error} ->
            {error, Error}
    end.


%% @private
syntax() ->
    #{
        uid => binary,
        domain => binary,
        group => binary,
        vsn => binary,
        resource => binary,
        name => binary,
        srv => atom,
        hash => binary,
        data => map,
        metadata => meta_syntax(),
        '__mandatory' => [domain, group, vsn, resource, name],
        '__defaults' => #{
            data => #{},
            metadata => #{}
        }
    }.


%% @private
meta_syntax() ->
    #{
        <<"uid">> => binary,
        <<"domain">> => binary,
        <<"name">> => binary,
        <<"subtype">> => binary,
        <<"generation">> => pos_integer,
        <<"creationTime">> => date_3339,
        <<"updateTime">> => date_3339,
        <<"isEnabled">> => boolean,
        <<"isActivated">> => boolean,
        <<"expiresTime">> => date_3339,
        <<"labels">> => fun ?MODULE:syntax_parse_fun/2,
        <<"annotations">> => fun ?MODULE:syntax_parse_fun/2,
        <<"links">> => fun ?MODULE:syntax_parse_fun/2,
        <<"fts">> => fun ?MODULE:syntax_parse_fun/2,
        <<"isInAlarm">> => boolean,
        <<"alarms">> => {list, binary},
        <<"nextStatusTime">> => date_3339,
        <<"description">> => binary,
        <<"createdBy">> => binary,
        <<"updatedBy">> => binary,
        <<"callbackUrl">> => binary
    }.


%% @private
syntax_parse_fun(_Key, Map) when is_map(Map) ->
    List = [{to_bin(K), to_bin(V)} || {K, V} <- maps:to_list(Map)],
    {ok, maps:from_list(List)};

syntax_parse_fun(_Key, _Val) ->
    error.


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).