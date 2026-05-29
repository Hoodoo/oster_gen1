:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/provenance').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').

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
    retractall(gate_blocked(_, _, _)),
    retractall(gate_transformed(_, _, _, _, _)),
    retractall(rule_trigger(_, _, _)),
    retractall(fixpoint_depth_exceeded(_)),
    retractall(rule_grounding_failed(_, _)),
    retractall(event_counter(_)), assertz(event_counter(0)),
    retractall(clock_counter(_)), assertz(clock_counter(0)).

:- begin_tests(fixpoint).

% T1 — Empty world reaches fixpoint immediately
test(t1_empty_world_fixpoint, [setup(reset_engine)]) :-
    advance_world(10),
    \+ fixpoint_depth_exceeded(_).

% T2 — Rule fires on hot event
test(t2_rule_fires_on_hot_event, [setup(reset_engine)]) :-
    assertz(scenes:scene_rule(r_echo, room, arrived(_, room, signal, _, hot), echo)),
    inject_event(room, signal, injected(player)),
    world_step,
    arrived(_, room, echo, _, hot).

% T3 — Rule does not fire when condition fails
test(t3_rule_does_not_fire, [setup(reset_engine)]) :-
    assertz(scenes:scene_rule(r_never, room, fail, ghost)),
    inject_event(room, signal, injected(player)),
    world_step,
    \+ arrived(_, room, ghost, _, _).

% T4 — Consequence deduplication
test(t4_deduplication, [setup(reset_engine)]) :-
    assertz(scenes:scene_rule(r_echo, room, arrived(_, room, signal, _, hot), echo)),
    inject_event(room, signal, injected(player)),
    inject_event(room, signal, injected(player)),
    world_step,
    aggregate_all(count, arrived(_, room, echo, _, _), N),
    N =:= 1.

% T5 — Rule-generated event propagates through gate
test(t5_rule_event_propagates_through_gate, [setup(reset_engine)]) :-
    assertz(gates:gate(g_out, src, dst, outward)),
    assertz(scenes:scene_rule(r_signal, src, arrived(_, src, trigger, _, hot), signal)),
    inject_event(src, trigger, injected(player)),
    world_step,
    arrived(_, src, signal, _, hot),
    arrived(_, dst, signal, _, hot).

% T6 — All events in one world_step share the same clock
test(t6_same_clock, [setup(reset_engine)]) :-
    assertz(gates:gate(g_out, src, dst, outward)),
    assertz(scenes:scene_rule(r_signal, src, arrived(_, src, trigger, _, hot), signal)),
    inject_event(src, trigger, injected(player)),
    findall(Id, arrived(Id, _, _, _, _), PreIds),
    world_step,
    % All events created during this world_step must share the same clock value.
    findall(Clock, (arrived(Id, _, _, Clock, _), \+ member(Id, PreIds)), NewClocks),
    sort(NewClocks, [_]).

% T7 — Deduplicating loop does NOT trigger depth guard
test(t7_dedup_loop_no_depth_exceeded, [setup(reset_engine)]) :-
    assertz(scenes:scene_rule(r_loop, loop, arrived(_, loop, ping, _, hot), ping)),
    inject_event(loop, ping, injected(player)),
    world_step,
    \+ fixpoint_depth_exceeded(_).

% T7b — Genuinely looping rule triggers depth guard
test(t7b_genuine_loop_depth_exceeded, [setup(reset_engine)]) :-
    assertz(scenes:scene_rule(r_grow, loop, (arrived(_, loop, seed, _, hot), gensym(evt, T)), T)),
    inject_event(loop, seed, injected(player)),
    advance_world(5),
    fixpoint_depth_exceeded(_).

% T8 — rule_grounding_failed asserted for ungroundable template
test(t8_grounding_failed, [setup(reset_engine)]) :-
    assertz(scenes:scene_rule(r_bad, room, true, event(_X))),
    inject_event(room, anything, injected(player)),
    world_step,
    rule_grounding_failed(r_bad, _),
    \+ arrived(_, room, event(_), _, _).

