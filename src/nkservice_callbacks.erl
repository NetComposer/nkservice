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

%% @doc Default plugin callbacks
-module(nkservice_callbacks).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([msg/1, msg/2, i18n/3]).
-export([service_event/3, service_timed_check/2]).
-export([service_init/2, service_handle_call/4, service_handle_cast/3,
         service_handle_info/3, service_code_change/4, service_terminate/3]).
-export([service_master_init/2, service_master_leader/4, service_master_find_uid/2,
         service_master_handle_call/3, service_master_handle_cast/2,
         service_master_handle_info/2, service_leader_code_change/3,
         service_master_terminate/2]).
-export([actor_activate/2, actor_config/1, actor_init/1, actor_terminate/2, actor_stop/2,
         actor_get/2, actor_event/2, actor_link_event/4, actor_sync_op/3, actor_async_op/2,
         actor_save/2, actor_delete/1, actor_link_down/2, actor_enabled/2, actor_next_status_timer/1,
         actor_alarms/1, actor_heartbeat/1,
         actor_handle_call/3, actor_handle_cast/2, actor_handle_info/2, actor_conflict_detected/3]).
-export([actor_do_active/1, actor_do_expired/1]).
-export([actor_db_find/2, actor_db_create/2, actor_db_read/2,
         actor_db_update/2, actor_db_delete/3, actor_db_search/3,
         actor_db_aggregate/3, actor_db_get_query/3,
         actor_db_get_service/2, actor_db_update_service/3]).
-export([nkservice_find_uid/2, nkservice_make_srv_id/2]).

-export_type([continue/0]).

-include_lib("nkpacket/include/nkpacket.hrl").
-include_lib("nkevent/include/nkevent.hrl").
-include("nkservice.hrl").
-include("nkservice_actor.hrl").

-type continue() :: continue | {continue, list()}.
%-type req() :: #nkreq{}.
-type user_state() :: map().
-type service() :: nkservice:service().



%% ===================================================================
%% Errors Callbacks
%% ===================================================================


%% @doc
-spec msg(nkservice:lang(), nkservice:msg()) ->
    atom() |
    tuple() |
    list() |
    {atom(), string()} |
    {Fmt::string(), Vals::string()} |
    {atom(), Fmt::string(), Vals::string()}.

msg(SrvId, Msg) ->
    ?CALL_SRV(SrvId, msg, [Msg]).


%% @doc
-spec msg(nkservice:msg()) ->
    atom() |
    tuple() |
    list() |
    {atom(), string()} |
    {Fmt::string(), Vals::string()} |
    {atom(), Fmt::string(), Vals::string()}.


