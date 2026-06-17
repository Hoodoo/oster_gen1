:- encoding(utf8).
:- use_module(library(plunit)).
:- use_module('../engine/scenes').
:- use_module('../engine/gates').
:- use_module('../engine/probes').
:- use_module('../engine/log').
:- use_module('../engine/clock').

reset_declarations :-
    retractall(scenes:scene(_)),
    retractall(scenes:scene_parent(_, _)),
    retractall(scenes:scene_rule(_, _, _, _)),
    retractall(gates:gate(_, _, _, _)),
    retractall(gates:gate_condition(_, _)),
    retractall(gates:gate_transform(_, _, _)).

:- begin_tests(probes).

%% T1 — Empty scene returns empty vocabulary
test(empty_scene_vocab, [setup(reset_declarations)]) :-
    assertz(scenes:scene(empty_room)),
    probe(empty_room, V),
    V = vocab([], []).

%% T2 — Rule heads returned
test(rule_heads_returned, [setup(reset_declarations)]) :-
    assertz(scenes:scene(deck)),
    assertz(scenes:scene_rule(r1, deck, _, drawn(card(1)))),
    assertz(scenes:scene_rule(r2, deck, _, shuffled)),
    probe(deck, vocab(Heads, _)),
    member(drawn(card(1)), Heads),
    member(shuffled, Heads).

%% T3 — Outgoing gates returned
test(outgoing_gates_returned, [setup(reset_declarations)]) :-
    assertz(scenes:scene(patron)),
    assertz(scenes:scene(tavern)),
    assertz(gates:gate(g_up, patron, tavern, upward)),
    probe(patron, vocab(_, Gates)),
    member(gate_info(g_up, tavern, upward), Gates).

%% T4 — Closed gate still appears in probe results
test(closed_gate_appears, [setup(reset_declarations)]) :-
    assertz(scenes:scene(patron)),
    assertz(scenes:scene(tavern)),
    assertz(gates:gate(g_closed, patron, tavern, downward)),
    assertz(gates:gate_condition(g_closed, fail)),
    probe(patron, vocab(_, Gates)),
    member(gate_info(g_closed, tavern, _), Gates).

%% T5 — probe does not alter log count
test(probe_no_log_side_effect, [setup(reset_declarations)]) :-
    assertz(scenes:scene(test_scene)),
    assertz(scenes:scene_rule(r1, test_scene, _, something)),
    assertz(gates:gate(g1, test_scene, other, forward)),
    log_count(Before),
    probe(test_scene, _),
    probe(test_scene, _),
    probe(test_scene, _),
    log_count(After),
    Before =:= After.

%% T6 — probe does not alter clock
test(probe_no_clock_side_effect, [setup(reset_declarations)]) :-
    clock_value(Before),
    probe(empty_room2, _),
    clock_value(After),
    Before =:= After.

%% T7 — probe called twice returns identical results
test(probe_idempotent, [setup(reset_declarations)]) :-
    assertz(scenes:scene(stable)),
    assertz(scenes:scene_rule(r1, stable, _, event_a)),
    assertz(scenes:scene_rule(r2, stable, _, event_b)),
    assertz(gates:gate(g1, stable, elsewhere, forward)),
    probe(stable, V1),
    probe(stable, V2),
    V1 = V2.

%% T8 — probe_reachable: rule head match
test(probe_reachable_rule_match, [setup(reset_declarations)]) :-
    assertz(scenes:scene(warrior)),
    assertz(scenes:scene_rule(r1, warrior, _, defeated)),
    probe_reachable(warrior, defeated).

%% T9 — probe_reachable: no match
test(probe_reachable_no_match, [setup(reset_declarations), fail]) :-
    assertz(scenes:scene(warrior)),
    assertz(scenes:scene_rule(r1, warrior, _, defeated)),
    probe_reachable(warrior, invisible).

%% T10 — probe_reachable: gate present means reachable
test(probe_reachable_via_gate, [setup(reset_declarations)]) :-
    assertz(scenes:scene(patron)),
    assertz(scenes:scene(somewhere)),
    assertz(gates:gate(g1, patron, somewhere, across)),
    probe_reachable(patron, anything).

%% T11 — probe_reachable does not bind caller variables
test(probe_reachable_no_binding, [setup(reset_declarations)]) :-
    assertz(scenes:scene(deck)),
    assertz(scenes:scene_rule(r1, deck, _, drawn(_Card))),
    probe_reachable(deck, drawn(X)),
    var(X).

%% T12 — probe_vocabulary convenience predicate
test(probe_vocabulary_predicate, [setup(reset_declarations)]) :-
    assertz(scenes:scene(room)),
    assertz(scenes:scene_rule(r1, room, _, opened)),
    assertz(scenes:scene_rule(r2, room, _, closed)),
    probe_vocabulary(room, Templates),
    member(opened, Templates),
    member(closed, Templates),
    length(Templates, 2).

%% T13 — probe_gates convenience predicate
test(probe_gates_predicate, [setup(reset_declarations)]) :-
    assertz(scenes:scene(room)),
    assertz(scenes:scene(north)),
    assertz(scenes:scene(south)),
    assertz(gates:gate(g_north, room, north, up)),
    assertz(gates:gate(g_south, room, south, down)),
    probe_gates(room, Gates),
    member(gate_info(g_north, north, up), Gates),
    member(gate_info(g_south, south, down), Gates),
    length(Gates, 2).

:- end_tests(probes).
