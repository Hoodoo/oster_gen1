# Session 11 — Catalog: Tavern Composite Scene

## What this session is

You are building Session 11 of the Oster implementation. This is the third and
final catalog entry — a tavern with patrons, a fight, and a street outside.
You are building only what is listed here. Do not read ahead or implement
anything from Session 12.

At the end of this session, all tests must be green, the session report must be
written to `docs/session_logs/session_11.md`, and no files outside the listed
scope may have been created or modified.

---

## Before you write a line of code

Run all prior session tests:

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
```

All tests must pass. If any fail, stop and report — do not proceed.

---

## Testing convention (in force for all sessions)

PLUnit runs test bodies in an isolated module (`plunit_*`). Any `assertz/1`
or `retractall/1` inside a test body targeting engine dynamic facts must be
module-qualified. Clock resets must use `clock:clock_counter`. The
`reset_engine` helper in `setup(...)` blocks is unaffected.

---

## Context: what this session builds

The tavern entry is the engine's most complete demonstration. It brings
together everything built so far:

- **A composite scene** (`tavern`) that acts as a pure propagation boundary
  with no rules of its own
- **Leaf scenes** (`patron_a`, `patron_b`, `street`) with their own
  vocabularies and rules
- **An inward gate** routing patron noise upward into the tavern
- **A conditional outward gate** routing tavern noise downward to the street,
  only when the window is open
- **D8 in the wild** — the transit invariant: a `strike` injected into a
  patron passes through the tavern scene topologically but must not appear
  in the tavern's `arrived` log

The guide's narrative example — the fight is local until the noise gate opens
— is exactly what this entry tests.

This session also has three gates (one per patron plus one outward), which
means `propagation_coverage` gets its first real multi-gate workout.

---

## Files to create

```
catalog/
└── tavern/
    ├── scene.pl   ← new
    ├── gates.pl   ← new
    └── tests.pl   ← new
```

No existing files are modified in this session.

---

## Key design decision: `window_open/1`

The outward gate condition is `window_open(tavern)`. This is a dynamic fact
that the author asserts to open the window. It lives in `catalog/tavern/scene.pl`
as:

```prolog
:- dynamic window_open/1.
% window_open(TavernScene)
% Asserted by authoring code to open the window, allowing noise to reach the street.
% Retracted to close it.
```

This fact is not an event — it does not go through `inject_event/3`. It is a
plain Prolog dynamic fact used as a gate condition. Gate conditions are
callable goals evaluated at propagation time; `window_open(tavern)` is a
valid goal that succeeds when the fact is asserted.

The test file retracts `window_open(tavern)` in `reset_engine` to ensure
tests are isolated. Note the module qualification required from test bodies:
`retractall(tavern_scene:window_open(_))` — or whatever module name the
`scene.pl` file declares.

---

## Specification

### `catalog/tavern/scene.pl`

```prolog
:- module(tavern_scene, [
    declare_tavern_world/0,
    declare_patron/1,
    declare_street/0,
    window_open/1
]).

:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/fixpoint').
```

---

#### `window_open/1`

```prolog
:- dynamic window_open/1.
% window_open(TavernScene)
```

---

#### `declare_tavern_world/0`

```prolog
declare_tavern_world :-
    declare_scene(tavern),
    declare_scene(patron_a),
    declare_scene(patron_b),
    declare_scene(street),
    declare_scene_parent(patron_a, tavern),
    declare_scene_parent(patron_b, tavern),
    declare_scene_parent(street, tavern),
    declare_patron_rules(patron_a),
    declare_patron_rules(patron_b),
    declare_street_rules.
```

Declares the full scene hierarchy and all rules. Gates are declared
separately in `gates.pl` via `declare_tavern_gates/0`.

---

#### `declare_patron/1`

```prolog
declare_patron(PatronScene) :-
    declare_scene(PatronScene),
    declare_patron_rules(PatronScene).
```

Convenience predicate for declaring an individual patron outside the standard
world setup.

---

#### `declare_patron_rules/1`

```prolog
declare_patron_rules(PatronScene) :-
    atomic_list_concat([rule_noise_strike_, PatronScene], RuleId1),
    atomic_list_concat([rule_noise_taunt_, PatronScene], RuleId2),
    declare_scene_rule(
        RuleId1,
        PatronScene,
        arrived(_, PatronScene, strike(_), _, _),
        noise(fight)
    ),
    declare_scene_rule(
        RuleId2,
        PatronScene,
        arrived(_, PatronScene, taunt, _, _),
        noise(fight)
    ).