msg(actor_expired)	                -> "Actor has expired";
msg(actor_has_linked_actors)	    -> "Actor has linked actors";
msg(actor_is_not_activable)	        -> "Actor is not activable";
msg(already_authenticated)	        -> "Already authenticated";
msg(already_started)	            -> "Already started";
msg(already_uploaded)   		    -> "Already uploaded";
msg(api_delete) 				    -> "API delete received";
msg(api_stop) 				        -> "API stop received";
msg(data_not_available)   	        -> "Data is not available";
msg(delete_too_deep)                -> "DELETE is too deep";
msg(duplicated_session_id)	        -> "Duplicated session";
msg({field_missing, Txt})	        -> {"Missing field: '~s'", [Txt]};
msg({field_invalid, Txt})	        -> {"Field '~s' is invalid", [Txt]};
msg({field_unknown, Txt})	        -> {"Unknown field: '~s'", [Txt]};
msg(file_read_error)   		        -> "File read error";
msg(internal_error)			        -> "Internal error";
msg({internal_error, Ref})	        -> {"Internal error: ~s", [Ref]};
msg({invalid_action, Txt})          -> {"Invalid action '~s'", [Txt]};
msg({invalid_state, St}) 	        -> {"Invalid state: ~s", [St]};
msg({invalid_value, V}) 		    -> {"Invalid value: '~s'", [V]};
msg(invalid_json) 			        -> "Invalid JSON";
msg(invalid_operation) 		        -> "Invalid operation";
msg(invalid_login_request)          -> "Invalid login request";
msg(invalid_parameters) 		    -> "Invalid parameters";
msg(invalid_password) 		        -> "Invalid password";
msg(invalid_reply) 			        -> "Invalid reply";
msg(invalid_role)			        -> "Invalid role";
msg(invalid_session_id)		        -> "Invalid session";
msg(invalid_state) 			        -> "Invalid state";
msg(invalid_uri) 			        -> "Invalid Uri";
msg(invalid_object_id) 		        -> "Invalid ObjectId";
msg(json_encode_error)              -> "JSON encode error";
msg(leader_is_down)                 -> "Service leader is down";
msg(linked_actor_unknown)           -> "Linked actor not found";
msg({linked_actor_unknown, Txt})    -> {"Linked actor '~s', not found", [Txt]};
msg(max_disabled_time)              -> "Maximum disabled time reached";
msg(method_not_allowed)             -> "Method not allowed";
msg(missing_id)				        -> "Missing Id";
msg(no_password) 		            -> "No supplied password";
msg(no_usages)           		    -> "No remaining usages";
msg(normal)           		        -> "Normal termination";
msg(normal_termination) 		    -> "Normal termination";
msg(not_authenticated)		        -> "Not authenticated";
msg(not_found) 				        -> "Not found";
msg(not_started) 				    -> "Not yet started";
msg(not_implemented) 		        -> "Not implemented";
msg(process_down)  			        -> "Process failed";
msg(process_not_found) 		        -> "Process not found";
msg(registered_down) 	            -> "Registered process stopped";
msg({service_not_available, S}) 	-> {"Service '~s' is not available", [S]};
msg(service_not_found) 		        -> "Service not found";
msg(session_not_found) 		        -> "Session not found";
msg(session_stop) 			        -> "Session stop";
msg(session_timeout) 		        -> "Session timeout";
msg({syntax_error, Txt})		    -> {"Syntax error: '~s'", [Txt]};
msg(timeout) 				        -> "Timeout";
msg(ttl_timeout) 			        -> "TTL Timeout";
msg(unauthorized) 			        -> "Unauthorized";
msg(uid_not_allowed) 	            -> "UID is not allowed";
msg(uniqueness_violation)	        -> "Actor is not unique";
msg({unknown_command, Txt})	        -> {"Unknown command '~s'", [Txt]};
msg(unknown_peer) 			        -> "Unknown peer";
msg(unknown_op)   			        -> "Unknown operation";
msg(updated_invalid_field) 	        -> "Tried to update invalid field";
msg({updated_invalid_field, Txt})   -> {"Tried to update invalid field: '~s'", [Txt]};
msg(user_not_found)			        -> "User not found";
msg({user_not_found, User})	        -> {"User not found: '~s'", [User]};
msg(user_stop) 				        -> "User stop";
msg(_)   		                    -> continue.



%% ===================================================================
%% i18n
%% ===================================================================


%% @doc
-spec i18n(nkservice:id(), nklib_i18n:key(), nklib_i18n:lang()) ->
    <<>> | binary().

i18n(SrvId, Key, Lang) ->
    nklib_i18n:get(SrvId, Key, Lang).


%% ===================================================================
%% Service Callbacks
%% ===================================================================

%% @doc
-spec service_event(nkservice:event(), service(), user_state()) ->
    {ok, user_state()}.

service_event(_Event, _Service, State) ->
    {ok, State}.


%% @doc Called periodically
-spec service_timed_check(service(), user_state()) ->
    {ok, user_state()}.

service_timed_check(_Service, State) ->
    {ok, State}.



%% @doc Called when a new service starts, first for the top-level plugin
-spec service_init(service(), user_state()) ->
	{ok, user_state()} | {stop, term()}.

service_init(_Service, UserState) ->
	{ok, UserState}.


%% @doc Called when the service process receives a handle_call/3.
-spec service_handle_call(term(), {pid(), reference()}, service(), user_state()) ->
	{reply, term(), user_state()} | {noreply, user_state()} | continue().

