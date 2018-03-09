%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Carlos Gonzalez Florido.  All Rights Reserved.
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


%% @doc Basic Obj utilities
-module(nkservice_actor_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-include("nkservice.hrl").
-include("nkservice_actor.hrl").
-include("nkservice_actor_debug.hrl").
-include_lib("nkevent/include/nkevent.hrl").


-export([load/1]).

%% ===================================================================
%% Public
%% ===================================================================


load(#actor_id{srv_id=SrvId}=ActorId) ->
    case ?CALL_SRV(SrvId, actor_find, [ActorId]) of
        {ok, Actor, StartOpts} ->
            nkservice_actor:start(SrvId, Actor, StartOpts);
        {error, Error} ->
            {error, Error}
    end.


%%%% @doc
%%obj_apply(Fun, Args, #obj_state{effective_srv_id=SrvId}) ->
%%    apply(SrvId, Fun, Args).
%%
%%
%%%% @private
%%obj_error(Error, #obj_state{effective_srv_id=SrvId}) ->
%%    nkservice_util:error(SrvId, Error).
%%
%%
%%
%%
%%%% @doc Event sending using specs
%%send_event({event, Type, State}) when is_atom(Type) ->
%%    send_event(Type, #{}, State);
%%
%%send_event({event, {Type, Body}, State}) ->
%%    send_event(Type, Body, State);
%%
%%send_event({event, {Type, ObjId, Body}, State}) ->
%%    send_event(Type, ObjId, Body, State);
%%
%%send_event({event, {Type, ObjId, Path, Body}, State}) ->
%%    send_event(Type, ObjId, Path, Body, State);
%%
%%send_event({event, [], State}) ->
%%    {ok, State};
%%
%%send_event({event, [Ev|Rest], State}) ->
%%    {ok, State2} = send_event({event, Ev, State}),
%%    send_event({event, Rest, State2});
%%
%%send_event({ok, State3}) ->
%%    {ok, State3};
%%
%%send_event({ignore, State3}) ->
%%    {ok, State3}.
%%
%%
%%%% @doc Sends events inside an object process directly to the event server
%%%% If the obj has session_events, they are sent directly to the session also
%%send_event(EvType, Body, #obj_state{id=#obj_id_ext{obj_id=ObjId, path=Path}}=State) ->
%%    send_event(EvType, ObjId, Path, Body, State).
%%
%%
%%%% @private
%%send_event(EvType, ObjId, Body, #obj_state{id=#obj_id_ext{path=Path}}=State) ->
%%    send_event(EvType, ObjId, Path, Body, State).
%%
%%
%%%% @private
%%send_event(EvType, ObjId, ObjPath, Body, #obj_state{id=#obj_id_ext{type=Type}}=State) ->
%%    Event = #nkevent{
%%        srv_id = ?NKROOT,
%%        class = ?DOMAIN_EVENT_CLASS,
%%        subclass = Type,
%%        type = nklib_util:to_binary(EvType),
%%        obj_id = ObjId,
%%        domain = ObjPath,
%%        body = Body
%%    },
%%    ?DEBUG("event sent to listeners: ~p", [lager:pr(Event, ?MODULE)], State),
%%    send_session_event(Event, State),
%%    ?CALL_NKROOT(object_db_event_send, [Event]),
%%    nkevent:send(Event),
%%    {ok, State}.
%%
%%
%%%% @private
%%send_session_event(#nkevent{type=Type}=Event, State) ->
%%    #obj_state{session_events=Events, session_link=Link} = State,
%%    case lists:member(Type, Events) of
%%        true ->
%%            case Link of
%%                {Mod, Pid} ->
%%                    Mod:send_event(Pid, Event);
%%                _ ->
%%                    ok
%%            end;
%%        false ->
%%            ok
%%    end.
%%
%%
%%%% @doc
%%search_syntax(Base) ->
%%    Base#{
%%        from => {integer, 0, none},
%%        size => {integer, 0, none},
%%        sort => {list, binary},
%%        fields => {list, binary},
%%        filters => map,
%%        simple_query => binary,
%%        simple_query_opts =>
%%        #{
%%            fields => {list, binary},
%%            default_operator => {atom, ['OR', 'AND']}
%%        }
%%    }.
%%
%%
%%%% @doc
%%get_obj_info(#obj_state{id=#obj_id_ext{obj_id=ObjId, path=Path}, obj=Obj}) ->
%%    #{
%%        domain_id := DomainId,
%%        parent_id := ParentId,
%%        obj_name := ObjName,
%%        created_by := CreatedBy,
%%        created_time := CreatedTime,
%%        updated_by := UpdatedBy,
%%        updated_time := UpdatedTime
%%    } = Obj,
%%    List = [
%%        {obj_id, ObjId},
%%        {obj_name, ObjName},
%%        {path, Path},
%%        {domain_id, DomainId},
%%        {parent_id, ParentId},
%%        {name, maps:get(name, Obj, ObjName)},
%%        {created_by, CreatedBy},
%%        {created_time, CreatedTime},
%%        {updated_by, UpdatedBy},
%%        {updated_time, UpdatedTime},
%%        case maps:get(description, Obj, <<>>) of
%%            <<>> -> [];
%%            Desc -> {description, Desc}
%%        end,
%%        case maps:get(tags, Obj, []) of
%%            [] -> [];
%%            Tags -> {tags, Tags}
%%        end,
%%        case maps:get(aliases, Obj, []) of
%%            [] -> [];
%%            Tags -> {tags, Tags}
%%        end,
%%        case maps:get(icon_id, Obj, <<>>) of
%%            <<>> -> [];
%%            IconId-> {icon_id, IconId}
%%        end
%%    ],
%%    maps:from_list(lists:flatten(List)).
%%
%%
%%%% @doc
%%get_obj_name(#obj_state{id=#obj_id_ext{obj_id=ObjId, path=Path}, obj=Obj}) ->
%%    #{
%%        obj_name := ObjName
%%    } = Obj,
%%    List = [
%%        {obj_id, ObjId},
%%        {obj_name, ObjName},
%%        {path, Path},
%%        {name, maps:get(name, Obj, ObjName)},
%%        case maps:get(description, Obj, <<>>) of
%%            <<>> -> [];
%%            Desc -> {description, Desc}
%%        end,
%%        case maps:get(icon_id, Obj, <<>>) of
%%            <<>> -> [];
%%            IconId-> {icon_id, IconId}
%%        end
%%    ],
%%    maps:from_list(lists:flatten(List)).
%%
%%
%%%% @doc
%%link_to_session_server(Module, #obj_state{session_link={Mod, Pid}} = State) when is_atom(Mod), is_pid(Pid) ->
%%    % Stop the API Server if we fail abruptly
%%    ok = Mod:register(Pid, {nkdomain_stop, Module, self()}),
%%    % Monitor the API server, reduce usage count if it fails
%%    nkdomain_obj:links_add(usage, {nkdomain_api_server, Pid}, State);
%%
%%link_to_session_server(_Module, State) ->
%%    State.
%%
%%
%%
%%
%%%% @doc
%%unlink_from_session_server(Module, #obj_state{session_link={Mod, _Pid}} = State) when is_atom(Mod) ->
%%    nkdomain_obj:links_iter(
%%        usage,
%%        fun
%%            ({nkdomain_api_server, Pid}, _Acc) ->
%%                Mod:unregister(Pid, {nkdomain_stop, Module, self()});
%%            (_, _Acc) ->
%%                ok
%%        end,
%%        ok,
%%        State),
%%    State.
%%
%%
%%%% @doc
%%get_obj_session(#obj_state{session=Session}) ->
%%    Session.
%%
%%
%%%% @doc
%%set_obj_session(Session, State) ->
%%    State#obj_state{session=Session}.
%%
%%
%%%% @doc
%%set_active(true, #obj_state{obj=Obj}=State) ->
%%    Obj2 = ?ADD_TO_OBJ(active, true, Obj),
%%    State#obj_state{obj=Obj2, is_dirty=true};
%%
%%set_active(false, #obj_state{obj=Obj}=State) ->
%%    Obj2 = ?REMOVE_FROM_OBJ(active, Obj),
%%    State#obj_state{obj=Obj2, is_dirty=true}.
%%
%%
%%%% @doc
%%set_next_status_timer(Time, #obj_state{obj=Obj, next_status_timer=Timer}=State) ->
%%    nklib_util:cancel_timer(Timer),
%%    case Time of
%%        0 ->
%%            Obj2 = ?REMOVE_FROM_OBJ(next_status_time, Obj),
%%            State#obj_state{obj=Obj2, is_dirty=true, next_status_timer=undefined};
%%        _ ->
%%            Now = nkdomain_util:timestamp(),
%%            Obj2 = ?ADD_TO_OBJ(next_status_time, Now+Time, Obj),
%%            Timer2 = erlang:send_after(Time, self(), nkdomain_obj_next_status_timer),
%%            State#obj_state{obj=Obj2, is_dirty=true, next_status_timer=Timer2}
%%    end.



