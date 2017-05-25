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
    session_meta = #{} :: map(),
    cmd = <<>> :: nkservice:req_cmd(),
    data = #{} :: nkservice:req_data(),
    unknown_fields = [] :: [binary()],
    user_id = <<>> :: nkservice:user_id(),      % <<>> if not authenticated
    user_meta = #{} :: nkservice:user_meta(),
    state = #{} :: map(),
    debug = false :: boolean()
}).





-endif.

