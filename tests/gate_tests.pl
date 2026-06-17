:- encoding(utf8).
:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/provenance').
:- use_module('../engine/gates').

reset_engine :-
    retractall(arrived(_, _, _, _, _)),
    retractall(arrived_key(_, _, _, _)),
    retractall(tier_status(_, _)),
    retractall(tier_transition(_, _, _, _)),
    retractall(caused_by(_, _)),
    retractall(scene(_)),
    retractall(scene_parent(_, _)),
    retractall(scene_rule(_, _, _, _)),
    retractall(gate(_, _, _, _)),
    retractall(gate_condition(_, _)),
    retractall(gate_transform(_, _, _)),
    retractall(gate_term_filter(_, _)),
    retractall(gate_blocked(_, _, _)),
    retractall(gate_transformed(_, _, _, _, _)),
    retractall(event_counter(_)), assertz(event_counter(0)),
    retractall(clock_counter(_)), assertz(clock_counter(0)).

:- begin_tests(gates).

test(t1_gate_declaration, [setup(reset_engine)]) :-
    declare_scene(deck),
    declare_scene(hand),
    declare_gate(g_draw, deck, hand, lateral),
    gate(g_draw, deck, hand, lateral).

test(t2_duplicate_gate_id_throws, [setup(reset_engine)]) :-
    declare_scene(a),
    declare_scene(b),
    declare_gate(g_001, a, b, lateral),
    catch(
        declare_gate(g_001, a, b, upward),
        error(duplicate_gate_id(g_001), _),
        true
    ).

test(t3_open_gate_no_conditions, [setup(reset_engine)]) :-
    declare_scene(a),
    declare_scene(b),
    declare_gate(g_open, a, b, lateral),
    gate_open(g_open).

test(t4_closed_gate_condition_fails, [setup(reset_engine)]) :-
    declare_scene(a),
    declare_scene(b),
    declare_gate(g_closed, a, b, lateral),
    assertz(gates:gate_condition(g_closed, fail)),
    \+ gate_open(g_closed).

test(t5_open_gate_all_conditions_pass, [setup(reset_engine)]) :-
    declare_scene(a),
    declare_scene(b),
    declare_gate(g_multi, a, b, lateral),
    assertz(gates:gate_condition(g_multi, true)),
    assertz(gates:gate_condition(g_multi, 1 =:= 1)),
    gate_open(g_multi).

test(t6_propagation_open_no_transform, [setup(reset_engine)]) :-
    declare_scene(src),
    declare_scene(dst),
    declare_gate(g_pass, src, dst, lateral),
    inject_event(src, noise(fight), injected(player)),
    arrived_key(src, noise(fight), _, EventId),
    attempt_propagation(EventId, g_pass),
    arrived(_, dst, noise(fight), _, hot),
    arrived(EventId, src, noise(fight), _, hot).

test(t7_propagation_blocked, [setup(reset_engine)]) :-
    declare_scene(src),
    declare_scene(dst),
    declare_gate(g_block, src, dst, lateral),
    assertz(gates:gate_condition(g_block, fail)),
    inject_event(src, noise(fight), injected(player)),
    arrived_key(src, noise(fight), _, EventId),
    attempt_propagation(EventId, g_block),
    gate_blocked(g_block, EventId, _),
    \+ arrived(_, dst, noise(fight), _, _).

test(t8_propagation_with_transform, [setup(reset_engine)]) :-
    declare_scene(warrior_a),
    declare_scene(warrior_b),
    declare_gate(g_strike, warrior_a, warrior_b, lateral),
    assertz((gates:gate_transform(g_strike, strike(D), strike(D2)) :- D2 is max(0, D - 3))),
    inject_event(warrior_a, strike(8), injected(player)),
    arrived_key(warrior_a, strike(8), _, EventId),
    attempt_propagation(EventId, g_strike),
    arrived(_, warrior_b, strike(5), _, hot),
    gate_transformed(g_strike, EventId, _, strike(8), strike(5)),
    arrived(EventId, warrior_a, strike(8), _, hot).

