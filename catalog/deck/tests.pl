:- encoding(utf8).
:- use_module(library(plunit)).
:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/provenance').
:- use_module('../../engine/gates').
:- use_module('../../engine/fixpoint').
:- use_module('../../engine/probes').
:- use_module('../../verify/contracts').
:- use_module('../../verify/invariants').
:- use_module('../../projections/investigation').
% DECISION: spec says use_module('deck_scene', ...) but the file is scene.pl per
% the Files to create list. Using 'scene' to match the actual filename.
:- use_module('scene', [
    declare_deck/1,
    current_order/2,
    deck_empty/1,
    deck_size/2
]).

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

:- begin_tests(deck).

% T1 — create establishes order
test(t1_create_establishes_order, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1), card(2), card(3)]), injected(test)),
    current_order(deck, Order),
    Order = [card(1), card(2), card(3)].

% T2 — draw removes top card
test(t2_draw_removes_top, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1), card(2), card(3)]), injected(test)),
    clock:advance_clock,
    log:inject_event(deck, draw, injected(test)),
    current_order(deck, Order),
    Order = [card(2), card(3)].

% T3 — shuffle reverses order
test(t3_shuffle_reverses, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1), card(2), card(3)]), injected(test)),
    clock:advance_clock,
    log:inject_event(deck, shuffle, injected(test)),
    current_order(deck, Order),
    Order = [card(3), card(2), card(1)].

% T4 — sort orders cards
test(t4_sort_orders, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(3), card(1), card(2)]), injected(test)),
    clock:advance_clock,
    log:inject_event(deck, sort, injected(test)),
    current_order(deck, Order),
    Order = [card(1), card(2), card(3)].

% T5 — multiple operations in sequence
test(t5_multiple_ops, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1), card(2), card(3)]), injected(test)),
    clock:advance_clock,
    log:inject_event(deck, shuffle, injected(test)),
    clock:advance_clock,
    log:inject_event(deck, draw, injected(test)),
    current_order(deck, Order),
    Order = [card(2), card(1)].

% T6 — deck_empty: non-empty deck fails
test(t6_deck_empty_nonempty_fails, [setup(reset_engine), fail]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1)]), injected(test)),
    deck_empty(deck).

% T7 — deck_empty: empty after drawing all cards
test(t7_deck_empty_after_draw, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1)]), injected(test)),
    clock:advance_clock,
    log:inject_event(deck, draw, injected(test)),
    deck_empty(deck).

% T8 — deck_size
test(t8_deck_size, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1), card(2), card(3)]), injected(test)),
    deck_size(deck, N),
    N = 3.

% T9 — draw from empty deck does not crash
test(t9_draw_empty_no_crash, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([]), injected(test)),
    clock:advance_clock,
    log:inject_event(deck, draw, injected(test)),
    current_order(deck, Order),
    Order = [].

% T10 — current_order fails on uncreated deck
test(t10_current_order_uncreated_fails, [setup(reset_engine), fail]) :-
    declare_deck(deck),
    current_order(deck, _).

% T11 — fixpoint terminates within 5 iterations for create
test(t11_fixpoint_create, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1)]), injected(test)),
    fixpoint:advance_world(5),
    \+ fixpoint:fixpoint_depth_exceeded(_).

% T12 — fixpoint terminates within 5 iterations for draw
test(t12_fixpoint_draw, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1)]), injected(test)),
    clock:advance_clock,
    log:inject_event(deck, draw, injected(test)),
    fixpoint:advance_world(5),
    \+ fixpoint:fixpoint_depth_exceeded(_).

% T13 — fixpoint terminates within 5 iterations for shuffle
test(t13_fixpoint_shuffle, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1)]), injected(test)),
    clock:advance_clock,
    log:inject_event(deck, shuffle, injected(test)),
    fixpoint:advance_world(5),
    \+ fixpoint:fixpoint_depth_exceeded(_).

% T14 — fixpoint terminates within 5 iterations for sort
test(t14_fixpoint_sort, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1)]), injected(test)),
    clock:advance_clock,
    log:inject_event(deck, sort, injected(test)),
    fixpoint:advance_world(5),
    \+ fixpoint:fixpoint_depth_exceeded(_).

% T15 — verify_contracts passes on deck world
test(t15_verify_contracts_deck, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1), card(2)]), injected(test)),
    verify_contracts.

% T16 — probe returns vocabulary surface
test(t16_probe_vocab, [setup(reset_engine)]) :-
    declare_deck(deck),
    probe(deck, vocab(_Heads, Gates)),
    Gates = [].

% T17 — provenance chain from draw event
test(t17_provenance_draw_chain, [setup(reset_engine)]) :-
    declare_deck(deck),
    log:inject_event(deck, create([card(1), card(2)]), injected(player)),
    clock:advance_clock,
    log:inject_event(deck, draw, injected(player)),
    log:arrived_key(deck, draw, _, DrawId),
    investigation_chain(DrawId, Chain),
    Chain \= [],
    last(Chain, step(_, _, _, injected(player))).

:- end_tests(deck).
