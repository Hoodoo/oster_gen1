# Session 16 — Tavern Hierarchy Reorg and Window Event-Sourcing

## What this session is

Two closely related changes to the tavern catalog, combined because they
touch the same files and one motivates the other:

1. **Hierarchy reorg**: Introduce `world` as the explicit root scene.
   `tavern` and `street` become siblings under `world` (street is no longer
   a child of tavern). `patron_a` and `patron_b` remain children of tavern.
   `tavern_noise_to_street`'s direction label changes from `downward` to
   `lateral` — it now connects siblings, not parent to child.

2. **Window event-sourcing**: Replace the bare `window_open/1` dynamic fact
   with `window_opened`/`window_closed` events injected into `tavern`'s own
   log. The gate condition becomes a "most recent qualifying event wins"
   projection. The initial open state is injected at world-load via
   `injected(setup)`, giving it a real clock value and full provenance for
   the first time.

A third change is included because the hierarchy reorg makes it necessary:
add a `noise(fight)` term filter to `tavern_noise_to_street`. Without it,
the freshly-injected `window_opened` event (hot in tavern's log at clock 0)
would propagate to street on the first `world_step`. The inward patron gates
already have this filter; the outward gate should have had it from Session 11
(the session 11 report itself flagged it as overdue).

This session does not modify any engine, projection, lifecycle, or verify
file.

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

## Files to modify

```
oster/
├── catalog/tavern/
│   ├── scene.pl   ← hierarchy, window_is_open projection, initial injection
│   ├── gates.pl   ← direction label, gate condition, outward term filter
│   └── tests.pl   ← updated T1/T5/T6/T10/T17, new T18
└── repl/
    └── repl.pl    ← remove assertz(window_open) from load_world
```

No other files are modified.

---

## Specification: `catalog/tavern/scene.pl`

### Module declaration

Replace the existing export list — remove `window_open/1`, add
`window_is_open/1`:

```prolog
:- module(tavern_scene, [
    declare_tavern_world/0,
    declare_patron/1,
    declare_street/0,
    window_is_open/1
]).
```

### Remove `window_open/1`

Delete these three lines entirely:

```prolog
:- dynamic window_open/1.
% window_open(TavernScene)
% Asserted by authoring code to open the window, allowing noise to reach the street.
% Retracted to close it.
```

### `declare_tavern_world/0`

Replace the existing predicate:

```prolog
declare_tavern_world :-
    declare_scene(world),
    declare_scene(tavern),
    declare_scene(patron_a),
    declare_scene(patron_b),
    declare_scene(street),
    declare_scene_parent(tavern, world),
    declare_scene_parent(street, world),
    declare_scene_parent(patron_a, tavern),
    declare_scene_parent(patron_b, tavern),
    declare_patron_rules(patron_a),
    declare_patron_rules(patron_b),
    declare_street_rules,
    inject_event(tavern, window_opened, injected(setup)).
```

`world` is the new root. `street` is a sibling of `tavern`, not its child.
The final line injects the initial window state at clock 0 with
`injected(setup)` provenance. This is a real log event — it has a clock
value, a cause, and is fully traversable by `chain`.

### `window_is_open/1` — add this new predicate

```prolog
window_is_open(TavernScene) :-
    % Collect all window state events from this scene's log
    findall(Clock-Term,
            ( log:arrived(_, TavernScene, Term, Clock, _),
              ( Term = window_opened ; Term = window_closed )
            ),
            Pairs),
    Pairs \= [],
    % Most recent clock wins; window is open iff that event was window_opened
    msort(Pairs, Sorted),
    last(Sorted, _-window_opened).
% NOTE: if window_opened and window_closed both arrive at the same clock tick,
% msort orders window_closed before window_opened (lexicographic), so
% window_opened wins on tie. Authors should not open and close in the same
% clock tick — behaviour in that edge case is intentionally unspecified.
```

This predicate is used as the gate condition for `tavern_noise_to_street`.
It is not a rule condition and is exempt from `check_rule_conditions_safe`.

---

## Specification: `catalog/tavern/gates.pl`

### Import

Remove the now-unused `window_open/1` import and replace with
`window_is_open/1`:

```prolog
:- use_module(scene, [window_is_open/1]).
```

### `declare_tavern_gates/0`

Replace the existing predicate:

```prolog
declare_tavern_gates :-
    % Inward gates: patron noise propagates upward to tavern
    declare_gate(patron_a_noise_to_tavern, patron_a, tavern, upward),
    declare_gate(patron_b_noise_to_tavern, patron_b, tavern, upward),
    declare_gate_term_filter(patron_a_noise_to_tavern, noise(fight)),
    declare_gate_term_filter(patron_b_noise_to_tavern, noise(fight)),

    % Outward gate: tavern noise propagates laterally to street (now a sibling)
    declare_gate(tavern_noise_to_street, tavern, street, lateral),
    declare_gate_term_filter(tavern_noise_to_street, noise(fight)),
    assertz(gates:gate_condition(
        tavern_noise_to_street,
        tavern_scene:window_is_open(tavern)
    )).
```

Two changes from the previous version:
- Direction: `downward` → `lateral` (street is now a sibling of tavern,
  not its child).
- `declare_gate_term_filter(tavern_noise_to_street, noise(fight))` is new.
  Without it, the `window_opened` setup event (hot in tavern at clock 0)
  propagates to street on the first `world_step`.

---

## Specification: `catalog/tavern/tests.pl`

### `reset_engine`

Remove the line:

```prolog
retractall(tavern_scene:window_open(_)),
```

The window state is now in the event log, which is already cleared by
`retractall(log:arrived(...))`.

### Updated tests

**T1** — verify the new hierarchy:

```prolog
test(t1_scene_hierarchy, [setup(reset_engine)]) :-
    setup_tavern,
    scenes:scene_type(world, composite),
    scenes:scene_type(tavern, composite),
    scenes:scene_type(patron_a, leaf),
    scenes:scene_type(patron_b, leaf),
    scenes:scene_type(street, leaf),
    scenes:scene_parent(tavern, world),
    scenes:scene_parent(street, world),
    scenes:scene_parent(patron_a, tavern),
    scenes:scene_parent(patron_b, tavern),
    \+ scenes:scene_parent(street, tavern).
```

**T5** — noise blocked when window is closed. The window starts open
(injected at setup). To test blocking: step the world to advance the clock,
then inject `window_closed`, step again, then inject a strike and test.

```prolog
test(t5_noise_blocked_window_closed, [setup(reset_engine)]) :-
    setup_tavern,
    % Advance clock past the setup injection, then close the window
    fixpoint:world_step,
    log:inject_event(tavern, window_closed, injected(player)),
    fixpoint:world_step,
    % Now inject the strike — window_closed is most recent
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    \+ log:arrived(_, street, noise(fight), _, _),
    gates:gate_blocked(tavern_noise_to_street, _, _).
```

**T6** — noise reaches street when window open. The window is already open
from `declare_tavern_world`'s setup injection — no additional setup needed:

```prolog
test(t6_noise_reaches_street_window_open, [setup(reset_engine)]) :-
    setup_tavern,
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    log:arrived(_, patron_a, noise(fight), _, _),
    log:arrived(_, tavern, noise(fight), _, _),
    log:arrived(_, street, noise(fight), _, _).
```

**T10** — window toggle: open → close → blocked. Use event injection for
the close instead of retractall:

```prolog
test(t10_window_toggles, [setup(reset_engine)]) :-
    setup_tavern,
    % Window is open from setup — inject strike and step
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    log:arrived(_, street, noise(fight), _, _),
    % Close the window
    log:inject_event(tavern, window_closed, injected(player)),
    fixpoint:world_step,
    % Inject another strike — should now be blocked at street
    log:inject_event(patron_b, strike(5), injected(player)),
    fixpoint:world_step,
    clock:clock_value(FinalClock),
    \+ log:arrived(_, street, noise(fight), FinalClock, _),
    gates:gate_blocked(tavern_noise_to_street, _, _).
```

**T17** — direction label is now `lateral`:

```prolog
test(t17_probe_tavern, [setup(reset_engine)]) :-
    setup_tavern,
    probes:probe(tavern, vocab(Heads, Gates)),
    Heads = [],
    member(gate_info(tavern_noise_to_street, street, lateral), Gates).
```

### New test T18

Add after T17:

```prolog
% T18 — window_opened setup event has injected(setup) provenance
% This is the main concrete payoff of event-sourcing the window:
% the initial state is now a real, traceable log event rather than an
% invisible dynamic fact.
test(t18_window_setup_provenance, [setup(reset_engine)]) :-
    setup_tavern,
    log:arrived(WinId, tavern, window_opened, 0, _),
    provenance:provenance_chain(WinId, Chain),
    Chain = [step(WinId, injected(setup))].
```

All other tests (T2, T3, T4, T7, T8, T9, T11, T12, T13, T14, T15, T16)
are unchanged — verify they still pass without modification.

---

## Specification: `repl/repl.pl`

In `load_world/0`, remove the line:

```prolog
assertz(tavern_scene:window_open(tavern)),
```

The initial window state is now part of `declare_tavern_world/0` itself
(injected as an event). No replacement line is needed.

---

## Design decisions in force for this session

**`window_is_open/1` is specific, not generalized.** The "most recent
qualifying event wins" pattern is now used for both the window and (after
Session 17) the barkeeper's amulet. A shared helper is not introduced here —
that abstraction waits until a second catalog entry actually uses it, at
which point the duplication is visible and the right shape is obvious.

