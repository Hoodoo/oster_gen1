:- module(tavern_gates, [
    declare_tavern_gates/0
]).

:- use_module('../../engine/gates').
% DECISION: spec says use_module(tavern_scene, ...) but the file is scene.pl.
% Using use_module(scene, ...) — relative to this file's directory — matching
% the warrior catalog pattern (catalog/warrior/tests.pl uses scene the same way).
:- use_module(scene, [window_open/1]).

declare_tavern_gates :-
    % Inward gates: patron noise propagates upward to tavern
    declare_gate(patron_a_noise_to_tavern, patron_a, tavern, upward),
    declare_gate(patron_b_noise_to_tavern, patron_b, tavern, upward),
    % Term filter: only noise(fight) crosses the inward gates.
    % Without this filter, all patron events (including strike/taunt)
    % would appear in the tavern log, violating D8.
    declare_gate_term_filter(patron_a_noise_to_tavern, noise(fight)),
    declare_gate_term_filter(patron_b_noise_to_tavern, noise(fight)),

    % Outward gate: tavern noise propagates downward to street
    declare_gate(tavern_noise_to_street, tavern, street, downward),
    % Condition: window must be open
    % NOTE: window_open(tavern) is a plain dynamic fact, not an event.
    % This is a design tradeoff: authoring code asserts/retracts it directly.
    % The alternative — modelling window state as an event — is architecturally
    % cleaner but out of scope for this entry.
    assertz(gates:gate_condition(
        tavern_noise_to_street,
        tavern_scene:window_open(tavern)
    )).
