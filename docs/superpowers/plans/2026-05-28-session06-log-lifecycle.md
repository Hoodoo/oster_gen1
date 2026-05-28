# Session 6 — Log Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the tier management system (hot/cold/archived) for the Oster log, plus closure injection and compaction authoring conveniences.

**Architecture:** The log is append-only; `arrived/5` is never retracted. Tier promotion works by updating a single `tier_status/2` index (retract old, assert new) and appending an audit `tier_transition/4` fact. The fixpoint already skips non-hot events because `advance_world` processes only `hot_events` (i.e., `tier_status(_, hot)`). Three lifecycle modules are layered on top of the existing engine.

**Tech Stack:** SWI-Prolog, PLUnit, existing `engine/log`, `engine/clock`, `engine/scenes`, `engine/gates`, `engine/fixpoint`, `engine/provenance` modules.

**Key path note:** The spec references `oster/` paths but the project convention (confirmed in session 5 report) is that all code lives under `scene_engine/`. All paths below use `scene_engine/`.

---

### Task 0: Verify prior session tests pass

Run all five prior test suites. Stop if any fail — do not proceed.

**Files:**
- (none modified)

- [ ] **Step 1: Run all prior tests**

```bash
cd scene_engine
swipl -g "run_tests" -t halt tests/log_tests.pl
swipl -g "run_tests" -t halt tests/provenance_tests.pl
swipl -g "run_tests" -t halt tests/gate_tests.pl
swipl -g "run_tests" -t halt tests/fixpoint_tests.pl
swipl -g "run_tests" -t halt tests/probe_tests.pl
```

Expected: all pass (9 + 11 + 13 + 14 + 13). If any fail, stop.

---

### Task 1: Add `update_tier_status/2` to `engine/log.pl`

This is the only change to an existing file. It encapsulates the retract/assert update of the single-valued `tier_status` index in the module that owns it.

**Files:**
- Modify: `scene_engine/engine/log.pl`

- [ ] **Step 1: Add export and predicate to log.pl**

Add `update_tier_status/2` to the module export list and add the predicate body. Open `scene_engine/engine/log.pl`. Change the module declaration from:

```prolog
:- module(log, [
    inject_event/3,
    hot_events/1,
    log_count/1,
    arrived/5,
    arrived_key/4,
    tier_status/2,
    tier_transition/4,
    caused_by/2,
    fresh_event_id/1,
    event_counter/1
]).
```

to:

```prolog
:- module(log, [
    inject_event/3,
    hot_events/1,
    log_count/1,
    arrived/5,
    arrived_key/4,
    tier_status/2,
    tier_transition/4,
    caused_by/2,
    fresh_event_id/1,
    event_counter/1,
    update_tier_status/2
]).
```

Then append this predicate at the end of the file:

```prolog
update_tier_status(EventId, NewTier) :-
    retract(tier_status(EventId, _)),
    assertz(tier_status(EventId, NewTier)).
```

- [ ] **Step 2: Smoke-test log.pl loads cleanly**

```bash
cd scene_engine
swipl -g "use_module(engine/log), halt" -t halt
```

Expected: no errors.

- [ ] **Step 3: Re-run log tests**

```bash
cd scene_engine
swipl -g "run_tests" -t halt tests/log_tests.pl
```

Expected: 9 passed, 0 failed.

---

### Task 2: Create `lifecycle/tiers.pl`

Tier promotion predicates. Calls `update_tier_status/2` from log (never directly retracts `tier_status`).

**Files:**
- Create: `scene_engine/lifecycle/tiers.pl`

- [ ] **Step 1: Create the directory and file**

```bash
mkdir -p scene_engine/lifecycle
```

Create `scene_engine/lifecycle/tiers.pl`:

```prolog
:- module(tiers, [
    promote_to_cold/2,
    promote_to_archived/2,
    cold_events/2,
    archived_events/2
]).

:- use_module('../engine/log').
:- use_module('../engine/clock').

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

cold_events(Scene, Events) :-
    findall(EventId,
            ( arrived(EventId, Scene, _, _, _),
              tier_status(EventId, cold)
            ),
            Events).

archived_events(Scene, Events) :-
    findall(EventId,
            ( arrived(EventId, Scene, _, _, _),
              tier_status(EventId, archived)
            ),
            Events).
```

