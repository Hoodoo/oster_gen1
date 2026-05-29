:- module(invariants, [
    record_log_baseline/0,
    check_log_append_only/0,
    check_probes_side_effect_free/0,
    check_gates_never_mutate_source/0,
    check_rules_locality/0,
    collect_foreign_arrived_calls/3
]).

:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/gates').
:- use_module('../engine/scenes').
:- use_module('../engine/probes').

:- dynamic log_baseline/1.

record_log_baseline :-
    retractall(log_baseline(_)),
    log:log_count(N),
    assertz(log_baseline(N)).

check_log_append_only :-
    ( log_baseline(Baseline) ->
        log:log_count(Current),
        ( Current >= Baseline ->
            true
        ;
            format("  INVARIANT VIOLATION: log shrank from ~w to ~w~n",
                   [Baseline, Current]),
            fail
        )
    ;
        format("  warning: no baseline recorded; call record_log_baseline first~n")
    ).

check_probes_side_effect_free :-
    \+ (
        scenes:scene(Scene),
        log:log_count(Before),
        clock:clock_value(ClockBefore),
        probes:probe(Scene, _),
        log:log_count(After),
        clock:clock_value(ClockAfter),
        % DECISION: spec uses \=:= (not a SWI-Prolog operator); =\= is correct.
        ( After =\= Before ->
            format("  probe on ~w altered log count~n", [Scene]), true
        ; ClockAfter =\= ClockBefore ->
            format("  probe on ~w altered clock~n", [Scene]), true
        ;
            fail
        )
    ).

check_gates_never_mutate_source :-
    \+ (
        gates:gate_transformed(_, SourceEventId, _, OriginalTerm, _),
        log:arrived(SourceEventId, _, CurrentTerm, _, _),
        CurrentTerm \= OriginalTerm,
        format("  gate transform mutated source event ~w~n", [SourceEventId])
    ).

check_rules_locality :-
    \+ (
        scenes:scene_rule(RuleId, Scene, Conditions, _),
        collect_foreign_arrived_calls(Conditions, Scene, ForeignCalls),
        ForeignCalls \= [],
        format("  rule ~w in scene ~w queries foreign scenes: ~w~n",
               [RuleId, Scene, ForeignCalls])
    ).

collect_foreign_arrived_calls(Conditions, OwnerScene, Foreign) :-
    findall(
        OtherScene,
        (   sub_term(Sub, Conditions),
            Sub = arrived(_, OtherScene, _, _, _),
            nonvar(OtherScene),
            OtherScene \= OwnerScene
        ),
        Foreign
    ).