service_handle_call(Msg, _From, _Service, State) ->
    lager:error("Module nkservice_srv received unexpected call ~p", [Msg]),
    {noreply, State}.


%% @doc Called when the NkApp process receives a handle_cast/3.
-spec service_handle_cast(term(), service(), user_state()) ->
	{noreply, user_state()} | continue().

service_handle_cast(Msg, _Service, State) ->
    lager:error("Module nkservice_srv received unexpected cast ~p", [Msg]),
	{noreply, State}.


%% @doc Called when the NkApp process receives a handle_info/3.
-spec service_handle_info(term(), service(), user_state()) ->
	{noreply, user_state()} | continue().

service_handle_info({'EXIT', _, normal}, _Service, State) ->
	{noreply, State};

service_handle_info(Msg, _Service, State) ->
    lager:notice("Module nkservice_srv received unexpected info ~p", [Msg]),
	{noreply, State}.


-spec service_code_change(term()|{down, term()}, service(), user_state(), term()) ->
    ok | {ok, service()} | {error, term()} | continue().

service_code_change(OldVsn, _Service, State, Extra) ->
	{continue, [OldVsn, State, Extra]}.


%% @doc Called when a service is stopped
-spec service_terminate(term(), service(), service()) ->
	{ok, service()}.

service_terminate(_Reason, _Service, State) ->
	{ok, State}.



%% ===================================================================
%% Service Master Callbacks
%% These callbacks are called by the service master process running
%% at each node. One of the will be elected master
%% ===================================================================


%% @doc
-spec service_master_init(nkservice:id(), user_state()) ->
    {ok, user_state()} | {stop, term()}.

service_master_init(_SrvId, UserState) ->
    {ok, UserState}.


%% @doc
-spec service_master_leader(nkservice:id(), boolean(), pid()|undefined, user_state()) ->
    {ok, user_state()}.

service_master_leader(_SrvId, _IsLeader, _Pid, UserState) ->
    {ok, UserState}.


