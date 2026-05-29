# Session 6 — Log Lifecycle

## What this session is

You are building Session 6 of the Oster implementation. You are building only
what is listed here. Do not read ahead or implement anything from future
sessions.

At the end of this session, all tests must be green, the session report must be
written to `docs/session_logs/session_06.md`, and no files outside the listed
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
```

All tests must pass. If any fail, stop and report — do not proceed.

---

## Testing convention (in force for all sessions)

PLUnit runs test bodies in an isolated module (`plunit_*`). Any `assertz/1`
or `retractall/1` call inside a test body targeting a dynamic fact owned by an
engine module must be module-qualified: `assertz(scenes:scene_rule(...))`,
`assertz(gates:gate_condition(...))`, etc. The `reset_engine` helper in
`setup(...)` blocks is unaffected.

---

## Context: what this session builds

The log is append-only and permanent — but permanent does not mean every fact
must be scanned on every fixpoint iteration forever. This session builds the
tier management system: the mechanism by which events move from `hot` (scanned
by the fixpoint) to `cold` (readable but not scanned) to `archived`
(disk-backed, paid on access).

The guide is explicit that tiers are not a performance optimisation bolted on
top of the model — they are a first-class authoring concept. The transition from
hot to cold is a narrative declaration: "this chapter is settled." The engine
records it as a `tier_transition` fact with provenance, and from that point
forward the fixpoint skips those events.

Three modules are built here:

**`tiers.pl`** — the mechanical tier promotion predicates. These are the engine
primitives. Everything else in the lifecycle layer calls them.

**`closure.pl`** — closure as an event. `closed(Scene, clock(N))` is injected
like any other event, propagates through gates like any other event, and can
trigger rules like any other event. The engine has no special knowledge of
`closed` terms. `declare_closure/2` is the authoring convenience that produces
the event.

**`compaction.pl`** — summary injection plus cold promotion in one authoring
operation. The pre-apocalypse dagger pattern from the guide: at a meaningful
story boundary, inject a summary event describing the settled state, and
promote the raw history to cold.

This session also contains a decision point regarding `tier_status` updates.
See below.

---

## Decision point: updating `tier_status/2`

`tier_status(EventId, Tier)` is declared and owned by `engine/log.pl`. It is a
single-valued index: exactly one fact per `EventId` at all times. Session 1
specified that updating it requires retracting the old value and asserting the
new one — the only permitted retraction in the log layer.

Session 1 did not expose a named predicate for this update. The lifecycle module
needs to perform it. Two options:

**Option A:** Add `update_tier_status/2` to `engine/log.pl` in this session,
and call it from `lifecycle/tiers.pl`.

```prolog
% In engine/log.pl:
update_tier_status(EventId, NewTier) :-
    retract(tier_status(EventId, _)),
    assertz(tier_status(EventId, NewTier)).
```

**Option B:** `lifecycle/tiers.pl` module-qualifies the retract/assertz directly:

```prolog
retract(log:tier_status(EventId, _)),
assertz(log:tier_status(EventId, NewTier)).
```

**Decision: use Option A.** Adding `update_tier_status/2` to `log.pl` keeps the
retraction isolated to the module that owns the fact, makes the operation
named and testable, and prevents `lifecycle/tiers.pl` from reaching into
`log.pl`'s internals directly. This is the only modification permitted to
`engine/log.pl` in this session.

---

## Files to create

```
oster/
├── lifecycle/
│   ├── tiers.pl        ← new
│   ├── closure.pl      ← new
│   └── compaction.pl   ← new
└── tests/
    └── lifecycle_tests.pl  ← new
```

One existing file is modified:

```
oster/
└── engine/
    └── log.pl          ← add update_tier_status/2 only
```

---

## Specification

### `engine/log.pl` addition

Add this predicate to `engine/log.pl`. No other changes.

```prolog
update_tier_status(EventId, NewTier) :-
    retract(tier_status(EventId, _)),
    assertz(tier_status(EventId, NewTier)).
```

---

### `lifecycle/tiers.pl`

```prolog
:- use_module('../engine/log').
:- use_module('../engine/clock').
```

---

#### `promote_to_cold/2`

```prolog
promote_to_cold(Scene, UpToClock) :-
    clock_value(Now),
    forall(
        ( arrived(EventId, Scene, _, Clock, _),
          tier_status(EventId, hot),
          Clock =< UpToClock
        ),
        ( update_tier_status(EventId, cold),
          assertz(tier_transition(EventId, hot, cold, Now))
        )
    ).
```

For all hot events in `Scene` with arrival clock `=< UpToClock`: updates
`tier_status` to `cold` and appends a `tier_transition` audit record. Does not
retract `arrived/5`.

---

#### `promote_to_archived/2`

```prolog
promote_to_archived(Scene, UpToClock) :-
    clock_value(Now),
    forall(
        ( arrived(EventId, Scene, _, Clock, _),
          tier_status(EventId, cold),
          Clock =< UpToClock
        ),
        ( update_tier_status(EventId, archived),
          assertz(tier_transition(EventId, cold, archived, Now))
        )
    ).
