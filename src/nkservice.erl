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

-export_type([id/0, name/0, spec/0, class/0]).
-export([start/2, stop/1, update/2, get_all/0, get_all/1]).
-export([get/2, get/3, put/3, put_new/3, del/2]).
-export([call/2, call/3, cast/2, get_spec/1]).

-type service_select() :: nkservice:id() | nkservice:name().


%% ===================================================================
%% Callbacks
%% ===================================================================

%% Plugins and services must implement this behaviour.

%% @doc Called to get the list of plugins this service/plugin depend on.
-callback plugin_deps() ->
    [module()].

%% @doc Called when the plugin or service is about to start or it is re-configured
%% It receives the full configuration, and must:
%% - parse its specific configuration options, and replace the values in the
%%   config with the parsed ones.
%% - add or updated the values of the 'cache' key. They will be expanded as
%%   functions cache_... at the compiled run-time module
%% - add or updated the values of the 'transport' key. They will be expanded as
%%   functions cache_... at the compiled run-time module
-callback plugin_start(spec()) ->
    {ok, spec()} | {stop, term()}.


%% @doc Called when the plugin or service is about to stop
%% It receives the full configuration, and must:
%% - remove any specific configuration options from the config
%% - remove specific configuration options from cache and transports
-callback plugin_stop(nkservice:id(), nkservice:spec()) ->
    {ok, spec()} | {stop, term()}.



%% ===================================================================
%% Types
%% ===================================================================

%% Service's name
-type name() :: term().

%% Service's id must be an atom
-type id() :: atom().

%% Service's class
-type class() :: term().

%% Service specification
%% - class: only used to find services
%% - plugins: list of dependant plugins
%% - callback: if present, will be the top-level plugin
%% - transports to start
%%
-type spec() :: 
	#{
		class => term(),
		plugins => [module()],
        callback => module(),
        transports => string() | binary() | [string() | binary()],
        term() => term()
	}.


% -type info() ::
%     #{
%         class => class(),
%         status => ok | starting | error,
%         error => binary(),
%         pid => pid()
%     }.


%% ===================================================================
%% Public
%% ===================================================================



%% @doc Starts a new service.
-spec start(nkservice:name(), nkservice:spec()) ->
    {ok, id()} | {error, term()}.

start(Name, Spec) ->
    Id = nkservice_util:make_id(Name),
    try
        case nkservice_server:get_srv_id(Id) of
            {ok, OldId} -> 
                case is_pid(whereis(OldId)) of
                    true -> throw(already_started);
                    false -> ok
                end;
            not_found -> 
                ok
        end,
        Spec1 = case nkservice_util:parse_syntax(Spec) of
            {ok, Parsed} -> Parsed;
            {error, ParseError} -> throw(ParseError)
        end,
        CacheKeys = maps:keys(nkservice_syntax:defaults()),
        ConfigCache = maps:with(CacheKeys, Spec1),
        Spec2 = Spec1#{id=>Id, name=>Name, cache=>ConfigCache},
        % lager:warning("Parsed: ~p", [Parsed2]),
        case nkservice_srv_sup:start_service(Spec2) of
            ok ->
                {ok, Id};
            {error, Error} -> 
                {error, Error}
        end
    catch
        throw:Throw -> {error, Throw}
    end.



%% @doc Stops a service
-spec stop(service_select()) ->
    ok | {error, service_not_found}.

stop(Srv) ->
    case nkservice_server:get_srv_id(Srv) of
        {ok, Id} ->
            case nkservice_srv_sup:stop_service(Id) of
                ok -> 
                    ok;
                error -> 
                    {error, service_not_found}
            end;
        not_found ->
            {error, service_not_found}
    end.



%% @private
-spec update(service_select(), nkservice:spec()) ->
    ok | {error, term()}.

update(Srv, Spec) ->
    case nkservice_server:get_srv_id(Srv) of
        {ok, Id} ->
            call(Id, {nkservice_update, Spec}, 30000);
        not_found ->
            {error, service_not_found}
    end.

    
%% @doc Gets all started services
-spec get_all() ->
    [{nkservice:id(), nkservice:name(), nkservice:class(), pid()}].

get_all() ->
    [{Id, Id:name(), Class, Pid} || 
     {{Id, Class}, Pid}<- nklib_proc:values(nkservice_server)].


%% @doc Gets all started services
-spec get_all(nkservice:class()) ->
    [{nkservice:id(), nkservice:name(), pid()}].

get_all(Class) ->
    [{Id, Name, Pid} || {Id, Name, C, Pid} <- get_all(), C==Class].



%% @doc Gets a value from service's store
-spec get(service_select(), term()) ->
    term().

get(Srv, Key) ->
    get(Srv, Key, undefined).

%% @doc Gets a value from service's store
-spec get(service_select(), term(), term()) ->
    term().

get(Srv, Key, Default) ->
    case nkservice_server:get_srv_id(Srv) of
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

put(Srv, Key, Value) ->
    case nkservice_server:get_srv_id(Srv) of
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

put_new(Srv, Key, Value) ->
    case nkservice_server:get_srv_id(Srv) of
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

del(Srv, Key) ->
    case nkservice_server:get_srv_id(Srv) of
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

call(Srv, Term) ->
    call(Srv, Term, 5000).


%% @doc Synchronous call to the service's gen_server process with a timeout
-spec call(service_select(), term(), pos_integer()|infinity|default) ->
    term().

call(Srv, Term, Time) ->
    case nkservice_server:get_srv_id(Srv) of
        {ok, Id} -> 
            gen_server:call(Id, Term, Time);
        not_found -> 
            error(service_not_found)
    end.


%% @doc Asynchronous call to the service's gen_server process
-spec cast(service_select(), term()) ->
    term().

cast(Srv, Term) ->
    case nkservice_server:get_srv_id(Srv) of
        {ok, Id} -> 
            gen_server:cast(Id, Term);
        not_found -> 
            error(service_not_found)
    end.


%% @doc Gets current service configuration
-spec get_spec(service_select()) ->
    nkservice:spec().

get_spec(Srv) ->
    nkservice_server:get_cache(Srv, spec).


