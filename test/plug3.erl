-module(plug3).
-compile([export_all]).


version() -> "1.5".

plugin_deps() -> [].


init(_SrvId, #{env:=Env}=Spec) ->
	lager:notice("Plugin ~p starting", [?MODULE]),
	{ok, Spec#{env:=maps:put(?MODULE, ok, Env)}}.

terminate(_SrvId, #{env:=Env}=Spec) ->
	lager:notice("Plugin ~p terminate", [?MODULE]),
	{ok, Spec#{env:=maps:remove(?MODULE, Env)}}.
