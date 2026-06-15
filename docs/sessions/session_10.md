# Session 10 — Catalog: Warrior Scene and Gate Transform

## What this session is

You are building Session 10 of the Oster implementation. This is the second
catalog entry — two warriors who can fight each other. You are building only
what is listed here. Do not read ahead or implement anything from future
sessions.

At the end of this session, all tests must be green, the session report must be
written to `docs/session_logs/session_10.md`, and no files outside the listed
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

The warrior catalog entry demonstrates three things the deck did not:

**Scene rules that inject events.** The deck had only projections. The warrior
has a rule: when HP drops to zero and the warrior is not yet defeated, inject
`defeated`. This is the first catalog-level scene rule.

**A gate with a transform that reads the destination scene's log.** The
armour-reduction gate between two warriors computes reduced damage by looking
up the destination warrior's armour value from its own log. The transform is
not a pure data rewrite — it is a callable goal that queries the log at
propagation time.

**A gate with a condition.** The fight gate is closed once either warrior is
defeated. Further strikes are blocked and recorded as `gate_blocked` facts.

This session also produces the first multi-hop `investigation_chain` test that
crosses a transform gate — the chain from `defeated` should trace back through
the reduced strikes to the original injected actions.

---

## Files to create

```
catalog/
└── warrior/
    ├── scene.pl   ← new
    └── tests.pl   ← new
```

No existing files are modified in this session.

---

## Key design decision: transform as callable goal

`gate_transform/3` is declared as a static fact:

```prolog
:- dynamic gate_transform/3.
% gate_transform(GateId, InputTerm, OutputTerm)
```

`apply_transform/4` in `engine/gates.pl` calls it as:

```prolog
gate_transform(GateId, InTerm, OutTerm)
```

This means `OutputTerm` is not required to be a ground data term — it can be
unified by the clause body. To make the transform read `warrior_b`'s armour
from the log at propagation time, declare the transform as a Prolog clause
with a body:

```prolog
gate_transform(fight_gate, strike(D), strike(D2)) :-
    arrived(_, warrior_b, created(armour(Armour)), _, _),
    D2 is max(0, D - Armour).
```

When `apply_transform/4` calls `gate_transform(fight_gate, strike(8), OutTerm)`,
Prolog executes the clause body, looks up `warrior_b`'s armour from the log,
and unifies `OutTerm` with `strike(D2)`.

This works because `gate_transform/3` is declared `dynamic` and Prolog
executes dynamic clauses with bodies normally. The gate transform is therefore
not just a data rewrite — it is a query-at-propagation-time computation.

**Implication for the test setup:** `warrior_b` must have a `created(armour(N))`
event in its log before any strike propagates through the fight gate. The test
must inject this before the fight begins.

**Implication for named warriors:** The transform clause hardcodes `warrior_b`
as the destination scene name. This makes the gate specific to these two named
scenes. A more general approach (looking up armour from the destination scene
dynamically) is possible but adds complexity not needed for a catalog entry.
Use named scenes. Document with a comment.

---

## Specification

### `catalog/warrior/scene.pl`

```prolog
:- module(warrior, [
    declare_warrior/2,
    current_hp/2,
    is_defeated/1,
    declare_fight_gate/2
]).

:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/gates').
:- use_module('../../engine/fixpoint').
```

---

#### `declare_warrior/2`

```prolog
declare_warrior(Name, Options) :-
    declare_scene(Name),
    ( member(hp(HP), Options) ->
        inject_event(Name, created(hp(HP)), injected(author))
    ; true ),
    ( member(armour(A), Options) ->
        inject_event(Name, created(armour(A)), injected(author))
    ; true ),
    declare_defeat_rule(Name).
```

Declares a warrior scene with initial HP and armour values injected as events.
`Options` is a list that may contain `hp(N)` and `armour(N)` terms.
`declare_defeat_rule/1` declares the scene rule that fires `defeated` when HP
reaches zero.

---

#### `declare_defeat_rule/1`

```prolog
declare_defeat_rule(WarriorScene) :-
    atomic_list_concat([rule_defeat_, WarriorScene], RuleId),
    declare_scene_rule(
        RuleId,
        WarriorScene,
        (   current_hp(WarriorScene, HP),
            HP =< 0,
            \+ arrived(_, WarriorScene, defeated, _, _)
        ),
        defeated
    ).
```

Declares the defeat rule for a specific warrior scene. The rule ID is derived
from the scene name to ensure uniqueness across multiple warriors.

