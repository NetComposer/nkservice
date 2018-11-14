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

%% @doc Basic Actor behaviour
%% Actors are identified by its 'uid' or its 'path'
%% - When using uid, it will located only on local node or if is has been cached
%%   at local node. Otherwise a database backend must be used.
%% - Path is always '/domain/group/resource/name'. The service will we asked if not cached


-module(nkservice_actor).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([find/2, create/3]).
-export([get_actor/2, get_path/2, is_enabled/2, enable/3, update/4, remove/2,
         stop/2, stop/3]).
-export([search_groups/3, search_resources/4]).
-export([search_linked_to/5, search_fts/5, search/3, search_ids/3,
         delete_all/3, delete_old/6]).
-export([config/1, parse/4, request/5, make_external/4]).
-export([find_registered/2]).
-export([actor_srv_init/2, actor_srv_sync_op/3, actor_srv_async_op/2,
         actor_srv_heartbeat/1, actor_srv_get/2, actor_srv_enabled/2, actor_srv_update/2,
         actor_srv_handle_call/3, actor_srv_handle_cast/2, actor_srv_handle_info/2,
         actor_srv_event/2, actor_srv_stop/2, actor_srv_terminate/2]).
-export([filter_fields/0, sort_fields/0, field_type/0, field_trans/0]).
-export_type([actor/0, id/0, uid/0, domain/0, resource/0, path/0, name/0,
              vsn/0, group/0, hash/0,
              data/0, metadata/0, alarm_class/0, alarm_body/0]).


-include("nkservice.hrl").
-include("nkservice_actor.hrl").
-include("nkservice_actor_debug.hrl").



%% ===================================================================
%% Callbacks definitions
%% ===================================================================

-type actor() :: #actor{}.

-type actor_id() :: #actor_id{}.

-type id() :: path() | uid() | actor_id().

-type uid() :: binary().

-type domain() :: binary().

-type group() :: binary().

-type vsn() :: binary().

-type hash() :: binary().

-type resource() :: binary().

-type path() :: binary().   %% /domain/group/type/name

-type name() :: binary().

-type data() ::
    #{
        binary() => binary() | integer() | float() | boolean()
    }.


-type alarm_class() :: binary().

%% Recommended alarm fields
%% ------------------------
%% - code (binary)
%% - message (binary)
%% - lastTime (binary, rfc3339)
%% - meta (map)

-type alarm_body() :: map().


%% Recognized metadata
%% -------------------
%% (see nkservice_actor_syntax)
%%
%% - resourceVersion (binary)
%%   hash of the Name, Spec and Meta, generated automatically
%%
%% - generation (integer)
%%   incremented at each change
%%
%% - creationTime (rfc3339)
%%   updated on creation
%%
%% - updateTime (rfc3339))
%%   updated on update
%%
%% - isActivated (boolean)
%%   must be loaded at all times
%%
%% - expiresTime (rfc3339)
%%
%% - labels (binary() => binary | integer | boolean)
%%
%% - fts (binary() => [binary()]
%%
%% - links (binary => binary)
%%
%% - annotations (binary => binary | integer | boolean)
%%
%% - isEnabled (boolean)
%%   defaults true, can be overridden on load
%%
%% - subtype (binary)
%%
%% - isInAlarm (boolean)
%%
%% - alarms [alarm()]
%%
%% - nextStatusTime (rfc3339)
%%
%% - description (binary)
%%
%% - createdBy (binary)
%%
%% - updatedBy (binary)
%%


-type metadata() ::
    #{
        binary() => binary() | integer() | float() | boolean()
    }.


-type update_opts() ::
    #{
        data_fields => [binary()]           % Fields in data to check for changes an update
    }.


-type config() ::
    #{
        group => group(),
        resource => resource(),
        versions => [vsn()],
        auto_activate => boolean(),                     %% Periodic automatic activation
        camel => binary(),
        singular => binary(),
        short_names => [binary()],
        verbs => [atom()],
        filter_fields => [nkservice_actor_search:field_name()],
        sort_fields => [nkservice_actor_search:field_name()],
        field_type => #{
            nkservice_actor_search:field_name() => nkservice_actor_search:field_type()
        },
        immutable_fields => [nkservice_actor_search:field_name()],
        module => module()
    }.

-type verb() :: atom().


-type request() :: map().


