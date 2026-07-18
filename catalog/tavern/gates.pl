:- encoding(utf8).
:- module(tavern_gates, [
    declare_tavern_gates/0
]).

:- use_module('../../engine/gates').
% DECISION: spec says use_module(tavern_scene, ...) but the file is scene.pl.
% Using use_module(scene, ...) — relative to this file's directory — matching
% the warrior catalog pattern (catalog/warrior/tests.pl uses scene the same way).
:- use_module(scene, [window_is_open/1, amulet_is_charged/1]).

declare_tavern_gates :-
    % Inward gates: patron noise propagates upward to tavern
    declare_gate(patron_a_noise_to_tavern, patron_a, tavern, upward),
    declare_gate(patron_b_noise_to_tavern, patron_b, tavern, upward),
    declare_gate_term_filter(patron_a_noise_to_tavern, noise(fight)),
    declare_gate_term_filter(patron_b_noise_to_tavern, noise(fight)),

    % Outward gate: tavern noise propagates laterally to street (now a sibling)
    declare_gate(tavern_noise_to_street, tavern, street, lateral),
    declare_gate_term_filter(tavern_noise_to_street, noise(fight)),
    assertz(gates:gate_condition(
        tavern_noise_to_street,
        tavern_scene:window_is_open(tavern)
    )),

    % One-directional alert gate: barkeeper → mob_lair
    % No return gate — mob_lair cannot send events back through any declared gate.
    declare_gate(barkeeper_amulet_alert, barkeeper, mob_lair, lateral),
    declare_gate_term_filter(barkeeper_amulet_alert, alert_sent),
    assertz(gates:gate_condition(
        barkeeper_amulet_alert,
        tavern_scene:amulet_is_charged(barkeeper)
    )).
