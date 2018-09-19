-ifndef(NKSERVICE_ACTOR_HRL_).
-define(NKSERVICE_ACTOR_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================


%% ===================================================================
%% Records
%% ===================================================================

-record(actor_id, {
    uid :: nkservice_actor:uid() | undefined,
    srv :: nkservice:id(),
    group :: nkservice_actor:group(),
    type :: nkservice_actor:type(),
    name :: nkservice_actor:name(),
    vsn :: nkservice_actor:vsn() | undefined,
    hash :: nkservice_actor:hash() | undefined,
    pid :: pid() | undefined
}).


%% 'run_state' is populated when reading the object from the server process
%% if would be undefined if read from db. It will never be saved.
-record(actor, {
    id :: #actor_id{},
    data = #{} :: nkservice_actor:data(),
    metadata = #{} :: nkservice_actor:metadata(),
    run_state = undefined :: nkservice_actor_srv:run_state() | undefined
}).


-record(actor_st, {
    actor :: #actor{},
    config :: nkservice_actor_srv:config(),
    module :: module(),
    leader_pid :: pid() | undefined,
    run_state = #{} :: nkservice_actor_srv:run_state(),
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