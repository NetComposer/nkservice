-module(serv1).
-compile([export_all]).



plugin_deps() -> nklib_util:randomize([plug1, plug3]).


plugin_start(Spec) ->
	lager:notice("Service ~p starting", [?MODULE]),
	{ok, maps:put(?MODULE, ok, Spec)}.

plugin_stop(Spec) ->
	lager:notice("Service ~p terminate", [?MODULE]),
	{ok, maps:remove(?MODULE, Spec)}.
