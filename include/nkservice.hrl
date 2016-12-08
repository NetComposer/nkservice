-ifndef(NKSERVICE_HRL_).
-define(NKSERVICE_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================

%% ===================================================================
%% Records
%% ===================================================================

-record(api_req, {
	srv_id :: nkservice_events:srv_id(),
	class :: nkservice_api:class(),
	subclass = <<>> :: nkservice_api:subclass(),
	cmd :: nkservice_api:cmd(),
	data = #{} :: map() | list(),
	tid :: term(),
	user_id :: binary(),
	session_id :: binary()
}).


-record(event, {
	srv_id :: nkservice_events:srv_id(),
	class :: nkservice_events:class(),
	subclass = <<>> :: nkservice_events:subclass(),
	type = <<>> :: nkservice_events:type() | [nkservice_events:type()],
	obj_id = <<>> :: nkservice_events:obj_id(),
	body = #{} :: nkservice_events:body(),
	pid = undefined :: pid() | undefined,
	meta = #{} :: map()
}).


-endif.

