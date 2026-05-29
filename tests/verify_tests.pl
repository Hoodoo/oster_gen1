:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/provenance').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').
:- use_module('../engine/probes').
:- use_module('../verify/contracts').
:- use_module('../verify/propagation').
:- use_module('../verify/invariants').

reset_engine :-
    retractall(log:arrived(_, _, _, _, _)),
    retractall(log:arrived_key(_, _, _, _)),
    retractall(log:tier_status(_, _)),
    retractall(log:tier_transition(_, _, _, _)),
    retractall(provenance:caused_by(_, _)),
    retractall(scenes:scene(_)),
    retractall(scenes:scene_parent(_, _)),
    retractall(scenes:scene_rule(_, _, _, _)),
    retractall(gates:gate(_, _, _, _)),
    retractall(gates:gate_condition(_, _)),
    retractall(gates:gate_transform(_, _, _)),
    retractall(gates:gate_blocked(_, _, _)),
    retractall(gates:gate_transformed(_, _, _, _, _)),
    retractall(gates:gate_passed(_, _, _)),
    retractall(fixpoint:rule_trigger(_, _, _)),
    retractall(fixpoint:fixpoint_depth_exceeded(_)),
    retractall(fixpoint:rule_grounding_failed(_, _)),
    retractall(log:event_counter(_)), assertz(log:event_counter(0)),
    retractall(clock:clock_counter(_)), assertz(clock:clock_counter(0)).

:- begin_tests(verify).

% T1 — gate_passed asserted for untransformed gate
test(gate_passed_asserted_for_untransformed, [setup(reset_engine)]) :-
    assertz(scenes:scene(src)),
    assertz(scenes:scene(dst)),
    assertz(gates:gate(g_pass, src, dst, forward)),
    log:inject_event(src, signal, injected(author)),
    log:arrived_key(src, signal, _, EventId),
    gates:attempt_propagation(EventId, g_pass),
    gates:gate_passed(g_pass, EventId, _DestEventId),
    \+ gates:gate_transformed(g_pass, _, _, _, _).

% T2 — provenance chain traverses untransformed gate
test(provenance_chain_traverses_untransformed_gate, [setup(reset_engine)]) :-
    assertz(scenes:scene(src)),
    assertz(scenes:scene(dst)),
    assertz(gates:gate(g_pass, src, dst, forward)),
    log:inject_event(src, signal, injected(author)),
    log:arrived_key(src, signal, _, EventId),
    gates:attempt_propagation(EventId, g_pass),
    gates:gate_passed(g_pass, EventId, DestEventId),
    provenance:provenance_chain(DestEventId, Chain),
    member(step(EventId, _), Chain),
    \+ member(step(unknown_gate_source(_), _), Chain).

% T3 — check_no_self_generating_rules: clean world passes
test(check_no_self_generating_rules_clean_passes, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    assertz(scenes:scene_rule(r_safe, room,
        arrived(_, room, trigger, _, hot), response)),
    check_no_self_generating_rules.

% T4 — check_no_self_generating_rules: self-generating rule caught
test(check_no_self_generating_rules_self_gen_fails, [setup(reset_engine), fail]) :-
    assertz(scenes:scene(room)),
    assertz(scenes:scene_rule(r_bad, room,
        arrived(_, room, noise, _, hot), noise)),
    check_no_self_generating_rules.

% T5 — check_provenance_acyclic: clean log passes
test(check_provenance_acyclic_clean_passes, [setup(reset_engine)]) :-
    log:inject_event(s1, ev1, injected(author)),
    log:inject_event(s1, ev2, injected(author)),
    log:inject_event(s1, ev3, injected(author)),
    check_provenance_acyclic.

% T6 — check_rule_conditions_safe: safe rule passes
test(check_rule_conditions_safe_safe_passes, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    assertz(scenes:scene_rule(r_safe6, room,
        arrived(_, room, signal, _, hot), response)),
    check_rule_conditions_safe(default_safe_predicates).

% T7 — check_rule_conditions_safe: unsafe call caught
test(check_rule_conditions_safe_unsafe_fails, [setup(reset_engine), fail]) :-
    assertz(scenes:scene(room)),
    assertz(scenes:scene_rule(r_unsafe, room,
        assert(foo), response)),
    check_rule_conditions_safe(default_safe_predicates).

% T8 — verify_contracts: clean world passes
test(verify_contracts_clean_passes, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    assertz(scenes:scene_rule(r_valid, room,
        arrived(_, room, signal, _, hot), response)),
    log:inject_event(room, signal, injected(author)),
    verify_contracts.

% T9 — verify_contracts: bad rule fails
test(verify_contracts_bad_rule_fails, [setup(reset_engine), fail]) :-
    assertz(scenes:scene(room)),
    assertz(scenes:scene_rule(r_selfgen, room,
        arrived(_, room, noise, _, hot), noise)),
    verify_contracts.

% T10 — check_log_append_only: growing log passes
test(check_log_append_only_growing_passes, [setup(reset_engine)]) :-
    record_log_baseline,
    log:inject_event(s1, ev1, injected(author)),
    log:inject_event(s1, ev2, injected(author)),
    check_log_append_only.

% T11 — check_probes_side_effect_free: probe leaves log unchanged
test(check_probes_side_effect_free_passes, [setup(reset_engine)]) :-
    assertz(scenes:scene(room11)),
    assertz(scenes:scene_rule(r11, room11,
        arrived(_, room11, signal, _, hot), response)),
    record_log_baseline,
    check_probes_side_effect_free,
    check_log_append_only.

% T12 — check_gates_never_mutate_source: clean world passes
test(check_gates_never_mutate_source_passes, [setup(reset_engine)]) :-
    assertz(scenes:scene(src12)),
    assertz(scenes:scene(dst12)),
    assertz(gates:gate(g12, src12, dst12, forward)),
    assertz(gates:gate_transform(g12, raw_signal, clean_signal)),
    log:inject_event(src12, raw_signal, injected(author)),
    log:arrived_key(src12, raw_signal, _, EventId),
    gates:attempt_propagation(EventId, g12),
    check_gates_never_mutate_source.

% T13 — propagation_coverage: crossed outcome
test(propagation_coverage_crossed, [setup(reset_engine)]) :-
    assertz(scenes:scene(src13)),
    assertz(scenes:scene(dst13)),
    assertz(gates:gate(g_cov, src13, dst13, forward)),
    assertz(scenes:scene_rule(r_dst13, dst13,
        arrived(_, dst13, response, _, _), result)),
    assert_propagation_test(g_cov, response, crossed),
    verify_propagation_tests.

% T14 — propagation_coverage: blocked outcome
test(propagation_coverage_blocked, [setup(reset_engine)]) :-
    assertz(scenes:scene(src14)),
    assertz(scenes:scene(dst14)),
    assertz(gates:gate(g_blocked, src14, dst14, forward)),
    assertz(gates:gate_condition(g_blocked, fail)),
    assertz(scenes:scene_rule(r_dst14, dst14,
        arrived(_, dst14, response, _, _), result)),
    assert_propagation_test(g_blocked, response, blocked),
    verify_propagation_tests.

% T15 — check_rules_locality: cross-scene query flagged
test(check_rules_locality_cross_scene_fails, [setup(reset_engine), fail]) :-
    assertz(scenes:scene(room_a)),
    assertz(scenes:scene(room_b)),
    assertz(scenes:scene_rule(r_cross, room_a,
        arrived(_, room_b, signal, _, _), response)),
    check_rules_locality.

:- end_tests(verify).
