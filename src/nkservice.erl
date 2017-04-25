%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Carlos Gonzalez Florido.  All Rights Reserved.
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
-export([call/2, call/3, cast/2, get_data/2, get_pid/1, get_timestamp/1]).
-export_type([id/0, name/0, class/0, spec/0, config/0, service/0]).
-export_type([lang/0, error/0]).
-export_type([user_id/0, user_session/0, event/0]).


-include_lib("nkpacket/include/nkpacket.hrl").


%% ===================================================================
%% Types
%% ===================================================================

%% Service's id must be an atom
-type id() :: atom().

%% Service's name
-type name() :: term().

%% Service's class
-type class() :: term().

%% Service specification
%% - class: only used to find services
%% - plugins: list of dependant plugins
%% - callback: if present, will be the top-level plugin
%%
-type spec() :: 
	#{
		class => term(),              % Only to find services
		plugins => [module()],
        callback => module(),         % If present, will be the top-level plugin
        term() => term()              % Any user info
	}.

-type config() :: #{term() => term()}.

-type service() ::
    #{
        id => atom(),
        name => term(),
        class => class(),
        plugins => [atom()],
        callback => module(),
        log_level => integer(),
        uuid => binary(),
        timestamp => nklib_util:l_timestamp(),
        config => config(),
        listen => #{Plugin::atom() => list()},
        listen_ids => #{Plugin::atom() => list()},
        term() => term()           % "config_(plugin)" values
    }.


%% See nkservice_callbacks:error_code/1
-type error() :: term().

%% See nkservice_callbacks:error_code/1
-type lang() :: any | atom().


-type service_select() :: id() | name().

-type user_id() :: binary().
-type user_session() :: binary().

-type event() :: nkevent:event().



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts a new service.
-spec start(name(), spec()) ->
    {ok, id()} | {error, term()}.

start(Name, UserSpec) ->
    Id = nkservice_util:make_id(Name),
    try
        case nkservice_srv:get_srv_id(Id) of
            {ok, OldId} -> 
                case is_pid(whereis(OldId)) of
                    true -> throw(already_started);
                    false -> ok
                end;
            not_found -> 
                ok
        end,
        case nkservice_srv_sup:pre_start_service(Id) of
            ok -> ok;
            {error, PreError} -> throw(PreError)
        end,
        Service = #{
            id => Id,
            name => Name,
            uuid => nkservice_util:update_uuid(Id, Name)
        },
        case nkservice_config:config_service(UserSpec, Service) of
            {ok, Service2} ->
                case nkservice_srv_sup:start_service(Service2) of
                    ok ->
                        lager:notice("Service '~s' (~p) has started", [Name, Id]),
                        {ok, Id};
                    {error, Error} -> 
                        {error, Error}
                end;
            {error, Error} ->
                throw(Error)
        end
    catch
        throw:already_started ->
            {error, already_started};
        throw:Throw -> 
            nkservice_srv_sup:stop_service(Id),
            {error, Throw};
        error:EError -> 
            nkservice_srv_sup:stop_service(Id),
            {error, EError}
    end.


%% @doc Stops a service
-spec stop(service_select()) ->
    ok | {error, not_running}.

stop(Service) ->
    case nkservice_srv:get_srv_id(Service) of
        {ok, Id} ->
            % nkservice_srv:stop_all(Id),
            case nkservice_srv_sup:stop_service(Id) of
                ok -> 
                    ok;
                error -> 
                    {error, internal_error}
            end;
        not_found ->
            {error, not_running}
    end.



%% @doc Reloads a configuration
-spec reload(service_select()) ->
    ok | {error, term()}.

reload(ServiceId) ->
    update(ServiceId, #{}).


%% @doc Updates a service configuration
%% New transports can be added, but old transports will not be automatically
%% stopped. Use get_listeners/2 to find transports and stop them manually.
%% (the info on get_listeners/2 will not be updated).
-spec update(service_select(), spec()) ->
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
    [{id(), name(), class(), pid()}].

get_all() ->
    [{Id, Id:name(), Class, Pid} || 
     {{Id, Class}, Pid}<- nklib_proc:values(nkservice_srv)].


%% @doc Gets all started services
-spec get_all(class()) ->
    [{id(), name(), pid()}].

get_all(Class) ->
    [{Id, Name, Pid} || {Id, Name, C, Pid} <- get_all(), C==Class].



%% @doc Gets a value from service's store
-spec get(service_select(), term()) ->
    term().

get(ServiceId, Key) ->
    get(ServiceId, Key, undefined).


%% @doc Gets a value from service's store
-spec get(service_select(), term(), term()) ->
    term().

get(ServiceId, Key, Default) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            nkservice_srv:get(Id, Key, Default);
        not_found ->
            error(service_not_found)
    end.


%% @doc Inserts a value in service's store
-spec put(service_select(), term(), term()) ->
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
-spec put_new(service_select(), term(), term()) ->
    true | false.

put_new(ServiceId, Key, Value) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            nkservice_srv:put_new(Id, Key, Value);
        not_found ->
            error(service_not_found)
    end.


%% @doc Deletes a value from service's store
-spec del(service_select(), term()) ->
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
-spec call(service_select(), term()) ->
    term().

call(ServiceId, Term) ->
    call(ServiceId, Term, 5000).


%% @doc Synchronous call to the service's gen_server process with a timeout
-spec call(service_select(), term(), pos_integer()|infinity|default) ->
    term().

call(ServiceId, Term, Time) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} -> 
            gen_server:call(Id, Term, Time);
        not_found -> 
            error(service_not_found)
    end.


%% @doc Asynchronous call to the service's gen_server process
-spec cast(service_select(), term()) ->
    term().

cast(ServiceId, Term) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} -> 
            gen_server:cast(Id, Term);
        not_found -> 
            error(service_not_found)
    end.


%% @doc Gets current service configuration
-spec get_data(service_select(), atom()) ->
   term().

get_data(ServiceId, Term) ->
    nkservice_srv:get_from_mod(ServiceId, Term).


%% @doc Gets current service timestamp
-spec get_timestamp(service_select()) ->
    nklib_util:l_timestamp().

get_timestamp(ServiceId) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} -> Id:timestamp();
        not_found -> error(service_not_found)
    end.


%% @doc Gets the internal name of an existing service
-spec get_pid(service_select()) ->
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
-spec get_listeners(service_select(), atom()) ->
    [nkpacket:listen_id()].

get_listeners(SrvId, Plugin) ->
    All = nkservice_srv:get_item(SrvId, listen_ids),
    maps:get(Plugin, All, []).


