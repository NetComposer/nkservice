-ifndef(NKSERVICE_SRV_HRL_).
-define(NKSERVICE_SRV_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================




%% ===================================================================
%% Records
%% ===================================================================


-record(state, {
    id :: nkservice:id(),
    service :: nkservice:service(),
    package_status :: #{nkservice:module_id() => nkservice_srv:package_status()},
    package_sup_pids :: [{nkservice:module_id(), pid()}],
    module_status :: #{nkservice:module_id() => nkservice_srv:module_status()},
    module_sup_pids :: [{nkservice:module_id(), pid()}],
    events :: {Size::integer(), queue:queue()},
    user :: map()
}).


-endif.

