:- module(log, [
    inject_event/3,
    hot_events/1,
    log_count/1,
    arrived/5,
    arrived_key/4,
    tier_status/2,
    tier_transition/4,
    caused_by/2,
    fresh_event_id/1,
    event_counter/1,
    update_tier_status/2
]).

:- use_module(library(aggregate)).
:- use_module(clock).
:- use_module(provenance).

:- dynamic arrived/5.
% arrived(EventId, Scene, Term, Clock, Tier)

:- dynamic arrived_key/4.
% arrived_key(Scene, Term, Clock, EventId)

:- dynamic tier_status/2.
% tier_status(EventId, Tier)

:- dynamic tier_transition/4.
% tier_transition(EventId, FromTier, ToTier, Clock)

:- dynamic event_counter/1.
event_counter(0).

fresh_event_id(EventId) :-
    retract(event_counter(N)),
    N1 is N + 1,
    assertz(event_counter(N1)),
    atom_concat(evt_, N1, EventId).

inject_event(Scene, Term, Cause) :-
    clock_value(Clock),
    (   arrived_key(Scene, Term, Clock, _)
    ->  true
    ;   fresh_event_id(EventId),
        assertz(arrived(EventId, Scene, Term, Clock, hot)),
        assertz(arrived_key(Scene, Term, Clock, EventId)),
        assertz(tier_status(EventId, hot)),
        assertz(caused_by(EventId, Cause))
    ).

hot_events(Events) :-
    findall(EventId, tier_status(EventId, hot), Events).

log_count(N) :-
    aggregate_all(count, arrived(_, _, _, _, _), N).

update_tier_status(EventId, NewTier) :-
    retract(tier_status(EventId, _)),
    assertz(tier_status(EventId, NewTier)).
