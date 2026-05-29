:- module(propagation, [
    propagation_test/3,
    assert_propagation_test/3,
    propagation_coverage/2,
    test_propagation/4,
    with_clean_world/1,
    verify_propagation_tests/0
]).

:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').
:- use_module('../engine/probes').

:- dynamic propagation_test/3.
% propagation_test(GateId, EventTerm, ExpectedOutcome)
% ExpectedOutcome is one of: crossed, blocked, no_interaction

assert_propagation_test(GateId, EventTerm, ExpectedOutcome) :-
    assertz(propagation_test(GateId, EventTerm, ExpectedOutcome)).

propagation_coverage(GateId, Report) :-
    gates:gate(GateId, SourceScene, DestScene, _),
    probes:probe(SourceScene, vocab(_, _)),
    probes:probe(DestScene, vocab(DestHeads, _)),
    findall(
        result(EventTerm, Outcome),
        (   member(EventTerm, DestHeads),
            test_propagation(GateId, SourceScene, EventTerm, Outcome)
        ),
        Report
    ).

test_propagation(GateId, SourceScene, EventTerm, Outcome) :-
    % Run in an isolated copy of the world state.
    % Save and restore engine state around the test.
    gates:gate(GateId, SourceScene, DestScene, _),
    with_clean_world(
        ( log:inject_event(SourceScene, EventTerm, injected(author)),
          log:arrived_key(SourceScene, EventTerm, _, EventId),
          gates:attempt_propagation(EventId, GateId),
          ( gates:gate_blocked(GateId, EventId, _) ->
              Outcome = blocked
          ;
              ( log:arrived(_, DestScene, _, _, _) ->
                  Outcome = crossed
              ;
                  Outcome = no_interaction
              )
          )
        )
    ).

% with_clean_world/1: resets event counter and clock after Goal.
% NOTE: arrived/5 facts injected during the test remain in the log —
% this predicate is designed for isolated plunit tests with reset_engine
% in setup(...), never for mid-simulation use.
with_clean_world(Goal) :-
    log:event_counter(CounterBefore),
    clock:clock_counter(ClockBefore),
    log:log_count(_LogBefore),
    call(Goal),
    log:log_count(_LogAfter),
    retract(log:event_counter(_)),
    assertz(log:event_counter(CounterBefore)),
    retract(clock:clock_counter(_)),
    assertz(clock:clock_counter(ClockBefore)).

verify_propagation_tests :-
    \+ (
        propagation_test(GateId, EventTerm, Expected),
        gates:gate(GateId, SourceScene, _, _),
        test_propagation(GateId, SourceScene, EventTerm, Actual),
        Actual \= Expected,
        format("  propagation test failed: gate ~w, event ~w: ~
                expected ~w, got ~w~n", [GateId, EventTerm, Expected, Actual])
    ).
