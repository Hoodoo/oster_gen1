:- module(why_blocked, [why_blocked/3, why_blocked_history/3]).

:- use_module('../engine/gates').
:- use_module('../engine/clock').

why_blocked(Scene, EventTerm, Explanation) :-
    ( gate(GateId, Scene, _, _) ->
        ( \+ gate_open(GateId) ->
            first_failing_condition(GateId, EventTerm, Explanation)
        ;
            Explanation = gate_is_open(GateId)
        )
    ;
        Explanation = no_gate(Scene, EventTerm)
    ).

first_failing_condition(GateId, _EventTerm, blocked_by(GateId, Cond)) :-
    gate_condition(GateId, Cond),
    \+ call(Cond),
    !.
first_failing_condition(GateId, _EventTerm, blocked_by(GateId, unknown)) :-
    \+ gate_open(GateId).

why_blocked_history(GateId, EventId, Clock) :-
    gate_blocked(GateId, EventId, Clock).
