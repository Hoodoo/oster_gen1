# Session 8 — verify_contracts and Invariant Checks

## What this session is

You are building Session 8 of the Oster implementation. You are building only
what is listed here. Do not read ahead or implement anything from future
sessions.

At the end of this session, all tests must be green, the session report must be
written to `docs/session_logs/session_08.md`, and no files outside the listed
scope may have been created or modified.

---

## Before you write a line of code

Run all prior session tests:

```bash
cd oster
swipl -g "run_tests" -t halt tests/log_tests.pl
swipl -g "run_tests" -t halt tests/provenance_tests.pl
swipl -g "run_tests" -t halt tests/gate_tests.pl
swipl -g "run_tests" -t halt tests/fixpoint_tests.pl
swipl -g "run_tests" -t halt tests/probe_tests.pl
swipl -g "run_tests" -t halt tests/lifecycle_tests.pl
swipl -g "run_tests" -t halt tests/projection_tests.pl
```

All tests must pass. If any fail, stop and report — do not proceed.

---

## Testing convention (in force for all sessions)

PLUnit runs test bodies in an isolated module (`plunit_*`). Any `assertz/1`
or `retractall/1` call inside a test body targeting a dynamic fact owned by an
engine module must be module-qualified. The `reset_engine` helper in
`setup(...)` blocks is unaffected. Clock resets must use `clock:clock_counter`,
not `log:clock_counter`.

---

## Resolving I-001 before catalog sessions

This session resolves the deferred issue documented in `docs/deferred.md` as
I-001: untransformed gate propagation leaves provenance chains untraversable.

**The fix is two small additions:**

1. `engine/gates.pl` — add `gate_passed/3` dynamic fact and assert it in
   `attempt_propagation/2` when a gate propagates without a transform.
2. `engine/provenance.pl` — add a second lookup path in `provenance_chain_/3`
   for `gate(GateId)` causes that uses `gate_passed/3` when
   `gate_transformed/5` is absent.

These are the only modifications to existing engine files in this session.
Full specification is in the "Resolving I-001" section below.

---

## Files to create

```
oster/
├── verify/
│   ├── contracts.pl        ← new
│   ├── propagation.pl      ← new
│   └── invariants.pl       ← new
└── tests/
    └── verify_tests.pl     ← new
```

Two existing files are modified:

```
oster/engine/
├── gates.pl       ← add gate_passed/3 (I-001)
└── provenance.pl  ← extend provenance_chain_ for gate_passed (I-001)
```

---

## Resolving I-001: `gate_passed/3`

### Addition to `engine/gates.pl`

Add the dynamic declaration:

```prolog
:- dynamic gate_passed/3.
% gate_passed(GateId, SourceEventId, DestEventId)
% Asserted for every untransformed gate propagation.
% Provides the source-to-destination link that gate_transformed/5 provides
% for transformed propagations. Together they make all gate hops traversable
% by provenance_chain/2. See docs/deferred.md I-001.
```

Modify `attempt_propagation/2` — in the open-gate branch, after `inject_event`
succeeds, assert `gate_passed` when no transform was applied:

```prolog
attempt_propagation(EventId, GateId) :-
    arrived(EventId, SourceScene, Term, Clock, _),
    gate(GateId, SourceScene, DestScene, _),
    ( gate_open(GateId) ->
        apply_transform(GateId, Term, OutTerm, Status),
        inject_event(DestScene, OutTerm, gate(GateId)),
        arrived_key(DestScene, OutTerm, Clock, DestEventId),
        ( Status = transformed ->
            assertz(gate_transformed(GateId, EventId, DestEventId, Term, OutTerm))
        ;
            assertz(gate_passed(GateId, EventId, DestEventId))
        )
    ;
        assertz(gate_blocked(GateId, EventId, Clock))
    ).
```

Note: the `arrived_key` lookup is now unconditional — it runs for both
transformed and untransformed cases. This is correct because `inject_event`
always asserts `arrived_key` before returning.

### Addition to `engine/provenance.pl`

Replace the `gate(GateId)` clause in `parent_event/3` with one that checks
both `gate_transformed/5` and `gate_passed/3`:

