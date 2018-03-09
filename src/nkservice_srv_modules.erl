
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


-module(nkservice_srv_modules).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([start/2, stop/2, do_stop/2, update_status/3]).

-include("nkservice.hrl").
-include("nkservice_srv.hrl").

-define(LLOG(Type, Id, Txt, Args),
    lager:Type("NkSERVICE '~s' "++Txt, [Id | Args])).


%% ===================================================================
%% Internal
%% ===================================================================


%% @private
start([], State) ->
    State;

start([ModuleId|Rest], #state{module_status=AllStatus}=State) ->
    Status = maps:get(ModuleId, AllStatus, #{}),
    State3 = case maps:get(status, Status, failed) of
        failed ->
            Self = self(),
            case start_sup(ModuleId, State) of
                {ok, _Pid, State2} ->
                    cast_status(Self, ModuleId, starting),
                    spawn_link(
                        fun() ->
                            do_start(ModuleId, Self, State)
                        end),
                    State2;
                error ->
                    cast_status(Self, ModuleId, {error, supervisor_down}),
                    State
            end;
        _ ->
            % for 'starting', 'running', 'updating', do nothing
            State
    end,
    start(Rest, State3).


%% @private
do_start(ModuleId, Self, #state{id=SrvId}=State) ->
    ?LLOG(info, SrvId, "starting module ~s", [ModuleId]),
    Res = case call_module(ModuleId, init, [], State) of
        not_exported ->
            running;
        {ok, _} ->
            running;
        {error, Error} ->
            {error, Error}
    end,
    cast_status(Self, ModuleId, Res).


%% @private
stop([], State) ->
    State;

stop([ModuleId|Rest], #state{module_sup_pids=Pids}=State) ->
    % Expect the down event from the supervisor and ignore it
    Pids2 = case find_sup_pid(ModuleId, State) of
        {ok, Pid} ->
            lists:keystore(Pid, 2, Pids, {ignore, Pid});
        undefined ->
            Pids
    end,
    State2 = State#state{module_sup_pids=Pids2},
    Self = self(),
    spawn_link(
        fun() ->
            cast_status(Self, ModuleId, stopping),
            do_stop(ModuleId, State),
            cast_status(Self, ModuleId, stopped)
        end),
    stop(Rest, State2).


%% @private
do_stop(ModuleId, #state{id=SrvId}=State) ->
    ?LLOG(info, SrvId, "stopping module ~s", [ModuleId]),
    case find_sup_pid(ModuleId, State) of
        {ok, _Pid} ->
            _ = call_module(ModuleId, terminate, [], State),
            nkservice_modules_sup:stop_module_sup(SrvId, ModuleId);
        undefined ->
            ok
    end.


%%%% @private
%%update([], State) ->
%%    State;
%%
%%update([ModuleId|Rest], #state{module_sup_pids=Pids}=State) ->
%%    % Expect the down event from the supervisor and ignore it
%%    case find_sup_pid(ModuleId, State) of
%%
%%
%%
%%        {ok, Pid} ->
%%            lists:keystore(Pid, 2, Pids, {ignore, Pid});
%%        undefined ->
%%            Pids
%%    end,
%%    State2 = State#state{module_sup_pids=Pids2},
%%    Self = self(),
%%    spawn_link(
%%        fun() ->
%%            cast_status(Self, ModuleId, updating),
%%            do_stop(ModuleId, State),
%%            case start_sup(ModuleId, State) of
%%                {ok, _Pid, State2} ->
%%                    cast_status(Self, ModuleId, starting),
%%                    spawn_link(
%%                        fun() ->
%%                            do_start(ModuleId, Self, State)
%%                        end),
%%                    State2;
%%                error ->
%%                    cast_status(Self, ModuleId, {error, supervisor_down}),
%%                    State
%%            end;
%%            do_start(ModuleId, Self, State)
%%        end),
%%    restart(Rest, State2).


%% @private
update_status(ModuleId, stopped, State) ->
    #state{id=SrvId, module_status=AllStatus} = State,
    ?LLOG(info, SrvId, "module '~s' stopped", [ModuleId]),
    AllStatus2 = maps:remove(ModuleId, AllStatus),
    State2 = State#state{module_status=AllStatus2},
    Event = {module_status, #{module_id=>ModuleId, status=>stopped}},
    % Maybe be stopped because of a restart, so launch check
    nkservice_srv:launch_check_status(self()),
    nkservice_srv:do_event(Event, State2);

update_status(ModuleId, Status, State) ->
    #state{id=SrvId, module_status=AllStatus} = State,
    Now = nklib_util:m_timestamp(),
    ModuleStatus1 = maps:get(ModuleId, AllStatus, #{}),
    ModuleStatus2 = case Status of
        {error, Error} ->
            ?LLOG(notice, SrvId, "module '~s' error: ~p", [ModuleId, Error]),
            ModuleStatus1#{
                status => failed,
                last_error => Error,
                last_error_time => Now,
                last_status_time => Now
            };
        _ ->
            case maps:get(status, ModuleStatus1, undefined) of
                Status ->
                    ok;
                Old ->
                    ?LLOG(info, SrvId, "module '~s' status ~p -> ~p",
                          [ModuleId, Old, Status])
            end,
            ModuleStatus1#{
                status => Status,
                last_status_time => Now
            }
    end,
    AllStatus2 = AllStatus#{ModuleId => ModuleStatus2},
    State2 = State#state{module_status=AllStatus2},
    #{status:=UserStatus} = ModuleStatus2,
    Event = {module_status, #{module_id=>ModuleId, status=>UserStatus}},
    nkservice_srv:do_event(Event, State2).


%% @private
start_sup(ModuleId, #state{id=SrvId, module_sup_pids=Sups}=State) ->
    case find_sup_pid(ModuleId, State) of
        {ok, Pid} ->
            {ok, Pid, State};
        undefined ->
            case nkservice_modules_sup:start_module_sup(SrvId, ModuleId) of
                {ok, Pid} ->
                    monitor(process, Pid),
                    Sups2 = lists:keystore(ModuleId, 1, Sups, {ModuleId, Pid}),
                    {ok, Pid, State#state{module_sup_pids=Sups2}};
                {error, Error} ->
                    ?LLOG(notice, SrvId, "could not start module '~s' supervisor: ~p",
                        [ModuleId, Error]),
                    error
            end
    end.


%% @private
find_sup_pid(ModuleId, #state{module_sup_pids=Sups}) ->
    case lists:keyfind(ModuleId, 1, Sups) of
        {ModuleId, Pid} when is_pid(Pid) ->
            {ok, Pid};
        _ ->
            undefined
    end.


%% @private
call_module(ModuleId, Fun, Args, #state{id=SrvId}) ->
    FunName = nkservice_config_luerl:service_table([callbacks, Fun]),
    try
        case nkservice_luerl_instance:call({SrvId, ModuleId, main}, FunName, [Args]) of
            {error, {lua_error, {undef_function, _}}} ->
                not_exported;
            {ok, Res} ->
                {ok, Res};
            {error, Error} ->
                {error, Error}
        end
    catch
        Class:CError ->
            {error, {Class, {CError, erlang:get_stacktrace()}}}
    end.


%% @private
cast_status(Pid, ModuleId, Status) ->
    gen_server:cast(Pid, {nkservice_module_status, ModuleId, Status}).



%%%% @private
%%to_bin(Term) when is_binary(Term) -> Term;
%%to_bin(Term) -> nklib_util:to_binary(Term).
