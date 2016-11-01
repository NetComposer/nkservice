-module(plug3).
-compile([export_all]).


plugin_deps() -> [].

plugin_start(Spec) ->
	lager:notice("Plugin ~p starting", [?MODULE]),
	{ok, maps:put(?MODULE, ok, Spec)}.

plugin_stop(Spec) ->
	lager:notice("Plugin ~p terminate", [?MODULE]),
	{ok, maps:remove(?MODULE, Spec)}.


fun31(A) ->
	{fun31_plug3, A}.

fun32(A, B) ->
	{fun32_plug3, A, B}.

fun33(A) ->
	{fun33_plug3, A}.
