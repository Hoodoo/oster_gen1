# Session 17 — Frontier Tracking Fix (I-004)

## What this session is

A correctness fix for a fundamental engine bug identified and confirmed by
external review. `advance_world/1` currently re-processes every hot-tier
event on every `world_step`, not just newly arrived ones. Because events
remain hot until lifecycle closure, a single injected event re-fires its
full rule and gate cascade on every subsequent tick indefinitely. This
violates the conceptual guide's explicit invariant on gate failure
("gate failure is a terminal fact... the old failed event does not
resurrect") and contradicts the engine's edge-triggered semantics throughout.

The fix: introduce `unprocessed/1` as a frontier marker in `engine/log.pl`,
assert it in `inject_event/3` alongside the existing log facts, and replace
`advance_world/1`'s hot-set iteration with frontier iteration that retracts
the marker after processing. The log itself is unchanged — `unprocessed/1`
is engine bookkeeping, not a world fact, and retracting it does not violate
append-only.

**Do not start this session until the Session 16 PR is merged.** This
session touches `engine/fixpoint.pl` and `engine/log.pl`; Session 16
touches only the tavern catalog. Rebase on top of Session 16's result.

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

All must pass. If any multi-step test fails after the fix (tests that call
`world_step` more than once), examine whether it was asserting the buggy
re-firing behaviour rather than intended behaviour, note it explicitly in
the session log, and update the assertion. Do not revert the fix to make an
existing test pass.

---

## Files to modify

```
oster/
├── engine/
│   ├── log.pl              ← add unprocessed/1, assert in inject_event
│   └── fixpoint.pl         ← replace advance_world/1, relax process_hot_event head
├── tests/
│   ├── log_tests.pl        ← reset_engine: add retractall(log:unprocessed(_))
│   ├── provenance_tests.pl ← same
│   ├── gate_tests.pl       ← same
│   ├── fixpoint_tests.pl   ← same + two new regression tests
│   ├── lifecycle_tests.pl  ← same
│   ├── projection_tests.pl ← same
│   └── verify_tests.pl     ← same
├── catalog/
│   ├── deck/tests.pl       ← same
│   ├── warrior/tests.pl    ← same
│   └── tavern/tests.pl     ← same + one new regression test
└── docs/
    └── deferred.md         ← add I-004 as resolved; add N-002 for out-of-scope item
```

`tests/probe_tests.pl` uses `reset_declarations` and never calls
`inject_event`, so no change is needed there.

---

## Specification: `engine/log.pl`

### Add `unprocessed/1` dynamic declaration

Add after the existing `event_counter/1` declaration:

```prolog
:- dynamic unprocessed/1.
% unprocessed(EventId)
% Frontier marker: this event has not yet been through a fixpoint pass.
% Asserted by inject_event/3 alongside the log facts.
% Retracted by the fixpoint after processing.
% Engine bookkeeping only — not part of the world log; retracting it
% does not violate the append-only invariant.
```

### Add to module export list

Add `unprocessed/1` to the `:- module(log, [...])` export list.

### Extend `inject_event/3`

In the branch that creates a new event (the `else` branch of the
`arrived_key` dedup check), add `assertz(unprocessed(EventId))` alongside
the existing four `assertz` calls. Order does not matter; place it last for
readability:

```prolog
inject_event(Scene, Term, Cause) :-
    clock_value(Clock),
    (   arrived_key(Scene, Term, Clock, _)
    ->  true
    ;   fresh_event_id(EventId),
        assertz(arrived(EventId, Scene, Term, Clock, hot)),
        assertz(arrived_key(Scene, Term, Clock, EventId)),
        assertz(tier_status(EventId, hot)),
        assertz(caused_by(EventId, Cause)),
        assertz(unprocessed(EventId))
    ).
```

---

## Specification: `engine/fixpoint.pl`

### Replace `advance_world/1`

Replace the existing two clauses with:

```prolog
advance_world(MaxDepth) :-
    MaxDepth > 0,
    findall(E, log:unprocessed(E), Frontier),
    ( Frontier == [] ->
        true
    ;
        forall(member(EventId, Frontier),
               ( process_hot_event(EventId),
                 retract(log:unprocessed(EventId)) )),
        Depth1 is MaxDepth - 1,
        advance_world(Depth1)
    ).
advance_world(0) :-
    clock_value(Clock),
    assertz(fixpoint:fixpoint_depth_exceeded(Clock)).
```

The `log_count/1` before/after comparison is removed — frontier emptiness
is the natural termination condition. The depth guard behaviour is
unchanged: a cascade that keeps injecting new events keeps refilling the
frontier and exhausts MaxDepth exactly as before.

`log:unprocessed(E)` is module-qualified because fixpoint already imports
log via `use_module(log)`, but the retract is safer qualified to avoid any
ambiguity; follow S-001 precedent for cross-module dynamic fact access.

### Relax `process_hot_event/1` head

The fifth argument of `arrived/5` was `hot` because tier was previously the
iteration criterion. Frontier membership is the criterion now; the tier
check is incidental coupling. Relax it:

```prolog
process_hot_event(EventId) :-
    arrived(EventId, Scene, _Term, _Clock, _),
    forall(
        scene_rule(RuleId, Scene, _Cond, _Template),
        evaluate_rule(EventId, Scene, RuleId)
    ),
    propagate_from_scene(Scene, EventId).
```

Freshly injected events are still `hot` at the time they're processed —
this change only removes the assumption that frontier membership and hot
tier are equivalent, which is now false.

---

## Specification: all `reset_engine` helpers

Every `reset_engine` predicate across all affected test files must include:

```prolog
retractall(log:unprocessed(_)),
```

Add it alongside the other `retractall` calls. No positional requirement —
place it near the other log-related retracts for readability.

The ten files that need this update are listed in the Files to Modify
section above. `tests/probe_tests.pl`'s `reset_declarations` does not call
`inject_event` and does not need this line.

---

## New regression tests

### Test A — in `tests/fixpoint_tests.pl`

Add after the existing tests. Uses the tavern world declared inline (not
the catalog — declare minimal scenes and rules to avoid a cross-file
dependency):

```prolog
test(t_no_rederivation_on_subsequent_steps, [setup(reset_engine)]) :-
    % Minimal world: one scene, one rule, one gate
    assertz(scenes:scene(src)),
    assertz(scenes:scene(dst)),
    assertz(scenes:scene_rule(r_echo, src,
                              arrived(_, src, signal, _, _), echo)),
    assertz(gates:gate(g_out, src, dst, lateral)),
    % Inject once, step once — cascade settles
    inject_event(src, signal, injected(player)),
    world_step,
    log_count(CountAfterStep1),
    % Step twice more with no new input — log must not grow
    world_step,
    log_count(CountAfterStep2),
    world_step,
    log_count(CountAfterStep3),
    CountAfterStep1 =:= CountAfterStep2,
    CountAfterStep2 =:= CountAfterStep3.
```

### Test B — in `catalog/tavern/tests.pl`

Add after T18. Tests that a blocked event does not resurrect when the gate
condition later becomes true — the core of the terminal-failure invariant:

```prolog
% T19 — blocked event does not resurrect when gate later opens
% Guard: conceptual guide states "gate failure is a terminal fact".
test(t19_blocked_event_does_not_resurrect, [setup(reset_engine)]) :-
    setup_tavern,
    % Close the window and inject a strike
    inject_event(tavern, window_closed, injected(player)),
    world_step,                            % window_closed processed
    inject_event(patron_a, strike(5), injected(player)),
    world_step,                            % cascade: noise in patron + tavern; blocked at street
    \+ log:arrived(_, street, noise(fight), _, _),
    % Now open the window — no new strike injected
    log:inject_event(tavern, window_opened, injected(player)),
    fixpoint:world_step,
    % Street log must still be empty — no new noise arrived
    \+ log:arrived(_, street, noise(fight), _, _).
```

**Watch out:** `setup_tavern` (post-Session 16) calls `declare_tavern_world`
which injects `window_opened` at clock 0. T19 then injects `window_closed`,
so both are in the log. The `window_is_open/1` projection finds `window_closed`
as more recent and correctly considers the gate closed. Verify the clock
values are as expected when tracing this test.

---

## Specification: `docs/deferred.md`

### Add I-004 as resolved

```markdown
### I-004 — Hot events re-fire rules and gates on every tick

**Identified:** External review, post-Session 15, commit `68222fe`
**Resolved:** Session 17, commit <fill in>

**Problem:**
`advance_world/1` consumed `hot_events/1`, which returns every hot-tier
event — not just newly arrived ones. Events stay hot until lifecycle
closure, so a single injected event re-fired its full rule and gate cascade
on every subsequent tick. This violated the guide's terminal-gate-failure
invariant ("gate failure is a terminal fact... the old failed event does not
resurrect") and caused unbounded log growth with zero input.

**Resolution:**
`unprocessed/1` added to `engine/log.pl` as a frontier marker, asserted in
`inject_event/3` and retracted by the fixpoint after processing. `advance_world/1`
now iterates over the frontier rather than the hot set. `process_hot_event/1`'s
tier-check coupling relaxed to `_`. All `reset_engine` helpers updated to
clear the frontier. Two regression tests added.
```

### Add N-002 for the out-of-scope item

```markdown
### N-002 — rule_trigger provenance may record a non-causal frontier event

**Identified:** External review (I-004 report), Session 17
**Severity:** Low — chains are traversable; recorded trigger is a peer
frontier event, not a fabricated one

`record_rule_trigger/3` stores whichever frontier event the fixpoint loop
happened to be iterating when a rule fired. Rule conditions never reference
that EventId — they query `arrived/5` directly — so when a rule has
multi-fact conditions the recorded trigger may be a peer event that
coincidentally triggered the same fixpoint pass, not the true causal
antecedent. Single-condition rules (the current common case) are unaffected.
Resolve if/when multi-condition rules become prevalent enough to make
incorrect trigger attribution noticeable in `chain` output.
```

---

## Constraints

- Do not change `arrived_key/4`'s key structure.
- Do not retract any fact from `arrived/5`, `arrived_key/4`, `caused_by/2`,
  or any other log predicate.
- Do not repurpose or remove the tier system — `hot_events/1` stays exported
  and the hot/cold/archived lifecycle is untouched.
- Do not rename `process_hot_event/1` in this session (cosmetic; keep the
  diff minimal).

---

## Acceptance criteria

1. All eleven prior suites pass. If any multi-step test fails after the fix,
   it must be examined, noted in the session log, and either updated (if it
   was asserting buggy re-firing behaviour) or reported as a new anomaly.
2. Regression test A passes: log count is identical after steps 2 and 3 to
   its value after step 1.
3. Regression test B (T19) passes: blocked event does not cross the gate
   after the gate condition changes, with no new injection.
4. Frontier is empty after every completed `world_step` — confirm by
   checking `findall(E, log:unprocessed(E), [])` at the end of the manual
   REPL session recorded in the session log.
5. `docs/deferred.md` has I-004 resolved (with real commit hash) and N-002
   added as open.
6. `docs/session_logs/session_17.md` is written.