```

Two rules per patron: a strike or a taunt produces `noise(fight)` in the
same patron scene. Rule IDs are derived from the patron scene name for
uniqueness.

**Note on deduplication:** Both rules produce the same `noise(fight)` term.
`inject_event/3`'s deduplication by `(Scene, Term, Clock)` means only one
`noise(fight)` arrives per patron per clock tick, regardless of how many
strikes or taunts occurred. This is correct behaviour.

---

#### `declare_street_rules/0`

```prolog
declare_street_rules :-
    declare_scene_rule(
        rule_guards_alerted,
        street,
        arrived(_, street, noise(fight), _, _),
        guards_alerted
    ).
```

One rule: when `noise(fight)` arrives at `street`, inject `guards_alerted`.

---

#### `declare_street/0`

```prolog
declare_street :-
    declare_scene(street),
    declare_street_rules.
```

Convenience predicate for declaring the street independently.

---

### `catalog/tavern/gates.pl`

```prolog
:- module(tavern_gates, [
    declare_tavern_gates/0
]).

:- use_module('../../engine/gates').
:- use_module(tavern_scene, [window_open/1]).
```

---

#### `declare_tavern_gates/0`

```prolog
declare_tavern_gates :-
    % Inward gates: patron noise propagates upward to tavern
    declare_gate(patron_a_noise_to_tavern, patron_a, tavern, upward),
    declare_gate(patron_b_noise_to_tavern, patron_b, tavern, upward),
    % No conditions on inward gates — noise always reaches the tavern
    % No transforms — noise(fight) crosses unchanged

    % Outward gate: tavern noise propagates downward to street
    declare_gate(tavern_noise_to_street, tavern, street, downward),
    % Condition: window must be open
    assertz(gates:gate_condition(
        tavern_noise_to_street,
        tavern_scene:window_open(tavern)
    )).
```

Three gates total. The two inward gates are always open. The outward gate
requires `window_open(tavern)` to be asserted.

**Note:** Only `noise(fight)` events will be routed by these gates in
practice — the gates have no term filter, so any event propagating from a
patron would cross the inward gate. The patron scene vocabulary only
produces `noise(fight)` events (via its rules), so in this catalog entry
only `noise(fight)` will be propagated. A production world would add
explicit term filtering to the gate conditions. Document with a comment.

---

### `catalog/tavern/tests.pl`

```prolog
:- use_module(library(plunit)).
:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/provenance').
:- use_module('../../engine/gates').
:- use_module('../../engine/fixpoint').
:- use_module('../../engine/probes').
:- use_module('../../projections/investigation').
:- use_module('../../verify/contracts').
:- use_module('../../verify/propagation').
:- use_module('../../verify/invariants').
:- use_module(scene, [
    declare_tavern_world/0,
    window_open/1
]).
:- use_module(gates, [
    declare_tavern_gates/0
]).
```

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
    retractall(tavern_scene:window_open(_)),
    retractall(log:event_counter(_)), assertz(log:event_counter(0)),
    retractall(clock:clock_counter(_)), assertz(clock:clock_counter(0)).

setup_tavern :-
    declare_tavern_world,
    declare_tavern_gates.
```

**Required test cases:**

**T1 — scene hierarchy declared correctly**
Call `setup_tavern`. Assert `scenes:scene_type(tavern, composite)`.
Assert `scenes:scene_type(patron_a, leaf)`.
Assert `scenes:scene_type(patron_b, leaf)`.
Assert `scenes:scene_type(street, leaf)`.
Assert `scenes:scene_parent(patron_a, tavern)`.
Assert `scenes:scene_parent(street, tavern)`.

**T2 — strike in patron generates noise(fight) in same patron**
Call `setup_tavern`. Inject `strike(5)` into `patron_a`. Call `world_step`.
Assert `arrived(_, patron_a, noise(fight), _, _)`.

**T3 — taunt in patron generates noise(fight)**
Call `setup_tavern`. Inject `taunt` into `patron_b`. Call `world_step`.
Assert `arrived(_, patron_b, noise(fight), _, _)`.

