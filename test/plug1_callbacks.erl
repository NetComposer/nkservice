-module(plug1_callbacks).
-compile([export_all]).


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

