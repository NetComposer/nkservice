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
    session_module :: module(),
    session_id = <<>> :: nkservice:session_id(),
    session_pid :: pid(),
    session_meta = #{} :: map(),
    session_manager = undefined :: term(),        % For pattern matching
    tid :: term(),
    cmd = <<>> :: nkservice:req_cmd(),
    data = #{} :: nkservice:req_data(),
    user_id = <<>> :: nkservice:user_id(),      % <<>> if not authenticated
    user_state = #{} :: nkservice:user_state(),
    req_state :: term(),
    unknown_fields = [] :: [binary()],
    timeout_pending = false :: boolean(),
    debug = false :: boolean()
}).





-endif.