**Note:** The rule's conditions call `current_hp/2` — a projection predicate
defined in this module. This is permitted: rule conditions are callable Prolog
goals and may call any predicate in scope. `check_rule_conditions_safe` will
flag `current_hp` as not in the default safe predicate list — this is
expected. Document with a comment and note it in the session report.

---

#### `current_hp/2`

```prolog
current_hp(WarriorScene, HP) :-
    ( arrived(_, WarriorScene, created(hp(BaseHP)), _, _) ->
        findall(D, arrived(_, WarriorScene, strike(D), _, _), Damages),
        sum_list(Damages, TotalDamage),
        HP is BaseHP - TotalDamage
    ;
        HP = 0
    ).
```

Derives current HP by finding the base HP from the `created(hp(N))` event and
subtracting the sum of all `strike(D)` damage values that have arrived.

**Important:** This sums all `strike(D)` events regardless of tier. Cold or
archived strikes still count — damage is permanent. This is intentional.

---

#### `is_defeated/1`

```prolog
is_defeated(WarriorScene) :-
    arrived(_, WarriorScene, defeated, _, _).
```

---

#### `declare_fight_gate/2`

```prolog
declare_fight_gate(WarriorA, WarriorB) :-
    atomic_list_concat([gate_fight_, WarriorA, '_vs_', WarriorB], GateId),
    declare_gate(GateId, WarriorA, WarriorB, lateral),
    % Gate condition: neither warrior may be defeated
    assertz(gates:gate_condition(GateId,
        \+ arrived(_, WarriorA, defeated, _, _))),
    assertz(gates:gate_condition(GateId,
        \+ arrived(_, WarriorB, defeated, _, _))),
    % Gate transform: reduce damage by destination warrior's armour
    % This clause reads warrior_b's armour from the log at propagation time.
    % The destination scene name is bound at declaration time, not at runtime.
    assertz((gates:gate_transform(GateId, strike(D), strike(D2)) :-
        ( arrived(_, WarriorB, created(armour(Armour)), _, _) ->
            D2 is max(0, D - Armour)
        ;
            D2 = D  % no armour declared: damage passes through unchanged
        )
    )).
```

Declares the fight gate between two warriors with:
- A condition requiring neither warrior is defeated
- A transform that reduces incoming strike damage by the defender's armour

The transform is declared as a dynamic clause with a body. `WarriorB` is
captured in the clause at declaration time via Prolog's standard closure
behaviour for `assertz`.

---

### `catalog/warrior/tests.pl`

```prolog
:- use_module(library(plunit)).
:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/provenance').
:- use_module('../../engine/gates').
:- use_module('../../engine/fixpoint').
:- use_module('../../projections/investigation').
:- use_module('../../verify/contracts').
:- use_module('../../verify/invariants').
:- use_module(scene, [
    declare_warrior/2,
    current_hp/2,
    is_defeated/1,
    declare_fight_gate/2
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
    retractall(log:event_counter(_)), assertz(log:event_counter(0)),
    retractall(clock:clock_counter(_)), assertz(clock:clock_counter(0)).

setup_fight :-
    declare_warrior(warrior_a, [hp(20), armour(0)]),
    declare_warrior(warrior_b, [hp(15), armour(5)]),
    declare_fight_gate(warrior_a, warrior_b).
```

**Required test cases:**

**T1 — initial HP correct**
Call `setup_fight`. Assert `current_hp(warrior_a, 20)`.
Assert `current_hp(warrior_b, 15)`.

**T2 — strike reduces HP**
Call `setup_fight`. Inject `strike(8)` into `warrior_a`. Call `world_step`.
Assert `current_hp(warrior_a, 12)` — warrior_a took the strike directly
(no gate routes inward strikes to warrior_a in this setup; the fight gate
is from warrior_a TO warrior_b). Clarification: `strike(8)` injected directly
into `warrior_a` means warrior_a took 8 damage. `current_hp(warrior_a, HP)`
should return `HP = 12`.

**T3 — transform reduces damage by armour**
Call `setup_fight`. Inject `strike(8)` into `warrior_a`.
Find the EventId of the `strike(8)` event in `warrior_a`.
Call `attempt_propagation(EventId, GateId)` where `GateId` is the fight gate.
Assert `arrived(_, warrior_b, strike(3), _, _)` — `8 - 5 = 3`.
Assert `gates:gate_transformed(GateId, EventId, _, strike(8), strike(3))`.
Assert the original `arrived(EventId, warrior_a, strike(8), _, _)` unchanged.

