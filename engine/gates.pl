:- module(gates, [
    gate/4,
    gate_condition/2,
    gate_transform/3,
    gate_open/1,
    gate_blocked/3,
    gate_transformed/5,
    gate_passed/3,
    declare_gate/4,
    apply_transform/4,
    attempt_propagation/2,
    propagate_from_scene/2,
    gates_from_scene/2
]).

:- use_module(log).
:- use_module(scenes).
:- use_module(provenance).

:- dynamic gate/4.
% gate(GateId, SourceScene, DestScene, Direction)

:- dynamic gate_condition/2.
% gate_condition(GateId, ConditionGoal)

:- dynamic gate_transform/3.
% gate_transform(GateId, InputTerm, OutputTerm)

:- dynamic gate_blocked/3.
% gate_blocked(GateId, EventId, Clock)

:- dynamic gate_transformed/5.
% gate_transformed(GateId, SourceEventId, DestEventId, InputTerm, OutputTerm)

:- dynamic gate_passed/3.
% gate_passed(GateId, SourceEventId, DestEventId)
% Asserted for every untransformed gate propagation.
% Provides the source-to-destination link that gate_transformed/5 provides
% for transformed propagations. Together they make all gate hops traversable
% by provenance_chain/2. See docs/deferred.md I-001.

declare_gate(GateId, SourceScene, DestScene, Direction) :-
    ( gate(GateId, _, _, _) ->
        throw(error(duplicate_gate_id(GateId), context(declare_gate/4, '')))
    ;
        assertz(gate(GateId, SourceScene, DestScene, Direction))
    ).

gate_open(GateId) :-
    gate(GateId, _, _, _),
    \+ (gate_condition(GateId, Cond), \+ call(Cond)).

apply_transform(GateId, InTerm, OutTerm, transformed) :-
    gate_transform(GateId, InTerm, OutTerm), !.
apply_transform(_GateId, Term, Term, unchanged).

attempt_propagation(EventId, GateId) :-
    arrived(EventId, SourceScene, Term, Clock, _),
    gate(GateId, SourceScene, DestScene, _),
    ( gate_open(GateId) ->
        apply_transform(GateId, Term, OutTerm, Status),
        inject_event(DestScene, OutTerm, gate(GateId)),
        % DECISION: use clock_value/1 (current clock) not Clock (source event clock).
        % inject_event stamps the dest event at the current clock; using the source
        % event's clock for the arrived_key lookup would fail whenever the source
        % event was created in a prior world_step (different clock).
        clock_value(CurrentClock),
        arrived_key(DestScene, OutTerm, CurrentClock, DestEventId),
        ( Status = transformed ->
            assertz(gate_transformed(GateId, EventId, DestEventId, Term, OutTerm))
        ;
            assertz(gate_passed(GateId, EventId, DestEventId))
        )
    ;
        assertz(gate_blocked(GateId, EventId, Clock))
    ).

propagate_from_scene(Scene, EventId) :-
    forall(
        gate(GateId, Scene, _, _),
        attempt_propagation(EventId, GateId)
    ).

gates_from_scene(Scene, GateIds) :-
    findall(GateId, gate(GateId, Scene, _, _), GateIds).
