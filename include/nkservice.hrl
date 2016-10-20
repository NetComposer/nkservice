-ifndef(NKSERVICE_HRL_).
-define(NKSERVICE_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================

% -define(
%     DO_LOG(Level, App, CtxId, Text, Opts),
%     case CtxId of
%         <<>> ->
%             lager:Level([{app, App}], "~p "++Text, [App|Opts]);
%         _ -> 
%             lager:Level([{app, App}, {ctx_id, CtxId}], "~p (~s) "++Text, [App, CtxId|Opts])
%     end).

% -define(DO_DEBUG(SrvMod, CtxId, Level, Text, List),
%     case SrvMod:config_debug() of
%         false -> ok;
%         _ -> SrvMod:nks_sip_debug(SrvMod, CtxId, {Level, Text, List})
%     end).


% -define(debug(SrvMod, CtxId, Text, List), 
%     ?DO_DEBUG(SrvMod, CtxId, debug, Text, List),
%     case SrvMod:config_log_level() >= 8 of
%         true -> ?DO_LOG(debug, SrvMod:name(), CtxId, Text, List);
%         false -> ok
%     end).

% -define(info(SrvMod, CtxId, Text, List), 
%     ?DO_DEBUG(SrvMod, CtxId, info, Text, List),
%     case SrvMod:config_log_level() >= 7 of
%         true -> ?DO_LOG(info, SrvMod:name(), CtxId, Text, List);
%         false -> ok
%     end).

% -define(notice(SrvMod, CtxId, Text, List), 
%     ?DO_DEBUG(SrvMod, CtxId, notice, Text, List),
%     case SrvMod:config_log_level() >= 6 of
%         true -> ?DO_LOG(notice, SrvMod:name(), CtxId, Text, List);
%         false -> ok
%     end).

% -define(warning(SrvMod, CtxId, Text, List), 
%     ?DO_DEBUG(SrvMod, CtxId, warning, Text, List),
%     case SrvMod:config_log_level() >= 5 of
%         true -> ?DO_LOG(warning, SrvMod:name(), CtxId, Text, List);
%         false -> ok
%     end).

% -define(error(SrvMod, CtxId, Text, List), 
%     ?DO_DEBUG(SrvMod, CtxId, error, Text, List),
%     case SrvMod:config_log_level() >= 4 of
%         true -> ?DO_LOG(error, SrvMod:name(), CtxId, Text, List);
%         false -> ok
%     end).

%% ===================================================================
%% Records
%% ===================================================================

-record(api_req, {
	srv_id :: nkservice_events:srv_id(),
	class :: nkservice_api:class(),
	subclass = <<"core">> :: nkservice_api:subclass(),
	cmd :: nkservice_api:cmd(),
	data = #{} :: term(),
	tid :: term(),
	user :: binary(),
	session :: binary()
}).


-record(event, {
	srv_id :: nkservice_events:srv_id(),
	class :: nkservice_events:class(),
	subclass = '*'  :: nkservice_events:subclass(),
	type = '*' :: nkservice_events:type(),
	obj_id = '*' :: nkservice_events:obj_id(),
	body = undefined :: term(),
	pid = undefined :: undefined | pid()
}).


-endif.

