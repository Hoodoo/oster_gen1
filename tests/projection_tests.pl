:- encoding(utf8).
:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/provenance').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').
:- use_module('../engine/probes').
:- use_module('../lifecycle/tiers').
:- use_module('../projections/legal_actions').
:- use_module('../projections/why_blocked').
:- use_module('../projections/post_fixpoint').
:- use_module('../projections/investigation').

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
    % DECISION: spec says log:clock_counter but clock_counter is defined in the
    % clock module, not log. Using clock:clock_counter to actually reset the clock;
    % otherwise post_fixpoint_summary(Clock,...) tests fail after any advance_clock call.
    retractall(clock:clock_counter(_)), assertz(clock:clock_counter(0)).

:- begin_tests(projections).

% T1 — legal_actions: open gate with vocabulary
test(legal_actions_open_gate_vocab, [setup(reset_engine)]) :-
    assertz(scenes:scene(patron)),
    assertz(scenes:scene(tavern)),
    assertz(gates:gate(g_up, patron, tavern, upward)),
    assertz(scenes:scene_rule(r_noise, tavern, true, noise(fight))),
    legal_actions(patron, Actions),
    member(action(g_up, tavern, noise(fight)), Actions).

% T2 — legal_actions: closed gate excluded
test(legal_actions_closed_gate_excluded, [setup(reset_engine)]) :-
    assertz(scenes:scene(patron)),
    assertz(scenes:scene(tavern)),
    assertz(gates:gate(g_up, patron, tavern, upward)),
    assertz(scenes:scene_rule(r_noise, tavern, true, noise(fight))),
    assertz(gates:gate_condition(g_up, fail)),
    legal_actions(patron, Actions),
    Actions = [].

% T3 — legal_actions: no gates returns empty
test(legal_actions_no_gates_empty, [setup(reset_engine)]) :-
    assertz(scenes:scene(isolated)),
    legal_actions(isolated, Actions),
    Actions = [].

% T4 — why_blocked: no gate
test(why_blocked_no_gate, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    why_blocked(room, any_event, Explanation),
    Explanation = no_gate(room, any_event).

% T5 — why_blocked: gate closed, condition identified
test(why_blocked_gate_closed_condition, [setup(reset_engine)]) :-
    assertz(scenes:scene(src)),
    assertz(scenes:scene(dst)),
    assertz(gates:gate(g_check, src, dst, upward)),
    assertz(gates:gate_condition(g_check, fail)),
    why_blocked(src, signal, Explanation),
    Explanation = blocked_by(g_check, fail).

% T6 — why_blocked: gate open
test(why_blocked_gate_open, [setup(reset_engine)]) :-
    assertz(scenes:scene(src)),
    assertz(scenes:scene(dst)),
    assertz(gates:gate(g_open, src, dst, upward)),
    why_blocked(src, signal, Explanation),
    Explanation = gate_is_open(g_open).

% T7 — why_blocked_history
test(why_blocked_history_succeeds, [setup(reset_engine)]) :-
    assertz(scenes:scene(src)),
    assertz(scenes:scene(dst)),
    assertz(gates:gate(g_blocked, src, dst, upward)),
    assertz(gates:gate_condition(g_blocked, fail)),
    inject_event(src, signal, injected(player)),
    arrived_key(src, signal, _, EventId),
    attempt_propagation(EventId, g_blocked),
    why_blocked_history(g_blocked, EventId, _Clock).

% T8 — post_fixpoint_summary: correct clock
% DECISION: spec says post_fixpoint_summary(1, Summary) but alpha arrives at clock 0
% and beta at clock 1; querying clock 0 is needed to find alpha and exclude beta.
% The spec comment ("beta arrived at clock 1, alpha at clock 0") confirms clock 0.
test(post_fixpoint_correct_clock, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    inject_event(room, alpha, injected(player)),
    advance_clock,
    inject_event(room, beta, injected(player)),
    post_fixpoint_summary(0, Summary),
    member(change(room, alpha, _), Summary),
    \+ member(change(room, beta, _), Summary).

% T9 — post_fixpoint_summary: excludes cold events
test(post_fixpoint_excludes_cold, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    inject_event(room, ev1, injected(player)),
    inject_event(room, ev2, injected(player)),
    promote_to_cold(room, 99),
    post_fixpoint_summary(0, Summary),
    Summary = [].

% T10 — post_fixpoint_summary: includes cause
test(post_fixpoint_includes_cause, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    inject_event(room, trigger, injected(player)),
    post_fixpoint_summary(0, Summary),
    member(change(room, trigger, injected(player)), Summary).

% T11 — investigation_chain: single hop
test(investigation_chain_single_hop, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    inject_event(room, signal, injected(player)),
    arrived_key(room, signal, _, EventId),
    investigation_chain(EventId, Chain),
    Chain = [step(EventId, room, signal, injected(player))].

% T12 — investigation_chain: multi-hop through rule
test(investigation_chain_multi_hop, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    assertz(scenes:scene_rule(r_echo, room, arrived(_, room, signal, _, hot), echo)),
    inject_event(room, signal, injected(player)),
    world_step,
    arrived_key(room, echo, _, EchoId),
    arrived_key(room, signal, _, SignalId),
    investigation_chain(EchoId, Chain),
    member(step(EchoId, room, echo, _), Chain),
    member(step(SignalId, room, signal, injected(player)), Chain).

% T13 — investigation_chain: reads cold events
test(investigation_chain_cold, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    inject_event(room, signal, injected(player)),
    arrived_key(room, signal, _, EventId),
    promote_to_cold(room, 99),
    investigation_chain(EventId, Chain),
    Chain \= [].

% T14 — chain_root: returns root event
test(chain_root_returns_root, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    assertz(scenes:scene_rule(r_echo, room, arrived(_, room, signal, _, hot), echo)),
    inject_event(room, signal, injected(player)),
    arrived_key(room, signal, _, SignalId),
    world_step,
    arrived_key(room, echo, _, EchoId),
    chain_root(EchoId, RootId),
    RootId = SignalId.

% T15 — post_fixpoint_summary sorted by scene
test(post_fixpoint_sorted_by_scene, [setup(reset_engine)]) :-
    assertz(scenes:scene(z_scene)),
    assertz(scenes:scene(a_scene)),
    inject_event(z_scene, ev1, injected(player)),
    inject_event(a_scene, ev2, injected(player)),
    post_fixpoint_summary(0, Summary),
    Summary = [change(a_scene, ev2, injected(player)), change(z_scene, ev1, injected(player))].

:- end_tests(projections).