-type response() ::
    ok | {ok, map()} | {ok, map(), request()} |
    {created, map()} |
    {status, nkservice:msg()} | {status, nkservice:msg(), request()} |  %% See status/2
    {error, nkservice:msg()} | {error, nkservice:msg(), request()}.


-type continue() ::
    continue | {continue, list()}.


-type actor_st() :: #actor_st{}.


%% ===================================================================
%% Behaviour callbacks
%% ===================================================================


%% @doc Called to get the actor's config
-callback config() -> config().


%% @doc Called to parse an actor from an external representation
-callback parse(nkservice:id(), actor(), request()) ->
    {ok, actor()} | {syntax, nklib_syntax:syntax()} | {error, term()}.


%% @doc Called to process an incoming API
%% SrvId will be the service supporting the domain in ApiReq
%% If not implemented, or 'continue' is returned, standard processing will apply
-callback request(nkservice:id(), verb(), actor_id(), config(), request()) ->
    response() | continue.


%% @doc Called to change the external representation of an actor,
%% for example to change date's format. Vsn will be the current ApiVsn asking for it
-callback make_external(nkservice:id(), actor(), vsn()) ->
    {ok, nkservice:actor()} | continue.


%% @doc Called when a new actor starts
-callback init(actor_st()) ->
    {ok, actor_st()} | {error, Reason::term()}.


%% @doc Called to process sync operations
-callback update(nkservice:actor(), actor_st()) ->
    {ok, nkservice:actor(), actor_st()} | {error, nkservice:msg(), actor_st()}.


%% @doc Called to process sync operations
-callback sync_op(term(), {pid(), reference()}, actor_st()) ->
    {reply, Reply::term(), actor_st()} | {reply_and_save, Reply::term(), actor_st()} |
    {noreply, actor_st()} | {noreply_and_save, actor_st()} |
    {stop, Reason::term(), Reply::term(), actor_st()} |
    {stop, Reason::term(), actor_st()} |
    continue().


%% @doc Called to process async operations
-callback async_op(term(), actor_st()) ->
    {noreply, actor_st()} | {noreply_and_save, actor_st()} |
    {stop, Reason::term(), actor_st()} |
    continue().


%%  @doc Called when an actor is sent inside the actor process
%%  Can be used to launch API events, calling
-callback event(term(), actor_st()) ->
    {ok, actor_st()} | continue().


%% @doc Called when an event is sent, for each registered process to the session
%% The events are 'erlang' events (tuples usually)
-callback link_event(nklib:link(), term(), nkservice_actor_srv:event(), actor_st()) ->
    {ok, actor_st()} | continue().


%% @doc Called when an object is enabled/disabled
-callback enabled(boolean(), actor_st()) ->
    {ok, actor_st()} | continue().


%% @doc Called on actor heartbeat (5 secs)
-callback heartbeat(actor_st()) ->
    {ok, actor_st()} | {error, nkservice_msg:msg(), actor_st()} | continue().


%% @doc Called on actor heartbeat (5 secs)
-callback get(actor(), actor_st()) ->
    {ok, actor(), actor_st()} | {error, nkservice_msg:msg(), actor_st()} | continue().


%% @doc
-callback handle_call(term(), {pid(), term()}, actor_st()) ->
    {reply, term(), actor_st()} | {noreply, actor_st()} |
    {stop, Reason::term(), Reply::term(), actor_st()} |
    {stop, Reason::term(), actor_st()} | continue().


%% @doc
-callback handle_cast(term(), actor_st()) ->
    {noreply, actor_st()} | {stop, term(), actor_st()} | continue().


%% @doc
-callback handle_info(term(), actor_st()) ->
    {noreply, actor_st()} | {stop, term(), actor_st()} | continue().


%% @doc
-callback stop(Reason::term(), actor_st()) ->
    {ok, actor_st()}.


%% @doc
-callback terminate(Reason::term(), actor_st()) ->
    {ok, actor_st()}.


%% @doc
-optional_callbacks([
    parse/3, request/5, make_external/3,
    init/1, get/2, update/2, sync_op/3, async_op/2, enabled/2, heartbeat/1,
    event/2, link_event/4, handle_call/3, handle_cast/2, handle_info/2,
    stop/2, terminate/2]).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc
find(SrvId, Id) ->
    nkservice_actor_db:find(SrvId, Id).


