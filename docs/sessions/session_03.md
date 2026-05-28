# Session 3 — Gates

## What this session is

You are building Session 3 of the Oster implementation. You are building only what is listed here. Do not read ahead or implement anything from future sessions.

At the end of this session, all tests must be green, the session report must be written to `docs/session_logs/session_03.md`, and no files outside the listed scope may have been created or modified.

---

## Before you write a line of code

Run all prior session tests:

```bash
cd oster
swipl -g "run_tests" -t halt tests/log_tests.pl
swipl -g "run_tests" -t halt tests/provenance_tests.pl
```

All tests from both sessions must pass. If any fail, stop and report — do not proceed.

---

## Context: what this session builds

Sessions 1 and 2 built the data layer and world structure. Events can arrive, scenes exist, rules are declared, provenance is recorded. But nothing moves anywhere. Events land in a scene and stay there.

This session builds gates — the propagation layer. Gates are the relationships between scenes that give events direction. They are the only mechanism by which an event in one scene causes something in another. Without gates, every scene is an island.

Three things are true of gates that are easy to get wrong:

**Gates are declared relationships, not owned by either scene.** A deck does not declare its gate to a hand. The gate is declared separately. This means `gate/4` is a static fact independent of both scenes it connects.

**Absence of a gate is not an error.** Calling `propagate_from_scene/2` on a scene with no gates declared must succeed silently. No warning, no failure. This is D5 and it is load-bearing — the fixpoint calls this predicate on every scene after every event, and most scenes will have no relevant gate at that moment.

**Gate failure is a terminal fact, not a pending state.** When a gate is closed, the event does not wait. A `gate_blocked` fact is asserted and propagation ends there. The blocked fact is the record — it is queryable, it carries provenance context, and it is the data that `why_blocked.pl` (Session 7) will read.

This session also produces `gate_transformed/5`, which is the fact that `provenance_chain/2` (Session 2, currently a stub) will use in Session 4 to traverse multi-hop causal chains. Get the structure of this fact right — the Session 4 prompt depends on it.

---

## Files to create

```
oster/
├── engine/
│   └── gates.pl       ← new
└── tests/
    └── gate_tests.pl  ← new
```

No existing files are modified in this session.

---

## Specification

### `engine/gates.pl`

```prolog
:- use_module(log).
:- use_module(scenes).
:- use_module(provenance).
```

---

#### `gate/4`

```prolog
:- dynamic gate/4.
% gate(GateId, SourceScene, DestScene, Direction)
```

Static declaration. `GateId` is a unique atom. `Direction` is one of `upward`, `downward`, or `lateral` (D4). Never retracted during engine evaluation.

Provide a convenience predicate:

```prolog
declare_gate(GateId, SourceScene, DestScene, Direction) :-
    ( gate(GateId, _, _, _) ->
        throw(error(duplicate_gate_id(GateId), context(declare_gate/4, '')))
    ;
        assertz(gate(GateId, SourceScene, DestScene, Direction))
    ).
```

`GateId` must be unique. Declaring a duplicate is an error.

---

#### `gate_condition/2`

```prolog
:- dynamic gate_condition/2.
% gate_condition(GateId, ConditionGoal)
```

Zero or more per gate. `ConditionGoal` is a callable Prolog goal evaluated at propagation time. Multiple conditions for the same gate are all required to succeed — they are conjunctive, not disjunctive.

No convenience wrapper is needed — conditions are added with `assertz(gate_condition(GateId, Goal))` directly.

---

#### `gate_transform/3`

```prolog
:- dynamic gate_transform/3.
% gate_transform(GateId, InputTerm, OutputTerm)
```

Zero or one per gate. `InputTerm` is unified with the arriving event term. `OutputTerm` is what arrives at the destination scene. If no transform is declared for a gate, the event term crosses unchanged.

No convenience wrapper needed.

---

#### `gate_open/1`

```prolog
gate_open(GateId) :-
    gate(GateId, _, _, _),
    \+ (gate_condition(GateId, Cond), \+ call(Cond)).
```

Succeeds if all conditions for `GateId` currently succeed. Fails (does not throw) if any condition fails. A gate with no conditions is always open — the `\+` double-negation pattern handles this correctly: if there is no condition that fails, the gate is open.

---

#### `gate_blocked/3`

```prolog
:- dynamic gate_blocked/3.
% gate_blocked(GateId, EventId, Clock)
```

Append-only. Asserted whenever `attempt_propagation/2` finds the gate closed. Never retracted.

---

#### `gate_transformed/5`

```prolog
:- dynamic gate_transformed/5.
% gate_transformed(GateId, SourceEventId, DestEventId, InputTerm, OutputTerm)
```

Append-only. Asserted whenever a gate transform is applied during propagation. Records the complete before/after picture: which gate, which source event, which destination event (the newly created one), and both terms. Never retracted.

This fact is the data source for multi-hop provenance traversal in Session 4. The structure must be exactly as specified.

---

#### `apply_transform/4`

```prolog
apply_transform(GateId, InTerm, OutTerm, transformed) :-
    gate_transform(GateId, InTerm, OutTerm), !.
apply_transform(_GateId, Term, Term, unchanged).
```

