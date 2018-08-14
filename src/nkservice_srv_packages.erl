
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


-module(nkservice_srv_packages).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([start/2, stop/3, do_stop/4, update/4, update_status/3]).

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

start([PackageId|Rest], #state{id=SrvId, package_status=PackagesStatus}=State) ->
    Status = maps:get(PackageId, PackagesStatus, #{}),
    State2 = case maps:get(status, Status, failed) of
        failed ->
            do_start(PackageId, State);
        running ->
            case find_sup_pid(PackageId, State) of
                {ok, _} ->
                    State;
                undefined ->
                    ?LLOG(warning, SrvId, "running package '~s' has no sup!",
                          [PackageId]),
                    do_start(PackageId, State)
            end;
        NewStatus ->
            % for 'starting', 'updating', 'runnig' do nothing
            case find_sup_pid(PackageId, State) of
                {ok, _} ->
                    ok;
                undefined ->
                    ?LLOG(warning, SrvId, "package '~s' in status '~s' has no sup!",
                        [PackageId, NewStatus])
            end,
            State
    end,
    start(Rest, State2).


%% @private
do_start(PackageId, #state{service=Service}=State) ->
    Self = self(),
    case start_sup(PackageId, State) of
        {ok, Pid, State2} ->
            cast_status(Self, PackageId, starting),
            spawn_link(
                fun() ->
                    Fun = fun() -> start_package(PackageId, Pid, Service) end,
                    Res = safe_call(Fun),
                    cast_status(Self, PackageId, Res)
                end),
            State2;
        error ->
            cast_status(Self, PackageId, {error, supervisor_down}),
            State
    end.


%% @private
stop([], _Service, State) ->
    State;

stop([PackageId|Rest], Service, State) ->
    #state{package_sup_pids=Pids} = State,
    Self = self(),
    % PackagesStatus2 = maps:remove(PackageId, PackagesStatus),
    Pids2 = case find_sup_pid(PackageId, State) of
        {ok, Pid} ->
            lists:keystore(Pid, 2, Pids, {ignore, Pid});
        undefined ->
            Pids
    end,
    State2 = State#state{package_sup_pids=Pids2},
    spawn_link(fun() -> do_stop(PackageId, Self, Service, State) end),
    stop(Rest, Service, State2).


%% @private
do_stop(PackageId, Self, Service, #state{id=Id}=State) ->
    cast_status(Self, PackageId, stopping),
    case find_sup_pid(PackageId, State) of
        {ok, Pid} ->
            safe_call(fun() -> stop_package(PackageId, Pid, Service) end),
            nkservice_packages_sup:stop_package_sup(Id, PackageId);
        undefined ->
            ok
    end,
    cast_status(Self, PackageId, stopped),
    State.


%% @private
%% We only ensure that the package's sup is up
%% Package must update itself, unloading and loading from sup or whatever
update([], _NewService, _OldService, State) ->
    State;

update([PackageId|Rest], NewService, OldService, State) ->
    Self = self(),
    State2 = case start_sup(PackageId, State) of
        {ok, Pid, State3} ->
            cast_status(Self, PackageId, updating),
            spawn_link(
                fun() ->
                    Fun = fun() -> update_package(PackageId, Pid, NewService, OldService) end,
                    Res = safe_call(Fun),
                    cast_status(Self, PackageId, Res)
                end),
            State3;
        error ->
            cast_status(Self, PackageId, {error, supervisor_down}),
            State
    end,
    update(Rest, NewService, OldService, State2).


%% @private
update_status(PackageId, stopped, State) ->
    #state{id=SrvId, package_status=AllStatus} = State,
    ?LLOG(notice, SrvId, "package '~s' status 'stopped'", [PackageId]),
    AllStatus2 = maps:remove(PackageId, AllStatus),
    State2 = State#state{package_status=AllStatus2},
    Event = {package_status, #{package_id=>PackageId, status=>stopped}},
    nkservice_srv:do_event(Event, State2);

update_status(PackageId, Status, State) ->
    #state{id=SrvId, package_status=AllStatus} = State,
    Now = nklib_date:epoch(msecs),
    PackageStatus1 = maps:get(PackageId, AllStatus, #{}),
    PackageStatus2 = case Status of
        {error, Error} ->
            ?LLOG(notice, SrvId, "package '~s' status 'failed': ~p", [PackageId, Error]),
            PackageStatus1#{
                status => failed,
                last_error => Error,
                last_error_time => Now,
                last_status_time => Now
            };
        _ ->
            case find_sup_pid(PackageId, State) of
                {ok, _} ->
                    case maps:get(status, PackageStatus1, none) of
                        Status ->
                            ok;
                        Old ->
                            ?LLOG(info, SrvId, "package '~s' status '~p' -> '~p'",
                                  [PackageId, Old, Status])
                    end,
                    PackageStatus1#{
                        status => Status,
                        last_status_time => Now
                    };
                undefined ->
                    % The supervisor has failed before completing the status
                    ?LLOG(notice, SrvId, "package '~s' status 'failed': ~p",
                          [PackageId, supervisor_down]),
                    PackageStatus1#{
                        status => failed,
                        last_error => supervisor_down,
                        last_error_time => Now,
                        last_status_time => Now
                    }
            end
    end,
    AllStatus2 = AllStatus#{PackageId => PackageStatus2},
    State2 = State#state{package_status=AllStatus2},
    #{status:=NewStatus} = PackageStatus2,
    Event = {package_status, #{package_id=>PackageId, status=>NewStatus}},
    nkservice_srv:do_event(Event, State2).


%% @private
start_package(PackageId, Pid, Service) ->
    #{id:=SrvId, packages:=Packages, plugin_ids:=Plugins} = Service,
    #{class:=Class} = Package = maps:get(PackageId, Packages),
    ?LLOG(info, SrvId, "starting package '~s' (~s)", [PackageId, Class]),
    start_package_plugins(Plugins, Package, Pid, Service).


%% @private
start_package_plugins([], _Package, _Pid, _Service) ->
    running;

start_package_plugins([Plugin|Rest], Package, Pid, Service) ->
    Mod = nkservice_config:get_plugin_mod(Plugin),
    #{class:=Class} = Package,
    % Bottom to top
    case nklib_util:apply(Mod, plugin_start, [Class, Package, Pid, Service]) of
        ok ->
            start_package_plugins(Rest, Package, Pid, Service);
        not_exported ->
            start_package_plugins(Rest, Package, Pid, Service);
        continue ->
            start_package_plugins(Rest, Package, Pid, Service);
        {error, Error} ->
            {error, Error}
    end.


%% @private
stop_package(PackageId, Pid, #{id:=SrvId, packages:=Config, plugin_ids:=Plugins}=Service) ->
    #{id:=Id, class:=Class} = Package = maps:get(PackageId, Config, #{}),
    ?LLOG(info, SrvId, "stopping package '~s' (~s)", [Id, Class]),
    stop_package_plugins(lists:reverse(Plugins), Package, Pid, Service).


%% @private
stop_package_plugins([Plugin|Rest], Package, Pid, #{id:=SrvId}=Service) ->
    Mod = nkservice_config:get_plugin_mod(Plugin),
    #{id:=Id, class:=Class} = Package,
    case nklib_util:apply(Mod, plugin_stop, [Class, Package, Pid, Service]) of
        ok ->
            stop_package_plugins(Rest, Package, Pid, Service);
        not_exported ->
            stop_package_plugins(Rest, Package, Pid, Service);
        continue ->
            stop_package_plugins(Rest, Package, Pid, Service);
        {error, Error} ->
            ?LLOG(warning, SrvId, "error stopping package '~s': ~p", [Id, Error]),
            {error, Error}
    end.


%% @private
update_package(PackageId, Pid, NewService, OldService) ->
    #{id:=SrvId, packages:=NewPackages, plugin_ids:=Plugins} = NewService,
    #{packages:=OldPackages} = OldService,
    #{id:=Id, class:=Class} = NewPackage = maps:get(PackageId, NewPackages),
    #{class:=Class} = OldPackage = maps:get(PackageId, OldPackages),
    ?LLOG(info, SrvId, "updating package '~s' (~s)", [Id, Class]),
    update_package_plugins(Plugins, NewPackage, OldPackage, Pid, NewService).


%% @private
update_package_plugins([], _Package, _OldPackage, _Pid, _Service) ->
    running;

update_package_plugins([Plugin|Rest], Package, OldPackage, Pid, Service) ->
    Mod = nkservice_config:get_plugin_mod(Plugin),
    #{class:=Class} = Package,
    Args = [Class, Package, OldPackage, Pid, Service],
    case nklib_util:apply(Mod, plugin_update, Args) of
        ok ->
            update_package_plugins(Rest, Package, OldPackage, Pid, Service);
        not_exported ->
            update_package_plugins(Rest, Package, OldPackage, Pid, Service);
        continue ->
            update_package_plugins(Rest, Package, OldPackage, Pid, Service);
        {error, Error} ->
            {error, Error}
    end.


%% @private
start_sup(PackageId, #state{id=SrvId, package_sup_pids=Sups}=State) ->
    case find_sup_pid(PackageId, State) of
        {ok, Pid} ->
            {ok, Pid, State};
        undefined ->
            case nkservice_packages_sup:start_package_sup(SrvId, PackageId) of
                {ok, Pid} ->
                    monitor(process, Pid),
                    Sups2 = lists:keystore(PackageId, 1, Sups, {PackageId, Pid}),
                    {ok, Pid, State#state{package_sup_pids=Sups2}};
                {error, Error} ->
                    ?LLOG(notice, SrvId, "could not start package '~s' supervisor: ~p",
                        [PackageId, Error]),
                    error
            end
    end.


%% @private
find_sup_pid(PackageId, #state{package_sup_pids =Sups}) ->
    case lists:keyfind(PackageId, 1, Sups) of
        {PackageId, Pid} when is_pid(Pid) ->
            {ok, Pid};
        _ ->
            undefined
    end.


%% @private
safe_call(Fun) ->
    try Fun() of
        Res ->
            Res
    catch
        Class:CError:Trace ->
            {error, {Class, {CError, Trace}}}
    end.


%% @private
%% Will call update_status/3 immediately
cast_status(Pid, PackageId, Status) ->
    gen_server:cast(Pid, {nkservice_package_status, PackageId, Status}).
