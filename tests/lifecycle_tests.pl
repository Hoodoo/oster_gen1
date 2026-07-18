:- encoding(utf8).
:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/provenance').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').
:- use_module('../lifecycle/tiers').
:- use_module('../lifecycle/closure').
:- use_module('../lifecycle/compaction').

reset_engine :-
    retractall(log:arrived(_, _, _, _, _)),
    retractall(log:arrived_key(_, _, _, _)),
    retractall(log:tier_status(_, _)),
    retractall(log:tier_transition(_, _, _, _)),
    retractall(log:unprocessed(_)),
    retractall(provenance:caused_by(_, _)),
    retractall(scenes:scene(_)),
    retractall(scenes:scene_parent(_, _)),
    retractall(scenes:scene_rule(_, _, _, _)),
    retractall(gates:gate(_, _, _, _)),
    retractall(gates:gate_condition(_, _)),
    retractall(gates:gate_transform(_, _, _)),
    retractall(gates:gate_blocked(_, _, _)),
    retractall(gates:gate_transformed(_, _, _, _, _)),
    retractall(fixpoint:rule_trigger(_, _, _)),
    retractall(fixpoint:fixpoint_depth_exceeded(_)),
    retractall(fixpoint:rule_grounding_failed(_, _)),
    retractall(log:event_counter(_)), assertz(log:event_counter(0)),
    retractall(log:clock_counter(_)), assertz(log:clock_counter(0)).

:- begin_tests(lifecycle).

% T1 — promote_to_cold does not retract arrived
% Inject 3 events, call promote_to_cold(deck, 99), assert all 3 arrived facts still exist
% and log_count is unchanged.
test(promote_cold_no_retract, [setup(reset_engine)]) :-
    inject_event(deck, ev1, injected(player)),
    inject_event(deck, ev2, injected(player)),
    inject_event(deck, ev3, injected(player)),
    log_count(Before),
    promote_to_cold(deck, 99),
    log_count(After),
    After =:= Before,
    arrived(_, deck, ev1, _, _),
    arrived(_, deck, ev2, _, _),
    arrived(_, deck, ev3, _, _).

% T2 — promoted events have cold tier_status
% Inject 2 events, promote_to_cold(deck, 99), assert tier_status(EventId, cold) for both
% and NOT tier_status(EventId, hot) for either.
test(promote_cold_tier_status, [setup(reset_engine)]) :-
    inject_event(deck, ev1, injected(player)),
    inject_event(deck, ev2, injected(player)),
    arrived_key(deck, ev1, _, Id1),
    arrived_key(deck, ev2, _, Id2),
    promote_to_cold(deck, 99),
    tier_status(Id1, cold),
    tier_status(Id2, cold),
    \+ tier_status(Id1, hot),
    \+ tier_status(Id2, hot).

% T3 — tier_transition audit records appended
% Inject 2 events, promote_to_cold(deck, 99), assert exactly 2 tier_transition(_, hot, cold, _) facts.
test(tier_transition_audit, [setup(reset_engine)]) :-
    inject_event(deck, ev1, injected(player)),
    inject_event(deck, ev2, injected(player)),
    promote_to_cold(deck, 99),
    aggregate_all(count, tier_transition(_, hot, cold, _), N),
    N =:= 2.

% T4 — fixpoint skips cold events
% Declare scene deck, rule r_test: cond arrived(_, deck, signal, _, hot), consequence echo.
% Inject signal. world_step -> assert echo arrived (count=1).
% promote_to_cold(deck, 99). world_step again (no new injection).
% Assert echo count still 1 — cold events were not reprocessed.
test(fixpoint_skips_cold, [setup(reset_engine)]) :-
    assertz(scenes:scene_rule(r_test, deck, arrived(_, deck, signal, _, hot), echo)),
    inject_event(deck, signal, injected(player)),
    world_step,
    aggregate_all(count, arrived(_, deck, echo, _, _), N1),
    N1 =:= 1,
    promote_to_cold(deck, 99),
    world_step,
    aggregate_all(count, arrived(_, deck, echo, _, _), N2),
    N2 =:= 1.

% T5 — cold events remain readable
% Inject an event. promote_to_cold. Assert arrived still holds. Assert cold_events includes it.
test(cold_events_readable, [setup(reset_engine)]) :-
    inject_event(deck, ev1, injected(player)),
    arrived_key(deck, ev1, _, EventId),
    promote_to_cold(deck, 99),
    arrived(EventId, deck, ev1, _, _),
    cold_events(deck, ColdList),
    member(EventId, ColdList).