Helper used by `attempt_propagation/2`. Returns the output term and a status atom (`transformed` or `unchanged`). The cut ensures that at most one transform is applied — if `gate_transform/3` has multiple clauses for a gate, only the first matching one fires.

---

#### `attempt_propagation/2`

```prolog
attempt_propagation(EventId, GateId) :-
    arrived(EventId, SourceScene, Term, Clock, _),
    gate(GateId, SourceScene, DestScene, _),
    ( gate_open(GateId) ->
        apply_transform(GateId, Term, OutTerm, Status),
        inject_event(DestScene, OutTerm, gate(GateId)),
        ( Status = transformed ->
            arrived_key(DestScene, OutTerm, Clock, DestEventId),
            assertz(gate_transformed(GateId, EventId, DestEventId, Term, OutTerm))
        ;
            true
        )
    ;
        assertz(gate_blocked(GateId, EventId, Clock))
    ).
```

The core propagation predicate. Ordering matters:

1. Reads the source event from `arrived/5`.
2. Confirms the gate connects from that event's scene.
3. Checks `gate_open/1`. If closed: asserts `gate_blocked/3` and succeeds — no error, no failure, no event.
4. If open: applies transform (or passes through unchanged), injects the result into the destination scene via `inject_event/3` with cause `gate(GateId)`, and if a transform was applied records `gate_transformed/5`.

**On the `arrived_key` lookup for `DestEventId`:** After `inject_event/3` succeeds, the destination event exists in the log. `arrived_key(DestScene, OutTerm, Clock, DestEventId)` retrieves its ID. This works because `inject_event/3` asserts `arrived_key/4` as part of its operation, and the clock value has not changed (the fixpoint holds the clock constant within a single `advance_world/1` call).

**Important:** `attempt_propagation/2` succeeds in all cases — whether the gate is open or closed. It never fails (unless the `arrived/5` lookup itself fails, which would indicate a programming error). This is what allows `propagate_from_scene/2` to call it for each gate without needing to handle failure.

---

#### `propagate_from_scene/2`

```prolog
propagate_from_scene(Scene, EventId) :-
    forall(
        gate(GateId, Scene, _, _),
        attempt_propagation(EventId, GateId)
    ).
```

Finds all gates with `Scene` as their source and calls `attempt_propagation/2` for each. `forall/2` succeeds vacuously when there are no matching gates (D5) — this is the correct behaviour. Do not use `findall` + `maplist` here; `forall/2` is the right idiom because it succeeds when the condition has no solutions.

---

#### `gates_from_scene/2`

```prolog
gates_from_scene(Scene, GateIds) :-
    findall(GateId, gate(GateId, Scene, _, _), GateIds).
```

Read-only query. Returns the list of gate IDs originating from a scene. Used by `probes.pl` (Session 5) and `legal_actions.pl` (Session 7).

---

### `reset_engine` extension

The `reset_engine` helper used in tests must be extended to retract gate-related facts. Define this version in `gate_tests.pl` (do not modify prior test files):

```prolog
reset_engine :-
    retractall(arrived(_, _, _, _, _)),
    retractall(arrived_key(_, _, _, _)),
    retractall(tier_status(_, _)),
    retractall(tier_transition(_, _, _, _)),
    retractall(caused_by(_, _)),
    retractall(scene(_)),
    retractall(scene_parent(_, _)),
    retractall(scene_rule(_, _, _, _)),
    retractall(gate(_, _, _, _)),
    retractall(gate_condition(_, _)),
    retractall(gate_transform(_, _, _)),
    retractall(gate_blocked(_, _, _)),
    retractall(gate_transformed(_, _, _, _, _)),
    retractall(event_counter(_)), assertz(event_counter(0)),
    retractall(clock_counter(_)), assertz(clock_counter(0)).
```

---

## Tests: `tests/gate_tests.pl`

```prolog
:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/provenance').
:- use_module('../engine/gates').
```

**Required test cases:**

**T1 — Gate declaration**
Declare scenes `deck`, `hand`. Declare gate `g_draw` from `deck` to `hand`, direction `lateral`. Assert `gate(g_draw, deck, hand, lateral)` holds.

**T2 — Duplicate gate ID throws**
Declare gate `g_001`. Attempting to declare another gate with ID `g_001` must throw `error(duplicate_gate_id(g_001), _)`.

**T3 — Open gate with no conditions**
Declare scenes `a`, `b` and gate `g_open` from `a` to `b`. Assert `gate_open(g_open)` succeeds. No conditions declared.

**T4 — Closed gate: condition fails**
Declare gate `g_closed` from `a` to `b`. Add condition `gate_condition(g_closed, fail)`. Assert `gate_open(g_closed)` fails.

**T5 — Open gate: all conditions pass**
Declare gate `g_multi` from `a` to `b`. Add conditions `gate_condition(g_multi, true)` and `gate_condition(g_multi, 1 =:= 1)`. Assert `gate_open(g_multi)` succeeds.