test(t9_source_event_unchanged, [setup(reset_engine)]) :-
    declare_scene(warrior_a),
    declare_scene(warrior_b),
    declare_gate(g_strike, warrior_a, warrior_b, lateral),
    assertz((gates:gate_transform(g_strike, strike(D), strike(D2)) :- D2 is max(0, D - 3))),
    inject_event(warrior_a, strike(8), injected(player)),
    arrived_key(warrior_a, strike(8), _, EventId),
    attempt_propagation(EventId, g_strike),
    arrived(EventId, warrior_a, strike(8), _, hot),
    \+ arrived(_, warrior_a, strike(5), _, _).

test(t10_propagate_from_scene_no_gates, [setup(reset_engine)]) :-
    declare_scene(isolated),
    inject_event(isolated, some_event, injected(player)),
    arrived_key(isolated, some_event, _, EventId),
    log_count(Before),
    propagate_from_scene(isolated, EventId),
    log_count(After),
    After =:= Before.

test(t11_propagate_from_scene_multiple_gates, [setup(reset_engine)]) :-
    declare_scene(hub),
    declare_scene(dest_1),
    declare_scene(dest_2),
    declare_gate(g1, hub, dest_1, lateral),
    declare_gate(g2, hub, dest_2, lateral),
    inject_event(hub, signal, injected(player)),
    arrived_key(hub, signal, _, EventId),
    propagate_from_scene(hub, EventId),
    arrived(_, dest_1, signal, _, hot),
    arrived(_, dest_2, signal, _, hot).

test(t12_gate_transformed_links_events, [setup(reset_engine)]) :-
    declare_scene(warrior_a),
    declare_scene(warrior_b),
    declare_gate(g_strike, warrior_a, warrior_b, lateral),
    assertz((gates:gate_transform(g_strike, strike(D), strike(D2)) :- D2 is max(0, D - 3))),
    inject_event(warrior_a, strike(8), injected(player)),
    arrived_key(warrior_a, strike(8), _, EventId),
    attempt_propagation(EventId, g_strike),
    gate_transformed(g_strike, EventId, DestEventId, _, _),
    arrived(DestEventId, warrior_b, strike(5), _, hot).

test(t13_gates_from_scene, [setup(reset_engine)]) :-
    declare_scene(room),
    declare_scene(hallway),
    declare_scene(outside),
    declare_gate(g_door, room, hallway, lateral),
    declare_gate(g_window, room, outside, lateral),
    gates_from_scene(room, GateIds),
    memberchk(g_door, GateIds),
    memberchk(g_window, GateIds),
    declare_scene(empty_room),
    gates_from_scene(empty_room, []).

% T14 — term filter blocks non-matching term
test(t14_term_filter_blocks, [setup(reset_engine)]) :-
    declare_scene(src),
    declare_scene(dst),
    declare_gate(g_filtered, src, dst, lateral),
    assertz(gates:gate_term_filter(g_filtered, noise(fight))),
    inject_event(src, strike(5), injected(player)),
    arrived_key(src, strike(5), _, EventId),
    % attempt_propagation fails when term filter rejects; absorb the failure
    ( attempt_propagation(EventId, g_filtered) -> true ; true ),
    \+ arrived(_, dst, strike(5), _, _),
    gates:gate_blocked(g_filtered, EventId, _).

% T15 — term filter permits matching term
test(t15_term_filter_permits, [setup(reset_engine)]) :-
    declare_scene(src),
    declare_scene(dst),
    declare_gate(g_filtered, src, dst, lateral),
    assertz(gates:gate_term_filter(g_filtered, noise(fight))),
    inject_event(src, noise(fight), injected(player)),
    arrived_key(src, noise(fight), _, EventId),
    attempt_propagation(EventId, g_filtered),
    arrived(_, dst, noise(fight), _, _),
    \+ gates:gate_blocked(g_filtered, EventId, _).

:- end_tests(gates).