```

Same pattern, `cold` → `archived`. Only promotes events already at `cold` —
does not skip directly from `hot` to `archived`. If disk-backing via
`library(persistency)` is desired, it is an authoring concern layered on top of
this predicate, not part of the engine primitive. For now, `archived` is an
in-memory tier distinguished only by its `tier_status` value and the fixpoint
skipping it.

---

#### `cold_events/2`

```prolog
cold_events(Scene, Events) :-
    findall(EventId,
            ( arrived(EventId, Scene, _, _, _),
              tier_status(EventId, cold)
            ),
            Events).
```

Read-only query. Used by tests and by `investigation_chain` (Session 7) to
confirm cold events remain readable.

---

#### `archived_events/2`

```prolog
archived_events(Scene, Events) :-
    findall(EventId,
            ( arrived(EventId, Scene, _, _, _),
              tier_status(EventId, archived)
            ),
            Events).
```

---

### `lifecycle/closure.pl`

```prolog
:- use_module('../engine/log').
:- use_module('../engine/clock').
```

---

#### `declare_closure/2`

```prolog
declare_closure(Scene, Clock) :-
    inject_event(Scene, closed(Scene, clock(Clock)), injected(author)).
```

Authoring convenience. Injects `closed(Scene, clock(Clock))` as a normal event
with authoring provenance. The fixpoint and any declared gates handle
propagation from here. The engine does not special-case `closed` terms — this
event is structurally identical to any other.

No scene rules that respond to `closed` events are built into the engine. Any
such rules are authored in specific scenes that need them. This module provides
only the injection convenience.

---

#### `scene_closed/2`

```prolog
scene_closed(Scene, Clock) :-
    arrived(_, Scene, closed(Scene, clock(Clock)), _, _).
```

Read-only query. Succeeds if a closure event for `Scene` at `Clock` exists in
the log at any tier. Used by tests and authoring tools.

---

### `lifecycle/compaction.pl`

```prolog
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module(tiers).
```

---

#### `assert_summary/4`

```prolog
assert_summary(Scene, ProjectionName, SummaryTerm, UpToClock) :-
    inject_event(Scene,
                 summary(ProjectionName, SummaryTerm),
                 injected(author)),
    promote_to_cold(Scene, UpToClock).
```

Two operations in sequence:

1. Injects `summary(ProjectionName, SummaryTerm)` into `Scene` with authoring
   provenance. This event lands in the log as hot — it is the new canonical
   record of the settled state.
2. Promotes all hot events in `Scene` up to `UpToClock` to cold — including,
   potentially, the summary event itself if its clock value falls within the
   boundary. The caller controls the boundary.

The summary event is not special to the engine. It is a normal event whose term
happens to be `summary/2`. Rules that want to fire on summaries declare
conditions matching that term.

---

#### `summary_exists/3`

```prolog
summary_exists(Scene, ProjectionName, SummaryTerm) :-
    arrived(_, Scene, summary(ProjectionName, SummaryTerm), _, _).
```

Read-only query. Succeeds if a summary for `ProjectionName` exists in `Scene`
at any tier.

---

### `reset_engine` for lifecycle tests

Define this version in `lifecycle_tests.pl`. It extends the Session 4 version
with no new facts to retract — the lifecycle predicates operate on existing
dynamic facts (`tier_status`, `tier_transition`, `arrived`) already covered by
prior versions:

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
    retractall(fixpoint:rule_trigger(_, _, _)),
    retractall(fixpoint:fixpoint_depth_exceeded(_)),
    retractall(fixpoint:rule_grounding_failed(_, _)),
    retractall(log:event_counter(_)), assertz(log:event_counter(0)),
    retractall(log:clock_counter(_)), assertz(log:clock_counter(0)).
```

---

## Tests: `tests/lifecycle_tests.pl`

```prolog
:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/provenance').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').
:- use_module('../lifecycle/tiers').
:- use_module('../lifecycle/closure').
:- use_module('../lifecycle/compaction').
```

**Required test cases:**

**T1 — promote_to_cold does not retract arrived**
Inject three events into scene `deck`. Call `promote_to_cold(deck, 99)`. Assert
all three `arrived/5` facts still exist. Assert `log_count(N)` is unchanged.

**T2 — promoted events have cold tier_status**
Inject two events into `deck`. Call `promote_to_cold(deck, 99)`. Assert
`tier_status(EventId, cold)` holds for both. Assert `tier_status(EventId, hot)`
does not hold for either.

