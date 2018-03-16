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

%% @doc Supervisor for the packages
-module(nkservice_packages_sup).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(supervisor).

-export([start_package_sup/2, stop_package_sup/2]).
-export([start_child/3, start_child/2, update_child/3, update_child_multi/3,
         remove_child/3, remove_child/2]).
-export([get_pid/1, get_pid/2, get_packages/1, get_package_childs/2]).
-export([init/1, start_link/1, start_link_package_sup/2]).

-include("nkservice.hrl").

-define(LLOG(Type, Txt, Args),lager:Type("NkSERVICE "++Txt, Args)).



-type update_opts() ::
    #{
        restart_delay => integer()          % msecs
    }.


%% @doc Tries to start a package supervisor, or returns existing one
start_package_sup(SrvId, PackageId) ->
    Pid = get_pid(SrvId),
    Child = #{
        id => PackageId,
        start => {?MODULE, start_link_package_sup, [SrvId, PackageId]},
        type => supervisor,
        restart => temporary
    },
    case supervisor:start_child(Pid, Child) of
        {ok, ChildPid} ->
            {ok, ChildPid};
        {error, {already_started, ChildPid}} ->
            {ok, ChildPid};
        {error, Error} ->
            {error, Error}
    end.


%% @doc
stop_package_sup(SrvId, PackageId) ->
    Pid = get_pid(SrvId),
    case supervisor:terminate_child(Pid, PackageId) of
        ok ->
            supervisor:delete_child(Pid, PackageId),
            ok;
        {error, Error} ->
            {error, Error}
    end.


%% @doc
start_child(SrvId, PackageId, Spec) ->
    Pid = get_pid(SrvId, PackageId),
    start_child(Pid, Spec).


%% @doc
start_child(Pid, Spec) when is_pid(Pid) ->
    case supervisor:start_child(Pid, Spec) of
        {ok, ChildPid} ->
            {ok, ChildPid};
        {error, Error} ->
            {error, Error}
    end.


%% @doc Updates (if Spec is different) or starts a new child
-spec update_child(pid(), supervisor:child_spec(), update_opts()) ->
    {ok, pid()} | {upgraded, pid()} | not_updated | {error, term()}.

update_child(Pid, Spec, Opts) when is_pid(Pid) ->
    ChildId = case Spec of
        #{id:=CI} -> CI;
        _ -> element(1, Spec)
    end,
    case supervisor:get_childspec(Pid, ChildId) of
        {ok, Spec} ->
            ?LLOG(warning, "child ~p not updated", [ChildId]),
            not_updated;
        {ok, _OldSpec} ->
            case remove_child(Pid, ChildId) of
                ok ->
                    Delay = maps:get(restart_delay, Opts, 500),
                    timer:sleep(Delay),
                    case supervisor:start_child(Pid, Spec) of
                        {ok, ChildPid} ->
                            ?LLOG(debug, "child ~p upgraded", [ChildId]),
                            {upgraded, ChildPid};
                        {error, Error} ->
                            {error, Error}
                    end;
                {error, Error} ->
                    {error, Error}
            end;
        {error, not_found} ->
            case supervisor:start_child(Pid, Spec) of
                {ok, ChildPid} ->
                    ?LLOG(debug, "child ~p started", [ChildId]),
                    {ok, ChildPid};
                {error, Error} ->
                    {error, Error}
            end
    end.


%% @doc Updates a series of childs, all or nothing
-spec update_child_multi(term()|pid(), [supervisor:child_spec()], map()) ->
    ok | upgraded | not_updated | {error, term()}.

update_child_multi(Pid, SpecList, Opts) when is_pid(Pid) ->
    OldIds = [ChildId || {ChildId, _, _, _} <- supervisor:which_children(Pid)],
    NewIds = [
        case is_map(Spec) of
            true -> maps:get(id, Spec);
            false -> element(1, Spec)
        end
        || Spec <- SpecList
    ],
    ToStop = OldIds -- NewIds,
    lists:foreach(fun(ChildId) -> remove_child(Pid, ChildId) end, ToStop),
    case update_child_multi(Pid, SpecList, Opts, not_updated) of
        {error, Error} ->
            lists:foreach(fun(ChildId) -> remove_child(Pid, ChildId) end, OldIds++NewIds),
            {error, Error};
        Other ->
            Other
    end.


%% @private
update_child_multi(_Pid, [], _Opts, Res) ->
    Res;

update_child_multi(Pid, [Spec|Rest], Opts, Res) ->
    case update_child(Pid, Spec, Opts) of
        {ok, _} ->
            update_child_multi(Pid, Rest, Opts, ok);
        {upgraded, _} ->
            update_child_multi(Pid, Rest, Opts, upgraded);
        not_updated ->
            update_child_multi(Pid, Rest, Opts, Res);
        {error, Error} ->
            {error, Error}
    end.


%% @doc
remove_child(SrvId, PackageId, ChildId) ->
    Pid = get_pid(SrvId, PackageId),
    remove_child(Pid, ChildId).


%% @doc
remove_child(Pid, ChildId) when is_pid(Pid) ->
    case supervisor:terminate_child(Pid, ChildId) of
        ok ->
            supervisor:delete_child(Pid, ChildId),
            ok;
        {error, Error} ->
            {error, Error}
    end.


%% @doc
get_packages(Id) ->
    [{I, Pid} || {I, Pid, _, _} <- supervisor:which_children(get_pid(Id))].


%% @doc
get_package_childs(Id, PackageId) ->
    [{I, Pid} || {I, Pid, _, _} <- supervisor:which_children(get_pid(Id, PackageId))].


%% @private Get pid() of master supervisor for all packages
get_pid(Pid) when is_pid(Pid) ->
    Pid;
get_pid(SrvId) ->
    nklib_proc:whereis_name({?MODULE, SrvId}).


%% @private Get pid() of supervisor for a package
get_pid(SrvId, PackageId) ->
    nklib_proc:whereis_name({?MODULE, SrvId, PackageId}).



%% @private Starts the main supervisor for all packages
%% It starts empty, nkservice_srv will add child supervisors calling
%% start_package/2
-spec start_link(nkservice:id()) ->
    {ok, pid()}.

start_link(Id) ->
    ChildSpec = {{one_for_one, 10, 60}, []},
    {ok, Pid} = supervisor:start_link(?MODULE, ChildSpec),
    yes = nklib_proc:register_name({?MODULE, Id}, Pid),
    {ok, Pid}.


%% @private
init(ChildsSpec) ->
    {ok, ChildsSpec}.


%% @private Called for each configured package
start_link_package_sup(Id, Package) ->
    ChildSpec = {{one_for_one, 10, 60}, []},
    {ok, Pid} = supervisor:start_link(?MODULE, ChildSpec),
    yes = nklib_proc:register_name({?MODULE, Id, Package}, Pid),
    {ok, Pid}.






