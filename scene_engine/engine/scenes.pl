:- module(scenes, [
    scene/1,
    scene_parent/2,
    scene_rule/4,
    declare_scene/1,
    declare_scene_parent/2,
    declare_scene_rule/4,
    scene_type/2,
    scene_root/1,
    scene_ancestors/2,
    rules_for_scene/2
]).

:- dynamic scene/1.
% scene(Name)

:- dynamic scene_parent/2.
% scene_parent(Child, Parent)

:- dynamic scene_rule/4.
% scene_rule(RuleId, Scene, Conditions, ConsequenceEventTemplate)

declare_scene(Name) :-
    ( scene(Name) -> true ; assertz(scene(Name)) ).

declare_scene_parent(Child, Parent) :-
    ( scene_parent(Child, _) ->
        throw(error(duplicate_parent(Child), context(declare_scene_parent/2, '')))
    ;
        assertz(scene_parent(Child, Parent))
    ).

declare_scene_rule(RuleId, Scene, Conditions, Template) :-
    ( scene_rule(RuleId, _, _, _) ->
        throw(error(duplicate_rule_id(RuleId), context(declare_scene_rule/4, '')))
    ;
        assertz(scene_rule(RuleId, Scene, Conditions, Template))
    ).

scene_type(Scene, composite) :-
    scene(Scene),
    scene_parent(_, Scene), !.
scene_type(Scene, leaf) :-
    scene(Scene).

scene_root(Scene) :-
    scene(Scene),
    \+ scene_parent(Scene, _).

scene_ancestors(Scene, Ancestors) :-
    scene_ancestors_(Scene, [], Ancestors).

% DECISION: spec code uses reverse/2 but accumulator already builds root-first
% (each parent prepended, so root ends up at head). Omitting reverse matches test T9.
scene_ancestors_(Scene, Acc, Ancestors) :-
    ( scene_parent(Scene, Parent) ->
        scene_ancestors_(Parent, [Parent|Acc], Ancestors)
    ;
        Ancestors = Acc
    ).

rules_for_scene(Scene, Rules) :-
    findall(rule(RuleId, Conditions, Template),
            scene_rule(RuleId, Scene, Conditions, Template),
            Rules).
