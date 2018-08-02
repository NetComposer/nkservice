-ifndef(NKSERVICE_ACTOR_DEBUG_HRL_).
-define(NKSERVICE_ACTOR_DEBUG_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================

-include("nkservice_actor.hrl").

-define(DEBUG(Txt, Args),
    case erlang:get(nkservice_actor_debug) of
        true -> ?LLOG(debug, Txt, Args);
        _ -> ok
    end).


-define(DEBUG(Txt, Args, State),
    case erlang:get(nkservice_actor_debug) of
        true -> ?LLOG(debug, Txt, Args, State);
        _ -> ok
    end).


-define(LLOG(Type, Txt, Args),
    lager:Type("NkSERVICE Actor " ++ Txt, Args)).


-define(LLOG(Type, Txt, Args, State),
    lager:Type(
        [
            {srv_id, State#actor_st.actor#actor.id#actor_id.srv},
            {uid, State#actor_st.actor#actor.id#actor_id.uid},
            {class, State#actor_st.actor#actor.id#actor_id.class}
        ],
        "NkSERVICE ~s Actor ~s (~s, ~s) " ++ Txt,
        [
            State#actor_st.actor#actor.id#actor_id.srv,
            State#actor_st.actor#actor.id#actor_id.name,
            State#actor_st.actor#actor.id#actor_id.class,
            State#actor_st.actor#actor.id#actor_id.uid | Args
        ]
    )).

-endif.
