# Session 18 — Barkeeper's Amulet

## What this session is

Extends the tavern world catalog with two new scenes (`barkeeper` and
`mob_lair`) and one one-directional conditional gate between them. The
gate exercises asymmetric directionality — there is no return gate, and the
condition is event-sourced via the same "most recent qualifying event wins"
pattern established in Session 16 for the window.

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

## Design context

The barkeeper owns a magical amulet. When he uses it, an `alert_sent`
event fires in his scene and crosses a gate to `mob_lair` — but only if
the amulet is charged. There is no return gate: `mob_lair` can receive
alerts but cannot send events back to `barkeeper` or `tavern` through any
declared gate. This is the point of the exercise — two scenes connected by
a one-directional gate with an event-sourced condition.

The amulet's charge state lives in `barkeeper`'s own log as
`amulet_charged`/`amulet_spent` events — the same relationship the window
has to the tavern. "The barkeeper has a charged amulet" is a fact about
the barkeeper, not about the gate or mob_lair.

`mob_lair` is a direct child of `world` (not of `tavern` — the mob does
not live in the tavern). `barkeeper` is a child of `tavern`.

---

## Files to modify

```
oster/
├── catalog/tavern/
│   ├── scene.pl   ← new scenes/rules, amulet_is_charged/1, setup injection
│   ├── gates.pl   ← new gate, term filter, condition
│   └── tests.pl   ← T20, T21, T22
└── repl/
    └── repl.pl    ← update load_world message; import amulet_is_charged
```

---

## Specification: `catalog/tavern/scene.pl`

### Module export list

Add `amulet_is_charged/1`:

```prolog
:- module(tavern_scene, [
    declare_tavern_world/0,
    declare_patron/1,
    declare_street/0,
    window_is_open/1,
    amulet_is_charged/1
]).
```

### `declare_tavern_world/0`

Replace the existing predicate. New lines are marked:

```prolog
declare_tavern_world :-
    declare_scene(world),
    declare_scene(tavern),
    declare_scene(patron_a),
    declare_scene(patron_b),
    declare_scene(street),
    declare_scene(barkeeper),          % NEW
    declare_scene(mob_lair),           % NEW
    declare_scene_parent(tavern, world),
    declare_scene_parent(street, world),
    declare_scene_parent(patron_a, tavern),
    declare_scene_parent(patron_b, tavern),
    declare_scene_parent(barkeeper, tavern),   % NEW — barkeeper is inside the tavern
    declare_scene_parent(mob_lair, world),     % NEW — mob_lair is a world-level scene
    declare_patron_rules(patron_a),
    declare_patron_rules(patron_b),
    declare_street_rules,
    declare_barkeeper_rules,           % NEW
    declare_mob_lair_rules,            % NEW
    inject_event(tavern, window_opened, injected(setup)),
    inject_event(barkeeper, amulet_charged, injected(setup)).  % NEW
```

### `declare_barkeeper_rules/0` — add this new predicate

```prolog
declare_barkeeper_rules :-
    declare_scene_rule(
        rule_alert_sent,
        barkeeper,
        arrived(_, barkeeper, use_amulet, _, _),
        alert_sent
    ).
```

One rule: using the amulet produces `alert_sent` in barkeeper's scene.
The gate then carries `alert_sent` to mob_lair — but only if the amulet
is charged. The rule fires unconditionally on `use_amulet`; the gate
condition is where the charge check lives.

### `declare_mob_lair_rules/0` — add this new predicate

```prolog
declare_mob_lair_rules :-
    declare_scene_rule(
        rule_mob_mobilized,
        mob_lair,
        arrived(_, mob_lair, alert_sent, _, _),
        mob_mobilized
    ).
```

One rule: when `alert_sent` arrives in mob_lair, the mob mobilizes.

### `amulet_is_charged/1` — add this new predicate

```prolog
amulet_is_charged(BarkeepScene) :-
    findall(Clock-Term,
            ( log:arrived(_, BarkeepScene, Term, Clock, _),
              ( Term = amulet_charged ; Term = amulet_spent )
            ),
            Pairs),
    Pairs \= [],
    msort(Pairs, Sorted),
    last(Sorted, _-amulet_charged).
% NOTE: same "most recent qualifying event wins" pattern as window_is_open/1.
% This is now the second instance. The abstraction is earned but deliberately
% deferred — extract a shared helper when a third use case appears.
% Same same-tick caveat applies: do not charge and spend in the same clock tick.
```

---

## Specification: `catalog/tavern/gates.pl`

### Import

Add `amulet_is_charged/1` to the import from `scene`:

```prolog
:- use_module(scene, [window_is_open/1, amulet_is_charged/1]).
```

### `declare_tavern_gates/0`

Add the new gate at the end of the existing predicate body:

