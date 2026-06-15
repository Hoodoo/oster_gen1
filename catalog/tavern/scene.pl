:- module(tavern_scene, [
    declare_tavern_world/0,
    declare_patron/1,
    declare_street/0,
    window_open/1
]).

:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/fixpoint').

:- dynamic window_open/1.
% window_open(TavernScene)
% Asserted by authoring code to open the window, allowing noise to reach the street.
% Retracted to close it.

declare_tavern_world :-
    declare_scene(tavern),
    declare_scene(patron_a),
    declare_scene(patron_b),
    declare_scene(street),
    declare_scene_parent(patron_a, tavern),
    declare_scene_parent(patron_b, tavern),
    declare_scene_parent(street, tavern),
    declare_patron_rules(patron_a),
    declare_patron_rules(patron_b),
    declare_street_rules.

declare_patron(PatronScene) :-
    declare_scene(PatronScene),
    declare_patron_rules(PatronScene).

declare_patron_rules(PatronScene) :-
    atomic_list_concat([rule_noise_strike_, PatronScene], RuleId1),
    atomic_list_concat([rule_noise_taunt_, PatronScene], RuleId2),
    declare_scene_rule(
        RuleId1,
        PatronScene,
        arrived(_, PatronScene, strike(_), _, _),
        noise(fight)
    ),
    declare_scene_rule(
        RuleId2,
        PatronScene,
        arrived(_, PatronScene, taunt, _, _),
        noise(fight)
    ).

declare_street_rules :-
    declare_scene_rule(
        rule_guards_alerted,
        street,
        arrived(_, street, noise(fight), _, _),
        guards_alerted
    ).

declare_street :-
    declare_scene(street),
    declare_street_rules.
