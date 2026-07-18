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
    retractall(log:unprocessed(_)),
    retractall(scene(_)),
    retractall(scene_parent(_, _)),
    retractall(scene_rule(_, _, _, _)),
    retractall(event_counter(_)), assertz(event_counter(0)),
    retractall(clock_counter(_)), assertz(clock_counter(0)),
    retractall(gates:gate_passed(_, _, _)).

:- begin_tests(scenes_and_provenance).

test(t1_scene_declaration, [setup(reset_engine)]) :-
    declare_scene(deck),
    scene(deck),
    scene_type(deck, leaf).

test(t2_scene_type_composite, [setup(reset_engine)]) :-
    declare_scene(tavern),
    declare_scene(patron_a),
    declare_scene_parent(patron_a, tavern),
    scene_type(tavern, composite),
    scene_type(patron_a, leaf).

test(t3_duplicate_parent_throws, [setup(reset_engine)]) :-
    declare_scene(patron_a),
    declare_scene(tavern),
    declare_scene(other_tavern),
    declare_scene_parent(patron_a, tavern),
    catch(
        declare_scene_parent(patron_a, other_tavern),
        error(duplicate_parent(patron_a), _),
        true
    ).

test(t4_scene_rule_declaration, [setup(reset_engine)]) :-
    declare_scene(warrior),
    declare_scene_rule(rule_defeat, warrior, true, defeated),
    scene_rule(rule_defeat, warrior, true, defeated),
    rules_for_scene(warrior, Rules),
    Rules = [rule(rule_defeat, true, defeated)].

test(t5_duplicate_rule_id_throws, [setup(reset_engine)]) :-
    declare_scene(deck),
    declare_scene_rule(rule_001, deck, true, something),
    catch(
        declare_scene_rule(rule_001, deck, true, other),
        error(duplicate_rule_id(rule_001), _),
        true
    ).

test(t6_caused_by_asserted_by_inject, [setup(reset_engine)]) :-
    inject_event(scene_a, action_event, injected(player)),
    arrived_key(scene_a, action_event, _, EventId),
    caused_by(EventId, injected(player)).

test(t7_provenance_chain_returns_step, [setup(reset_engine)]) :-
    inject_event(scene_a, authored_event, injected(author)),
    arrived_key(scene_a, authored_event, _, EventId),
    provenance_chain(EventId, Chain),
    Chain = [step(EventId, injected(author))].

test(t8_provenance_acyclic_for_injected, [setup(reset_engine)]) :-
    inject_event(scene_a, ev1, injected(player)),
    inject_event(scene_a, ev2, injected(player)),
    inject_event(scene_b, ev3, injected(author)),
    findall(Id, arrived(Id, _, _, _, _), [Id1, Id2, Id3]),
    provenance_acyclic(Id1),
    provenance_acyclic(Id2),
    provenance_acyclic(Id3).

test(t9_scene_ancestors_leaf_with_parent, [setup(reset_engine)]) :-
    declare_scene(street),
    declare_scene(tavern),
    declare_scene(city),
    declare_scene_parent(street, tavern),
    declare_scene_parent(tavern, city),
    scene_ancestors(street, Ancestors),
    Ancestors = [city, tavern].

test(t10_scene_ancestors_root_has_none, [setup(reset_engine)]) :-
    declare_scene(city),
    scene_ancestors(city, Ancestors),
    Ancestors = [].

test(t11_scene_root, [setup(reset_engine)]) :-
    declare_scene(city),
    declare_scene(tavern),
    declare_scene_parent(tavern, city),
    scene_root(city),
    \+ scene_root(tavern).

test(t12_provenance_acyclic_detects_cycle, [setup(reset_engine)]) :-
    assertz(provenance:caused_by(evt_loop_a, gate(g_loop))),
    assertz(provenance:caused_by(evt_loop_b, gate(g_loop))),
    assertz(gates:gate_passed(g_loop, evt_loop_b, evt_loop_a)),
    assertz(gates:gate_passed(g_loop, evt_loop_a, evt_loop_b)),
    \+ provenance_acyclic(evt_loop_a).

:- end_tests(scenes_and_provenance).