```prolog
    % One-directional alert gate: barkeeper → mob_lair
    % No return gate — mob_lair cannot send events back through any declared gate.
    declare_gate(barkeeper_amulet_alert, barkeeper, mob_lair, lateral),
    declare_gate_term_filter(barkeeper_amulet_alert, alert_sent),
    assertz(gates:gate_condition(
        barkeeper_amulet_alert,
        tavern_scene:amulet_is_charged(barkeeper)
    )).
```

Do not modify the existing patron or window gate declarations.

---

## Specification: `catalog/tavern/tests.pl`

### `reset_engine`

No changes needed — the new events are in the log (`retractall(log:arrived(...))`)
and the new gate facts are cleared by the existing gate retracts.

### New tests T20, T21, T22

Add after T19.

**Watch out on clock sequencing (same lesson as T19):** `declare_tavern_world`
injects both `window_opened` and `amulet_charged` at clock 0 as hot events.
The first `world_step` in each test processes these setup events. Tests that
need to change amulet state must do so after that first step, not before —
otherwise the setup injection and the test injection share clock 0 and the
"most recent" check is unreliable. This is the same pattern that caused the
T19 draft issue in Session 17; apply the same fix here proactively.

**T20 — amulet charged, alert reaches mob_lair:**

```prolog
test(t20_amulet_alert_reaches_mob_lair, [setup(reset_engine)]) :-
    setup_tavern,
    fixpoint:world_step,    % process setup events (window_opened, amulet_charged)
    log:inject_event(barkeeper, use_amulet, injected(player)),
    fixpoint:world_step,
    log:arrived(_, barkeeper, alert_sent, _, _),
    log:arrived(_, mob_lair, alert_sent, _, _),
    log:arrived(_, mob_lair, mob_mobilized, _, _).
```

**T21 — amulet spent, alert blocked:**

```prolog
test(t21_amulet_spent_alert_blocked, [setup(reset_engine)]) :-
    setup_tavern,
    fixpoint:world_step,    % process setup events
    log:inject_event(barkeeper, amulet_spent, injected(player)),
    fixpoint:world_step,    % amulet_spent now most recent
    log:inject_event(barkeeper, use_amulet, injected(player)),
    fixpoint:world_step,
    log:arrived(_, barkeeper, alert_sent, _, _),
    \+ log:arrived(_, mob_lair, alert_sent, _, _),
    gates:gate_blocked(barkeeper_amulet_alert, _, _).
```

**T22 — chain from mob_mobilized traces back to use_amulet:**

```prolog
test(t22_mob_mobilized_chain, [setup(reset_engine)]) :-
    setup_tavern,
    fixpoint:world_step,
    log:inject_event(barkeeper, use_amulet, injected(player)),
    fixpoint:world_step,
    log:arrived(MobId, mob_lair, mob_mobilized, _, _),
    provenance:provenance_chain(MobId, Chain),
    Chain \= [],
    last(Chain, step(_, barkeeper, use_amulet, injected(player))),
    member(step(_, mob_lair, alert_sent, _), Chain),
    member(step(_, barkeeper, alert_sent, _), Chain).
```

---

## Specification: `repl/repl.pl`

### Import

Add `amulet_is_charged/1` to the existing tavern scene import:

```prolog
:- use_module('../catalog/tavern/scene', [declare_tavern_world/0,
                                          window_is_open/1,
                                          amulet_is_charged/1]).
```

### `load_world/0`

Update the format message to reflect the expanded world:

```prolog
load_world :-
    declare_tavern_world,
    declare_tavern_gates,
    register_projections,
    format("World loaded: world → [tavern → [patron_a, patron_b, barkeeper], street, mob_lair]~n").
```

---

## `docs/deferred.md`

Add a new note:

```markdown
### N-003 — "most recent qualifying event" projection is duplicated across two gate conditions

**Identified:** Session 18
**Severity:** Low — duplication is intentional and documented inline

`window_is_open/1` and `amulet_is_charged/1` in `catalog/tavern/scene.pl`
share identical structure: findall over two event terms, msort, last check.
The abstraction was deliberately deferred in both sessions (16 and 18)
pending a third use case. Extract a shared `most_recent_state/3` helper
(or similar) when a third caller appears.
```

---

## Constraints

- Do not add a return gate from `mob_lair` to `barkeeper` or `tavern`.
  One-directionality is the point of this entry.
- Do not modify any engine, projection, lifecycle, or verify file.
- Do not modify `catalog/deck/` or `catalog/warrior/`.
- `mob_lair` must have no outgoing gates declared.

---

## Acceptance criteria

1. All eleven suites pass, with `catalog/tavern/tests.pl` now at 22
   tests (was 19).
2. `scenes.` in the REPL shows `mob_lair` and `barkeeper` in the correct
   positions in the hierarchy.
3. `gates.` in the REPL shows `barkeeper_amulet_alert` as `lateral` with
   correct open/closed status.
4. `chain` from `mob_mobilized` traces back to `injected(player)` for
   `use_amulet` — confirm in the manual REPL transcript.
5. `docs/deferred.md` has the N-003 entry added.
6. `docs/session_logs/session_18.md` is written.
