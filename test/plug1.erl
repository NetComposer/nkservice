-module(plug1).
-compile([export_all]).


version() -> "1".

deps() -> [plug2].

init(_SrvId, #{env:=Env}=Spec) ->
	lager:notice("Plugin ~p starting", [?MODULE]),
	{ok, Spec#{env:=maps:put(?MODULE, ok, Env)}}.

terminate(_SrvId, #{env:=Env}=Spec) ->
	lager:notice("Plugin ~p terminate", [?MODULE]),
	{ok, Spec#{env:=maps:remove(?MODULE, Env)}}.
