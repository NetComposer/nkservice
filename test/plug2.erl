-module(plug2).
-compile([export_all]).


plugin_deps() -> [].

plugin_start(Spec) ->
	lager:notice("Plugin ~p starting", [?MODULE]),
	{ok, maps:put(?MODULE, ok, Spec)}.

plugin_stop(Spec) ->
	lager:notice("Plugin ~p terminate", [?MODULE]),
	{ok, maps:remove(?MODULE, Spec)}.



fun21(A) ->
	{fun21_plug2, A}.


fun22(A, B) ->
	{fun22_plug2, A, B}.


fun23(A, B, C) ->
	{fun23_plug2, A, B, C}.