% T9 — rule_trigger recorded on rule firing
test(t9_rule_trigger_recorded, [setup(reset_engine)]) :-
    assertz(scenes:scene_rule(r_echo, room, arrived(_, room, signal, _, hot), echo)),
    inject_event(room, signal, injected(player)),
    arrived_key(room, signal, _, SignalId),
    world_step,
    rule_trigger(r_echo, room, SignalId).

% T10 — provenance_chain multi-hop: rule
test(t10_provenance_chain_rule, [setup(reset_engine)]) :-
    assertz(scenes:scene_rule(r_echo, room, arrived(_, room, signal, _, hot), echo)),
    inject_event(room, signal, injected(player)),
    arrived_key(room, signal, _, SignalId),
    world_step,
    arrived_key(room, echo, _, EchoId),
    provenance_chain(EchoId, Chain),
    memberchk(step(EchoId, rule(room, r_echo)), Chain),
    memberchk(step(SignalId, injected(player)), Chain).

% T11 — provenance_chain multi-hop: gate
% Uses a gate WITH a transform so gate_transformed/5 is asserted, enabling full chain traversal.
% Untransformed gates produce unknown_gate_source terminals (see spec note + T13).
test(t11_provenance_chain_gate, [setup(reset_engine)]) :-
    assertz(gates:gate(g_out, src, dst, outward)),
    assertz(gates:gate_transform(g_out, signal, signal_xfm)),
    assertz(scenes:scene_rule(r_signal, src, arrived(_, src, trigger, _, hot), signal)),
    inject_event(src, trigger, injected(player)),
    arrived_key(src, trigger, _, TriggerId),
    world_step,
    arrived_key(dst, signal_xfm, _, DestSignalId),
    provenance_chain(DestSignalId, Chain),
    % Full chain: dst/signal_xfm <- gate(g_out) <- src/signal <- rule(src,r_signal) <- src/trigger <- injected(player)
    memberchk(step(DestSignalId, gate(g_out)), Chain),
    memberchk(step(TriggerId, injected(player)), Chain).

% T12 — Monotonicity: arrived/5 never retracted
test(t12_monotonicity, [setup(reset_engine)]) :-
    inject_event(scene_a, ev1, injected(player)),
    inject_event(scene_a, ev2, injected(player)),
    log_count(N0),
    world_step,
    log_count(N1),
    N1 >= N0,
    world_step,
    log_count(N2),
    N2 >= N1.

% T13 — Integration test
test(t13_integration, [setup(reset_engine)]) :-
    assertz(scenes:scene(patron)),
    assertz(scenes:scene(tavern)),
    assertz(scenes:scene_parent(patron, tavern)),
    assertz(scenes:scene_rule(r_noise, patron,
        arrived(_, patron, strike(_), _, hot), noise(fight))),
    assertz(gates:gate(g_up, patron, tavern, upward)),
    inject_event(patron, strike(5), injected(player)),
    findall(Id, arrived(Id, _, _, _, _), PreIds),
    world_step,
    once(arrived(_, patron, strike(5), _, hot)),
    once(arrived(_, patron, noise(fight), _, hot)),
    once(arrived(_, tavern, noise(fight), _, hot)),
    \+ fixpoint_depth_exceeded(_),
    % All events created during this world_step share the same clock value.
    findall(Clock, (arrived(Id, _, _, Clock, _), \+ member(Id, PreIds)), StepClocks),
    sort(StepClocks, [_]),
    % Provenance of patron/noise(fight) reaches back to the injected strike(5).
    % (tavern/noise(fight) was propagated through an untransformed gate, so its chain
    %  cannot recover the source event ID — see spec note on unknown_gate_source.)
    once(arrived_key(patron, noise(fight), _, PatronNoiseId)),
    once(provenance_chain(PatronNoiseId, PatronChain)),
    memberchk(step(PatronNoiseId, rule(patron, r_noise)), PatronChain),
    memberchk(step(_, injected(player)), PatronChain),
    % Tavern noise provenance reaches the gate step (terminates at unknown_gate_source
    % because the gate is untransformed — no gate_transformed fact asserted).
    once(arrived_key(tavern, noise(fight), _, TavernNoiseId)),
    once(provenance_chain(TavernNoiseId, TavernChain)),
    memberchk(step(TavernNoiseId, gate(g_up)), TavernChain).

:- end_tests(fixpoint).