```prolog
parent_event(EventId, gate(GateId), ParentId) :-
    ( gate_transformed(GateId, ParentId, EventId, _, _) -> true
    ; gate_passed(GateId, ParentId, EventId) -> true
    ; ParentId = unknown_gate_source(GateId)
    ).
```

The `unknown_gate_source` terminal now only fires if neither fact exists — which
should not happen in a correctly running engine after this fix, but is retained
as a defensive fallback.

Also add `gate_passed` to the imports in `provenance.pl`:

```prolog
:- use_module(gates).
```

If `provenance.pl` already imports `gates` for `gate_transformed`, confirm the
import covers `gate_passed` too — it will, since it imports the module.

---

## Specification

### `verify/contracts.pl`

```prolog
:- use_module('../engine/log').
:- use_module('../engine/scenes').
:- use_module('../engine/gates').
:- use_module('../engine/provenance').
:- use_module('../engine/fixpoint').
```

---

#### `verify_contracts/0`

```prolog
verify_contracts :-
    run_check('no self-generating rules',  check_no_self_generating_rules),
    run_check('consequence specificity',   check_consequence_specificity),
    run_check('provenance acyclic',        check_provenance_acyclic),
    run_check('rule conditions safe',
              check_rule_conditions_safe(default_safe_predicates)),
    format("verify_contracts: all checks passed~n").

run_check(Name, Goal) :-
    ( call(Goal) ->
        format("  [ok] ~w~n", [Name])
    ;
        format("  [FAIL] ~w~n", [Name]),
        fail
    ).
```

Runs each check in sequence. Prints a line per check. Fails immediately if any
check fails — later checks are not run. The output is informational; the
pass/fail signal is the success or failure of `verify_contracts/0` itself.

---

#### `check_no_self_generating_rules/0`

```prolog
check_no_self_generating_rules :-
    \+ (
        scene_rule(RuleId, _Scene, Conditions, Template),
        functor(Template, F, _),
        term_contains_functor(Conditions, F),
        format("  rule ~w: consequence functor '~w' appears in conditions~n",
               [RuleId, F])
    ).
```

For each rule: if the functor of the consequence template appears anywhere in
the conditions goal, report it and fail the check. A rule that fires when
`noise(fight)` exists and produces `noise(fight)` would be caught here.

#### `term_contains_functor/2`

```prolog
term_contains_functor(Term, F) :-
    functor(Term, F, _), !.
term_contains_functor(Term, F) :-
    compound(Term),
    Term =.. [_|Args],
    member(Arg, Args),
    term_contains_functor(Arg, F).
```

Recursively checks whether functor `F` appears anywhere in `Term`.

---

#### `check_consequence_specificity/0`

```prolog
check_consequence_specificity :-
    % Warning only — not a hard failure.
    % Checks that consequence templates are not bare atoms or overly general.
    forall(
        scene_rule(RuleId, _Scene, _Conditions, Template),
        ( ( atomic(Template), \+ is_list(Template) ) ->
            format("  warning: rule ~w has atomic consequence '~w' ~
                    (consider structured term)~n", [RuleId, Template])
        ;
            true
        )
    ).
```

Issues a warning for rules whose consequence is a bare atom (e.g. `defeated`
rather than `defeated(warrior_a)`). Does not fail — the guide marks this check
as unproven. The warning is advisory.

---

#### `check_provenance_acyclic/0`

```prolog
check_provenance_acyclic :-
    \+ (
        arrived(EventId, _, _, _, _),
        \+ provenance_acyclic(EventId),
        format("  cyclic provenance chain from event ~w~n", [EventId])
    ).
```

Calls `provenance_acyclic/1` for every event in the log. Fails if any chain is
cyclic.

---

#### `check_rule_conditions_safe/1`

