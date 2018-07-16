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

-module(nkservice).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([start/2, stop/1, replace/2, update/2]).
-export([force_stop/1, force_reload/1]).
-export([get_services/0, get_status/1]).
-export([get/2, get/3, put/3, put_new/3, del/2]).
-export_type([id/0, service_spec/0]).
-export_type([service/0]).
-export_type([error/0, event/0]).


-include_lib("nkpacket/include/nkpacket.hrl").
-include("nkservice.hrl").


%% ===================================================================
%% Types
%% ===================================================================

-type id() :: atom().

-type class() :: binary().

-type name() :: binary().

%%
%% Types for a specifying a service
%%

-type package_id() :: binary().

-type package_class() :: binary().

-type package_spec() ::
    #{
        id => package_id(),             % Mandatory
        class => package_class(),       % Mandatory
        config => map(),
        remove => boolean()
    }.

-type module_id() :: binary().

-type module_spec() ::
    #{
        id => module_id(),
        class => luerl,
        file => binary(),
        url => binary(),
        code => binary(),
        remove => boolean()         % true to remove the entry
    }.


-type secret_spec() ::
    #{
        key => atom(),                % Mandatory
        value => map(),
        remove => boolean()
    }.

%% Service specification
-type service_spec() ::
	#{
        class => class(),                % Used to find similar services
        name => name(),                  % Optional name
        plugins => [binary()],           % Plugins to add to all packages
        uuid => binary(),                % Generated automatically
        packages => [package_spec()],
        modules => [module_spec()],
        secret => [secret_spec()],
        meta => map(),
        parent => id()                  % Parent service, used for counters
	}.

%%
%% Types for a running service
%%

-type service_package() ::
    #{
        id => id(),
        class => package_class(),
        config => map(),
        hash => integer(),
        plugin => atom()
    }.

-type service_module() ::
    #{
        id => module_id(),
        class => luerl,
        code => binary(),
        debug => boolean(),
        max_instances => integer(),
        hash => integer(),
        lua_state => binary(),          % Accessible only in direct functions
        packages => [package_id()]      % Used packages
    }.


-type service_secret() ::
    #{
        module_id => module_id(),
        value => term()
    }.

-type service() ::
    #{
        id => atom(),
        class => class(),
        name => name(),
        uuid => binary(),
        plugins => [atom()],
        plugin_ids => [atom()],         % Expanded,bottom to top
        packages => #{package_id() => service_package()},
        modules => #{module_id() => service_module()},
        timestamp => nklib_date:epoch(msecs),
        secret => #{{term(), binary(), binary()} => service_secret()},
        hash => integer(),
        meta => map(),
        parent => id()
    }.

%%
%% Service info
%%


-type service_info() ::
    #{
        class => class(),
        name => name(),
        hash => integer(),
        pid => pid()
    }.


-type service_status() ::
    nkservice_srv:service_status().



-type event() ::
    atom() | {atom(), map()}.

%% See nkservice_callbacks:error_code/1
-type error() :: term().

%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts a new service.
%% It tries to find its UUID from a file in log_dir with the same name, if it
%% is not present, it will generate a new one
-spec start(id(), service_spec()) ->
    ok | {error, term()}.

start(SrvId, Spec) ->
    case nkservice_master:get_leader_pid(SrvId) of
        Pid when is_pid(Pid) ->
            {error, already_started};
        undefined ->
            case nkservice_config:config_service(SrvId, Spec, #{}) of
                {ok, Service2} ->
                    % io:format("NKLOG SERV ~p\n", [Service2]),
                    % Master will be started and leader elected,
                    % and it will start service in all nodes
                    nkservice_srv:start(Service2);
                {error, Error} ->
                    {error, Error}
            end
    end.


%% @doc Stops a service, only in local node
-spec stop(id()) ->
    ok | {error, not_running|term()}.

stop(SrvId) ->
    nkservice_master:stop(SrvId).


%% @doc Replaces a service configuration with a new full set of parameters
-spec replace(id(), service_spec()) ->
    ok | {error, term()}.

replace(SrvId, Spec) ->
    nkservice_master:replace(SrvId, Spec).


%% @doc Updates a service configuration in local node
%% Fields class, name, global, plugins, uuid, meta, if used, overwrite previous settings
%% Packages and modules are merged. Use remove => true to remove an old one
%% Fields cache, debug, secret are merged. Use remove => true to remove an old one
-spec update(id(), service_spec()) ->
    ok | {error, term()}.

update(SrvId, Spec) ->
    nkservice_master:update(SrvId, Spec).


%% @private
force_stop(SrvId) ->
    rpc:eval_everywhere(nkservice_srv, stop, [SrvId]).


%% @doc Reloads a configuration
-spec force_reload(id()) ->
    ok | {error, term()}.

force_reload(Id) ->
    rpc:eval_everywhere(nkservice_srv, update, [Id, #{}]),
    ok.


%% @doc Gets quick info on all services on all nodes
-spec get_services() ->
    #{id() => [service_info()]}.

get_services() ->
    Nodes = [node()|nodes()],
    {ResL, _Bad} = rpc:multicall(Nodes, nkservice_srv, get_all, []),
    lists:foldl(
        fun
            (List, Acc1) when is_list(List) ->
                lists:foldl(
                    fun({Id, Class, Name, Hash, Pid}, Acc2) ->
                        Srvs = maps:get(Id, Acc2, []),
                        Value = #{class=>Class, name=>Name, hash=>Hash, pid=>Pid},
                        Acc2#{Id => [Value|Srvs]}
                    end,
                    Acc1,
                    List);
            (_, Acc1) ->
                Acc1
        end,
        #{},
        ResL).


%% @doc
-spec get_status(id()) ->
    #{node() => [service_status()]}.

get_status(SrvId) ->
    Nodes = [node()|nodes()],
    {ResL, _Bad} = rpc:multicall(Nodes, nkservice_srv, get_status, [SrvId]),
    lists:foldl(
        fun
            ({ok, #{node:=Node}=LocalStatus}, Acc) ->
                Acc#{Node => LocalStatus};
            (_, Acc1) ->
                Acc1
        end,
        #{},
        ResL).


%% @doc Gets a value from service's store
-spec get(id(), term()) ->
    term().

get(SrvId, Key) ->
    get(SrvId, Key, undefined).


%% @doc Gets a value from service's store
-spec get(id(), term(), term()) ->
    term().

get(SrvId, Key, Default) ->
    case ets:lookup(SrvId, Key) of
        [{_, Value}] -> Value;
        [] -> Default
    end.


%% @doc Inserts a value in service's store
-spec put(id(), term(), term()) ->
    ok.

put(SrvId, Key, Value) ->
    true = ets:insert(SrvId, {Key, Value}),
    ok.


%% @doc Inserts a value in service's store
-spec put_new(id(), term(), term()) ->
    true | false.

put_new(SrvId, Key, Value) ->
    ets:insert_new(SrvId, {Key, Value}).


%% @doc Deletes a value from service's store
-spec del(id(), term()) ->
    ok.

del(SrvId, Key) ->
    true = ets:delete(SrvId, Key),
    ok.