**T4 — noise propagates upward to tavern (inward gate)**
Call `setup_tavern`. Inject `strike(5)` into `patron_a`. Call `world_step`.
Assert `arrived(_, patron_a, noise(fight), _, _)`.
Assert `arrived(_, tavern, noise(fight), _, _)`.

**T5 — noise blocked at street when window closed**
Call `setup_tavern`. Inject `strike(5)` into `patron_a`. Call `world_step`.
Assert `\+ arrived(_, street, noise(fight), _, _)`.
Assert `gates:gate_blocked(tavern_noise_to_street, _, _)`.

**T6 — noise reaches street when window open**
Call `setup_tavern`. Assert `tavern_scene:window_open(tavern)`.
Inject `strike(5)` into `patron_a`. Call `world_step`.
Assert `arrived(_, patron_a, noise(fight), _, _)`.
Assert `arrived(_, tavern, noise(fight), _, _)`.
Assert `arrived(_, street, noise(fight), _, _)`.

**T7 — guards_alerted fires when noise reaches street**
Using state from T6: assert `arrived(_, street, guards_alerted, _, _)`.

**T8 — D8: strike does NOT appear in tavern log**
Call `setup_tavern`. Assert `tavern_scene:window_open(tavern)`.
Inject `strike(5)` into `patron_a`. Call `world_step`.
Assert `\+ arrived(_, tavern, strike(5), _, _)`.
The `strike(5)` event is in `patron_a`'s log only. The tavern receives
`noise(fight)` through the inward gate — not the original `strike`.
This is D8: transit events do not appear in composite scene logs.

**T9 — patron_b's events do not contaminate patron_a's log**
Call `setup_tavern`. Inject `strike(5)` into `patron_a`.
Inject `taunt` into `patron_b`. Call `world_step`.
Assert `\+ arrived(_, patron_a, taunt, _, _)`.
Assert `\+ arrived(_, patron_b, strike(5), _, _)`.
Patron scenes are independent leaf scenes.

**T10 — window closed after being open: noise blocked again**
Call `setup_tavern`.
Assert `tavern_scene:window_open(tavern)`.
Inject `strike(5)` into `patron_a`. Call `world_step`.
Assert `arrived(_, street, noise(fight), _, _)`.
Advance clock. Retract `tavern_scene:window_open(tavern)`.
Inject `strike(5)` into `patron_b`. Call `world_step`.
Assert the second `noise(fight)` from `patron_b` did NOT reach `street`.
Assert a new `gate_blocked` fact exists for the second strike's propagation.

**T11 — two patrons both contribute noise to tavern**
Call `setup_tavern`. Assert `tavern_scene:window_open(tavern)`.
Inject `strike(5)` into `patron_a`. Advance clock.
Inject `taunt` into `patron_b`. Call `world_step`.
Assert `arrived(_, tavern, noise(fight), _, _)` holds for events from
both patrons — two separate `noise(fight)` events arrived at tavern at
different clock ticks.

**T12 — investigation_chain from guards_alerted**
Using state from T7: find the EventId of `guards_alerted` in `street`.
Call `investigation_chain(AlertedId, Chain)`.
Assert the chain is non-empty and terminates at `injected(player)`.
Assert the chain passes through `street`, `tavern`, and `patron_a` — the
full causal path from the original strike to the alert is traceable.

**T13 — propagation_coverage for inward gate**
Call `setup_tavern`.
Call `verify:propagation_coverage(patron_a_noise_to_tavern, Report)`.
Assert `Report \= []`.

**T14 — propagation_coverage for outward gate, window closed**
Call `setup_tavern` (window closed by default).
Call `verify:propagation_coverage(tavern_noise_to_street, Report)`.
Assert `Report` contains a `result(_, blocked)` entry — with the window
closed, the gate is blocked for all event types.

**T15 — verify_contracts passes on tavern world**
Call `setup_tavern`. Inject `strike(5)` into `patron_a`. Call `world_step`.
Call `verify_contracts`. Assert it succeeds.

