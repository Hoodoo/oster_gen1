# Session 14 — Provenance Acyclic Check Fix

## What this session is

A real correctness bug, found during external review and confirmed against
source before this prompt was written: `provenance_acyclic/1` in
`engine/provenance.pl` never actually traverses the provenance chain. This
session fixes the predicate, removes the now-dead helper it leaves behind,
adds a regression test that would have caught this, and logs the issue —
already resolved by the time this session ends — in `docs/deferred.md`.

This session does not touch the REPL, any catalog file, or any engine file
other than `provenance.pl`.

---

## Before you write a line of code

```bash
cd oster
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

All must pass. If any fail, stop and report — do not proceed.

---

## Context

`provenance_acyclic/1` was left by Session 2 as a "leaf traversal only" stub,
with that session's own report explicitly flagging it for Session 4 to
extend — the same treatment `provenance_chain/2` got in that same stub.
Session 4 did extend `provenance_chain/2` to full multi-hop traversal, but
its prompt scoped that work as "the only modification permitted to
`engine/provenance.pl` in this session," referring only to
`provenance_chain/2`. `provenance_acyclic/1` was never revisited. Its
`Visited` accumulator is passed into the helper once and never grows — the
predicate checks only the immediate event's cause and returns, so
`check_provenance_acyclic` in `verify_contracts` currently succeeds for any
event with a `caused_by/2` fact, regardless of whether the full chain
contains a cycle. The existing test (T8 in `provenance_tests.pl`) only
exercises three independent injected events — no chain depth at all — which
is why nothing has caught this.

The fix is cheap because the correct traversal already exists a few lines
above the broken one: `provenance_chain/2` already walks the full chain and
emits `cycle_detected(_)` when it finds a repeat.

---

## Files to modify

```
oster/
├── engine/
│   └── provenance.pl        ← fix provenance_acyclic/1
├── tests/
│   └── provenance_tests.pl  ← add regression test
└── docs/
    └── deferred.md           ← log as a resolved issue
```

No other files are touched.

---

## Specification

### `engine/provenance.pl`

Replace this:

```prolog
provenance_acyclic(EventId) :-
    provenance_acyclic_(EventId, []).

provenance_acyclic_(EventId, Visited) :-
    \+ member(EventId, Visited),
    ( caused_by(EventId, injected(_)) -> true
    ; caused_by(EventId, simulation_boundary(_)) -> true
    ; caused_by(EventId, Cause),
      ( Cause = rule(_, _) -> true
      ; Cause = gate(_) -> true
      ; true
      )
    ).
```

with this:

```prolog
provenance_acyclic(EventId) :-
    provenance_chain(EventId, Chain),
    \+ member(cycle_detected(_), Chain).
```

`provenance_acyclic_/2` is deleted entirely — it is not exported (check the
module's export list, which does not change) and has no other callers in
the codebase.

### `tests/provenance_tests.pl`

Add a new test — use the next sequential number after whatever is currently
last in this file, don't assume it's still T11. The test hand-constructs a
2-cycle directly via `caused_by/2` and `gate_passed/3` — this state is not
reachable through normal engine operation (`inject_event`/
`attempt_propagation` cannot produce a cycle), it simulates a malformed log
to test the detector itself:

```prolog
test(provenance_acyclic_detects_cycle, [setup(reset_engine)]) :-
    assertz(provenance:caused_by(evt_loop_a, gate(g_loop))),
    assertz(provenance:caused_by(evt_loop_b, gate(g_loop))),
    assertz(gates:gate_passed(g_loop, evt_loop_b, evt_loop_a)),
    assertz(gates:gate_passed(g_loop, evt_loop_a, evt_loop_b)),
    \+ provenance_acyclic(evt_loop_a).
```

Extend this file's `reset_engine` to also `retractall(gates:gate_passed(_,
_, _))` — this test is the first one in this file to produce that fact, and
nothing else here depends on it persisting.

---

### `docs/deferred.md`

Add a new entry under **Resolved** (fill in the actual commit hash when
committing):

```markdown
### I-003 — `provenance_acyclic/1` never traversed past the immediate cause

**Identified:** External review, confirmed against source
**Resolved:** Session 14, commit <fill in>

**Problem:**
`provenance_acyclic/1` was left as a Session 2 stub ("leaf traversal only —
Session 4 extends") and never actually extended. Session 4 extended
`provenance_chain/2` to full multi-hop traversal but its prompt scoped that
session as the only permitted change to `engine/provenance.pl`, and
`provenance_acyclic/1` was never revisited. Its `Visited` accumulator was
passed but never grown — the predicate checked only the immediate event's
cause and returned, so `check_provenance_acyclic` in `verify_contracts`
succeeded unconditionally for any event with a `caused_by/2` fact, regardless
of whether the full chain contained a cycle. The existing T8 test only
exercised independently-injected events with no chain depth, so nothing
caught this.

**Resolution:**
`provenance_acyclic/1` now reuses the (correct) `provenance_chain/2`
traversal and fails if the resulting chain contains a `cycle_detected(_)`
step. The dead `provenance_acyclic_/2` helper was removed. A new test
hand-constructs a 2-cycle via direct `caused_by/2` and `gate_passed/3`
assertions and confirms the fixed predicate now correctly rejects it.
```

---

## Design decisions in force for this session

**T8 is untouched.** It's still valid coverage for the terminal-cause case;
it was just never sufficient on its own. The new test adds the missing
case rather than replacing the existing one.

**No change to `verify_tests.pl`.** `check_provenance_acyclic` calls
`provenance_acyclic/1` directly, so fixing and testing at the source
predicate is sufficient — a separate contract-level negative test would be
redundant.

**`provenance_chain/2` is not touched.** It is already correct (Session 4)
and is being reused, not modified.

---

## Constraints

- Do not modify any file outside the three listed above.
- Do not change `provenance_acyclic/1`'s exported signature or arity.
- Do not touch `parent_event/3`, `terminal_cause/1`, or `provenance_chain/2`.

---

## Acceptance criteria

1. All eleven prior suites pass with the same counts as before, plus one
   additional passing test in `tests/provenance_tests.pl`.
2. Before committing, confirm the new test actually exercises the bug:
   temporarily revert to the old `provenance_acyclic_/2` implementation,
   confirm the new test fails, then reapply the fix and confirm it passes.
   Note the result of this check in the session report.
3. `docs/deferred.md` has the new I-003 entry under Resolved, with the real
   commit hash filled in.
4. `docs/session_logs/session_14.md` is written.