**T3 — tier_transition audit records appended**
Inject two events into `deck`. Call `promote_to_cold(deck, 99)`. Assert two
`tier_transition(_, hot, cold, _)` facts exist.

**T4 — fixpoint skips cold events**
Declare scene `deck` with rule `r_test`: conditions
`arrived(_, deck, signal, _, hot)`, consequence `echo`. Inject `signal`.
Call `world_step` — assert `echo` arrives. Call `promote_to_cold(deck, 99)`.
Inject `signal` again (new clock tick, so not a duplicate). Call `world_step`.
Assert no new `echo` arrives for the cold `signal` — the fixpoint skipped it.

**T5 — cold events remain readable**
Inject an event. Call `promote_to_cold(deck, 99)`. Assert
`arrived(EventId, deck, _, _, _)` still succeeds for the promoted event.
Assert `cold_events(deck, Events)` includes it.

**T6 — promote_to_archived from cold**
Inject an event. Call `promote_to_cold(deck, 99)`. Call
`promote_to_archived(deck, 99)`. Assert `tier_status(EventId, archived)`.
Assert `archived_events(deck, Events)` includes it.
Assert `arrived/5` still holds.

**T7 — promote_to_archived does not skip hot events**
Inject an event (hot). Call `promote_to_archived(deck, 99)` without first
calling `promote_to_cold`. Assert the event remains `hot` —
`promote_to_archived` only promotes cold events.

**T8 — declare_closure injects closed event**
Declare scene `room`. Call `advance_clock`. Call `declare_closure(room, 1)`.
Assert `arrived(_, room, closed(room, clock(1)), _, hot)` holds.
Assert `caused_by(EventId, injected(author))` holds for the closure event.

**T9 — closure event propagates through gates**
Declare scenes `patron`, `tavern`. Declare open gate `g_up` from `patron` to
`tavern`, direction `upward`. Call `declare_closure(patron, 1)`. Call
`world_step`. Assert `arrived(_, tavern, closed(patron, clock(1)), _, hot)`
holds — the closure event propagated upward.

**T10 — scene_closed query**
Using state from T8: call `scene_closed(room, 1)`. Assert it succeeds.
Call `scene_closed(room, 99)`. Assert it fails — no closure at clock 99.

**T11 — assert_summary injects summary event**
Inject three events into `deck`. Call
`assert_summary(deck, order, [card(1), card(2)], 99)`. Assert
`arrived(_, deck, summary(order, [card(1), card(2)]), _, _)` holds.

**T12 — assert_summary promotes underlying events to cold**
Using state from T11: assert the three original events are now cold
(`tier_status(_, cold)` for each). Assert `summary_exists(deck, order, _)`
succeeds.

**T13 — update_tier_status correctness**
Inject an event. Assert `tier_status(EventId, hot)`. Call
`update_tier_status(EventId, cold)`. Assert `tier_status(EventId, cold)`.
Assert exactly one `tier_status` fact exists for `EventId` — not two.

---

## Design decisions in force for this session

**D12 — Tier promotion mechanics.** `tier_status/2` is a single-valued index.
Updates retract the old value and assert the new one. `arrived/5` is never
retracted. The `tier_transition/4` audit log is append-only.

**Closure as event.** The engine has no special knowledge of `closed` terms.
No predicates in any engine module pattern-match on `closed`. Closure is purely
an authoring convention — a term that propagates and triggers rules like any
other.

---

## Constraints

- The only modification to `engine/log.pl` is adding `update_tier_status/2`.
  No other changes to any prior session file.
- `lifecycle/tiers.pl` must not directly retract or assert `tier_status` facts
  — it must call `update_tier_status/2` from `log.pl`.
- `lifecycle/closure.pl` must not special-case the `closed` term anywhere in
  its implementation. It injects a normal event. That is all.
- Do not implement `library(persistency)` disk-backing for `archived` tier —
  that is deferred. `archived` is distinguished by `tier_status` value only.
- Do not modify any existing test file.
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
7. No `arrived/5` fact is retracted at any point during any test run.
8. `docs/session_logs/session_06.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_06.md`:

```
# Session 6 Report — Log Lifecycle

## Files created
- lifecycle/tiers.pl
- lifecycle/closure.pl
- lifecycle/compaction.pl
- tests/lifecycle_tests.pl

## Files modified
- engine/log.pl (added update_tier_status/2)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed
- tests/fixpoint_tests.pl: 13 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed
- tests/lifecycle_tests.pl: 13 passed, 0 failed

## Stubs left for future sessions
(none expected)

## Anomalies, surprises, questions
(anything unexpected encountered during implementation)
```

Do not produce the report until all tests pass.

---

## Ambiguity resolution

If something is unclear: session prompt first, then `docs/implementation_plan.md`,
then `docs/conceptual_guide.md`. If genuine ambiguity remains, make the most
conservative choice and leave a `% DECISION:` comment.
