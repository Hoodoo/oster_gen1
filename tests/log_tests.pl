:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').

reset_log :-
    retractall(arrived(_, _, _, _, _)),
    retractall(arrived_key(_, _, _, _)),
    retractall(tier_status(_, _)),
    retractall(tier_transition(_, _, _, _)),
    retractall(caused_by(_, _)),
    retractall(unprocessed(_)),
    retractall(event_counter(_)),
    assertz(event_counter(0)),
    retractall(clock_counter(_)),
    assertz(clock_counter(0)).

:- begin_tests(log_and_clock).

test(t1_basic_injection, [setup(reset_log)]) :-
    inject_event(scene_a, greet(world), user),
    aggregate_all(count, arrived(_, scene_a, greet(world), 0, hot), 1),
    findall(Id, arrived(Id, scene_a, greet(world), 0, hot), [EventId]),
    tier_status(EventId, hot),
    arrived_key(scene_a, greet(world), 0, EventId).

test(t2_deduplication, [setup(reset_log)]) :-
    inject_event(scene_a, dup_event, user),
    inject_event(scene_a, dup_event, user),
    aggregate_all(count, arrived(_, scene_a, dup_event, 0, hot), Count),
    Count =:= 1.

test(t3_clock_stamps_events, [setup(reset_log)]) :-
    advance_clock,
    advance_clock,
    inject_event(scene_b, stamped_event, user),
    findall(Id, arrived(Id, scene_b, stamped_event, 2, hot), [_]),
    \+ arrived(_, scene_b, stamped_event, 0, hot),
    \+ arrived(_, scene_b, stamped_event, 1, hot).

test(t4_append_only, [setup(reset_log)]) :-
    inject_event(scene_a, ev1, user),
    inject_event(scene_b, ev2, user),
    inject_event(scene_c, ev3, user),
    log_count(3),
    advance_clock,
    inject_event(scene_a, ev4, user),
    log_count(C2),
    C2 >= 3.

test(t5_tier_status_hot, [setup(reset_log)]) :-
    inject_event(scene_a, some_event, user),
    findall(Id, arrived(Id, _, some_event, _, _), [EventId]),
    tier_status(EventId, hot).

test(t6_tier_transition_audit, [setup(reset_log)]) :-
    inject_event(scene_a, transition_event, user),
    findall(Id, arrived(Id, _, transition_event, _, _), [EventId]),
    assertz(tier_transition(EventId, hot, cold, 1)),
    assertz(tier_transition(EventId, cold, archived, 2)),
    findall(T, tier_transition(EventId, _, T, _), Tiers),
    length(Tiers, 2).

test(t7_clock_advances, [setup(reset_log)]) :-
    clock_value(V0),
    advance_clock,
    advance_clock,
    advance_clock,
    clock_value(V1),
    V1 =:= V0 + 3.

test(t8_event_id_uniqueness, [setup(reset_log)]) :-
    inject_event(scene_a, event_one, user),
    inject_event(scene_a, event_two, user),
    inject_event(scene_b, event_three, user),
    inject_event(scene_b, event_four, user),
    inject_event(scene_c, event_five, user),
    findall(Id, arrived(Id, _, _, _, _), Ids),
    length(Ids, 5),
    sort(Ids, Sorted),
    length(Sorted, 5).

test(t9_caused_by_asserted, [setup(reset_log)]) :-
    inject_event(scene_a, action_event, injected(player)),
    findall(Id, arrived(Id, scene_a, action_event, _, _), [EventId]),
    caused_by(EventId, injected(player)).

:- end_tests(log_and_clock).