**T4 — armour cannot produce negative damage**
Call `setup_fight` with `warrior_b` having `armour(20)`.
Inject `strike(8)` into `warrior_a` and propagate.
Assert `arrived(_, warrior_b, strike(0), _, _)` — `max(0, 8 - 20) = 0`.

**T5 — defeat rule fires when HP reaches zero**
Call `setup_fight`. Inject enough strikes to reduce `warrior_b` to zero HP
(three `strike(5)` events through the fight gate = 0 net damage after armour
of 5 each time — use `strike(10)` to deal 5 net damage, three times = 15
total = 0 HP). Call `world_step` after each injection.
Assert `arrived(_, warrior_b, defeated, _, _)`.
Assert `is_defeated(warrior_b)`.

**T6 — gate closes after defeat**
Using state from T5 where `warrior_b` is defeated: inject another `strike(8)`
into `warrior_a`. Find its EventId. Call `attempt_propagation(EventId, GateId)`.
Assert `gates:gate_blocked(GateId, EventId, _)` holds.
Assert no new `strike` event arrived in `warrior_b`.

**T7 — no armour: damage passes through unchanged**
Declare `warrior_c` with `hp(10), armour(0)`. Declare `warrior_d` with
`hp(10), armour(0)`. Declare fight gate between them.
Inject `strike(7)` into `warrior_c` and propagate.
Assert `arrived(_, warrior_d, strike(7), _, _)`.

**T8 — investigation_chain from defeated traces to root**
Using state from T5: find the EventId of `warrior_b`'s `defeated` event.
Call `investigation_chain(DefeatedId, Chain)`.
Assert the chain is non-empty.
Assert the chain contains a step with `injected(player)` or
`injected(author)` cause at the root — the chain terminates at an injection.
Assert no `unknown_gate_source` terminal appears in the chain — the fight
gate uses a transform, so `gate_transformed/5` provides the full link.

**T9 — verify_contracts passes on warrior world**
Call `setup_fight`. Call `verify_contracts`.
The defeat rule calls `current_hp/2` which is not in the default safe
predicate list. `check_rule_conditions_safe` will warn but `verify_contracts`
should still pass (the check reports violations but the session report should
note this warning explicitly).

**T10 — fixpoint terminates for strike injection**
Call `setup_fight`. Record `log:log_count(Before)`. Inject `strike(5)` into
`warrior_a`. Call `advance_world(10)`.
Assert `fixpoint:fixpoint_depth_exceeded(_)` does not hold.

**T11 — current_hp stable after defeat**
Using state from T5: assert `current_hp(warrior_b, HP)` succeeds and `HP =< 0`.
Inject another `strike(5)` directly into `warrior_b` (bypassing the gate).
Assert `current_hp` correctly reflects the additional damage — HP goes further
negative. The projection does not special-case defeated warriors.

**T12 — propagation_coverage for fight gate**
Call `setup_fight`. Call
`verify:propagation_coverage(GateId, Report)` where `GateId` is the fight gate.
Assert `Report` is non-empty. Assert the report contains a `result(strike(_), _)`
entry — the gate carries `strike` events.

---

## Design decisions in force for this session

**Transform as callable clause.** `gate_transform/3` is declared as a dynamic
clause with a body, not a pure data fact. This is supported by `apply_transform/4`
which calls `gate_transform(GateId, InTerm, OutTerm)` using normal Prolog
clause resolution. Document with `% DESIGN:` comments in the scene file.

**Named scenes in transform.** The fight gate transform hardcodes the defender's
scene name at declaration time. This is correct for a catalog entry demonstrating
the pattern. A general parameterised transform is out of scope.

**`check_rule_conditions_safe` warning.** The defeat rule calls `current_hp/2`
which is not in `default_safe_predicates`. This will produce a warning but not
a hard failure. Note it explicitly in the session report.

**S-001 in force.** If any import creates a circular dependency, use
module-qualified calls.

---

## Constraints

- Do not modify any existing engine, lifecycle, verify, or test file.
- Do not modify `catalog/deck/scene.pl` or `catalog/deck/tests.pl`.
- `catalog/warrior/scene.pl` must not import `verify` or `lifecycle` modules.
- The fight gate must be declared via `declare_fight_gate/2` — do not
  hardcode gate declarations in the test file.
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
11. No `arrived/5` fact is retracted at any point during any test run.
12. `docs/session_logs/session_10.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_10.md`:

```
# Session 10 Report — Catalog: Warrior Scene and Gate Transform

## Files created
- catalog/warrior/scene.pl
- catalog/warrior/tests.pl

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

## verify_contracts warnings
(note any check_rule_conditions_safe warnings for current_hp/2)

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
