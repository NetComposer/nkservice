-ifndef(NKSERVICE_ACTOR_HRL_).
-define(NKSERVICE_ACTOR_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================


%% ===================================================================
%% Records
%% ===================================================================

-record(actor_id, {
    srv_id :: nkservice:id(),
    uid :: nkservice_actor:uid(),
    api :: binary(),
    kind :: nkservice_actor:kind(),
    name :: nkservice_actor:name(),
    pid :: pid() | undefined
}).


-record(actor_st, {
    srv_id :: nkservice:id(),
    id :: #actor_id{},
    config :: nkservice_actor:config(),
    spec :: nkservice_actor:spec(),
    meta :: nkservice_actor:metadata(),
    status :: map(),
    master_pid :: pid() | undefined,
    is_master_enabled :: boolean(),
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