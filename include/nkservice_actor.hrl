-ifndef(NKSERVICE_ACTOR_HRL_).
-define(NKSERVICE_ACTOR_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================


-define(ROOT_DOMAIN, <<"root">>).


%% ===================================================================
%% Records
%% ===================================================================

-record(actor_id, {
    domain :: nkservice_actor:domain(),
    group :: nkservice_actor:group(),
    vsn :: nkservice_actor:vsn() | undefined,
    resource :: nkservice_actor:resource(),
    name :: nkservice_actor:name(),
    uid :: nkservice_actor:uid() | undefined,
    pid :: pid() | undefined
}).


%% 'run_state' is populated when reading the object from the server process
%% It will be undefined if read from db. It will never be saved.
%% 'hash' represents a version, it is not updated by nkservice
-record(actor, {
    id :: #actor_id{},
    data = #{} :: nkservice_actor:data(),
    metadata = #{} :: nkservice_actor:metadata(),
    hash :: nkservice_actor:hash() | undefined,
    run_state = undefined :: term()
}).


-record(actor_st, {
    srv :: nkservice:id(),
    module :: module(),
    config :: nkservice_actor:config(),
    actor :: #actor{},
    run_state :: term(),
    father_pid :: pid() | undefined,
    is_dirty :: true | false | deleted,
    save_timer :: reference(),
    is_enabled :: boolean(),
    activated_time :: nklib_util:m_timestamp(),
    links :: nklib_links:links(),
    stop_reason = false :: false | nkservice:msg(),
    unload_policy :: permanent | {expires, nklib_util:m_timestamp()} | {ttl, integer()},
    ttl_timer :: reference() | undefined,
    status_timer :: reference() | undefined
}).


-endif.