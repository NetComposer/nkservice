%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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

-export([start/2, stop/1, update/2, get_all/0, get_all/1]).
-export([get/2, get/3, put/3, put_new/3, del/2]).
-export([call/2, call/3, cast/2, get_data/2, get_pid/1, get_timestamp/1]).
-export_type([id/0, name/0, class/0, user_spec/0, service/0]).


-include_lib("nkpacket/include/nkpacket.hrl").


%% ===================================================================
%% Types
%% ===================================================================

%% Service's id must be an atom
-type id() :: atom().

%% Service's name
-type name() :: binary().

%% Service's class
-type class() :: term().

%% Service specification
%% - class: only used to find services
%% - plugins: list of dependant plugins
%% - callback: if present, will be the top-level plugin
%% - transports to start
%%
-type user_spec() :: 
	#{
		class => term(),              % Only to find services
		plugins => [module()],
        callback => module(),         % If present, will be the top-level plugin
        ?SERVICE_TYPES,
        ?TLS_SYNTAX,
        term() => term()              % Any user info
	}.


-type service() ::
    #{
        id => atom(),
        name => binary(),
        class => class(),
        plugins => [atom()],
        callback => module(),
        log_level => integer(),
        transports => term(),
        cache => #{term() => term()},   % This will be first-level functions
        uuid => binary(),
        timestamp => nklib_util:l_timestamp(),
        term() => term()                % Per-plugin data, copied to service's state
    }.

-type service_select() :: id() | name().



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts a new service.
-spec start(name(), user_spec()) ->
    {ok, id()} | {error, term()}.

start(Name, UserSpec) ->
    Name2 = nklib_util:to_binary(Name),
    Id = nkservice_util:make_id(Name2),
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
        Service = #{
            id => Id,
            name => Name2,
            uuid => nkservice_util:update_uuid(Id, Name2),
            timestamp => nklib_util:l_timestamp()
        },
        case nkservice_util:update_service(UserSpec, Service) of
            {ok, Service2} ->
                nkservice_util:make_cache(Service2),
                {ok, Service2};
                % case nkservice_srv_sup:start_service(Service2) of
                %     ok ->
                %         {ok, Id};
                %     {error, Error} -> 
                %         {error, Error}
                % end;
            {error, Error} ->
                throw(Error)
        end
    catch
        throw:Throw -> {error, Throw}
    end.


%% @doc Stops a service
-spec stop(service_select()) ->
    ok | {error, not_running}.

stop(Service) ->
    case nkservice_srv:get_srv_id(Service) of
        {ok, Id} ->
            case nkservice_srv_sup:stop_service(Id) of
                ok -> 
                    ok;
                error -> 
                    {error, not_running}
            end;
        not_found ->
            {error, not_running}
    end.



%% @private
-spec update(service_select(), user_spec()) ->
    ok | {error, term()}.

update(ServiceId, UserSpec) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            case nkservice_util:parse_plugins(UserSpec) of
                {ok, UserSpec2, Service} ->
                    call(Id, {nkservice_update, UserSpec2, Service}, 30000);
                {error, Error} ->
                    {error, Error}
            end;
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
            case catch ets:lookup(Id, Key) of
                [{_, Value}] -> Value;
                [] -> Default;
                _ -> error(service_not_found)
            end;
        not_found ->
            error(service_not_found)
    end.


%% @doc Inserts a value in service's store
-spec put(service_select(), term(), term()) ->
    ok.

put(ServiceId, Key, Value) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            case catch ets:insert(Id, {Key, Value}) of
                true -> ok;
                _ -> error(service_not_found)
            end;
        not_found ->
            error(service_not_found)
    end.


%% @doc Inserts a value in service's store
-spec put_new(service_select(), term(), term()) ->
    true | false.

put_new(ServiceId, Key, Value) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            case catch ets:insert_new(Id, {Key, Value}) of
                true -> true;
                false -> false;
                _ -> error(service_not_found)
            end;
        not_found ->
            error(service_not_found)
    end.


%% @doc Deletes a value from service's store
-spec del(service_select(), term()) ->
    ok.

del(ServiceId, Key) ->
    case nkservice_srv:get_srv_id(ServiceId) of
        {ok, Id} ->
            case catch ets:delete(Id, Key) of
                true -> ok;
                _ -> error(service_not_found)
            end;
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
        {ok, ServiceId} ->
            case whereis(ServiceId) of
                Pid when is_pid(Pid) -> Pid;
                _ -> undefined
            end;
        not_found ->
            undefined
    end.







    