:- encoding(utf8).
:- module(fixpoint, [
    advance_world/1,
    world_step/0,
    evaluate_rule/3,
    fixpoint_depth_exceeded/1,
    rule_grounding_failed/2
]).

:- use_module(log).
:- use_module(clock).
:- use_module(scenes).
:- use_module(provenance).
:- use_module(gates).

% DECISION: rule_trigger/3 is declared in provenance.pl (not here) to avoid a
% circular module dependency — fixpoint use_modules provenance, and parent_event
% in provenance.pl needs rule_trigger. Asserting via assertz(rule_trigger(...))
% works because provenance exports rule_trigger and fixpoint imports it.

:- dynamic fixpoint_depth_exceeded/1.
% fixpoint_depth_exceeded(Clock)

:- dynamic rule_grounding_failed/2.
% rule_grounding_failed(RuleId, Clock)

evaluate_rule(EventId, Scene, RuleId) :-
    scene_rule(RuleId, Scene, Conditions, Template),
    clock_value(Clock),
    ( call(Conditions) ->
        ( ground(Template) ->
            ( \+ arrived_key(Scene, Template, Clock, _) ->
                inject_event(Scene, Template, rule(Scene, RuleId)),
                record_rule_trigger(RuleId, Scene, EventId)
            ;
                true
            )
        ;
            assertz(fixpoint:rule_grounding_failed(RuleId, Clock))
        )
    ;
        true
    ).

record_rule_trigger(RuleId, Scene, TriggeringEventId) :-
    assertz(rule_trigger(RuleId, Scene, TriggeringEventId)).

process_hot_event(EventId) :-
    arrived(EventId, Scene, _Term, _Clock, _),
    forall(
        scene_rule(RuleId, Scene, _Cond, _Template),
        evaluate_rule(EventId, Scene, RuleId)
    ),
    propagate_from_scene(Scene, EventId).

advance_world(MaxDepth) :-
    MaxDepth > 0,
    findall(E, log:unprocessed(E), Frontier),
    ( Frontier == [] ->
        true
    ;
        forall(member(EventId, Frontier),
               ( process_hot_event(EventId),
                 retract(log:unprocessed(EventId)) )),
        Depth1 is MaxDepth - 1,
        advance_world(Depth1)
    ).
advance_world(0) :-
    clock_value(Clock),
    assertz(fixpoint:fixpoint_depth_exceeded(Clock)).

world_step :-
    advance_clock,
    advance_world(100).