- [ ] **Step 2: Smoke-test tiers.pl loads cleanly**

```bash
cd scene_engine
swipl -g "use_module(lifecycle/tiers), halt" -t halt
```

Expected: no errors.

---

### Task 3: Create `lifecycle/closure.pl`

Closure injection — `closed/2` terms are normal events. The module provides only an injection convenience and a read query.

**Files:**
- Create: `scene_engine/lifecycle/closure.pl`

- [ ] **Step 1: Create lifecycle/closure.pl**

Create `scene_engine/lifecycle/closure.pl`:

```prolog
:- module(closure, [
    declare_closure/2,
    scene_closed/2
]).

:- use_module('../engine/log').
:- use_module('../engine/clock').

declare_closure(Scene, Clock) :-
    inject_event(Scene, closed(Scene, clock(Clock)), injected(author)).

scene_closed(Scene, Clock) :-
    arrived(_, Scene, closed(Scene, clock(Clock)), _, _).
```

- [ ] **Step 2: Smoke-test closure.pl loads cleanly**

```bash
cd scene_engine
swipl -g "use_module(lifecycle/closure), halt" -t halt
```

Expected: no errors.

---

### Task 4: Create `lifecycle/compaction.pl`

Summary injection + cold promotion in one authoring operation.

**Files:**
- Create: `scene_engine/lifecycle/compaction.pl`

- [ ] **Step 1: Create lifecycle/compaction.pl**

Create `scene_engine/lifecycle/compaction.pl`:

```prolog
:- module(compaction, [
    assert_summary/4,
    summary_exists/3
]).

:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module(tiers).

assert_summary(Scene, ProjectionName, SummaryTerm, UpToClock) :-
    inject_event(Scene,
                 summary(ProjectionName, SummaryTerm),
                 injected(author)),
    promote_to_cold(Scene, UpToClock).

summary_exists(Scene, ProjectionName, SummaryTerm) :-
    arrived(_, Scene, summary(ProjectionName, SummaryTerm), _, _).
```

- [ ] **Step 2: Smoke-test compaction.pl loads cleanly**

```bash
cd scene_engine
swipl -g "use_module(lifecycle/compaction), halt" -t halt
```

Expected: no errors.

---

### Task 5: Create `tests/lifecycle_tests.pl`

All 13 PLUnit tests for the lifecycle layer.

**Files:**
- Create: `scene_engine/tests/lifecycle_tests.pl`

- [ ] **Step 1: Create lifecycle_tests.pl**

Create `scene_engine/tests/lifecycle_tests.pl`:

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

:- begin_tests(lifecycle).

%% T1 — promote_to_cold does not retract arrived
test(promote_cold_no_retract, [setup(reset_engine)]) :-
    assertz(scenes:scene(deck)),
    inject_event(deck, evt_a, injected(author)),
    inject_event(deck, evt_b, injected(author)),
    inject_event(deck, evt_c, injected(author)),
    log_count(Before),
    promote_to_cold(deck, 99),
    log_count(After),
    Before =:= After,
    findall(E, log:arrived(E, deck, _, _, _), Events),
    length(Events, 3).

%% T2 — promoted events have cold tier_status
test(promote_cold_tier_status, [setup(reset_engine)]) :-
    assertz(scenes:scene(deck)),
    inject_event(deck, evt_a, injected(author)),
    inject_event(deck, evt_b, injected(author)),
    promote_to_cold(deck, 99),
    findall(E, log:arrived(E, deck, _, _, _), EventIds),
    forall(member(EventId, EventIds),
           ( log:tier_status(EventId, cold),
             \+ log:tier_status(EventId, hot)
           )).

%% T3 — tier_transition audit records appended
test(tier_transition_audit, [setup(reset_engine)]) :-
    assertz(scenes:scene(deck)),
    inject_event(deck, evt_a, injected(author)),
    inject_event(deck, evt_b, injected(author)),
    promote_to_cold(deck, 99),
    findall(_, log:tier_transition(_, hot, cold, _), Ts),
    length(Ts, 2).