```prolog
default_safe_predicates([
    arrived/5, arrived_key/4, tier_status/2,
    caused_by/2, scene/1, scene_parent/2, scene_rule/4,
    gate/4, gate_condition/2, gate_open/1,
    is/2, =:=/2, =\=/2, </2, >/2, =</2, >=/2,
    =/2, \=/2, ==/2, \==/2,
    true/0, fail/0, not/1, \+/1,
    ','/2, ';'/2, '->' /2,
    member/2, memberchk/2, findall/3, aggregate_all/3,
    functor/3, arg/3, =../2, ground/1, atomic/1, compound/1,
    atom/1, number/1, integer/1, is_list/1, length/2,
    format/2, write/1, nl/0
]).

check_rule_conditions_safe(AllowedPreds) :-
    \+ (
        scene_rule(RuleId, _Scene, Conditions, _Template),
        collect_calls(Conditions, Calls),
        member(Call, Calls),
        functor(Call, F, A),
        \+ member(F/A, AllowedPreds),
        format("  rule ~w calls unsafe predicate ~w/~w~n", [RuleId, F, A])
    ).
```

#### `collect_calls/2`

```prolog
collect_calls(Goal, [Goal]) :-
    ( atomic(Goal) ; var(Goal) ), !.
collect_calls((A, B), Calls) :-
    !,
    collect_calls(A, CA),
    collect_calls(B, CB),
    append(CA, CB, Calls).
collect_calls((A ; B), Calls) :-
    !,
    collect_calls(A, CA),
    collect_calls(B, CB),
    append(CA, CB, Calls).
collect_calls((A -> B), Calls) :-
    !,
    collect_calls(A, CA),
    collect_calls(B, CB),
    append(CA, CB, Calls).
collect_calls(\+(A), Calls) :-
    !, collect_calls(A, Calls).
collect_calls(Goal, [Goal]).
```

Recursively collects all atomic call terms from a compound goal structure.

---

### `verify/propagation.pl`

```prolog
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').
:- use_module('../engine/probes').
```

---

#### `propagation_test/3`

```prolog
:- dynamic propagation_test/3.
% propagation_test(GateId, EventTerm, ExpectedOutcome)
% ExpectedOutcome is one of: crossed, blocked, no_interaction
```

Static declaration. Authoring predicate — catalog entries assert these before
calling `verify_propagation_tests/0`.

#### `assert_propagation_test/3`

```prolog
assert_propagation_test(GateId, EventTerm, ExpectedOutcome) :-
    assertz(propagation_test(GateId, EventTerm, ExpectedOutcome)).
```

---

#### `propagation_coverage/2`

```prolog
propagation_coverage(GateId, Report) :-
    gate(GateId, SourceScene, DestScene, _),
    probe(SourceScene, vocab(_, _)),
    probe(DestScene, vocab(DestHeads, _)),
    findall(
        result(EventTerm, Outcome),
        (   member(EventTerm, DestHeads),
            test_propagation(GateId, SourceScene, EventTerm, Outcome)
        ),
        Report
    ).
```

For a given gate: collects the destination scene's vocabulary (rule heads),
tests each term's propagation through the gate in an isolated mini-world, and
returns a list of `result(EventTerm, Outcome)` terms.

#### `test_propagation/4`

```prolog
test_propagation(GateId, SourceScene, EventTerm, Outcome) :-
    % Run in an isolated copy of the world state.
    % Save and restore engine state around the test.
    with_clean_world(
        ( inject_event(SourceScene, EventTerm, injected(author)),
          arrived_key(SourceScene, EventTerm, _, EventId),
          attempt_propagation(EventId, GateId),
          ( gate_blocked(GateId, EventId, _) ->
              Outcome = blocked
          ;
              gate(GateId, SourceScene, DestScene, _),
              ( arrived(_, DestScene, _, _, _) ->
                  Outcome = crossed
              ;
                  Outcome = no_interaction
              )
          )
        )
    ).
```

#### `with_clean_world/1`