%% @doc
create(SrvId, Actor, StartOpts) ->
    Actor2 = nkservice_actor_util:put_create_fields(Actor),
    nkservice_actor_db:create(SrvId, Actor2, StartOpts).


%% @doc
-spec get_actor(nkservice:id(), id()|pid()) ->
    {ok, actor()} | {error, term()}.

get_actor(SrvId, Id) ->
    nkservice_actor_srv:sync_op(SrvId, Id, get_actor).


%% @doc
-spec get_path(nkservice:id(), id()|pid()) ->
    {ok, path()} | {error, term()}.

get_path(SrvId, Id) ->
    case nkservice_actor_srv:sync_op(SrvId, Id, get_actor_id) of
        {ok, ActorId} ->
            {ok, nkservice_actor_util:actor_id_to_path(ActorId)};
        {error, Error} ->
            {error, Error}
    end.


%% @doc Check if an actor is enabled
-spec is_enabled(nkservice:id(), id()|pid()) ->
    {ok, boolean()} | {error, term()}.

is_enabled(SrvId, Id) ->
    nkservice_actor_srv:sync_op(SrvId, Id, is_enabled).


%% @doc Enables/disabled an object
-spec enable(nkservice:id(), id()|pid(), boolean()) ->
    ok | {error, term()}.

enable(SrvId, Id, Enable) ->
    nkservice_actor_srv:sync_op(SrvId, Id, {enable, Enable}).


%% @doc Updates an object
-spec update(nkservice:id(), id()|pid(), map(), update_opts()) ->
    {ok, UnknownFields::[binary()]} | {error, term()}.

update(SrvId, Id, Update, Opts) ->
    nkservice_actor_srv:sync_op(SrvId, Id, {update, Update, Opts}).


%% @doc Remove an object
-spec remove(nksservice:id(), id()|pid()) ->
    ok | {error, term()}.

remove(SrvId, Id) ->
    nkservice_actor_srv:sync_op(SrvId, Id, delete).


%% @doc Unloads the object
-spec stop(nkservice:id(), id()|pid()) ->
    ok | {error, term()}.

stop(SrvId, Id) ->
    stop(SrvId, Id, normal).


%% @doc Unloads the object
-spec stop(nkservice:id(), id()|pid(), Reason::nkservice:msg()) ->
    ok | {error, term()}.

stop(SrvId, Id, Reason) ->
    nkservice_actor_srv:async_op(SrvId, Id, {stop, Reason}).


