:- module(tavern_scene, [
    declare_tavern_world/0,
    declare_patron/1,
    declare_street/0,
    window_is_open/1,
    amulet_is_charged/1
]).

:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/fixpoint').

declare_tavern_world :-
    declare_scene(world),
    declare_scene(tavern),
    declare_scene(patron_a),
    declare_scene(patron_b),
    declare_scene(street),
    declare_scene(barkeeper),          % NEW
    declare_scene(mob_lair),           % NEW
    declare_scene_parent(tavern, world),
    declare_scene_parent(street, world),
    declare_scene_parent(patron_a, tavern),
    declare_scene_parent(patron_b, tavern),
    declare_scene_parent(barkeeper, tavern),   % NEW — barkeeper is inside the tavern
    declare_scene_parent(mob_lair, world),     % NEW — mob_lair is a world-level scene
    declare_patron_rules(patron_a),
    declare_patron_rules(patron_b),
    declare_street_rules,
    declare_barkeeper_rules,           % NEW
    declare_mob_lair_rules,            % NEW
    inject_event(tavern, window_opened, injected(setup)),
    inject_event(barkeeper, amulet_charged, injected(setup)).  % NEW

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

declare_barkeeper_rules :-
    declare_scene_rule(
        rule_alert_sent,
        barkeeper,
        arrived(_, barkeeper, use_amulet, _, _),
        alert_sent
    ).

declare_mob_lair_rules :-
    declare_scene_rule(
        rule_mob_mobilized,
        mob_lair,
        arrived(_, mob_lair, alert_sent, _, _),
        mob_mobilized
    ).

amulet_is_charged(BarkeepScene) :-
    findall(Clock-Term,
            ( log:arrived(_, BarkeepScene, Term, Clock, _),
              ( Term = amulet_charged ; Term = amulet_spent )
            ),
            Pairs),
    Pairs \= [],
    msort(Pairs, Sorted),
    last(Sorted, _-amulet_charged).
% NOTE: same "most recent qualifying event wins" pattern as window_is_open/1.
% This is now the second instance. The abstraction is earned but deliberately
% deferred — extract a shared helper when a third use case appears.
% Same same-tick caveat applies: do not charge and spend in the same clock tick.

window_is_open(TavernScene) :-
    % Collect all window state events from this scene's log
    findall(Clock-Term,
            ( log:arrived(_, TavernScene, Term, Clock, _),
              ( Term = window_opened ; Term = window_closed )
            ),
            Pairs),
    Pairs \= [],
    % Most recent clock wins; window is open iff that event was window_opened
    msort(Pairs, Sorted),
    last(Sorted, _-window_opened).
% NOTE: if window_opened and window_closed both arrive at the same clock tick,
% msort orders window_closed before window_opened (lexicographic), so
% window_opened wins on tie. Authors should not open and close in the same
% clock tick — behaviour in that edge case is intentionally unspecified.
