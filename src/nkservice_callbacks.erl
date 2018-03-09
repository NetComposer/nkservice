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
-export([error/1, error/2, i18n/3]).
-export([service_event/3]).
-export([service_init/2, service_handle_call/4, service_handle_cast/3,
         service_handle_info/3, service_code_change/4, service_terminate/3]).
-export([service_leader_init/2, service_leader_find_uid/2,
         service_leader_handle_call/3, service_leader_handle_cast/2,
         service_leader_handle_info/2, service_leader_code_change/3,
         service_leader_terminate/2]).
-export([actor_init/1, actor_terminate/2, actor_stop/2,
         actor_event/2, actor_link_event/4, actor_sync_op/3, actor_async_op/2,
         actor_save/1, actor_delete/1, actor_link_down/2, actor_enabled/2, actor_next_status_timer/1,
         actor_alarms/1, actor_heartbeat/1,
         actor_handle_call/3, actor_handle_cast/2, actor_handle_info/2, actor_conflict_detected/3]).
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
-spec error(nkservice:lang(), nkservice:error()) ->
    atom() |
    tuple() |
    list() |
    {atom(), string()} |
    {Fmt::string(), Vals::string()} |
    {atom(), Fmt::string(), Vals::string()}.

error(SrvId, Error) ->
    SrvId:error(Error).


%% @doc
-spec error(nkservice:error()) ->
    atom() |
    tuple() |
    list() |
    {atom(), string()} |
    {Fmt::string(), Vals::string()} |
    {atom(), Fmt::string(), Vals::string()}.


error(actor_expired)	        -> "Actor has expired";
error(already_authenticated)	-> "Already authenticated";
error(already_started)	        -> "Already started";
error(already_uploaded)   		-> "Already uploaded";
error(api_delete) 				-> "API delete received";
error(api_stop) 				-> "API stop received";
error(data_not_available)   	-> "Data is not available";
error(destionation_not_found)   -> "Destination not found";
error(duplicated_session_id)	-> "Duplicated session";
error(file_read_error)   		-> "File read error";
error(internal_error)			-> "Internal error";
error({internal_error, Ref})	-> {"Internal error: ~s", [Ref]};
error({invalid_action, Txt})    -> {"Invalid action '~s'", [Txt]};
error({invalid_state, St}) 	    -> {"Invalid state: ~s", [St]};
error({invalid_value, V}) 		-> {"Invalid value: '~s'", [V]};
error(invalid_json) 			-> "Invalid JSON";
error(invalid_operation) 		-> "Invalid operation";
error(invalid_login_request)    -> "Invalid login request";
error(invalid_parameters) 		-> "Invalid parameters";
error(invalid_password) 		-> "Invalid password";
error(invalid_reply) 			-> "Invalid reply";
error(invalid_role)			    -> "Invalid role";
error(invalid_session_id)		-> "Invalid session";
error(invalid_state) 			-> "Invalid state";
error(invalid_uri) 			    -> "Invalid Uri";
error(invalid_object_id) 		-> "Invalid ObjectId";
error(max_disabled_time)        -> "Maximum disabled time reached";
error({missing_field, Txt})	    -> {"Missing field: '~s'", [Txt]};
error(missing_id)				-> "Missing Id";
error(no_password) 		        -> "No supplied password";
error(no_usages)           		-> "No remaining usages";
error(normal)           		-> "Normal termination";
error(normal_termination) 		-> "Normal termination";
error(not_authenticated)		-> "Not authenticated";
error(not_found) 				-> "Not found";
error(not_started) 				-> "Not yet started";
error(not_implemented) 		    -> "Not implemented";
error(process_down)  			-> "Process failed";
error(process_not_found) 		-> "Process not found";
error(registered_down) 	        -> "Registered process stopped";
error(service_not_found) 		-> "Service not found";
error(session_not_found) 		-> "Session not found";
error(session_stop) 			-> "Session stop";
error(session_timeout) 		    -> "Session timeout";
error({syntax_error, Txt})		-> {"Syntax error: '~s'", [Txt]};
error(timeout) 				    -> "Timeout";
error(ttl_timeout) 			    -> "TTL Timeout";
error(unauthorized) 			-> "Unauthorized";
error({unknown_command, Txt})	-> {"Unknown command '~s'", [Txt]};
error(unknown_peer) 			-> "Unknown peer";
error(unknown_op)   			-> "Unknown operation";
error(updated_invalid_field) 	-> "Tried to update invalid field";
error(user_not_found)			-> "User not found";
error({user_not_found, User})	-> {"User not found: '~s'", [User]};
error(user_stop) 				-> "User stop";
error(_)   		                -> continue.



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



