-module(serv1).
-compile([export_all]).


version() -> "1".

plugin_deps() -> nklib_util:randomize([plug1, plug3]).

init(_SrvId, #{env:=Env}=Spec) ->
	lager:notice("Plugin ~p starting/updating", [?MODULE]),
	{ok, Spec#{env:=maps:put(?MODULE, ok, Env)}}.

terminate(_SrvId, #{env:=Env}=Spec) ->
	lager:notice("Plugin ~p terminate", [?MODULE]),
	{ok, Spec#{env:=maps:remove(?MODULE, Env)}}.
