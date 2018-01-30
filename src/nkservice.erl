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

-export([start/2, stop/1, reload/1, update/2, modify/2, get_all/0, get_all/1]).
-export([get/2, get/3, put/3, put_new/3, del/2]).
-export_type([id/0, spec/0, config/0, service/0]).
-export_type([error/0, event/0]).
-export_type([user_id/0, user_state/0, session_id/0]).
-export_type([req_cmd/0, req_data/0, req_tid/0]).


-include_lib("nkpacket/include/nkpacket.hrl").
-include("nkservice.hrl").


%% ===================================================================
%% Types
%% ===================================================================

%% Service's id must be an atom
-type id() :: atom().

-type plugin_spec() :: #{class=>atom(), config=>map()}.
-type debug_spec() :: #{key=>atom(), spec=>map()}.
-type cache_spec() :: #{key=>atom(), value=>term()}.

-type script_spec() ::
    #{
        id => binary(),
        class => luerl | remove,
        file => binary(),
        url => binary(),
        code => binary()
    }.

-type callback_spec() ::
    #{
        id => binary(),
        class => luerl | http | remove,
        luerl_id => binary(),
        url => binary()
    }.

-type listen_spec() ::
    #{
        id => binary(),
        url => binary(),
        opts => nkpacket:listen_opts()
    }.


%% Service specification
-type spec() ::
	#{
        class => binary(),                % Used to find similar services
        name => binary(),                 % Optional name
        plugins => [plugin_spec()],
        %listen => listen_spec(),
        log_level => log_level(),
        debug => [debug_spec()],
        cache => [cache_spec()],
        scripts => [script_spec()],
        callbacks => [callback_spec()],
        listen => [listen_spec()]
	}.

-type config() :: #{term() => term()}.

-type log_level() :: 0..8 |
    none | emergency | alert | critical | error | warning | notice | info |debug.


-type service() ::
    #{
        id => atom(),
        class => binary(),               % Optional class
        name => binary(),                 % Optional name
        plugins => [atom()],
        config => #{atom() => map()},
        uuid => binary(),               % Each service is assigned an uuid
        log_level => log_level(),
        timestamp => nklib_util:m_timestamp(),  % Started time
        cache => #{atom() => map()},
        debug => #{atom() => map()},
        scripts => #{Id::binary() => map()},
        callbacks => #{Id::binary() => map()},
        listen => #{Plugin::atom() => [{Id::term(), [nkpacket:conn()]}]},
        listen_started => #{Plugin::atom() => [Id::term()]}
    }.


%% See nkservice_callbacks:error_code/1
-type error() :: term().

-type user_id() :: binary().
-type user_state() :: map().
-type session_id() :: binary().
-type req_cmd() :: binary().
-type req_data() :: map() | list().
-type req_tid() :: integer() | binary().

-type event() :: nkevent:event().



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts a new service.
%% It tries to find its UUID from a file in log_dir with the same name, if it
%% is not present, it will generate a new one



-spec start(id(), spec()) ->
    {ok, pid()} | {error, term()}.

start(Id, Spec) ->
    case whereis(Id) of
        Pid when is_pid(Pid) ->
            {error, {already_started, Pid}};
        undefined ->
            Service = case Spec of
                #{uuid:=UUID} ->
                    #{id=>Id, uuid=>UUID};
                _ ->
                    #{id=>Id, uuid=>nkservice_util:update_uuid(Id, Spec)}
            end,
            case nkservice_config:config_service(Spec, Service) of
                {ok, Service2} ->
                    lager:error("NKLOG S2 ~p", [Service2]),
                    nkservice_srv_sup:start_service(Service2);
                {error, Error} ->
                    {error, Error}
            end
    end.


%% @doc Stops a service
-spec stop(id()) ->
    ok | {error, not_running|term()}.

stop(Id) ->
    Reply = nkservice_srv_sup:stop_service(Id),
    code:purge(Id),
    Reply.


%% @doc Reloads a configuration
-spec reload(id()) ->
    ok | {error, term()}.

reload(Id) ->
    modify(Id, #{}).


%% @doc Updates a service configuration
%% Full replacement configuration must be used

%% New transports can be added, but old transports will not be automatically
%% stopped. Use get_listeners/2 to find transports and stop them manually.
%% (the info on get_listeners/2 will not be updated).
-spec update(id(), spec()) ->
    ok | {error, term()}.

update(Id, Spec) ->
    nkservice_srv:call(Id, {?MODULE, update, Spec}, 30000).


%% @doc Modifies a service configuration

modify(Id, UserSpec) ->
    Spec1 = Id:spec(),
    Spec2 = maps:merge(Spec1, UserSpec),
    update(Id, Spec2).


    
%% @doc Gets all started services
-spec get_all() ->
    [{id(), binary(), binary(), pid()}].

get_all() ->
    [{Id, Id:name(), Class, Pid} || 
     {{Id, Class}, Pid}<- nklib_proc:values(nkservice_srv)].


%% @doc Gets all started services
-spec get_all(Class::binary()) ->
    [{id(), binary(), pid()}].

get_all(Class) ->
    [{Id, Name, Pid} || {Id, Name, C, Pid} <- get_all(), C==Class].



%% @doc Gets a value from service's store
-spec get(id(), term()) ->
    term().

get(Id, Key) ->
    get(Id, Key, undefined).


%% @doc Gets a value from service's store
-spec get(id(), term(), term()) ->
    term().

get(Id, Key, Default) ->
    nkservice_srv:get(Id, Key, Default).


%% @doc Inserts a value in service's store
-spec put(id(), term(), term()) ->
    ok.

put(Id, Key, Value) ->
    nkservice_srv:put(Id, Key, Value).


%% @doc Inserts a value in service's store
-spec put_new(id(), term(), term()) ->
    true | false.

put_new(Id, Key, Value) ->
    nkservice_srv:put_new(Id, Key, Value).


%% @doc Deletes a value from service's store
-spec del(id(), term()) ->
    ok.

del(Id, Key) ->
    nkservice_srv:del(Id, Key).

