-module(serv1_callbacks).
-compile([export_all]).

nks_service_init(SrvId, _Spec) ->
	{ok, {state, SrvId}}.

nks_handle_call(Msg, From, State) ->
	{continue, [Msg, From, {ok, State}]}.


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