%% T4 — fixpoint skips cold events
test(fixpoint_skips_cold, [setup(reset_engine)]) :-
    assertz(scenes:scene(deck)),
    assertz(scenes:scene_rule(r_test, deck,
                              arrived(_, deck, signal, _, hot),
                              echo)),
    inject_event(deck, signal, injected(author)),
    world_step,
    findall(_, log:arrived(_, deck, echo, _, _), Echos1),
    length(Echos1, 1),
    promote_to_cold(deck, 99),
    advance_clock,
    inject_event(deck, signal, injected(author)),
    world_step,
    findall(_, log:arrived(_, deck, echo, _, _), Echos2),
    length(Echos2, 1).

%% T5 — cold events remain readable
test(cold_events_readable, [setup(reset_engine)]) :-
    assertz(scenes:scene(deck)),
    inject_event(deck, something, injected(author)),
    findall(E, log:arrived(E, deck, something, _, _), [EventId|_]),
    promote_to_cold(deck, 99),
    log:arrived(EventId, deck, _, _, _),
    cold_events(deck, Events),
    member(EventId, Events).

%% T6 — promote_to_archived from cold
test(promote_archived_from_cold, [setup(reset_engine)]) :-
    assertz(scenes:scene(deck)),
    inject_event(deck, something, injected(author)),
    findall(E, log:arrived(E, deck, something, _, _), [EventId|_]),
    promote_to_cold(deck, 99),
    promote_to_archived(deck, 99),
    log:tier_status(EventId, archived),
    archived_events(deck, Events),
    member(EventId, Events),
    log:arrived(EventId, deck, _, _, _).

%% T7 — promote_to_archived does not skip hot events
test(archived_skips_hot, [setup(reset_engine)]) :-
    assertz(scenes:scene(deck)),
    inject_event(deck, something, injected(author)),
    findall(E, log:arrived(E, deck, something, _, _), [EventId|_]),
    promote_to_archived(deck, 99),
    log:tier_status(EventId, hot).