% T6 — promote_to_archived from cold
% Inject event. promote_to_cold. promote_to_archived. Assert archived tier_status.
% Assert archived_events includes it. Assert arrived still holds.
test(promote_archived_from_cold, [setup(reset_engine)]) :-
    inject_event(deck, ev1, injected(player)),
    arrived_key(deck, ev1, _, EventId),
    promote_to_cold(deck, 99),
    promote_to_archived(deck, 99),
    tier_status(EventId, archived),
    archived_events(deck, ArchivedList),
    member(EventId, ArchivedList),
    arrived(EventId, deck, ev1, _, _).

% T7 — promote_to_archived does not skip hot events
% Inject event (hot). Call promote_to_archived without promote_to_cold. Assert still hot.
test(archived_skips_hot, [setup(reset_engine)]) :-
    inject_event(deck, ev1, injected(player)),
    arrived_key(deck, ev1, _, EventId),
    promote_to_archived(deck, 99),
    tier_status(EventId, hot),
    \+ tier_status(EventId, archived).

% T8 — declare_closure injects closed event
% Declare scene room. advance_clock. declare_closure(room, 1).
% Assert arrived(_, room, closed(room, clock(1)), _, hot).
% Assert caused_by(EventId, injected(author)).
test(declare_closure_injects, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    advance_clock,
    declare_closure(room, 1),
    arrived(EventId, room, closed(room, clock(1)), _, hot),
    caused_by(EventId, injected(author)).

% T9 — closure event propagates through gates
% Declare scenes patron, tavern. Gate g_up from patron to tavern, upward.
% declare_closure(patron, 1). world_step.
% Assert arrived(_, tavern, closed(patron, clock(1)), _, hot).
test(closure_propagates_gate, [setup(reset_engine)]) :-
    assertz(scenes:scene(patron)),
    assertz(scenes:scene(tavern)),
    assertz(gates:gate(g_up, patron, tavern, upward)),
    declare_closure(patron, 1),
    world_step,
    arrived(_, tavern, closed(patron, clock(1)), _, hot).

% T10 — scene_closed query
% Declare scene room. advance_clock. declare_closure(room, 1).
% scene_closed(room, 1) succeeds. \+ scene_closed(room, 99).
test(scene_closed_query, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    advance_clock,
    declare_closure(room, 1),
    scene_closed(room, 1),
    \+ scene_closed(room, 99).

% T11 — assert_summary injects summary event
% Inject 3 events into deck. assert_summary(deck, order, [card(1), card(2)], 99).
% Assert arrived(_, deck, summary(order, [card(1), card(2)]), _, _).
test(assert_summary_injects, [setup(reset_engine)]) :-
    inject_event(deck, ev1, injected(player)),
    inject_event(deck, ev2, injected(player)),
    inject_event(deck, ev3, injected(player)),
    assert_summary(deck, order, [card(1), card(2)], 99),
    arrived(_, deck, summary(order, [card(1), card(2)]), _, _).

% T12 — assert_summary promotes underlying events to cold
% Inject 3 events into deck. Record their EventIds. assert_summary(deck, order, [card(1), card(2)], 99).
% Assert all 3 original EventIds have tier_status cold.
% Assert summary_exists(deck, order, _) succeeds.
test(assert_summary_promotes_cold, [setup(reset_engine)]) :-
    inject_event(deck, ev1, injected(player)),
    inject_event(deck, ev2, injected(player)),
    inject_event(deck, ev3, injected(player)),
    arrived_key(deck, ev1, _, Id1),
    arrived_key(deck, ev2, _, Id2),
    arrived_key(deck, ev3, _, Id3),
    assert_summary(deck, order, [card(1), card(2)], 99),
    tier_status(Id1, cold),
    tier_status(Id2, cold),
    tier_status(Id3, cold),
    summary_exists(deck, order, _).

% T13 — update_tier_status correctness
% Inject event. Assert tier_status(EventId, hot). Call update_tier_status(EventId, cold).
% Assert tier_status(EventId, cold). Assert exactly ONE tier_status fact for EventId.
test(update_tier_status_correctness, [setup(reset_engine)]) :-
    inject_event(deck, ev1, injected(player)),
    arrived_key(deck, ev1, _, EventId),
    tier_status(EventId, hot),
    update_tier_status(EventId, cold),
    tier_status(EventId, cold),
    aggregate_all(count, tier_status(EventId, _), N),
    N =:= 1.

% T14 — all scene events are cold after declare_closure + promote_to_cold
% Guard: closing a scene must settle its history, not just inject the closed event.
test(t14_closure_demotes_events_to_cold, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    inject_event(room, signal, injected(player)),
    inject_event(room, echo, injected(player)),
    clock_value(Clock),
    declare_closure(room, Clock),
    world_step,
    promote_to_cold(room, Clock),
    % No hot events should remain in room
    findall(E,
            ( log:arrived(E, room, _, _, _),
              log:tier_status(E, hot)
            ),
            StillHot),
    StillHot = [].

:- end_tests(lifecycle).
