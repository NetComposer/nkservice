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


%% @doc Basic Actor utilities
-module(nkservice_actor_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-include("nkservice.hrl").
-include("nkservice_actor.hrl").
-include("nkservice_actor_debug.hrl").
-include_lib("nkevent/include/nkevent.hrl").

-export([make/2, update/2, update_meta/4, check_links/1]).
-export([is_path/1, actor_id_to_path/1, actor_to_actor_id/1]).
-export([make_reversed_srv_id/1, gen_srv_id/1]).
-export([make_plural/1, normalized_name/1]).

%% ===================================================================
%% Public
%% ===================================================================

%% @doc Creates a new actor
make(Actor, _Opts) ->
    Syntax1 = nkservice_actor_syntax:syntax(),
    Syntax2 = Syntax1#{
        '__mandatory' := [srv, class, type, vsn]
    },
    case nklib_syntax:parse(Actor, Syntax2, #{}) of
        {ok, Actor2, []} ->
            #{type:=Type, spec:=Spec, metadata:=Meta1} = Actor2,
            %% Add UID if not present
            UID = case maps:find(uid, Actor2) of
                {ok, UID0} ->
                    UID0;
                error ->
                    make_uid(Type)
            end,
            %% Add Name if not present
            Name = case maps:find(name, Actor2) of
                {ok, Name0} ->
                    normalized_name(Name0);
                error ->
                    make_name(UID)
            end,
            {ok, Time} = nklib_date:to_3339(nklib_date:epoch(msecs)),
            Meta2 = Meta1#{<<"creationTime">> => Time},
            Meta3 = update_meta(Name, Spec, Meta2, Time),
            case check_links(Meta3) of
                {ok, Meta4} ->
                    Actor3 = Actor2#{
                        uid => UID,
                        name => Name,
                        metadata := Meta4
                    },
                    {ok, Actor3};
                {error, Error} ->
                    {error, Error}
            end;
        {ok, _, [Field|_]} ->
            {error, {field_unknown, Field}};
        {error, Error} ->
            {error, Error}
    end.


%% @doc
update(Actor, _Opts) ->
    Syntax = nkservice_actor_syntax:syntax(),
    case nklib_syntax:parse(Actor, Syntax, #{}) of
        {ok, Actor2, []} ->
            Id = case Actor2 of
                #{uid:=UID} ->
                    UID;
                _ ->
                    nkservice_actor_util:actor_to_actor_id(Actor2)
            end,
            % nkservice_actor_srv will call update_meta/4
            case nkservice_actor:update(Id, Actor2) of
                ok ->
                    {ok, Id};
                {error, Error} ->
                    {error, Error}
            end;
        {ok, _, [Field|_]} ->
            {error, {field_unknown, Field}};
        {error, Error} ->
            {error, Error}
    end.


%% @private
update_meta(Name, Spec, Meta, Time3339) ->
    Gen = maps:get(<<"generation">>, Meta, -1),
    Vsn = erlang:phash2({Name, Spec, Meta}),
    Meta#{
        <<"updateTime">> => Time3339,
        <<"generation">> => Gen+1,
        <<"resourceVersion">> => to_bin(Vsn)
    }.


%% @private
check_links(#{<<"links">>:=Links}=Meta) ->
    case do_check_links(maps:to_list(Links), []) of
        {ok, Links2} ->
            {ok, Meta#{<<"links">>:=Links2}};
        {error, Error} ->
            {error, Error}
    end;

check_links(Meta) ->
    {ok, Meta}.


%% @private
do_check_links([], Acc) ->
    {ok, maps:from_list(Acc)};

do_check_links([{Type, Id}|Rest], Acc) ->
    case nkservice_actor_db:find(Id) of
        {ok, #actor_id{uid=UID}, _} ->
            true = is_binary(UID),
            do_check_links(Rest, [{Type, UID}|Acc]);
        {error, actor_not_found} ->
            {error, linked_actor_unknown};
        {error, Error} ->
            {error, Error}
    end.


%% @doc Checks if ID is a path or #actor_id{}
is_path(Path) ->
    case to_bin(Path) of
        <<$/, Path2/binary>> ->
            case binary:split(Path2, <<$/>>, [global]) of
                [SrvId, Class, Type, Name] ->
                    ActorId = #actor_id{
                        srv = gen_srv_id(SrvId),
                        class = Class,
                        type = Type,
                        name = Name,
                        uid = undefined,
                        pid = undefined
                    },
                    {true, ActorId};
                _ ->
                    false
            end;
        _ ->
            false
    end.


%% @doc
actor_id_to_path(#actor_id{srv=SrvId, class=Class, type=Type, name=Name}) ->
    list_to_binary([$/, to_bin(SrvId), $/, Class, $/, Type, $/, Name]).


%% @doc
actor_to_actor_id(Actor) ->
    #{
        srv := SrvId,
        class := Class,
        type := Type,
        name := Name,
        uid := UID
    } = Actor,
    #actor_id{
        srv=SrvId,
        class=Class,
        type=Type,
        name=Name,
        uid=UID
    }.


%% @private
%% Will make an atom from a binary defining a service
%% If the atom does not exist yet, and a default db service is defined,
%% it is called to allow the generation of the atom
gen_srv_id(BinSrvId) when is_binary(BinSrvId) ->
    case catch binary_to_existing_atom(BinSrvId, utf8) of
        {'EXIT', _} ->
            case nkservice_app:get_db_default_service() of
                undefined ->
                    lager:warning("Module ~s creating atom '~s'", [?MODULE, BinSrvId]),
                    binary_to_atom(BinSrvId, utf8);
                DefSrvId ->
                    case ?CALL_SRV(DefSrvId, nkservice_make_srv_id, [DefSrvId, BinSrvId]) of
                        {ok, SrvId} ->
                            SrvId;
                        {error, Error} ->
                            error(Error)

                    end
            end;
        ExistingAtom ->
            ExistingAtom
    end.


%% @private
make_reversed_srv_id(SrvId) ->
    Parts = lists:reverse(binary:split(to_bin(SrvId), <<$.>>, [global])),
    nklib_util:bjoin(Parts, $.).


%% @private
make_uid(Kind) ->
    UUID = nklib_util:luid(),<<(to_bin(Kind))/binary, $-, UUID/binary>>.


%% @private
make_name(Id) ->
    UUID = case binary:split(Id, <<"-">>) of
        [_, Rest] when byte_size(Rest) >= 7 ->
            Rest;
        [Rest] when byte_size(Rest) >= 7 ->
            Rest;
        _ ->
            nklib_util:luid()
    end,
    normalized_name(binary:part(UUID, 0, 7)).


%% @private
normalized_name(Name) ->
    nklib_parse:normalize(Name, #{space=>$_, allowed=>[$+, $-, $., $_]}).


%% @private
make_plural(Type) ->
    Type2 = to_bin(Type),
    Size = byte_size(Type2),
    case binary:at(Type2, Size-1) of
        $s ->
            <<Type2/binary, "es">>;
        $y ->
            <<Type2:(Size-1)/binary, "ies">>;
        _ ->
            <<Type2/binary, "s">>
    end.


%% @private
to_bin(T) when is_binary(T)-> T;
to_bin(T) -> nklib_util:to_binary(T).
