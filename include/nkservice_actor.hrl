-ifndef(NKSERVICE_ACTOR_HRL_).
-define(NKSERVICE_ACTOR_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================


%% ===================================================================
%% Records
%% ===================================================================

-record(actor, {
    srv :: nkservice:id(),                    %% Service where it is loaded
    class :: nkservice_actor:class(),         %% Mandatory
    type :: nkservice_actor:type(),           %% Mandatory
    name :: nkservice_actor:name(),           %% Generated if not included
    uid :: nkservice_actor:uid() | undefined, %%
    vsn :: nkservice_actor:vsn(),             %% DB version
    data = #{} :: nkservice_actor:data(),
    metadata = #{} :: nkservice_actor:metadata(),
    status :: nkservice_actor:status() | undefined
}).


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
    config :: nkservice_actor_srv:config(),
    actor :: #actor{},
    leader_pid :: pid() | undefined,
    is_dirty :: boolean(),
    save_timer :: reference(),
    is_enabled :: boolean(),
    loaded_time :: nklib_util:m_timestamp(),
    links :: nklib_links:links(),
    stop_reason = false :: false | nkservice:msg(),
    unload_policy :: permanent | {expires, nklib_util:m_timestamp()} | {ttl, integer()},
    ttl_timer :: reference() | undefined,
    status_timer :: reference() | undefined
}).





-endif.