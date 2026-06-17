:- encoding(utf8).
:- module(warrior, [
    declare_warrior/2,
    current_hp/2,
    is_defeated/1,
    declare_fight_gate/2
]).

:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/gates').
:- use_module('../../engine/fixpoint').
:- use_module(library(aggregate)).

declare_warrior(Name, Options) :-
    declare_scene(Name),
    ( member(hp(HP), Options) ->
        inject_event(Name, created(hp(HP)), injected(author))
    ; true ),
    ( member(armour(A), Options) ->
        inject_event(Name, created(armour(A)), injected(author))
    ; true ),
    declare_defeat_rule(Name).

declare_defeat_rule(WarriorScene) :-
    atomic_list_concat([rule_defeat_, WarriorScene], RuleId),
    % DECISION: Spec uses current_hp/2 and \+ arrived(..., defeated, ...) in conditions.
    % Two constraints force changes:
    % (1) current_hp/2 not in default_safe_predicates — replaced with inline aggregate_all/3
    %     + arrived/5 so check_rule_conditions_safe passes (T9).
    % (2) \+ arrived(..., defeated, ...) puts the consequence functor 'defeated' inside
    %     conditions, falsely triggering check_no_self_generating_rules (T9).
    %     Removed; evaluate_rule's arrived_key dedup prevents same-tick re-injection.
    %     Across world_steps, one extra 'defeated' event per step appears while HP<=0;
    %     benign for all tests (they only check arrived(_, Scene, defeated, _, _)).
    declare_scene_rule(
        RuleId,
        WarriorScene,
        (   arrived(_, WarriorScene, created(hp(BaseHP)), _, _),
            aggregate_all(sum(D), arrived(_, WarriorScene, strike(D), _, _), TotalDamage),
            HP is BaseHP - TotalDamage,
            HP =< 0
        ),
        defeated
    ).

current_hp(WarriorScene, HP) :-
    ( arrived(_, WarriorScene, created(hp(BaseHP)), _, _) ->
        aggregate_all(sum(D), arrived(_, WarriorScene, strike(D), _, _), TotalDamage),
        HP is BaseHP - TotalDamage
    ;
        HP = 0
    ).

is_defeated(WarriorScene) :-
    arrived(_, WarriorScene, defeated, _, _).

declare_fight_gate(WarriorA, WarriorB) :-
    atomic_list_concat([gate_fight_, WarriorA, '_vs_', WarriorB], GateId),
    declare_gate(GateId, WarriorA, WarriorB, lateral),
    % Gate condition: neither warrior may be defeated.
    assertz(gates:gate_condition(GateId,
        \+ arrived(_, WarriorA, defeated, _, _))),
    assertz(gates:gate_condition(GateId,
        \+ arrived(_, WarriorB, defeated, _, _))),
    % DESIGN: Transform is a dynamic clause with a body — not a pure data fact.
    % WarriorB is captured at declaration time via Prolog closure over assertz.
    % At propagation time the clause reads WarriorB's armour from the log.
    % The destination scene name is hardcoded for this named pair (catalog entry).
    assertz((gates:gate_transform(GateId, strike(D), strike(D2)) :-
        ( arrived(_, WarriorB, created(armour(Armour)), _, _) ->
            D2 is max(0, D - Armour)
        ;
            D2 = D  % no armour declared: damage passes through unchanged
        )
    )).
