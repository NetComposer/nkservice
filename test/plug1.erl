-module(plug1).
-compile([export_all]).


plugin_deps() -> [plug2].

plugin_start(Spec) ->
	lager:notice("Plugin ~p starting", [?MODULE]),
	{ok, maps:put(?MODULE, ok, Spec)}.

plugin_stop(Spec) ->
	lager:notice("Plugin ~p terminate", [?MODULE]),
	{ok, maps:remove(?MODULE, Spec)}.




fun21(A) ->
	{fun21_plug1, A}.

fun22(A, B) ->
	{continue, [{plug1, A}, B]}.


fun11(A) ->
	{fun11_plug1, A}.

fun12(A, B) ->
	{fun12_plug1, A, B}.

fun13(A, B, C) ->
	{fun13_plug1, A, B, C}.

