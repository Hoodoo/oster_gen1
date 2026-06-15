# Session 11b — Gate Term Filtering and D8 Fix

## What this session is

This is a focused engine fix between Session 11 and Session 12. Session 11
identified that `gate_open/1` has no access to the event term being propagated,
which means gates cannot filter by term. This caused an inward gate from
`patron_a` to `tavern` to carry `strike(5)` into the tavern log, violating D8.

This session adds `gate_term_filter/2` to `engine/gates.pl`, applies term
filters to the tavern's inward gates, and restores T8 in
`catalog/tavern/tests.pl` to its intended assertion: `strike(5)` does NOT
appear in the tavern log.

No other changes. No new features.

---

## Before you write a line of code

Run all tests:

```bash
swipl -g "run_tests" -t halt tests/log_tests.pl
swipl -g "run_tests" -t halt tests/provenance_tests.pl
swipl -g "run_tests" -t halt tests/gate_tests.pl
swipl -g "run_tests" -t halt tests/fixpoint_tests.pl
swipl -g "run_tests" -t halt tests/probe_tests.pl
swipl -g "run_tests" -t halt tests/lifecycle_tests.pl
swipl -g "run_tests" -t halt tests/projection_tests.pl
swipl -g "run_tests" -t halt tests/verify_tests.pl
swipl -g "run_tests" -t halt catalog/deck/tests.pl
swipl -g "run_tests" -t halt catalog/warrior/tests.pl
swipl -g "run_tests" -t halt catalog/tavern/tests.pl
```

Record the current pass counts. All must pass before you touch anything.

---

## Files to modify

```
engine/gates.pl                  ← add gate_term_filter/2 and update
                                    attempt_propagation/2
catalog/tavern/gates.pl          ← add term filter declarations
catalog/tavern/tests.pl          ← restore T8 to correct assertion
tests/gate_tests.pl              ← add two tests for gate_term_filter
```

No other files are modified.

---

## Specification

### `engine/gates.pl` changes

#### Add `gate_term_filter/2`

```prolog
:- dynamic gate_term_filter/2.
% gate_term_filter(GateId, TermPattern)
%
% If any filter is declared for a gate, only events whose term unifies
% with at least one declared pattern may cross. Events that match no
% pattern are blocked and recorded as gate_blocked facts.
%
% If no filter is declared for a gate, all terms may cross (existing
% behaviour preserved).
```

Add this declaration alongside the other dynamic fact declarations at the
top of the file.

#### Update `attempt_propagation/2`

Add a term filter check after binding `Term` and before the `gate_open/1`
check. The full updated predicate:

```prolog
attempt_propagation(EventId, GateId) :-
    arrived(EventId, SourceScene, Term, Clock, _),
    gate(GateId, SourceScene, DestScene, _),
    ( gate_term_filter(GateId, _) ->
        % At least one filter declared — term must match at least one pattern
        ( gate_term_filter(GateId, Pattern), \+ \+ Term = Pattern ->
            true
        ;
            assertz(gate_blocked(GateId, EventId, Clock)),
            !,
            fail
        )
    ;
        true  % No filter declared — all terms permitted (existing behaviour)
    ),
    ( gate_open(GateId) ->
        apply_transform(GateId, Term, OutTerm, Status),
        inject_event(DestScene, OutTerm, gate(GateId)),
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
```

**Note on the cut and fail:** When a term filter rejects an event, we assert
`gate_blocked` and then cut+fail to prevent the open-gate branch from running.
The cut is local to the filter branch. `attempt_propagation/2` fails in this
case — which means `propagate_from_scene/2`'s `forall/2` will also fail.

**This changes `attempt_propagation/2`'s success behaviour.** Previously it
always succeeded. Now it fails when a term filter rejects the event. Update
`propagate_from_scene/2` to handle this:

```prolog
propagate_from_scene(Scene, EventId) :-
    forall(
        gate(GateId, Scene, _, _),
        ( attempt_propagation(EventId, GateId) -> true ; true )
    ).
```

The `( ... -> true ; true )` wrapper means `forall/2` continues even if
`attempt_propagation/2` fails for a filtered event. This preserves the
original invariant: `propagate_from_scene/2` always succeeds.

#### Add `declare_gate_term_filter/2`

```prolog
declare_gate_term_filter(GateId, Pattern) :-
    assertz(gate_term_filter(GateId, Pattern)).
```

Convenience predicate. Consistent with the `declare_*` pattern used throughout.

---

### `catalog/tavern/gates.pl` changes

Add term filter declarations to `declare_tavern_gates/0` after the inward
gate declarations:

```prolog
declare_tavern_gates :-
    declare_gate(patron_a_noise_to_tavern, patron_a, tavern, upward),
    declare_gate(patron_b_noise_to_tavern, patron_b, tavern, upward),
    % Term filter: only noise(fight) crosses the inward gates.
    % Without this filter, all patron events (including strike/taunt)
    % would appear in the tavern log, violating D8.
    declare_gate_term_filter(patron_a_noise_to_tavern, noise(fight)),
    declare_gate_term_filter(patron_b_noise_to_tavern, noise(fight)),
    declare_gate(tavern_noise_to_street, tavern, street, downward),
    assertz(gates:gate_condition(
        tavern_noise_to_street,
        tavern_scene:window_open(tavern)
    )).
```

---

### `catalog/tavern/tests.pl` changes

**Restore T8** to its intended assertion. Find the test currently containing
a `% DECISION:` comment about the inverted assertion and replace its body:

The test should assert:

```prolog
\+ arrived(_, tavern, strike(5), _, _)
```

Remove the `% DECISION:` comment and the inverted assertion entirely. T8
should read cleanly as a positive statement of D8.

---

### `tests/gate_tests.pl` additions

Add two new tests at the end of the test suite. These go after the existing
T13 test. Do not modify any existing tests.

**T14 — term filter blocks non-matching term**
Declare scenes `src`, `dst`. Declare open gate `g_filtered` from `src` to
`dst`. Add `assertz(gates:gate_term_filter(g_filtered, noise(fight)))`.
Inject `strike(5)` into `src`. Find its EventId. Call
`attempt_propagation(EventId, g_filtered)`.
Assert `\+ arrived(_, dst, strike(5), _, _)` — the term was filtered.
Assert `gates:gate_blocked(g_filtered, EventId, _)` — blocked fact recorded.

**T15 — term filter permits matching term**
Using same gate `g_filtered` with filter `noise(fight)`.
Inject `noise(fight)` into `src`. Find its EventId. Call
`attempt_propagation(EventId, g_filtered)`.
Assert `arrived(_, dst, noise(fight), _, _)` — the term crossed.
Assert `\+ gates:gate_blocked(g_filtered, EventId, _)` — not blocked.

**Also add `gate_term_filter` to `reset_engine` in `gate_tests.pl`:**

```prolog
retractall(gates:gate_term_filter(_, _)),
```

---

### `reset_engine` in `catalog/tavern/tests.pl`

Add `gate_term_filter` retractall to the tavern `reset_engine`:

```prolog
retractall(gates:gate_term_filter(_, _)),
```

---

## Design decisions

**`attempt_propagation/2` now fails on filter rejection.** This is a
deliberate change. The previous "always succeed" contract was based on the
assumption that gate blocking was the only terminal — but a term filter
rejection is semantically distinct from a gate condition failure. Both
result in a `gate_blocked` fact; the difference is what caused the block.
`propagate_from_scene/2` is updated to absorb the failure.

**`\+ \+ Term = Pattern` for unification check.** This checks whether `Term`
unifies with `Pattern` without binding either. This is correct for pattern
matching where `Pattern` may contain unbound variables (e.g.
`noise(_)` would match any `noise/1` term).

**I-002 resolved by this session.** Mark it resolved in `docs/deferred.md`
with this session's commit hash after the commit.

---

## Acceptance criteria

1. All prior test suites pass with the same counts as before this session.
2. `swipl -g "run_tests" -t halt tests/gate_tests.pl` — 15 pass (13 + 2 new).
3. `swipl -g "run_tests" -t halt catalog/tavern/tests.pl` — all 17 pass,
   including T8 with the correct `\+` assertion.
4. T8 in `catalog/tavern/tests.pl` contains no `% DECISION:` comment
   referencing the inverted assertion.
5. No `arrived/5` fact is retracted at any point during any test run.
6. I-002 marked resolved in `docs/deferred.md` with commit hash.
7. `docs/session_logs/session_11b.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_11b.md`:

```
# Session 11b Report — Gate Term Filtering and D8 Fix

## Files modified
- engine/gates.pl (gate_term_filter/2, updated attempt_propagation/2,
  updated propagate_from_scene/2, added declare_gate_term_filter/2)
- catalog/tavern/gates.pl (added term filter declarations)
- catalog/tavern/tests.pl (restored T8 to correct assertion)
- tests/gate_tests.pl (added T14, T15, gate_term_filter in reset_engine)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 15 passed, 0 failed
- tests/fixpoint_tests.pl: 13 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed
- tests/lifecycle_tests.pl: 13 passed, 0 failed
- tests/projection_tests.pl: 15 passed, 0 failed
- tests/verify_tests.pl: 15 passed, 0 failed
- catalog/deck/tests.pl: 17 passed, 0 failed
- catalog/warrior/tests.pl: 12 passed, 0 failed
- catalog/tavern/tests.pl: 17 passed, 0 failed

## I-002 resolution
Commit hash: (fill in after commit)

## Anomalies, surprises, questions
(anything unexpected)
```

Do not produce the report until all tests pass and T8 is correct.
