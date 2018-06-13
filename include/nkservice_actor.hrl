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


-record(actor_st, {
    actor_id :: #actor_id{},
    % srv_id :: nkservice:id(),
    config :: nkservice_actor_srv:config(),
    spec :: nkservice_actor:spec(),
    meta :: nkservice_actor:metadata(),
    vsn :: nkservice_actor:vsn(),
    status :: map(),
    leader_pid :: pid() | undefined,
    is_leader_enabled :: boolean(),
    is_dirty :: boolean(),
    saved_time :: nklib_util:m_timestamp(),
    is_enabled :: boolean(),
    disabled_time :: nklib_util:m_timestamp(),
    loaded_time :: nklib_util:m_timestamp(),
    links :: nklib_links:links(),
    stop_reason = false :: false | nkservice:error(),
    unload_policy :: permanent | {expires, nklib_util:m_timestamp()} | {ttl, integer()},
    ttl_timer :: reference() | undefined,
    status_timer :: reference() | undefined
}).





-endif.