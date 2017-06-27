-ifndef(NKSERVICE_HRL_).
-define(NKSERVICE_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================

-define(SRV_DELAYED_DESTROY, 3000).



%% ===================================================================
%% Records
%% ===================================================================


-record(nkreq, {
    srv_id :: nkservice:id(),
    % conn_id :: term(),
    session_module :: module(),
    session_id = <<>> :: nkservice:session_id(),
    session_pid :: pid(),
    session_meta = #{} :: map(),
    tid :: term(),
    cmd = <<>> :: nkservice:req_cmd(),
    data = #{} :: nkservice:req_data(),
    user_id = <<>> :: nkservice:user_id(),      % <<>> if not authenticated
    user_meta = #{} :: nkservice:user_meta(),
    req_state :: term(),
    debug = false :: boolean()
}).





-endif.

