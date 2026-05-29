:- module(tiers, [
    promote_to_cold/2,
    promote_to_archived/2,
    cold_events/2,
    archived_events/2
]).

:- use_module('../engine/log').
:- use_module('../engine/clock').

promote_to_cold(Scene, UpToClock) :-
    clock_value(Now),
    forall(
        ( arrived(EventId, Scene, _, Clock, _),
          tier_status(EventId, hot),
          Clock =< UpToClock
        ),
        ( update_tier_status(EventId, cold),
          assertz(tier_transition(EventId, hot, cold, Now))
        )
    ).

promote_to_archived(Scene, UpToClock) :-
    clock_value(Now),
    forall(
        ( arrived(EventId, Scene, _, Clock, _),
          tier_status(EventId, cold),
          Clock =< UpToClock
        ),
        ( update_tier_status(EventId, archived),
          assertz(tier_transition(EventId, cold, archived, Now))
        )
    ).

cold_events(Scene, Events) :-
    findall(EventId,
            ( arrived(EventId, Scene, _, _, _),
              tier_status(EventId, cold)
            ),
            Events).

archived_events(Scene, Events) :-
    findall(EventId,
            ( arrived(EventId, Scene, _, _, _),
              tier_status(EventId, archived)
            ),
            Events).
