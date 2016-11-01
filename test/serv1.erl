-module(serv1).
-compile([export_all]).



plugin_deps() -> nklib_util:randomize([plug1, plug3]).


plugin_start(Spec) ->
	lager:notice("Service ~p starting", [?MODULE]),
	{ok, maps:put(?MODULE, ok, Spec)}.

plugin_stop(Spec) ->
	lager:notice("Service ~p terminate", [?MODULE]),
	{ok, maps:remove(?MODULE, Spec)}.


service_init(_Spec, State) ->
	{ok, State#{serv1=>0}}.

service_handle_call(Msg, From, #{serv1:=Counter}=State) ->
	{continue, [Msg, From, State#{serv1:=Counter+1}]}.


fun11(A) ->
	{fun11_serv1, A}.

fun12(A, B) ->
	{continue, [{serv1, A}, B]}.


fun21(A) ->
	{fun21_serv1, A}.

fun22(A, B) ->
	{continue, [{serv1, A}, B]}.



fun31(A) ->
	{fun31_serv1, A}.

fun32(A, B) ->
	{continue, [{serv1, A}, B]}.