**T16 — probe on patron_a returns noise(fight) in vocabulary**
Call `setup_tavern`.
Call `probes:probe(patron_a, vocab(Heads, Gates))`.
Assert `noise(fight)` appears in `Heads`.
Assert `Gates` contains `gate_info(patron_a_noise_to_tavern, tavern, upward)`.

**T17 — probe on tavern: no rules, one outward gate**
Call `setup_tavern`.
Call `probes:probe(tavern, vocab(Heads, Gates))`.
Assert `Heads = []` — the tavern has no rules.
Assert `Gates` contains `gate_info(tavern_noise_to_street, street, downward)`.

---

## Design decisions in force for this session

**D8 — Composite transit events.** A `strike` injected into `patron_a`
propagates through the tavern topologically but must not appear in the
tavern's `arrived` log. The tavern only logs events that arrive through its
declared inward gates — `noise(fight)` via the patron gates. T8 is the
direct test of this invariant.

**`window_open/1` as a gate condition fact.** This is a plain dynamic fact,
not an event. It is asserted and retracted by authoring/test code directly.
Gate conditions are callable goals; `window_open(tavern)` is valid. The
alternative — modelling window state as an event — is architecturally cleaner
but out of scope for this entry. Document the tradeoff with a comment in
`gates.pl`.

**No term filter on gates.** The inward gates carry any event from the patron
scenes, not just `noise(fight)`. In this entry that distinction doesn't matter
because patrons only produce `noise(fight)`. A production gate would filter
by term. Document with a comment.

**S-001 in force.** If any import creates a circular dependency, use
module-qualified calls.

**C-002 in force.** The patron rules produce `noise(fight)` as a consequence.
If writing guards for these rules, avoid matching `noise(fight)` in the
conditions — use `aggregate_all` instead. In this entry no guard is needed
(the rules should fire on every strike/taunt), so C-002 does not apply
directly. Be aware of it.

---

## Constraints

- `catalog/tavern/scene.pl` must not import `gates.pl` — that import runs
  the other direction (`gates.pl` imports `scene.pl` for `window_open/1`).
- `catalog/tavern/scene.pl` must not declare any gates — those live in
  `gates.pl`.
- The tavern scene must have no `scene_rule/4` declarations — it is a pure
  propagation boundary.
- Do not modify any existing engine, lifecycle, verify, or test file.
- Do not modify `catalog/deck/` or `catalog/warrior/`.
- All predicate names must match the specification exactly.

---

## Acceptance criteria

1. `swipl -g "run_tests" -t halt tests/log_tests.pl` — all 9 pass.
2. `swipl -g "run_tests" -t halt tests/provenance_tests.pl` — all 11 pass.
3. `swipl -g "run_tests" -t halt tests/gate_tests.pl` — all 13 pass.
4. `swipl -g "run_tests" -t halt tests/fixpoint_tests.pl` — all 13 pass.
5. `swipl -g "run_tests" -t halt tests/probe_tests.pl` — all 13 pass.
6. `swipl -g "run_tests" -t halt tests/lifecycle_tests.pl` — all 13 pass.
7. `swipl -g "run_tests" -t halt tests/projection_tests.pl` — all 15 pass.
8. `swipl -g "run_tests" -t halt tests/verify_tests.pl` — all 15 pass.
9. `swipl -g "run_tests" -t halt catalog/deck/tests.pl` — all 17 pass.
10. `swipl -g "run_tests" -t halt catalog/warrior/tests.pl` — all 12 pass.
11. `swipl -g "run_tests" -t halt catalog/tavern/tests.pl` — all 17 pass.
12. No `arrived/5` fact is retracted at any point during any test run.
13. `docs/session_logs/session_11.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_11.md`:

```
# Session 11 Report — Catalog: Tavern Composite Scene

## Files created
- catalog/tavern/scene.pl
- catalog/tavern/gates.pl
- catalog/tavern/tests.pl

## Files modified
(none)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed
- tests/fixpoint_tests.pl: 13 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed
- tests/lifecycle_tests.pl: 13 passed, 0 failed
- tests/projection_tests.pl: 15 passed, 0 failed
- tests/verify_tests.pl: 15 passed, 0 failed
- catalog/deck/tests.pl: 17 passed, 0 failed
- catalog/warrior/tests.pl: 12 passed, 0 failed
- catalog/tavern/tests.pl: 17 passed, 0 failed

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