%% @doc Called when a new service starts, first for the top-level plugin
-spec service_event(nkservice:event(), service(), user_state()) ->
    {ok, user_state()}.

service_event(_Event, _Service, State) ->
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




%% @doc Called when a new service starts, first for the top-level plugin
-spec service_leader_init(service(), user_state()) ->
    {ok, user_state()} | {stop, term()}.

service_leader_init(_Service, UserState) ->
    {ok, UserState}.


%% @doc Find an UUID in global database
-spec service_leader_find_uid(UID::binary(), user_state()) ->
    {reply, #actor_id{}, user_state()} |
    {stop, actor_not_found|term(), user_state()} |
    continue().

service_leader_find_uid(_Service, UserState) ->
    {stop, actor_not_found, UserState}.


%% @doc Called when the service process receives a handle_call/3.
-spec service_leader_handle_call(term(), {pid(), reference()}, user_state()) ->
    {reply, term(), user_state()} | {noreply, user_state()} | continue().

service_leader_handle_call(Msg, _From, State) ->
    lager:error("Module nkservice_leader received unexpected call ~p", [Msg]),
    {noreply, State}.


%% @doc Called when the NkApp process receives a handle_cast/3.
-spec service_leader_handle_cast(term(), user_state()) ->
    {noreply, user_state()} | continue().

service_leader_handle_cast(Msg, State) ->
    lager:error("Module nkservice_leader received unexpected cast ~p", [Msg]),
    {noreply, State}.


%% @doc Called when the NkApp process receives a handle_info/3.
-spec service_leader_handle_info(term(), user_state()) ->
    {noreply, user_state()} | continue().

service_leader_handle_info({'EXIT', _, normal}, State) ->
    {noreply, State};

service_leader_handle_info(Msg, State) ->
    lager:notice("Module nkservice_leader received unexpected info ~p", [Msg]),
    {noreply, State}.


-spec service_leader_code_change(term()|{down, term()}, user_state(), term()) ->
    {ok, user_state()} | {error, term()} | continue().

service_leader_code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% @doc Called when a service is stopped
-spec service_leader_terminate(term(), user_state()) ->
    ok.

service_leader_terminate(_Reason, _State) ->
    ok.




%% ===================================================================
%% Actor callbacks
%% ===================================================================

-type actor_st() :: #actor_st{}.
-type actor_id() :: #actor_id{}.


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
-spec actor_stop(nkservice:error(), actor_st()) ->
    {ok, actor_st()} | continue().

actor_stop(_Reason, State) ->
    {ok, State}.


%%  @doc Called to send an event
-spec actor_event(nkdomain_obj:event(), actor_st()) ->
    {ok, actor_st()} | continue().

actor_event(_Event, State) ->
    % nkservice_actor_util:send_event(Event)
    {ok, State}.


%% @doc Called when an event is sent, for each registered process to the session
%% The events are 'erlang' events (tuples usually)
-spec actor_link_event(nklib:link(), nkservice_actor:link_opts(), nkservice_actor:event(), actor_st()) ->
    {ok, actor_st()} | continue().

actor_link_event(_Link, _LinkOpts, _Event, State) ->
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
-spec actor_save(actor_st()) ->
    {ok, actor_st(), Meta::map()} | {error, term(), actor_st()} | continue().

actor_save(State) ->
    {error, not_implemented, State}.


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
    {ok, actor_st()} | continue().

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
%%    {error, nkservice:error()}  |
%%    {error, nkservice:error(), req()}.
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
