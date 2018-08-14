-ifndef(NKSERVICE_ACTOR_HRL_).
-define(NKSERVICE_ACTOR_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================


%% ===================================================================
%% Records
%% ===================================================================

-record(actor_id, {
    srv :: nkservice:id(),
    class :: nkservice_actor:class(),
    type :: nkservice_actor:type(),
    name :: nkservice_actor:name(),
    uid :: nkservice_actor:uid() | undefined,
    pid :: pid() | undefined
}).


-record(actor, {
    id :: #actor_id{},
    vsn :: nkservice_actor:vsn(),
    data = #{} :: nkservice_actor:data(),
    metadata = #{} :: nkservice_actor:metadata(),
    status :: nkservice_actor:status() | undefined
}).



-record(actor_st, {
    actor :: #actor{},
    config :: nkservice_actor_srv:config(),
    leader_pid :: pid() | undefined,
    is_dirty2 :: true | false | deleted,
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