# Session 19 — Closure Tier Wiring and Minor Cleanup

## What this session is

Two things, both small and mechanical.

**Primary:** Wire `promote_to_cold` into the REPL's `close(Scene)` command.
`declare_closure` and tier promotion are currently disconnected — closing a
scene injects the `closed` event but leaves all prior events `hot`. This is
why `log(Scene)` after `close(Scene)` shows everything still marked `hot`.
The fix belongs in the REPL command, not in `declare_closure` itself —
`declare_closure` is a low-level primitive that catalog authors call
directly and may want fine-grained control over; the REPL is the opinionated
layer that says "close means settle everything up to now."

**Secondary:** Normalise four `reset_engine` helpers that use unqualified
`retractall(unprocessed(_))` to the module-qualified form
`retractall(log:unprocessed(_))` used consistently elsewhere. Currently
harmless (per C-003) but a latent portability risk and an inconsistency
worth closing while we're touching test files.

This session does not change any engine predicate, does not touch catalog
files, and adds exactly one new test.

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

Baseline: 158 tests, 0 failures. If any fail, stop and report.

---

## Files to modify

```
oster/
├── repl/
│   └── repl.pl                  ← add tiers import, update close handler
├── tests/
│   ├── log_tests.pl             ← normalise unprocessed retract
│   ├── provenance_tests.pl      ← normalise unprocessed retract
│   ├── gate_tests.pl            ← normalise unprocessed retract
│   ├── fixpoint_tests.pl        ← normalise unprocessed retract
│   └── lifecycle_tests.pl       ← add T14
└── docs/
    └── deferred.md              ← log this as a resolved gap
```

No engine, projection, lifecycle, verify, or catalog files are modified.

---

## Specification: `repl/repl.pl`

### Add `lifecycle/tiers` import

Add to the existing import block:

```prolog
:- use_module('../lifecycle/tiers').
```

`lifecycle/tiers` exports `promote_to_cold/2` and `promote_to_archived/2`.
`lifecycle/closure` is already imported; no change there.

### Update `handle_command(close(Scene))`

Replace:

```prolog
handle_command(close(Scene)) :- !,
    clock_value(Clock),
    declare_closure(Scene, Clock),
    world_step,
    format("Declared closure for ~w at clock ~w~n", [Scene, Clock]).
```

With:

```prolog
handle_command(close(Scene)) :- !,
    clock_value(Clock),
    declare_closure(Scene, Clock),
    world_step,
    promote_to_cold(Scene, Clock),
    format("Declared closure for ~w at clock ~w~n", [Scene, Clock]).
```

One line added. Everything else in the predicate is unchanged.

**Clock sequencing note:** `clock_value(Clock)` captures the clock before
`world_step` advances it. `declare_closure` injects `closed(Scene, clock(Clock))`
at that clock value. `world_step` processes the frontier (including the closure
event) and advances the clock by one. `promote_to_cold(Scene, Clock)` then
promotes all hot events in the scene at clocks 0..Clock — which includes the
closure event itself. Events that propagated OUT of this scene during
`world_step` (to child scenes via gates) arrive at Clock+1 and are not
promoted — that is correct, those scenes have their own independent closure
lifecycle.

---

## Specification: four `reset_engine` normalisation changes

In each of the following files, find the line:

```prolog
retractall(unprocessed(_)),
```

and replace it with:

```prolog
retractall(log:unprocessed(_)),
```

Files:
- `tests/log_tests.pl` (line 11 per CC's audit)
- `tests/provenance_tests.pl` (line 14)
- `tests/gate_tests.pl` (line 15)
- `tests/fixpoint_tests.pl` (line 16)

No other changes to these files.

---

## Specification: `tests/lifecycle_tests.pl` — add T14

Add after the existing T13. This is the first test that exercises the
combined `declare_closure` + `promote_to_cold` pattern — the gap that
existed before this session:

```prolog
% T14 — all scene events are cold after declare_closure + promote_to_cold
% Guard: closing a scene must settle its history, not just inject the closed event.
test(t14_closure_demotes_events_to_cold, [setup(reset_engine)]) :-
    assertz(scenes:scene(room)),
    inject_event(room, signal, injected(player)),
    inject_event(room, echo, injected(player)),
    clock_value(Clock),
    declare_closure(room, Clock),
    world_step,
    promote_to_cold(room, Clock),
    % No hot events should remain in room
    findall(E,
            ( log:arrived(E, room, _, _, _),
              log:tier_status(E, hot)
            ),
            StillHot),
    StillHot = [].
```

**Watch out:** `world_step` advances the clock after processing the frontier.
`promote_to_cold(room, Clock)` uses the pre-step clock value, which is the
same value passed to `declare_closure`. The closure event (`closed(room,
clock(Clock))`) arrives at `Clock` and IS included in the promotion range —
it should be cold too. Verify by checking `tier_status` for the closure
event specifically if the test is failing in unexpected ways.

---

## Specification: `docs/deferred.md`

Add a new resolved entry:

```markdown
### I-005 — `declare_closure` and `promote_to_cold` were disconnected

**Identified:** Playtest observation, Session 19
**Resolved:** Session 19, commit <fill in>

**Problem:**
`declare_closure/2` injected `closed(Scene, clock(N))` as a normal event
but never called `promote_to_cold`. The REPL's `close(Scene)` command called
`declare_closure` and `world_step` but also never promoted events. The tier
promotion machinery (Session 6) was correct and complete but had no caller
on the closure path. `log(Scene)` after `close(Scene)` showed all prior
events still marked `hot`.

**Resolution:**
`promote_to_cold(Scene, Clock)` added to the REPL's `close(Scene)` handler,
after `world_step`, using the pre-step clock value so all events up to and
including the closure event itself are promoted. `declare_closure/2` itself
is unchanged — it remains a low-level primitive. A regression test (T14 in
`lifecycle_tests.pl`) confirms the combined pattern works.
```

---

## Manual verification

```bash
swipl -g "use_module(repl/repl), start_repl" -t halt
```

```prolog
inject(patron_a, strike(5)).
log(tavern).          % events should be hot
close(tavern).
log(tavern).          % ALL events including window_opened and noise(fight)
                      % should now show (cold) not (hot)
inject(patron_a, taunt).
log(tavern).          % new event at the new clock should be (hot)
                      % prior events must still be (cold)
```

Confirm that:
1. All events present before `close(tavern)` show `(cold)` in the log afterward.
2. New events injected after closure arrive as `(hot)` — the scene continues
   to receive events, tier promotion only affects what existed at closure time.
3. The `closed(tavern, clock(N))` event itself also shows `(cold)`.

Record the transcript in the session log.

---

## Constraints

- Do not modify `declare_closure/2` in `lifecycle/closure.pl`.
- Do not modify `promote_to_cold/2` in `lifecycle/tiers.pl`.
- Do not touch any engine, catalog, projection, or verify file.
- The four unqualified retract changes are the only modifications to those
  test files — no other lines change.

---

## Acceptance criteria

1. All eleven suites pass: 158 tests + 1 new = **159 tests, 0 failures**.
2. Manual REPL transcript confirms events are `(cold)` after `close(Scene)`.
3. New events injected after closure are `(hot)`.
4. `docs/deferred.md` has I-005 resolved with real commit hash.
5. `docs/session_logs/session_19.md` is written.
