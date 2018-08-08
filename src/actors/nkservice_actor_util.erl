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

-export([check_create_fields/1, update_meta/4, check_links/1]).
-export([is_path/1, actor_id_to_path/1]).
-export([make_reversed_srv_id/1, gen_srv_id/1]).
-export([make_plural/1, normalized_name/1]).
-export([fts_normalize_word/1, fts_normalize_multi/1]).

%% ===================================================================
%% Public
%% ===================================================================


%% @doc Prepares an actor for creation
%% - uuid is added
%% - name is added (if not present)
%% - metas creationTime, updateTime, generation and resourceVersion are added
%% - links are checked to exist
check_create_fields(#actor{id=#actor_id{uid=UID}}) when UID /= undefined ->
    {error, uid_not_allowed};

check_create_fields(Actor) ->
    #actor{id=ActorId, data=Data, metadata=Meta1} = Actor,
    #actor_id{type=Type, name=Name1} = ActorId,
    UID = make_uid(Type),
    %% Add Name if not present
    Name2 = case normalized_name(Name1) of
        <<>> ->
            make_name(UID);
        NormName ->
            NormName
    end,
    {ok, Time} = nklib_date:to_3339(nklib_date:epoch(msecs)),
    Meta2 = Meta1#{<<"creationTime">> => Time},
    Meta3 = update_meta(Name2, Data, Meta2, Time),
    case check_links(Meta3) of
        {ok, Meta4} ->
            Actor2 = Actor#actor{
                id = ActorId#actor_id{uid = UID, name = Name2},
                metadata = Meta4
            },
            {ok, Actor2};
        {error, Error} ->
            {error, Error}
    end.


%% @private
update_meta(Name, Data, Meta, Time3339) ->
    Gen = maps:get(<<"generation">>, Meta, -1),
    Vsn = erlang:phash2({Name, Data, Meta}),
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


%% @private
%% Will make an atom from a binary defining a service
%% If the atom does not exist yet, and a default db service is defined,
%% it is called to allow the generation of the atom
gen_srv_id(BinSrvId) when is_binary(BinSrvId) ->
    case catch binary_to_existing_atom(BinSrvId, utf8) of
        {'EXIT', _} ->
            case nkservice_app:get_db_default_service() of
                undefined ->
                    nklib_util:make_atom(?MODULE, BinSrvId);
                DefSrvId ->
                    case ?CALL_SRV(DefSrvId, nkservice_make_srv_id, [DefSrvId, BinSrvId]) of
                        {ok, SrvId} ->
                            SrvId;
                        {error, Error} ->
                            error(Error)

                    end
            end;
        SrvId ->
            SrvId
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
fts_normalize_word(Word) ->
    nklib_parse:normalize(Word, #{unrecognized=>keep}).


%% @doc
fts_normalize_multi(Text) ->
    nklib_parse:normalize_words(Text, #{unrecognized=>keep}).


%% @private
to_bin(T) when is_binary(T)-> T;
to_bin(T) -> nklib_util:to_binary(T).
