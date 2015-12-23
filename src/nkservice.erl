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

-export([register_plugin/2]).
-export([start/2, stop/1, update/2, get_all/0, get_all/1]).
-export([get/2, get/3, put/3, put_new/3, del/2]).
-export([call/2, call/3, cast/2, get_data/2, get_pid/1, get_timestamp/1]).
-export_type([id/0, name/0, class/0, user_spec/0, service/0, plugin_spec/0]).

-type service_select() :: id() | name().

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



%% ===================================================================
%% Public
%% ===================================================================

-spec register_plugin(atom(), plugin_spec()) ->
    ok.

register_plugin(Name, Spec) when is_atom(Name), is_map(Spec) ->
    nkservice_app:put({plugin, Name}, Spec).


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
        Syntax = nkservice_syntax:syntax(), 
        Defaults = nkservice_syntax:defaults(),
        ParseOpts = #{return=>map, defaults=>Defaults},
        Service1 = case nklib_config:parse_config(UserSpec, Syntax, ParseOpts) of
            {ok, Parsed1, _} -> Parsed1;
            {error, ParseError1} -> throw(ParseError1)
        end,
        Plugins1 = maps:get(plugins, Service1),
        CallBack = maps:get(callback, Service1, none),
        Plugins2 = case nkservice_cache:get_plugins(Plugins1, CallBack) of
            {ok, AllPlugins} -> 
                AllPlugins;
            {error, PlugError} -> 
                throw(PlugError)
        end,
        {UserSpec2, Cache, Transps} = plugin_syntax(Plugins2, UserSpec, #{}, []),
        Service2 = Service1#{id=>Id, name=>Name2, transports=>Transps},
        case nkservice_srv_sup:start_service(UserSpec2, Service2) of
            ok ->
                {ok, Id};
            {error, Error} -> 
                {error, Error}
        end
    catch
        throw:Throw -> {error, Throw}
    end.



%% @private
plugin_syntax([], UserSpec, Cache, Transps) ->
    {UserSpec, Cache, Transps};

plugin_syntax([Plugin|Rest], UserSpec, Cache, Transps) ->
    Data = case nkservice_app:get({plugin, Plugin}) of
        Map when is_map(Map) -> Map;
        undefined -> throw({unknown_plugin, Plugin})
    end,
    Syntax = maps:get(syntax, Data, #{}),
    Defaults = maps:get(defaults, Data, #{}),
    Opts = #{return=>map, defaults=>Defaults},
    UserSpec2 = case nklib_config:parse_config(UserSpec, Syntax, Opts) of
        {ok, Parsed1, _} -> maps:merge(UserSpec, Parsed1);
        {error, Error} -> throw({syntax_error, {Plugin, Error}})
    end,
    Callback = maps:get(callback, Data, Plugin),
    code:ensure_loaded(Callback),
    UserSpec3 = case nklib_util:apply(Callback, plugin_prepare, [UserSpec2]) of
        not_exported -> UserSpec2;
        {ok, Parsed2} -> {ok, Parsed2}
    end,
    case nklib_util:apply(Callback, plugin_cache, [UserSpec3]) of
        not_exported -> UserCache = #{};
        {ok, UserCache} -> ok
    end,
    case nklib_util:apply(Callback, plugin_transports, [UserSpec3]) of
        not_exported -> 
            UserTransps = [];
        {ok, UserTranspList} -> 
            case nkservice_util:parse_transports(UserTranspList) of
                {ok, UserTransps} -> ok;
                error -> UserTransps = throw({invalid_pluign_transport, Plugin})
            end
    end,
    Cache2 = maps:merge(Cache, UserCache),
    Transps2 = Transps ++ UserTransps,
    plugin_syntax(Rest, UserSpec3, Cache2, Transps2).
    


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
-spec update(service_select(), nkservice:user_spec()) ->
    ok | {error, term()}.

update(Service, Spec) ->
    case nkservice_srv:get_srv_id(Service) of
        {ok, Id} ->
            call(Id, {nkservice_update, Spec}, 30000);
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

get(Service, Key) ->
    get(Service, Key, undefined).

%% @doc Gets a value from service's store
-spec get(service_select(), term(), term()) ->
    term().

get(Service, Key, Default) ->
    case nkservice_srv:get_srv_id(Service) of
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

put(Service, Key, Value) ->
    case nkservice_srv:get_srv_id(Service) of
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

put_new(Service, Key, Value) ->
    case nkservice_srv:get_srv_id(Service) of
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

del(Service, Key) ->
    case nkservice_srv:get_srv_id(Service) of
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

call(Service, Term) ->
    call(Service, Term, 5000).


%% @doc Synchronous call to the service's gen_server process with a timeout
-spec call(service_select(), term(), pos_integer()|infinity|default) ->
    term().

call(Service, Term, Time) ->
    case nkservice_srv:get_srv_id(Service) of
        {ok, Id} -> 
            gen_server:call(Id, Term, Time);
        not_found -> 
            error(service_not_found)
    end.


%% @doc Asynchronous call to the service's gen_server process
-spec cast(service_select(), term()) ->
    term().

cast(Service, Term) ->
    case nkservice_srv:get_srv_id(Service) of
        {ok, Id} -> 
            gen_server:cast(Id, Term);
        not_found -> 
            error(service_not_found)
    end.


%% @doc Gets current service configuration
-spec get_data(service_select(), atom()) ->
   term().

get_data(Service, Term) ->
    nkservice_srv:get_from_mod(Service, Term).


%% @doc Gets current service timestamp
-spec get_timestamp(service_select()) ->
    nklib_util:l_timestamp().

get_timestamp(Service) ->
    case nkservice_srv:get_srv_id(Service) of
        {ok, Id} -> Id:timestamp();
        not_found -> error(service_not_found)
    end.


%% @doc Gets the internal name of an existing service
-spec get_pid(service_select()) ->
    pid() | undefined.

get_pid(Service) ->
    case nkservice_srv:get_srv_id(Service) of
        {ok, ServiceId} ->
            case whereis(ServiceId) of
                Pid when is_pid(Pid) -> Pid;
                _ -> undefined
            end;
        not_found ->
            undefined
    end.







    