```prolog
with_clean_world(Goal) :-
    % Snapshot current event counter and clock
    log:event_counter(CounterBefore),
    clock:clock_counter(ClockBefore),
    % Run goal, then retract only the facts added during this call
    % by comparing arrived count before and after
    log:log_count(LogBefore),
    call(Goal),
    % Retract test-injected events by EventId range
    % This is the one place in the verify layer where targeted cleanup
    % of test artifacts is permitted — not of the real log, but of
    % mini-world test injections.
    log:log_count(_LogAfter),
    retract(log:event_counter(_)),
    assertz(log:event_counter(CounterBefore)),
    retract(clock:clock_counter(_)),
    assertz(clock:clock_counter(ClockBefore)),
    % Note: arrived/5 facts injected during the test remain in the log.
    % They are test artifacts at the current clock value and will not
    % affect a real world running at a different clock. This is a known
    % limitation of propagation_coverage — it is designed for use before
    % world_step is called, not mid-simulation.
    true.
```

**Important note on `with_clean_world/1`:** The propagation coverage machinery
runs mini-world tests that inject events. These events land in the real log.
`with_clean_world/1` resets the counter and clock but cannot retract `arrived/5`
facts (append-only invariant). This means `propagation_coverage/2` is designed
for use in dedicated test runs, not mid-simulation. Catalog tests use it in
isolated plunit tests with `reset_engine` in `setup(...)`. Document this
limitation with a comment.

---

#### `verify_propagation_tests/0`

```prolog
verify_propagation_tests :-
    \+ (
        propagation_test(GateId, EventTerm, Expected),
        test_propagation(GateId, _, EventTerm, Actual),
        Actual \= Expected,
        format("  propagation test failed: gate ~w, event ~w: ~
                expected ~w, got ~w~n", [GateId, EventTerm, Expected, Actual])
    ).
```

Runs all declared `propagation_test/3` assertions and fails if any mismatch.

---

### `verify/invariants.pl`

```prolog
:- use_module('../engine/log').
:- use_module('../engine/gates').
:- use_module('../engine/scenes').
:- use_module('../engine/probes').
```

---

#### `record_log_baseline/0`

```prolog
:- dynamic log_baseline/1.

record_log_baseline :-
    retractall(log_baseline(_)),
    log:log_count(N),
    assertz(log_baseline(N)).
```

---

#### `check_log_append_only/0`

```prolog
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
```

---

#### `check_probes_side_effect_free/0`

```prolog
check_probes_side_effect_free :-
    \+ (
        scenes:scene(Scene),
        log:log_count(Before),
        clock:clock_value(ClockBefore),
        probes:probe(Scene, _),
        log:log_count(After),
        clock:clock_value(ClockAfter),
        ( After \=:= Before ->
            format("  probe on ~w altered log count~n", [Scene]), true
        ; ClockAfter \=:= ClockBefore ->
            format("  probe on ~w altered clock~n", [Scene]), true
        ;
            fail
        )
    ).
```

---

#### `check_gates_never_mutate_source/0`

```prolog
check_gates_never_mutate_source :-
    \+ (
        gates:gate_transformed(_, SourceEventId, _, OriginalTerm, _),
        log:arrived(SourceEventId, _, CurrentTerm, _, _),
        CurrentTerm \= OriginalTerm,
        format("  gate transform mutated source event ~w~n", [SourceEventId])
    ).
```

For every `gate_transformed` fact, confirms the original source event still
carries its original term. Fails if any source event has been modified.

---

#### `check_rules_locality/0`

```prolog
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
```

