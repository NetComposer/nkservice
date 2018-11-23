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

%% @doc NkService registration facilties with cache
%%

-module(nkservice_actor_register).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([find_registered/1, find_cached/1]).
-export([get_all_registered/0]).


-include("nkservice.hrl").
-include_lib("nkservice/include/nkservice.hrl").
-include_lib("nkservice/include/nkservice_actor.hrl").
-include_lib("nkservice/include/nkservice_actor_debug.hrl").



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Checks if an actor is activated
%% - checks if it is in the local cache
%% - if not, asks the registration callback

-spec find_registered(nkservice_actor:id()) ->
    {true, #actor_id{}} | false.

find_registered(Id) ->
    case nkservice_actor_util:id_to_actor_id(Id) of
        {ok, SrvId, Id2} ->
            case find_cached(Id2) of
                {true, ActorId2} ->
                    {true, ActorId2};
                false ->
                    case ?CALL_SRV(SrvId, actor_find_registered, [SrvId, Id2]) of
                        {true, ActorId2} ->
                            #actor_id{
                                domain = Domain,
                                group = Group,
                                resource = Res,
                                name = Name,
                                uid = UID,
                                pid = Pid
                            } = ActorId2,
                            true = is_binary(UID) andalso UID /= <<>>,
                            true = is_pid(Pid),
                            nklib_proc:put({nkservice_actor, Domain, Group, Res, Name}, ActorId2, Pid),
                            nklib_proc:put({nkservice_actor_uid, UID}, ActorId2, Pid),
                            nklib_proc:put(nkservice_all_actors, UID, Pid),
                            {true, ActorId2};
                        false ->
                            false;
                        {error, Error} ->
                            ?ACTOR_LOG(warning, "error calling nkservice_find_actor for ~s: ~p", [Error]),
                            false
                    end
            end;
        {error, _} ->
            false
    end.


%% @private
find_cached(#actor_id{}=ActorId) ->
    #actor_id{domain=Domain, group=Group, resource=Res, name=Name} = ActorId,
    case nklib_proc:values({nkservice_actor, Domain, Group, Res, Name}) of
        [{ActorId2, _Pid}|_] ->
            {true, ActorId2};
        [] ->
            false
    end;

find_cached(UID) ->
    case nklib_proc:values({nkservice_actor_uid, to_bin(UID)}) of
        [{ActorId, _Pid}|_] ->
            {true, ActorId};
        [] ->
            false
    end.



%% @private
get_all_registered() ->
    nklib_proc:values(nkservice_all_actors).



%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).