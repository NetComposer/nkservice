-ifndef(NKSERVICE_ACTOR_DEBUG_HRL_).
-define(NKSERVICE_ACTOR_DEBUG_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================

-include("nkservice_actor.hrl").

-define(DEBUG(Txt, Args, State),
    case erlang:get(nkservice_actor_debug) of
        true -> ?LLOG(debug, Txt, Args, State);
        _ -> ok
    end).

-define(LLOG(Type, Txt, Args, State),
    lager:Type(
        [
            {srv_id, State#actor_st.id#actor_id.srv_id},
            {uid, State#actor_st.id#actor_id.uid},
            {kind, State#actor_st.id#actor_id.kind}
        ],
        "NkSERVICE ~s Actor ~s (~s, ~s) " ++ Txt,
        [
            State#actor_st.srv_id,
            State#actor_st.id#actor_id.name,
            State#actor_st.id#actor_id.kind,
            State#actor_st.id#actor_id.uid | Args
        ]
    )).

-endif.
