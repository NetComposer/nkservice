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

-export([start/2, stop/1, reload/1, update/2, get_all/0, get_all/1]).
-export([get/2, get/3, put/3, put_new/3, del/2]).
-export([get_listeners/2]).
-export([call/2, call/3, cast/2, get_pid/1, get_timestamp/1]).
-export_type([id/0, class/0, spec/0, config/0, service/0]).
-export_type([error/0, event/0]).
-export_type([user_id/0, user_state/0, session_id/0]).
-export_type([req_cmd/0, req_data/0, req_tid/0]).


-include_lib("nkpacket/include/nkpacket.hrl").


%% ===================================================================
%% Types
%% ===================================================================

%% Service's id must be an atom
-type id() :: atom().

%% Service's class
-type class() :: term().



%% Service specification
-type spec() ::
	#{
        plugins => [atom()],
		class => term(),                % Only to find services
        name => binary(),                 % Optional name
        %listen => listen_spec(),
        log_level => log_level(),
        debug => [atom() | {atom, term()}], % Specific to each plugin
        config => map()                 % Any user info, usually one entry per plugin
	}.

-type config() :: #{term() => term()}.

-type log_level() :: 0..8 |
    none | emergency | alert | critical | error | warning | notice | info |debug.


-type service() ::
    #{
        id => atom(),
        plugins => [atom()],
        name => term(),                 % Optional name
        class => class(),               % Optional class
        uuid => binary(),               % Each service is assigned an uuid
        log_level => log_level(),
        timestamp => nklib_util:m_timestamp(),  % Started time
        config => config(),
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
            Service = #{
                id => Id,
                uuid => nkservice_util:update_uuid(Id, Spec)
            },
            case nkservice_config:config_service(Spec, Service) of
                {ok, Service2} ->
                    lager:error("NKLOG S2 ~p", [Service2]),
                    nkservice_srv_sup:start_service(Service2);
                {error, Error} ->
                    {error, Error}
            end
    end.



%%    try
%%        case nkservice_srv_sup:pre_start_service(Id) of
%%            ok ->
%%                ok;
%%            {error, PreError} ->
%%                throw(PreError)
%%        end,
%%        Service = #{
%%            id => Id,
%%            uuid => nkservice_util:update_uuid(Id, Spec)
%%        },
%%        case nkservice_config:config_service(Spec, Service) of
%%            {ok, Service4} ->
%%                case nkservice_srv_sup:start_service(Service4) of
%%                    ok ->
%%                        lager:notice("NkSERVICE '~s' has started", [Id]),
%%                        {ok, whereis(Id)};
%%                    {error, Error} ->
%%                        {error, Error}
%%                end;
%%            {error, Error} ->
%%                throw(Error)
%%        end
%%    catch
%%        throw:{already_started, Pid} ->
%%            {error, {already_started, Pid}};
%%        throw:Throw ->
%%            nkservice_srv_sup:stop_service(Id),
%%            {error, Throw};
%%        error:EError ->
%%            Trace = erlang:get_stacktrace(),
%%            nkservice_srv_sup:stop_service(Id),
%%            {error, {EError, Trace}}
%%    end.


%% @doc Stops a service
-spec stop(id()) ->
    ok | {error, not_running|term()}.

stop(Id) ->
    nkservice_srv_sup:stop_service(Id).




%% @doc Reloads a configuration
-spec reload(id()) ->
    ok | {error, term()}.

reload(ServiceId) ->
    update(ServiceId, #{}).


%% @doc Updates a service configuration
%% New transports can be added, but old transports will not be automatically
%% stopped. Use get_listeners/2 to find transports and stop them manually.
%% (the info on get_listeners/2 will not be updated).
-spec update(id(), spec()) ->
    ok | {error, term()}.

update(ServiceId, UserSpec) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            call(Id, {nkservice_update, UserSpec}, 30000);
        not_found ->
            {error, service_not_found}
    end.

    
%% @doc Gets all started services
-spec get_all() ->
    [{id(), binary(), class(), pid()}].

get_all() ->
    [{Id, Id:name(), Class, Pid} || 
     {{Id, Class}, Pid}<- nklib_proc:values(nkservice_srv)].


%% @doc Gets all started services
-spec get_all(class()) ->
    [{id(), binary(), pid()}].

get_all(Class) ->
    [{Id, Name, Pid} || {Id, Name, C, Pid} <- get_all(), C==Class].



%% @doc Gets a value from service's store
-spec get(id(), term()) ->
    term().

get(ServiceId, Key) ->
    get(ServiceId, Key, undefined).


%% @doc Gets a value from service's store
-spec get(id(), term(), term()) ->
    term().

get(ServiceId, Key, Default) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            nkservice_srv:get(Id, Key, Default);
        not_found ->
            error(service_not_found)
    end.


%% @doc Inserts a value in service's store
-spec put(id(), term(), term()) ->
    ok.

put(ServiceId, Key, Value) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            nkservice_srv:put(Id, Key, Value),
            ok;
        not_found ->
            error(service_not_found)
    end.


%% @doc Inserts a value in service's store
-spec put_new(id(), term(), term()) ->
    true | false.

put_new(ServiceId, Key, Value) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            nkservice_srv:put_new(Id, Key, Value);
        not_found ->
            error(service_not_found)
    end.


%% @doc Deletes a value from service's store
-spec del(id(), term()) ->
    ok.

del(ServiceId, Key) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            nkservice_srv:del(Id, Key),
            ok;
        not_found ->
            error(service_not_found)
    end.


%% @doc Synchronous call to the service's gen_server process
-spec call(id(), term()) ->
    term().

call(ServiceId, Term) ->
    call(ServiceId, Term, 5000).


%% @doc Synchronous call to the service's gen_server process with a timeout
-spec call(id(), term(), pos_integer()|infinity|default) ->
    term().

call(ServiceId, Term, Time) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} -> 
            gen_server:call(Id, Term, Time);
        not_found -> 
            error(service_not_found)
    end.


%% @doc Asynchronous call to the service's gen_server process
-spec cast(id(), term()) ->
    term().

cast(ServiceId, Term) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} -> 
            gen_server:cast(Id, Term);
        not_found -> 
            error(service_not_found)
    end.




%% @doc Gets current service timestamp
-spec get_timestamp(id()) ->
    nklib_util:l_timestamp().

get_timestamp(ServiceId) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} -> Id:timestamp();
        not_found -> error(service_not_found)
    end.


%% @doc Gets the internal name of an existing service
-spec get_pid(id()) ->
    pid() | undefined.

get_pid(ServiceId) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            case whereis(Id) of
                Pid when is_pid(Pid) -> Pid;
                _ -> undefined
            end;
        not_found ->
            undefined
    end.


%% @doc Get all current listeners for a plugin
-spec get_listeners(id(), atom()) ->
    [nkpacket:listen_id()].

get_listeners(SrvId, Plugin) ->
    All = nkservice_srv:get_item(SrvId, listen_ids),
    maps:get(Plugin, All, []).