**T6 — Propagation through open gate, no transform**
Declare scenes `src`, `dst` and open gate `g_pass` from `src` to `dst`. Inject event `noise(fight)` into `src`. Call `attempt_propagation(EventId, g_pass)`. Assert `arrived(_, dst, noise(fight), _, hot)` holds. Assert the source event `arrived(EventId, src, noise(fight), _, hot)` is unchanged.

**T7 — Propagation blocked: gate_blocked asserted**
Declare gate `g_block` from `src` to `dst` with condition `fail`. Inject event `noise(fight)` into `src`. Call `attempt_propagation(EventId, g_block)`. Assert `gate_blocked(g_block, EventId, _)` holds. Assert no new event arrived in `dst`.

**T8 — Propagation with transform**
Declare scenes `warrior_a`, `warrior_b`. Declare gate `g_strike` from `warrior_a` to `warrior_b`. Add transform `gate_transform(g_strike, strike(D), strike(D2)) :- D2 is max(0, D - 3)`. Inject `strike(8)` into `warrior_a`. Call `attempt_propagation(EventId, g_strike)`. Assert `arrived(_, warrior_b, strike(5), _, hot)` holds. Assert `gate_transformed(g_strike, EventId, _, strike(8), strike(5))` holds. Assert the original `arrived(EventId, warrior_a, strike(8), _, hot)` is unchanged.

**T9 — Source event unchanged after transform**
Using the state from T8: assert that `arrived(EventId, warrior_a, strike(8), _, hot)` still holds. Assert there is no `arrived(_, warrior_a, strike(5), _, _)` — the transform did not modify the source.

**T10 — propagate_from_scene: no gates, no error**
Declare scene `isolated`. Inject any event into `isolated`. Call `propagate_from_scene(isolated, EventId)`. Assert it succeeds without error and no new events were created (D5).

**T11 — propagate_from_scene: multiple gates**
Declare scene `hub` and scenes `dest_1`, `dest_2`. Declare open gates `g1` and `g2` both from `hub`. Inject `signal` into `hub`. Call `propagate_from_scene(hub, EventId)`. Assert `arrived(_, dest_1, signal, _, hot)` holds. Assert `arrived(_, dest_2, signal, _, hot)` holds.

**T12 — gate_transformed links source to destination event**
Using the state from T8: find the `DestEventId` in `gate_transformed(g_strike, EventId, DestEventId, _, _)`. Assert `arrived(DestEventId, warrior_b, strike(5), _, hot)` holds. This confirms the transform record correctly identifies the destination event.

**T13 — gates_from_scene returns correct IDs**
Declare scene `room` with two outgoing gates `g_door` and `g_window`. Call `gates_from_scene(room, GateIds)`. Assert both IDs appear in `GateIds`. Assert a scene with no gates returns `[]`.

---

## Design decisions in force for this session

**D4 — Gate direction encoding.** `Direction` is one of `upward`, `downward`, `lateral`. The engine does not currently enforce semantic rules about direction — it is metadata for authoring and future projection queries. Do not validate direction values at declaration time.

**D5 — Absent gates.** `propagate_from_scene/2` must succeed silently when no gates exist. Use `forall/2` — it is the correct predicate for this pattern.

**D6 — Gate block logging.** Every blocked propagation asserts `gate_blocked(GateId, EventId, Clock)`. This is append-only and never retracted. It is the data source for `why_blocked.pl` in Session 7.

---

## Constraints

- Do not implement the fixpoint loop — that is Session 4.
- Do not implement `why_blocked/3` or any projection predicate — those are Sessions 7 and beyond.
- Do not modify `engine/log.pl`, `engine/clock.pl`, `engine/scenes.pl`, or `engine/provenance.pl`.
- Do not modify `tests/log_tests.pl` or `tests/provenance_tests.pl`.
- The `gate_transform/3` fact uses a callable term as `OutputTerm` — it may contain arithmetic that is evaluated at propagation time inside `apply_transform/4`. This is correct and intentional.
- `gate_transformed/5` must be asserted only when a transform was actually applied — not for unchanged pass-through events.
- All predicate names must match the specification exactly.

---

## Acceptance criteria

The session is complete when:

1. `swipl -g "run_tests" -t halt tests/log_tests.pl` — all 9 pass.
2. `swipl -g "run_tests" -t halt tests/provenance_tests.pl` — all 11 pass.
3. `swipl -g "run_tests" -t halt tests/gate_tests.pl` — all 13 pass.
4. No `arrived/5` fact is retracted at any point during any test run.
5. `docs/session_logs/session_03.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_03.md`:

```
# Session 3 Report — Gates

## Files created
- engine/gates.pl
- tests/gate_tests.pl

## Files modified
(none)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed

## Stubs left for future sessions
(none — gate_transformed/5 is complete and ready for Session 4's provenance_chain extension)

## Anomalies, surprises, questions
(anything unexpected encountered during implementation)
```

Do not produce the report until all tests pass.

---

## Ambiguity resolution

If something is unclear: session prompt first, then `docs/implementation_plan.md`, then `docs/conceptual_guide.md`. If genuine ambiguity remains, make the most conservative choice and leave a `% DECISION:` comment.