%% @doc Find an UUID in global database
-spec service_master_find_uid(UID::binary(), user_state()) ->
    {reply, #actor_id{}, user_state()} |
    {stop, actor_not_found|term(), user_state()} |
    continue().

service_master_find_uid(_UID, UserState) ->
    {stop, actor_not_found, UserState}.


%% @doc Called when the service master process receives a handle_call/3.
-spec service_master_handle_call(term(), {pid(), reference()}, user_state()) ->
    {reply, term(), user_state()} | {noreply, user_state()} | continue().

service_master_handle_call(Msg, _From, State) ->
    lager:error("Module nkservice_master received unexpected call ~p", [Msg]),
    {noreply, State}.


%% @doc Called when the service master process receives a handle_cast/3.
-spec service_master_handle_cast(term(), user_state()) ->
    {noreply, user_state()} | continue().

service_master_handle_cast(Msg, State) ->
    lager:error("Module nkservice_master received unexpected cast ~p", [Msg]),
    {noreply, State}.


%% @doc Called when the service master process receives a handle_info/3.
-spec service_master_handle_info(term(), user_state()) ->
    {noreply, user_state()} | continue().

service_master_handle_info({'EXIT', _, normal}, State) ->
    {noreply, State};

service_master_handle_info(Msg, State) ->
    lager:notice("Module nkservice_master received unexpected info ~p", [Msg]),
    {noreply, State}.


-spec service_leader_code_change(term()|{down, term()}, user_state(), term()) ->
    {ok, user_state()} | {error, term()} | continue().

service_leader_code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% @doc Called when a service is stopped
-spec service_master_terminate(term(), user_state()) ->
    ok.

service_master_terminate(_Reason, _State) ->
    ok.



%% ===================================================================
%% Actor callbacks
%% ===================================================================

-type actor_st() :: #actor_st{}.
-type actor_id() :: #actor_id{}.

%% @doc Called from nkdomain_actor_db:load() when an actor has been read and must be activated
%% Can be used to select a different node, etc()
%% By default we start it at this node
-spec actor_activate(nkservice:actor(), nkservice_actor_srv:start_opts()) ->
    {ok, pid()} | {error, term()}.

actor_activate(Actor, StartOpts) ->
    nkservice_actor_srv:start(Actor, StartOpts).


%% @doc Called to get the default configuration for an actor
-spec actor_config(actor_id()) ->
    nkservice_actor_srv:config().

actor_config(_ActorId) ->
    #{}.


%% @doc Called when a new session starts
-spec actor_init(actor_st()) ->
    {ok, actor_st()} | {error, Reason::term()}.

actor_init(State) ->
    {ok, State}.


%% @doc Called when the session stops
-spec actor_terminate(Reason::term(), actor_st()) ->
    {ok, actor_st()}.

actor_terminate(_Reason, State) ->
    {ok, State}.


%% @private
-spec actor_stop(nkservice:msg(), actor_st()) ->
    {ok, actor_st()} | continue().

actor_stop(_Reason, State) ->
    {ok, State}.


%%  @doc Called update an actor with status
-spec actor_get(nkservice_actor:actor(), actor_st()) ->
    {ok, nkservice_actor:actor(), actor_st()} | continue().

actor_get(Actor, State) ->
    {ok, Actor, State}.


%%  @doc Called to send an event
-spec actor_event(nkdomain_obj:event(), actor_st()) ->
    {ok, actor_st()} | continue().

actor_event(_Event, State) ->
    % nkservice_actor_util:send_event(Event)
    {ok, State}.


%% @doc Called when an event is sent, for each registered process to the session
%% The events are 'erlang' events (tuples usually)
-spec actor_link_event(nklib:link(), term(), nkservice_actor_srv:event(), actor_st()) ->
    {ok, actor_st()} | continue().

actor_link_event(_Link, _LinkData, _Event, State) ->
    {ok, State}.


%% @doc
-spec actor_sync_op(term(), {pid(), reference()}, actor_st()) ->
    {reply, Reply::term(), session} | {reply_and_save, Reply::term(), session} |
    {noreply, actor_st()} | {noreply_and_save, session} |
    {stop, Reason::term(), Reply::term(), actor_st()} |
    {stop, Reason::term(), actor_st()} |
    continue().

actor_sync_op(_Op, _From, _State) ->
    continue.


%% @doc
-spec actor_async_op(term(), actor_st()) ->
    {noreply, actor_st()} | {noreply_and_save, session} |
    {stop, Reason::term(), actor_st()} |
    continue().

actor_async_op(_Op, _State) ->
    continue.


%% @doc Called to save the object to disk
-spec actor_save(nkservice_actor_srv:save_reason(), actor_st()) ->
    {ok, Meta::map(), actor_st()} | {error, term(), actor_st()} | continue().

actor_save(Reason, #actor_st{actor=Actor}=ActorSt) ->
    #actor{srv=SrvId, uid=UID} = Actor,
    true = is_binary(UID) andalso UID /= <<>>,
    Fun = case Reason of
        creation ->
            actor_db_create;
        _ ->
            actor_db_update
    end,
    case ?CALL_SRV(SrvId, Fun, [SrvId, Actor]) of
        {ok, DbMeta} ->
            {ok, DbMeta, ActorSt};
        {error, Error} ->
            {error, Error, ActorSt}
    end.


%% @doc Called to save the remove the object from disk
-spec actor_delete(actor_st()) ->
    {ok, actor_st()} | {error, term(), actor_st()} | continue().

actor_delete(State) ->
    {error, not_implemented, State}.


%% @doc Called when a linked process goes down
-spec actor_link_down(nklib_links:link(), actor_st()) ->
    {ok, actor_st()} | continue().

actor_link_down(_Link, State) ->
    {ok, State}.


%% @doc Called when an object is enabled/disabled
-spec actor_enabled(boolean(), actor_st()) ->
    {ok, actor_st()} | continue().

actor_enabled(_Enabled, State) ->
    {ok, State}.


%% @doc Called when an object is enabled/disabled
-spec actor_heartbeat(actor_st()) ->
    {ok, actor_st()} | {error, nkservice_msg:msg(), actor_st()} | continue().

actor_heartbeat(State) ->
    {ok, State}.


%% @doc Called when the timer in next_status_time is fired
-spec actor_next_status_timer(actor_st()) ->
    {ok, actor_st()} | continue().

actor_next_status_timer(State) ->
    {ok, State}.


%% @doc Called when a object with alarms is loaded
-spec actor_alarms(actor_st()) ->
    {ok, actor_st()} | {error, term(), actor_st()} | continue().

actor_alarms(State) ->
    {ok, State}.


%% @doc
-spec actor_handle_call(term(), {pid(), term()}, actor_st()) ->
    {reply, term(), actor_st()} | {noreply, actor_st()} |
    {stop, term(), term(), actor_st()} | {stop, term(), actor_st()} | continue().

actor_handle_call(Msg, _From, State) ->
    lager:error("Module nkdomain_obj received unexpected call: ~p", [Msg]),
    {noreply, State}.


%% @doc
-spec actor_handle_cast(term(), actor_st()) ->
    {noreply, actor_st()} | {stop, term(), actor_st()} | continue().

actor_handle_cast(Msg, State) ->
    lager:error("Module nkdomain_obj received unexpected cast: ~p", [Msg]),
    {noreply, State}.


%% @doc
-spec actor_handle_info(term(), actor_st()) ->
    {noreply, actor_st()} | {stop, term(), actor_st()} | continue().

actor_handle_info(Msg, State) ->
    lager:warning("Module nkdomain_obj received unexpected info: ~p", [Msg]),
    {noreply, State}.


%% @doc
-spec actor_conflict_detected(actor_id(), Winner::pid(), actor_st()) ->
    {ok, actor_st()} | continue().

actor_conflict_detected(_ActorId, _Pid, _State) ->
    erlang:error(conflict_detected).



%% ===================================================================
%% Actor utilities
%% ===================================================================

%% @doc Called when an 'isActivated' actor is read
%% If 'removed' is returned the actor will not load
-spec actor_do_active(nkservice_actor_srv:actor()) ->
    ok | removed.

actor_do_active(_Actor) ->
    ok.


%% @doc Called when an expired actor is read
-spec actor_do_expired(nkservice_actor:actor()) ->
    ok.

actor_do_expired(_Actor) ->
    ok.


%%%% @doc Tries to find the #actor_id{} of a path
%%%% Plugins can modify the behaviour
%%-spec actor_path_preprocess([binary()]) ->
%%    {ok, #actor_id{}, Resource::binary()} | {error, term()}.
%%
%%actor_path_preprocess(Parts) ->
%%    nkservice_actor_util:path_parts_to_actor_id(Parts).




%% ===================================================================
%% Actor DB
%% ===================================================================


%% @doc Called to find an actor on disk
-spec actor_db_find(nkservice:id(), nkservice_actor:id()) ->
    {ok, #actor_id{}, Meta::map()} | {error, term()} | continue().

actor_db_find(_SrvId, _Id) ->
    {error, not_implemented}.


%% @doc Called to save the actor to disk
-spec actor_db_read(nkservice:id(), nkservice_actor:id()) ->
    {ok, nkservice_actor:actor(), Meta::map()} | {error, term()} | continue().

actor_db_read(_SrvId, _Id) ->
    {error, not_implemented}.


%% @doc Called to save the actor to disk
-spec actor_db_create(nkservice:id(), nkservice:actor()) ->
    {ok, Meta::map()} | {error, term()} | continue().

actor_db_create(_SrvId, _Actor) ->
    {error, not_implemented}.


%% @doc Called to save the actor to disk
-spec actor_db_update(nkservice:id(), nkservice:actor()) ->
    {ok, Meta::map()} | {error, term()} | continue().

actor_db_update(_SrvId, _Actor) ->
    {error, not_implemented}.


%% @doc Called to delete the actor to disk
%% The implementation must call nkservice_actor_srv:actor_deleted/1 before deletion
-spec actor_db_delete(nkservice:id(), nkservice_actor:uid(), nkservice_actor_db:delete_opts()) ->
    {ok, Meta::map()} | {error, term()} | continue().

actor_db_delete(_SrvId, _UID, _Opts) ->
    {error, not_implemented}.


%% @doc
-spec actor_db_search(nkservice:id(), nkservice_actor_db:search_type(),
                      nkservice_actor_db:opts()) ->
    ok.

actor_db_search(_SrvId, _SearchType, _Opts) ->
    {error, not_implemented}.


%% @doc
-spec actor_db_aggregate(nkservice:id(), nkservice_actor_db:agg_type(),
    nkservice_actor_db:opts()) ->
    ok.

actor_db_aggregate(_SrvId, _SearchType, _Opts) ->
    {error, not_implemented}.


%% @doc
-spec actor_db_get_query(term(), nkservice_actor_db:search_type() | nkservice_actor_db:agg_type(),
                            nkservice_actor_db:opts()) ->
    {ok, term()} | {error, term()}.

actor_db_get_query(pgsql, SearchType, Opts) ->
    nkservice_actor_queries_pgsql:get_query(SearchType, Opts);

actor_db_get_query(Backend, _SearchType, _Opts) ->
    {error, {query_backend_unknown, Backend}}.


%% @doc
-spec actor_db_get_service(nkservice:id(), nkservice:id()) ->
    {ok, nkservice_actor_db:service_info()} | {error, term()}.

actor_db_get_service(_SrvId, _ActorSrvId) ->
    {error, not_implemented}.


%% @doc
-spec actor_db_update_service(nkservice:id(), nkservice:id(), binary()) ->
    {ok, Meta::map()} | {error, term()}.

actor_db_update_service(_SrvId, _ActorSrvId, _Cluster) ->
    {error, not_implemented}.



%% @doc Called to find an actor on disk, when we only have the UUID and no service
%% from id_to_actor_id/1
%% SrvId will be nkservice_app:get(dbDefaultService)
-spec nkservice_find_uid(nkservice:id(), UID::binary()) ->
    {ok, #actor_id{}, Meta::map()} | {error, term()} | continue().

nkservice_find_uid(_SrvId, _UID) ->
    {error, not_implemented}.


%% @doc Called to check if a service atom must be created,
%% from nkservice_actor_util:gen_srv_id/1
%% SrvId will be nkservice_app:get(dbDefaultService)
-spec nkservice_make_srv_id(nkservice:id(), Srv::binary()) ->
    {ok, nkservice:id()} | {error, term()}.

nkservice_make_srv_id(_SrvId, _UID) ->
    {error, not_implemented}.




%% ===================================================================
%% Service API
%% ===================================================================

%%-type api_id() :: term().
%%
%%
%%%% @doc Called to get the syntax for an external API command
%%-spec service_api_syntax(api_id(), nklib_syntax:syntax(), req()) ->
%%    {nklib_syntax:syntax(), req()}.
%%
%%service_api_syntax(_Id, SyntaxAcc, Req) ->
%%    {SyntaxAcc, Req}.
%%
%%
%%%% @doc Called to authorize process a new API command
%%-spec service_api_allow(api_id(), req()) ->
%%    boolean() | {true, req(), user_actor_st()}.
%%
%%service_api_allow(_Id, _Req) ->
%%    false.
%%
%%
%%%% @doc Called to process a new authorized API command
%%%% For slow requests, reply ack, and the ServiceModule:reply/2.
%%-spec service_api_cmd(api_id(), req()) ->
%%    {ok, Reply::map()} |
%%    {ok, Reply::map(), req()} |
%%    ack |
%%    {ack, pid()} |
%%    {ack, pid()|undefined, req()} |
%%    {error, nkservice:msg()}  |
%%    {error, nkservice:msg(), req()}.
%%
%%service_api_cmd(_Id, _Req) ->
%%    {error, not_implemented}.
%%
%%
%%%% @doc Called when the service received an event it has subscribed to
%%%% By default, we forward it to the client
%%-spec service_api_event(api_id(), req()) ->
%%    {ok, req()} |  {forward, req()}.
%%
%%service_api_event(_Id, Req) ->
%%    {forward, Req}.
%%
%%
%%