%% @doc Counts classes and objects of each class
-spec search_groups(nkservice:id(), domain(), #{deep=>boolean()}) ->
    {ok, [{binary(), integer()}], Meta::map()} | {error, term()}.

search_groups(SrvId, Domain, Opts) ->
    nkservice_actor_db:aggregation(SrvId, {service_aggregation_groups, Domain, Opts}).


%% @doc
-spec search_resources(nkservice:id(), group(), domain(), #{deep=>boolean()}) ->
    {ok, [{binary(), integer()}], Meta::map()} | {error, term()}.

search_resources(SrvId, Domain, Group, Opts) ->
    nkservice_actor_db:aggregation(SrvId, {service_aggregation_resources, Domain, Group, Opts}).


%% @doc Gets objects pointing to another
-spec search_linked_to(nkservice:id(), domain(), id(), binary()|any,
                       #{deep=>boolean(), from=>pos_integer(), size=>pos_integer()}) ->
    {ok, #{UID::binary() => LinkType::binary()}} | {error, term()}.

search_linked_to(SrvId, Domain, Id, LinkType, Opts) ->
    case nkservice_actor_db:find(SrvId, Id) of
        {ok, #actor_id{uid=UID}, _} ->
            nkservice_actor_db:search(SrvId, {service_search_linked, Domain, UID, LinkType, Opts});
        {error, Error} ->
            {error, Error}
    end.


%% @doc Gets objects under a path, sorted by path
-spec search_fts(nkservce:id(), domain(), binary()|any, binary(),
    #{deep=>boolean(), from=>pos_integer(), size=>pos_integer()}) ->
    {ok, [UID::binary()], Meta::map()} | {error, term()}.

search_fts(SrvId, Domain, Field, Word, Opts) ->
    nkservice_actor_db:search(SrvId, {service_search_fts, Domain, Field, Word, Opts}).


%% @doc Generic search returning actors
-spec search(nkservice:id(), nkservice_actor_search:search_spec(),
             nkservice_actor_search:search_opts()) ->
    {ok, [actor()], Meta::map()} | {error, term()}.

search(SrvId, SearchSpec, SearchOpts) ->
    case nkservice_actor_search:parse(SearchSpec, SearchOpts) of
        {ok, SearchSpec2} ->
            nkservice_actor_db:search(SrvId, {service_search_actors, SearchSpec2});
        {error, Error} ->
            {error, Error}
    end.



%% @doc Generic search returning actors
%% Meta will include size, last_updated and total (if not totals=false)
-spec search_ids(nkservice:id(), nkservice_actor_search:search_spec(),
    nkservice_actor_search:search_opts()) ->
    {ok, [actor_id()], Meta::map()} | {error, term()}.

search_ids(SrvId, SearchSpec, SearchOpts) ->
    case nkservice_actor_search:parse(SearchSpec, SearchOpts) of
        {ok, SearchSpec2} ->
            nkservice_actor_db:search(SrvId, {service_search_actors_id, SearchSpec2});
        {error, Error} ->
            {error, Error}
    end.


%% @doc Deletes actors older than Epoch (secs)
-spec delete_old(nkservice:id(), domain(), group(), resource(), binary(), #{deep=>boolean()}) ->
    {ok, integer(), Meta::map()}.

delete_old(SrvId, Domain, Group, Type, Date, Opts) ->
    nkservice_actor_db:search(SrvId, {service_delete_old_actors, Domain, Group, Type, Date, Opts}).


%% @doc Generic deletion of objects
%% Use delete=>true for real deletion
%% Use search_opts() to be able to use special fields, otherwise anything is accepted
-spec delete_all(nkservice:id(), nkservice_actor_search:search_spec()|#{delete=>boolean()},
                 nkservice_actor_search:search_opts()) ->
    {ok|deleted, integer(), Meta::map()}.

delete_all(SrvId, SearchSpec, SearchOpts) ->
    {Delete, SearchSpec2} = case maps:take(delete, SearchSpec) of
        error ->
            {false, SearchSpec};
        {Test0, SearchSpec0} ->
            {Test0, SearchSpec0}
    end,
    case nkservice_actor_search:parse(SearchSpec2, SearchOpts) of
        {ok, SearchSpec3} ->
            case nkservice_actor_db:search(SrvId, {service_delete_actors, Delete, SearchSpec3}) of
                {ok, Total, Meta} when Delete ->
                    {deleted, Total, Meta};
                {ok, Total, Meta} ->
                    {ok, Total, Meta};
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end.


%% ===================================================================
%% Registration
%% ===================================================================


%% @doc Checks if an actor is activated
%% - checks if it is in the local cache
%% - if not, asks to the domain actor responsible for that domain
%% - if we are asking for a domain, a shortcut is used
%% - for UIDs, we can only check if it is in local cache
%% CAUTION: an actor can be activated and we will not find it by UID unless
%% a previous call with path or #actor_id{} is made
%% Call to nkservice_actor_db:is_activated/2 to be sure

-spec find_registered(nkservice:id(), id()) ->
    {true, #actor_id{}} | false.

find_registered(SrvId, Id) ->
    case find_cached(Id) of
        {true, ActorId2} ->
            {true, ActorId2};
        false ->
            case ?CALL_SRV(SrvId, actor_find_registered, [SrvId, Id]) of
                {true, ActorId2} ->
                    #actor_id{
                        domain = Domain,
                        group = Group,
                        resource = Res,
                        name = Name,
                        uid = UID,
                        pid = Pid
                    } = ActorId2,
                    true = is_binary(UID) andalso UID /= <<>>,
                    nklib_proc:put({nkdomain_actor, Domain, Group, Res, Name}, ActorId2, Pid),
                    nklib_proc:put({nkdomain_actor_uid, UID}, ActorId2, Pid),
                    nklib_proc:put(nkdomain_all_actors, UID, Pid),
                    {true, ActorId2};
                false ->
                    false;
                {error, Error} ->
                    ?ACTOR_LOG(warning, "error calling nkdomain_find_actor for ~s: ~p", [Error]),
                    false
            end
    end.


%% @private
find_cached(#actor_id{}=ActorId) ->
    #actor_id{domain=Domain, group=Group, resource=Res, name=Name} = ActorId,
    case nklib_proc:values({nkdomain_actor, Domain, Group, Res, Name}) of
        [{ActorId2, _Pid}|_] ->
            {true, ActorId2};
        [] ->
            false
    end;

find_cached(UID) ->
    case nklib_proc:values({nkdomain_actor_uid, to_bin(UID)}) of
        [{ActorId, _Pid}|_] ->
            {true, ActorId};
        [] ->
            false
    end.




%% ===================================================================
%% Actor Proxy
%% ===================================================================


%% @doc Used to call the 'config' callback on an actor's module
%% You normally will use nkdomain_util:get_config/2, as its has a complete set of fields
config(Module) ->
    case erlang:function_exported(Module, config, 0) of
        true ->
            Module:config();
        false ->
            not_exported
    end.


%% @doc Used to parse an actor, trying the module callback first
%% Must set also vsn
parse(SrvId, Actor, Module, Request) ->
    SynSpec = case erlang:function_exported(Module, parse, 3) of
        true ->
            apply(Module, parse, [SrvId, Actor, Request]);
        false ->
            {syntax, #{}}
    end,
    case SynSpec of
        {ok, #actor{}=Actor2} ->
            {ok, Actor2};
        {syntax, Syntax} when is_map(Syntax) ->
            {syntax, Syntax};
        {error, Error} ->
            {error, Error}
    end.


%% @doc Used to call the 'request' callback on an actor's module
request(SrvId, ActorId, #{module:=Module}=Config, Verb, Request) ->
    case erlang:function_exported(Module, request, 5) of
        true ->
            Module:request(SrvId, Verb, ActorId, Config, Request);
        false ->
            continue
    end;

request(_SrvId, _ActorId, _Config, _Verb, _ApiReq) ->
    continue.


%% @doc Used to update the external API representation of an actor
%% to match a version and also to filter and populate 'data' (specially, data.status)
%% If Vsn is 'undefined' actor can use it's last version
-spec make_external(nkservice:id(), actor(), module(), vsn()|undefined) ->
    actor().

make_external(SrvId, Actor, Module, Vsn) ->
    case erlang:function_exported(Module, make_external, 3) of
        true ->
            case Module:make_external(SrvId, Actor, Vsn) of
                continue ->
                    Actor;
                {ok, Actor2} ->
                    Actor2
            end;
        false ->
            Actor
    end.


%% @doc Called from nkdomain_callbacks for actor initialization
actor_srv_init(_StartOpts, ActorSt) ->
    case call_actor(init, [ActorSt], ActorSt) of
        continue ->
            {ok, ActorSt};
        Other ->
            Other
    end.


%% @doc Called on a periodic basis
actor_srv_heartbeat(ActorSt) ->
    case call_actor(heartbeat, [ActorSt], ActorSt) of
        continue ->
            {ok, ActorSt};
        Other ->
            Other
    end.


%% @doc Called on a periodic basis
actor_srv_get(Actor, ActorSt) ->
    case call_actor(get, [Actor, ActorSt], ActorSt) of
        continue ->
            {ok, Actor, ActorSt};
        Other ->
            Other
    end.


%% @doc Called from nkdomain_callbacks after enable change
actor_srv_enabled(Enabled, ActorSt) ->
    case call_actor(enabled, [Enabled, ActorSt], ActorSt) of
        continue ->
            {ok, ActorSt};
        Other ->
            Other
    end.


%% @doc Called from nkdomain_callbacks before terminating an update
actor_srv_update(Actor, ActorSt) ->
    case call_actor(update, [Actor, ActorSt], ActorSt) of
        continue ->
            {ok, Actor, ActorSt};
        Other ->
            Other
    end.


%% @doc Called from nkdomain_callbacks for sync operations
actor_srv_sync_op(Op, From, ActorSt) ->
    call_actor(sync_op, [Op, From, ActorSt], ActorSt).


%% @doc Called from nkdomain_callbacks for async operations
actor_srv_async_op(Op, ActorSt) ->
    call_actor(async_op, [Op,  ActorSt], ActorSt).


%% @doc Called from nkdomain_callbacks when a event is sent
actor_srv_event(Op, ActorSt) ->
    case call_actor(event, [Op,  ActorSt], ActorSt) of
        continue ->
            {ok, ActorSt};
        Other ->
            Other
    end.


%% @doc Called from nkdomain_callbacks for handle_call
actor_srv_handle_call(Msg, From, ActorSt) ->
    case call_actor(handle_call, [Msg, From, ActorSt], ActorSt) of
        continue ->
            lager:error("Module nkservice_actor_srv received unexpected call: ~p", [Msg]),
            {noreply, ActorSt};
        Other ->
            Other
    end.


%% @doc Called from nkdomain_callbacks for handle_cast
actor_srv_handle_cast(Msg, ActorSt) ->
    case call_actor(handle_cast, [Msg, ActorSt], ActorSt) of
        continue ->
            lager:error("Module nkservice_actor_srv received unexpected cast: ~p", [Msg]),
            {noreply, ActorSt};
        Other ->
            Other
    end.


%% @doc Called from nkdomain_callbacks for handle_info
actor_srv_handle_info(Msg, ActorSt) ->
    case call_actor(handle_info, [Msg, ActorSt], ActorSt) of
        continue ->
            lager:error("NKLOG MOD ~p", [ActorSt#actor_st.module]),
            lager:error("Module nkservice_actor_srv received unexpected info: ~p", [Msg]),
            {noreply, ActorSt};
        Other ->
            Other
    end.


%% @doc Called from nkdomain_callbacks for actor termination
actor_srv_stop(Reason, ActorSt) ->
    case call_actor(stop, [Reason,  ActorSt], ActorSt) of
        continue ->
            {ok, ActorSt};
        Other ->
            Other
    end.



%% @doc Called from nkdomain_callbacks for actor termination
actor_srv_terminate(Reason, ActorSt) ->
    case call_actor(terminate, [Reason,  ActorSt], ActorSt) of
        continue ->
            {ok, ActorSt};
        Other ->
            Other
    end.



%% ===================================================================
%% Common fields
%% ===================================================================


%% @doc Default filter fields
%% Must be sorted!
filter_fields() ->
    [
        <<"apiGroup">>,
        <<"domain">>,
        <<"groups">>,
        <<"group+resource">>,           % Maps to special group + resource
        <<"kind">>,
        <<"metadata.createdBy">>,
        <<"metadata.creationTime">>,
        <<"metadata.domain">>,
        <<"metadata.expiresTime">>,
        <<"metadata.generation">>,
        <<"metadata.isEnabled">>,
        <<"metadata.isInAlarm">>,
        <<"metadata.name">>,
        <<"metadata.resourceVersion">>,
        <<"metadata.subtype">>,
        <<"metadata.uid">>,
        <<"metadata.updateTime">>,
        <<"metadata.updatedBy">>,
        <<"name">>,
        <<"path">>,
        <<"resource">>,
        <<"srv">>,
        <<"uid">>,
        <<"vsn">>
    ].


%% @doc Default sort fields
%% Must be sorted!
sort_fields() ->
    [
        <<"apiGroup">>,
        <<"domain">>,
        <<"group">>,
        <<"group+resource">>,
        <<"kind">>,
        <<"metadata.createdBy">>,
        <<"metadata.creationTime">>,
        <<"metadata.domain">>,
        <<"metadata.expiresTime">>,
        <<"metadata.generation">>,
        <<"metadata.isEnabled">>,
        <<"metadata.isInAlarm">>,
        <<"metadata.name">>,
        <<"metadata.subtype">>,
        <<"metadata.updateTime">>,
        <<"metadata.updatedBy">>,
        <<"name">>,
        <<"path">>,
        <<"srv">>
    ].


%% @doc
field_trans() ->
    #{
        <<"apiGroup">> => <<"group">>,
        <<"kind">> => <<"data.kind">>,
        <<"metadata.uid">> => <<"uid">>,
        <<"metadata.name">> => <<"name">>
    }.


%% @doc Field value, applied after trans
field_type() ->
    #{
        <<"metadata.generation">> => integer,
        <<"metadata.isEnabled">> => boolean,
        <<"metadata.isInAlarm">> => boolean
    }.




%% ===================================================================
%% Internal
%% ===================================================================

%% @private
call_actor(Fun, Args, #actor_st{module=Module}) ->
    case erlang:function_exported(Module, Fun, length(Args)) of
        true ->
            apply(Module, Fun, Args);
        false ->
            continue
    end;

call_actor(_Fun, _Args, _ActorSt) ->
    continue.



%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).