Scans each rule's conditions for `arrived/5` calls where the scene argument is
bound to a scene other than the rule's own scene. Reports violations as warnings
— this check surfaces cross-scene rule queries for review but does not prevent
them, since some cross-scene queries may be intentional (e.g. a gate condition
that checks another scene's state).

---

### `reset_engine` for verify tests

```prolog
reset_engine :-
    retractall(log:arrived(_, _, _, _, _)),
    retractall(log:arrived_key(_, _, _, _)),
    retractall(log:tier_status(_, _)),
    retractall(log:tier_transition(_, _, _, _)),
    retractall(provenance:caused_by(_, _)),
    retractall(scenes:scene(_)),
    retractall(scenes:scene_parent(_, _)),
    retractall(scenes:scene_rule(_, _, _, _)),
    retractall(gates:gate(_, _, _, _)),
    retractall(gates:gate_condition(_, _)),
    retractall(gates:gate_transform(_, _, _)),
    retractall(gates:gate_blocked(_, _, _)),
    retractall(gates:gate_transformed(_, _, _, _, _)),
    retractall(gates:gate_passed(_, _, _)),
    retractall(fixpoint:rule_trigger(_, _, _)),
    retractall(fixpoint:fixpoint_depth_exceeded(_)),
    retractall(fixpoint:rule_grounding_failed(_, _)),
    retractall(log:event_counter(_)), assertz(log:event_counter(0)),
    retractall(clock:clock_counter(_)), assertz(clock:clock_counter(0)).
```

---

## Tests: `tests/verify_tests.pl`

```prolog
:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/provenance').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').
:- use_module('../engine/probes').
:- use_module('../verify/contracts').
:- use_module('../verify/propagation').
:- use_module('../verify/invariants').
```

**Required test cases:**

**T1 — I-001 resolved: gate_passed asserted for untransformed gate**
Declare scenes `src`, `dst`. Declare open gate `g_pass` from `src` to `dst`
with no transform. Inject `signal` into `src` at clock 0. Call
`attempt_propagation(EventId, g_pass)`. Assert
`gates:gate_passed(g_pass, EventId, _DestEventId)` holds. Assert
`gates:gate_transformed(g_pass, _, _, _, _)` does NOT hold.

**T2 — I-001 resolved: provenance chain traverses untransformed gate**
Using state from T1: find `DestEventId` via
`gates:gate_passed(g_pass, EventId, DestEventId)`. Call
`investigation_chain(DestEventId, Chain)`. Assert the chain contains a step
for the original `signal` event in `src` — the chain is now fully traversable
through the untransformed hop. Assert no `unknown_gate_source` terminal in
the chain.

**T3 — check_no_self_generating_rules: clean world passes**
Declare rule `r_safe` with conditions `arrived(_, room, trigger, _, hot)` and
consequence `response`. Call `check_no_self_generating_rules`. Assert it
succeeds.

**T4 — check_no_self_generating_rules: self-generating rule caught**
Declare rule `r_bad` with conditions `arrived(_, room, noise, _, hot)` and
consequence `noise`. Call `check_no_self_generating_rules`. Assert it fails.

**T5 — check_provenance_acyclic: clean log passes**
Inject three events. Call `check_provenance_acyclic`. Assert it succeeds.

**T6 — check_rule_conditions_safe: safe rule passes**
Declare rule with conditions `arrived(_, room, signal, _, hot)` and safe
consequence. Call `check_rule_conditions_safe(default_safe_predicates)`.
Assert it succeeds.

**T7 — check_rule_conditions_safe: unsafe call caught**
Declare rule with conditions containing `assert(foo)` (not in allowed list).
Call `check_rule_conditions_safe(default_safe_predicates)`. Assert it fails.

**T8 — verify_contracts: clean world passes**
Declare a small valid world (one scene, one safe rule). Inject an event. Call
`verify_contracts`. Assert it succeeds.

**T9 — verify_contracts: bad rule fails**
Declare a self-generating rule. Call `verify_contracts`. Assert it fails.

**T10 — check_log_append_only: growing log passes**
Call `record_log_baseline`. Inject two events. Call `check_log_append_only`.
Assert it succeeds.

**T11 — check_probes_side_effect_free: probe leaves log unchanged**
Declare a scene with rules and gates. Call `record_log_baseline`. Call
`check_probes_side_effect_free`. Call `check_log_append_only`. Assert both
succeed.

**T12 — check_gates_never_mutate_source: clean world passes**
Declare a gate with a transform. Inject and propagate an event. Call
`check_gates_never_mutate_source`. Assert it succeeds — source event is
unchanged.

**T13 — propagation_coverage: crossed outcome**
Declare scenes `src`, `dst`. Declare open gate `g_cov` from `src` to `dst`.
Declare rule `r_dst` in `dst` with consequence `response`. Call
`assert_propagation_test(g_cov, response, crossed)`. Call
`verify_propagation_tests`. Assert it succeeds.

**T14 — propagation_coverage: blocked outcome**
Declare gate `g_blocked` from `src` to `dst` with condition `fail`. Declare
rule in `dst` with consequence `response`. Call
`assert_propagation_test(g_blocked, response, blocked)`. Call
`verify_propagation_tests`. Assert it succeeds.

**T15 — check_rules_locality: cross-scene query flagged**
Declare scene `room_a` with a rule whose conditions query
`arrived(_, room_b, _, _, _)` — a foreign scene. Call `check_rules_locality`.
Assert it fails (reports the violation).

---

## Design decisions in force for this session

**I-001 resolved.** `gate_passed/3` is asserted for all untransformed
propagations. `provenance_chain_/3` checks `gate_passed/3` before falling back
to `unknown_gate_source`. After this session, fully traversable chains are the
expected behaviour for all gate hops, transformed or not.

**`with_clean_world/1` limitation.** Propagation coverage tests inject events
into the real log. This is acceptable in isolated plunit tests with
`reset_engine` in `setup(...)`. Never call `propagation_coverage/2` in a
running simulation.

**`check_rules_locality` is advisory.** It reports cross-scene queries but does
not prevent them. The invariant check surfaces the pattern for human review; it
does not enforce the locality guarantee automatically. The locality guarantee
is a model property; this check is an authoring aid.

---

## Constraints

- The only modifications to `engine/gates.pl` are: adding `gate_passed/3`
  declaration and the `assertz(gate_passed(...))` call in
  `attempt_propagation/2`.
- The only modification to `engine/provenance.pl` is: updating the
  `gate(GateId)` clause in `parent_event/3`.
- Do not modify any test file from Sessions 1–7.
- `verify/contracts.pl`, `verify/propagation.pl`, and `verify/invariants.pl`
  must not import each other.
- All predicate names must match the specification exactly.

---

## Acceptance criteria

The session is complete when:

1. `swipl -g "run_tests" -t halt tests/log_tests.pl` — all 9 pass.
2. `swipl -g "run_tests" -t halt tests/provenance_tests.pl` — all 11 pass.
3. `swipl -g "run_tests" -t halt tests/gate_tests.pl` — all 13 pass.
4. `swipl -g "run_tests" -t halt tests/fixpoint_tests.pl` — all 13 pass.
5. `swipl -g "run_tests" -t halt tests/probe_tests.pl` — all 13 pass.
6. `swipl -g "run_tests" -t halt tests/lifecycle_tests.pl` — all 13 pass.
7. `swipl -g "run_tests" -t halt tests/projection_tests.pl` — all 15 pass.
8. `swipl -g "run_tests" -t halt tests/verify_tests.pl` — all 15 pass.
9. No `arrived/5` fact is retracted at any point during any test run.
10. I-001 is marked resolved in `docs/deferred.md` with this session's commit
    hash.
11. `docs/session_logs/session_08.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_08.md`:

```
# Session 8 Report — verify_contracts and Invariant Checks

## Files created
- verify/contracts.pl
- verify/propagation.pl
- verify/invariants.pl
- tests/verify_tests.pl

## Files modified
- engine/gates.pl (I-001: added gate_passed/3)
- engine/provenance.pl (I-001: extended parent_event/3 for gate_passed)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed
- tests/fixpoint_tests.pl: 13 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed
- tests/lifecycle_tests.pl: 13 passed, 0 failed
- tests/projection_tests.pl: 15 passed, 0 failed
- tests/verify_tests.pl: 15 passed, 0 failed

## I-001 resolution
Commit hash: (fill in after commit)
gate_passed/3 asserted for all untransformed propagations.
provenance_chain_ now traverses both gate_transformed and gate_passed.

## Stubs left for future sessions
(none expected)

## Anomalies, surprises, questions
(anything unexpected)
```

Do not produce the report until all tests pass.

---

## Ambiguity resolution

If something is unclear: session prompt first, then `docs/implementation_plan.md`,
then `docs/conceptual_guide.md`. If genuine ambiguity remains, make the most
conservative choice and leave a `% DECISION:` comment.