**`world_step` is not called inside `declare_tavern_world`.** The setup
injection leaves `window_opened` hot in the log at clock 0. It will be
processed normally on the first `world_step` the caller issues. This is
consistent with how every other event enters the log — nothing about setup
justifies special treatment.

**`window_opened` and `window_closed` are not rule consequences.** They are
inject targets — events authored directly into the log, either by setup
code or by player/author action. Patron scenes have no rules that produce
them. This is correct: window state is authored, not derived.

**The term filter on `tavern_noise_to_street` is not retroactive.** It
applies to all future propagation attempts. Events already in the tavern
log (specifically: the `window_opened` setup event) would only become a
problem if they were still hot when the gate is first evaluated — which
is exactly what happens on the first `world_step`. The filter closes this
cleanly.

---

## Constraints

- Do not modify any engine, projection, lifecycle, or verify file.
- Do not modify `catalog/deck/` or `catalog/warrior/`.
- `scene.pl` must not declare any gates.
- `gates.pl` must not declare any rules.
- The `world` scene must have no rules and no outgoing gates.
- `window_open/1` must not appear anywhere in the codebase after this
  session — search for it before committing.

---

## Acceptance criteria

1. All eleven prior suites pass, plus `catalog/tavern/tests.pl` now has 18
   tests passing (was 17).
2. `scenes.` in the REPL shows `world` as root with `tavern` and `street`
   as siblings beneath it.
3. `gates.` in the REPL shows `tavern_noise_to_street` with direction
   `lateral`.
4. `grep -r window_open . --include='*.pl'` returns no results — the old
   dynamic fact is completely gone.
5. `chain` on the `window_opened` event ID shows `injected(setup)` as
   its cause.
6. `docs/session_logs/session_16.md` is written, including any divergences.