%% T8 — declare_closure injects closed event
test(declare_closure_injects, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    advance_clock,
    declare_closure(room, 1),
    log:arrived(EventId, room, closed(room, clock(1)), _, hot),
    provenance:caused_by(EventId, injected(author)).

%% T9 — closure event propagates through gates
test(closure_propagates_gate, [setup(reset_engine)]) :-
    assertz(scenes:scene(patron)),
    assertz(scenes:scene(tavern)),
    assertz(gates:gate(g_up, patron, tavern, upward)),
    declare_closure(patron, 1),
    world_step,
    log:arrived(_, tavern, closed(patron, clock(1)), _, hot).

%% T10 — scene_closed query
test(scene_closed_query, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    advance_clock,
    declare_closure(room, 1),
    scene_closed(room, 1),
    \+ scene_closed(room, 99).

%% T11 — assert_summary injects summary event
test(assert_summary_injects, [setup(reset_engine)]) :-
    assertz(scenes:scene(deck)),
    inject_event(deck, evt_a, injected(author)),
    inject_event(deck, evt_b, injected(author)),
    inject_event(deck, evt_c, injected(author)),
    assert_summary(deck, order, [card(1), card(2)], 99),
    log:arrived(_, deck, summary(order, [card(1), card(2)]), _, _).

%% T12 — assert_summary promotes underlying events to cold
test(assert_summary_promotes_cold, [setup(reset_engine)]) :-
    assertz(scenes:scene(deck)),
    inject_event(deck, evt_a, injected(author)),
    inject_event(deck, evt_b, injected(author)),
    inject_event(deck, evt_c, injected(author)),
    findall(E, log:arrived(E, deck, _, _, _), OriginalIds),
    assert_summary(deck, order, [card(1), card(2)], 99),
    forall(member(EId, OriginalIds), log:tier_status(EId, cold)),
    summary_exists(deck, order, _).

%% T13 — update_tier_status correctness
test(update_tier_status_correctness, [setup(reset_engine)]) :-
    assertz(scenes:scene(deck)),
    inject_event(deck, something, injected(author)),
    findall(E, log:arrived(E, deck, something, _, _), [EventId|_]),
    log:tier_status(EventId, hot),
    update_tier_status(EventId, cold),
    log:tier_status(EventId, cold),
    findall(_, log:tier_status(EventId, _), StatusFacts),
    length(StatusFacts, 1).

:- end_tests(lifecycle).
```

- [ ] **Step 2: Run lifecycle tests**

```bash
cd scene_engine
swipl -g "run_tests" -t halt tests/lifecycle_tests.pl
```

Expected: 13 passed, 0 failed.

---

### Task 6: Run full test suite

All six test files must pass before writing the session report.

- [ ] **Step 1: Run all tests**

```bash
cd scene_engine
swipl -g "run_tests" -t halt tests/log_tests.pl
swipl -g "run_tests" -t halt tests/provenance_tests.pl
swipl -g "run_tests" -t halt tests/gate_tests.pl
swipl -g "run_tests" -t halt tests/fixpoint_tests.pl
swipl -g "run_tests" -t halt tests/probe_tests.pl
swipl -g "run_tests" -t halt tests/lifecycle_tests.pl
```

Expected counts: 9 + 11 + 13 + 14 + 13 + 13. All must pass.

---

### Task 7: Write session report

Only after all tests pass.

**Files:**
- Create: `docs/session_logs/session_06.md`

- [ ] **Step 1: Write report**

Create `docs/session_logs/session_06.md` with this content (filling in actual test counts):

```markdown
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
- tests/fixpoint_tests.pl: 14 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed
- tests/lifecycle_tests.pl: 13 passed, 0 failed

## Stubs left for future sessions
(none)

## Anomalies, surprises, questions
- The spec references `oster/` paths; actual code lives in `scene_engine/` per established project convention.
- fixpoint_tests reports 14 (not 13) — pre-existing since session 5, not a regression.
```

---

## Self-Review Checklist

**Spec coverage:**
- `update_tier_status/2` in log.pl ✓ (Task 1)
- `promote_to_cold/2` ✓ (Task 2)
- `promote_to_archived/2` ✓ (Task 2)
- `cold_events/2` ✓ (Task 2)
- `archived_events/2` ✓ (Task 2)
- `declare_closure/2` ✓ (Task 3)
- `scene_closed/2` ✓ (Task 3)
- `assert_summary/4` ✓ (Task 4)
- `summary_exists/3` ✓ (Task 4)
- `reset_engine` helper ✓ (Task 5)
- T1–T13 tests ✓ (Task 5)
- Decision A (update_tier_status in log.pl) ✓
- Constraint: tiers.pl calls update_tier_status, never raw retract/assert on tier_status ✓
- Constraint: closure.pl does not special-case `closed` term ✓
- Constraint: no library(persistency) ✓
- Constraint: no modification to existing test files ✓
- Session report ✓ (Task 7)

**Notes on T4 (fixpoint skips cold events):**
The fixpoint works via `advance_world` → `hot_events` → `tier_status(_, hot)`. After `promote_to_cold`, the promoted events no longer appear in `hot_events`, so `process_hot_event` never fires for them. T4 verifies this by injecting `signal` twice — first hot (echo fires), then cold (echo count stays at 1). The `advance_clock` before the second inject ensures the dedup key `arrived_key(Scene, Term, Clock, _)` doesn't suppress it.

**Notes on T9 (closure propagates through gates):**
`declare_closure(patron, 1)` injects `closed(patron, clock(1))` at clock 0 (before world_step advances it). `world_step` calls `advance_clock` (clock becomes 1) then `advance_world`. The hot `closed` event in `patron` propagates through `g_up` to `tavern` at clock 1. The test asserts `arrived(_, tavern, closed(patron, clock(1)), _, hot)` — the clock in the term is `1` (the argument to `declare_closure`), the arrival clock after propagation is also 1. This is consistent.
