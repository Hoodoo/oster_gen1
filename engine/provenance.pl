:- module(provenance, [
    caused_by/2,
    assert_provenance/2,
    provenance_chain/2,
    provenance_acyclic/1,
    rule_trigger/3
]).

:- dynamic caused_by/2.
% caused_by(EventId, Cause)
%
% Cause is one of:
%   injected(player)
%   injected(author)
%   rule(Scene, RuleId)
%   gate(GateId)
%   simulation_boundary(SimId)

:- dynamic rule_trigger/3.
% rule_trigger(RuleId, Scene, TriggeringEventId)
% DECISION: declared here (not in fixpoint.pl) to avoid circular module dependency.
% fixpoint.pl use_modules provenance and asserts rule_trigger via the import.

assert_provenance(EventId, Cause) :-
    assertz(caused_by(EventId, Cause)).

provenance_chain(EventId, Chain) :-
    provenance_chain_(EventId, [EventId], Chain).

provenance_chain_(EventId, _Visited, []) :-
    \+ caused_by(EventId, _), !.
provenance_chain_(EventId, Visited, [step(EventId, Cause)|Rest]) :-
    caused_by(EventId, Cause),
    (   terminal_cause(Cause)
    ->  Rest = []
    ;   parent_event(EventId, Cause, ParentId),
        ( member(ParentId, Visited) ->
            Rest = [cycle_detected(ParentId)]
        ;
            provenance_chain_(ParentId, [ParentId|Visited], Rest)
        )
    ).

terminal_cause(injected(_)).
terminal_cause(simulation_boundary(_)).

parent_event(EventId, gate(GateId), ParentId) :-
    ( gates:gate_transformed(GateId, ParentId, EventId, _, _) -> true
    ; gates:gate_passed(GateId, ParentId, EventId) -> true
    ; ParentId = unknown_gate_source(GateId)
    ).
parent_event(_EventId, rule(Scene, RuleId), ParentId) :-
    rule_trigger(RuleId, Scene, ParentId), !.
parent_event(_EventId, rule(Scene, RuleId), unknown_rule_trigger(Scene, RuleId)).

provenance_acyclic(EventId) :-
    provenance_chain(EventId, Chain),
    \+ member(cycle_detected(_), Chain).
