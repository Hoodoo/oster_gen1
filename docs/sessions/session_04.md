# Session 4 — Fixpoint

## What this session is

You are building Session 4 of the Oster implementation. You are building only what is listed here. Do not read ahead or implement anything from future sessions.

At the end of this session, all tests must be green, the session report must be written to `docs/session_logs/session_04.md`, and no files outside the listed scope may have been created or modified.

---

## Before you write a line of code

Run all prior session tests:

```bash
cd oster
swipl -g "run_tests" -t halt tests/log_tests.pl
swipl -g "run_tests" -t halt tests/provenance_tests.pl
swipl -g "run_tests" -t halt tests/gate_tests.pl
```

All tests must pass. If any fail, stop and report — do not proceed.

---

## Testing convention established in Session 3

PLUnit runs test bodies in an isolated module (`plunit_*`). Any `assertz/1` or `retractall/1` call inside a test body that targets a dynamic fact owned by an engine module must be module-qualified. Examples:

```prolog
assertz(gates:gate_condition(g1, fail))
assertz(scenes:scene_rule(rule_id, my_scene, true, my_event))
```

The `reset_engine` helper in `setup(...)` blocks is unaffected — it runs in user context where imports resolve correctly. Every test body in this session that asserts engine facts must use this pattern.

---

## Context: what this session builds

Sessions 1–3 built the data layer, world structure, and propagation layer. Everything is declared but nothing runs. This session builds the fixpoint — the engine's consequence machine.

The fixpoint is the loop that asks, after any event arrives: what must follow? It evaluates scene rules against hot events, injects the consequences, propagates them through gates, and repeats until nothing new is generated. That stable state is the world's response to the original event.

This is the first session where the engine actually runs end-to-end. The integration test at the end of this session — a minimal world with a rule and a gate, one injected event, one `world_step` — is the first real demonstration that the engine works.

This session also completes the `provenance_chain/2` stub left in Session 2. That predicate currently returns single-step chains. Now that `gate_transformed/5` exists (Session 3) and rule firing is implemented here, the full multi-hop traversal can be written.

---

## Files to create

```
oster/
├── engine/
│   └── fixpoint.pl          ← new
└── tests/
    └── fixpoint_tests.pl    ← new
```

One existing file is modified in this session:

```
oster/
└── engine/
    └── provenance.pl        ← extend provenance_chain/2 (stub removal)
```

---

## Stub removal: `provenance_chain/2` in `provenance.pl`

Session 2 left `provenance_chain/2` as a single-step stub with the comment:

```prolog
% STUB: Session 4 will extend provenance_chain/2 to traverse multi-hop chains.
```

Replace the stub implementation with the full version below. This is the only modification permitted to `engine/provenance.pl` in this session.

### Full `provenance_chain/2`

```prolog
provenance_chain(EventId, Chain) :-
    provenance_chain_(EventId, [EventId], Chain).

provenance_chain_(EventId, Visited, [step(EventId, Cause)|Rest]) :-
    caused_by(EventId, Cause),
    (   terminal_cause(Cause)
    ->  Rest = []
    ;   parent_event(EventId, Cause, ParentId),
        ( member(ParentId, Visited) ->
            Rest = [cycle_detected(ParentId)]   % safety: should not occur in valid logs
        ;
            provenance_chain_(ParentId, [ParentId|Visited], Rest)
        )
    ).

terminal_cause(injected(_)).
terminal_cause(simulation_boundary(_)).

parent_event(_EventId, gate(GateId), ParentId) :-
    gate_transformed(GateId, ParentId, _EventId, _, _), !.
parent_event(_EventId, gate(GateId), ParentId) :-
    % Gate with no transform: source event is the one that triggered propagation.
    % We cannot recover ParentId from the log without gate_transformed.
    % Treat as terminal for untransformed gates.
    \+ gate_transformed(GateId, _, _EventId, _, _),
    ParentId = unknown_gate_source(GateId).
parent_event(_EventId, rule(Scene, RuleId), ParentId) :-
    rule_trigger(RuleId, Scene, ParentId), !.
parent_event(_EventId, rule(Scene, RuleId), unknown_rule_trigger(Scene, RuleId)).
```

`rule_trigger/3` is a dynamic fact asserted by the fixpoint (see `record_rule_trigger/3` below) that records which event caused a rule to fire.

**Note on untransformed gate sources:** When a gate passes an event through unchanged, `gate_transformed/5` is not asserted (by design — Session 3). This means the provenance chain cannot recover the source event ID for untransformed propagations from the log alone. The chain records `unknown_gate_source(GateId)` as a terminal rather than silently dropping the link. This is honest and queryable. A future improvement could assert a `gate_passed/3` fact for untransformed propagations — that is not in scope for this session.

---

## Specification

### `engine/fixpoint.pl`

```prolog
:- use_module(log).
:- use_module(clock).
:- use_module(scenes).
:- use_module(provenance).
:- use_module(gates).
```

---

#### `rule_trigger/3`

```prolog
:- dynamic rule_trigger/3.
% rule_trigger(RuleId, Scene, TriggeringEventId)
```

Asserted by the fixpoint when a rule fires, recording which hot event was being processed when the rule's conditions were evaluated and succeeded. Used by `provenance_chain/2` to trace rule-generated events back to their trigger.

One fact per rule firing. Append-only.

---

#### `fixpoint_depth_exceeded/1`

```prolog
:- dynamic fixpoint_depth_exceeded/1.
% fixpoint_depth_exceeded(Clock)
```

Asserted when `advance_world/1` reaches `MaxDepth` iterations without stabilising. Signals a probable unbounded cascade. Append-only.

---

#### `rule_grounding_failed/2`

```prolog
:- dynamic rule_grounding_failed/2.
% rule_grounding_failed(RuleId, Clock)
```

Asserted when a rule's `ConsequenceEventTemplate` cannot be fully grounded after `call(Conditions)`. The rule does not fire. Append-only.

---

#### `evaluate_rule/3`

```prolog
evaluate_rule(EventId, Scene, RuleId) :-
    scene_rule(RuleId, Scene, Conditions, Template),
    clock_value(Clock),
    ( call(Conditions) ->
        ( ground(Template) ->
            ( \+ arrived_key(Scene, Template, Clock, _) ->
                inject_event(Scene, Template, rule(Scene, RuleId)),
                arrived_key(Scene, Template, Clock, _NewEventId),
                record_rule_trigger(RuleId, Scene, EventId)
            ;
                true  % already present, deduplication
            )
        ;
            assertz(fixpoint:rule_grounding_failed(RuleId, Clock))
        )
    ;
        true  % conditions not met, rule does not fire
    ).
```

Evaluates a single rule for a single scene, in the context of a specific triggering event `EventId`. If conditions succeed and the template is ground and not already in the log, injects the consequence and records the trigger linkage.

---

#### `record_rule_trigger/3`

```prolog
record_rule_trigger(RuleId, Scene, TriggeringEventId) :-
    assertz(rule_trigger(RuleId, Scene, TriggeringEventId)).
```

---

#### `advance_world/1`

```prolog
advance_world(MaxDepth) :-
    MaxDepth > 0,
    log_count(Before),
    hot_events(HotEventIds),
    forall(
        member(EventId, HotEventIds),
        process_hot_event(EventId)
    ),
    log_count(After),
    ( After > Before ->
        Depth1 is MaxDepth - 1,
        advance_world(Depth1)
    ;
        true  % fixpoint reached
    ).
advance_world(0) :-
    clock_value(Clock),
    assertz(fixpoint:fixpoint_depth_exceeded(Clock)).
```

The outer loop. Each iteration:
1. Records the current log count.
2. Collects all hot event IDs via `hot_events/1` (from `log.pl`).
3. For each hot event, calls `process_hot_event/1`.
4. Re-counts. If the log grew, recurses with depth decremented. If stable, halts.
5. If depth reaches 0, asserts `fixpoint_depth_exceeded` and halts.

**Important:** `hot_events/1` is called once per iteration and its result is bound to `HotEventIds` before processing begins. Events injected during this iteration are not re-processed in the same iteration — they will be picked up in the next iteration's `hot_events/1` call. This prevents a newly-arrived event from being processed before it has been fully logged.

---

#### `process_hot_event/1`

```prolog
process_hot_event(EventId) :-
    arrived(EventId, Scene, _Term, _Clock, hot),
    forall(
        scene_rule(RuleId, Scene, _Cond, _Template),
        evaluate_rule(EventId, Scene, RuleId)
    ),
    propagate_from_scene(Scene, EventId).
```

For a single hot event: evaluates all rules declared for that event's scene, then propagates the event through all outgoing gates. Both operations are `forall/2` — they succeed even if there are no rules or no gates.

---

#### `world_step/0`

```prolog
world_step :-
    advance_clock,
    advance_world(100).
```

The normal single-action entry point. Advances the clock, then runs the fixpoint to stability (or depth limit). All events generated within this call carry the clock value set by `advance_clock` at the start.

---

### `reset_engine` extension

Add `rule_trigger/3`, `fixpoint_depth_exceeded/1`, and `rule_grounding_failed/2` to the `reset_engine` helper. Define this version in `fixpoint_tests.pl`:

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
    retractall(rule_trigger(_, _, _)),
    retractall(fixpoint_depth_exceeded(_)),
    retractall(rule_grounding_failed(_, _)),
    retractall(event_counter(_)), assertz(event_counter(0)),
    retractall(clock_counter(_)), assertz(clock_counter(0)).
```

---

## Tests: `tests/fixpoint_tests.pl`

```prolog
:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/provenance').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').
```

Remember: assert engine facts from test bodies with module qualification — `assertz(scenes:scene_rule(...))`, `assertz(gates:gate_condition(...))`, etc.

**Required test cases:**

**T1 — Empty world reaches fixpoint immediately**
No scenes, no rules, no gates. Call `advance_world(10)`. Assert it succeeds. Assert `fixpoint_depth_exceeded(_)` does not hold.

**T2 — Rule fires on hot event**
Declare scene `room`. Declare rule `r_echo` for `room`: conditions `arrived(_, room, signal, _, hot)`, consequence `echo`. Inject `signal` into `room`. Call `world_step`. Assert `arrived(_, room, echo, _, hot)` holds.

**T3 — Rule does not fire when condition fails**
Declare scene `room`. Declare rule `r_never` for `room`: conditions `fail`, consequence `ghost`. Inject `signal` into `room`. Call `world_step`. Assert `arrived(_, room, ghost, _, _)` does not hold.

**T4 — Consequence deduplication**
Declare scene `room` with rule `r_echo` (same as T2). Inject `signal` twice at the same clock value (before calling `world_step`). Call `world_step`. Assert exactly one `arrived(_, room, echo, _, _)` fact exists — not two.

**T5 — Rule-generated event propagates through gate**
Declare scenes `src`, `dst`. Declare open gate `g_out` from `src` to `dst`. Declare rule `r_signal` for `src`: conditions `arrived(_, src, trigger, _, hot)`, consequence `signal`. Inject `trigger` into `src`. Call `world_step`. Assert `arrived(_, src, signal, _, hot)` holds. Assert `arrived(_, dst, signal, _, hot)` holds.

**T6 — All events in one world_step share the same clock**
Inject `trigger` into a scene with a rule that generates a consequence that propagates through a gate. Call `world_step`. Collect all `arrived(_, _, _, Clock, _)` facts created in this step. Assert all carry the same `Clock` value.

**T7 — Depth guard fires on looping rule**
Declare scene `loop`. Declare rule `r_loop` for `loop`: conditions `arrived(_, loop, ping, _, hot)`, consequence `ping`. Note: `ping` → rule fires → `ping` already present (deduplication) → no growth. This should NOT trigger the depth guard. Assert `fixpoint_depth_exceeded(_)` does not hold after injecting `ping` and calling `world_step`.

**T7b — Depth guard fires on genuinely looping rule**
Declare scene `loop`. Declare rule `r_grow` for `loop` that generates a fresh term each firing (e.g. using a counter or `gensym`). Inject one event. Call `advance_world(5)`. Assert `fixpoint_depth_exceeded(_)` holds.

**Note on T7:** The deduplication in `inject_event/3` means a rule that generates the same term it responds to will not loop — the second injection is a no-op and the fixpoint stabilises. A genuinely looping rule must generate fresh terms each iteration. T7b uses `gensym/2` for this purpose: `assertz(scenes:scene_rule(r_grow, loop, (arrived(_, loop, seed, _, hot), gensym(evt, T)), T))`.

**T8 — rule_grounding_failed asserted for ungroundable template**
Declare scene `room`. Declare rule `r_bad` for `room`: conditions `true`, consequence `event(_X)` where `_X` is unbound and `conditions` does not bind it. Inject any event. Call `world_step`. Assert `rule_grounding_failed(r_bad, _)` holds. Assert no `arrived(_, room, event(_), _, _)` fact exists.

**T9 — rule_trigger recorded on rule firing**
Declare scene `room` with rule `r_echo` (conditions: `arrived(_, room, signal, _, hot)`, consequence: `echo`). Inject `signal`, call `world_step`. Find the `EventId` of the `signal` event. Assert `rule_trigger(r_echo, room, EventId)` holds.

**T10 — provenance_chain multi-hop: rule**
Using the state from T9: find the `EventId` of the `echo` event. Call `provenance_chain(EchoId, Chain)`. Assert `Chain` contains `step(EchoId, rule(room, r_echo))` and `step(SignalId, injected(player))` — a two-step chain.

**T11 — provenance_chain multi-hop: gate**
Using the state from T5: find the `EventId` of `signal` in `dst`. Call `provenance_chain(DestSignalId, Chain)`. Assert the chain traces back through the gate to the original `signal` in `src` and ultimately to the injected `trigger`.

**T12 — Monotonicity: arrived/5 never retracted**
Inject several events, run `world_step` multiple times. Call `log_count(N)` before and after each step. Assert `N` never decreases.

**Integration test — T13**
This is the end-to-end smoke test for the engine.

Declare the following minimal world:
- Scene `patron` (leaf)
- Scene `tavern` (composite, parent of `patron`)
- Rule `r_noise` in `patron`: when `strike(_)` arrives in `patron`, generate `noise(fight)`
- Gate `g_up` from `patron` to `tavern`, direction `upward`, no conditions

Inject `strike(5)` into `patron`. Call `world_step`.

Assert all of the following:
- `arrived(_, patron, strike(5), _, hot)` — original event present
- `arrived(_, patron, noise(fight), _, hot)` — rule fired
- `arrived(_, tavern, noise(fight), _, hot)` — gate propagated upward
- `fixpoint_depth_exceeded(_)` does not hold
- All three events share the same clock value

Then call `provenance_chain` on the `tavern` `noise(fight)` event and assert the chain reaches back to `strike(5)` in `patron`.

---

## Design decisions in force for this session

**D3 — Rules as data.** `scene_rule/4` conditions are called via `call/1`. The safe-predicate restriction is not enforced at runtime — `verify_contracts` (Session 8) handles that.

**D7 — Rule grounding.** If `Template` is not fully ground after `call(Conditions)`, assert `rule_grounding_failed/2` and do not inject. Use `ground/1` to check.

**D8 — Composite transit events.** `process_hot_event/1` calls `propagate_from_scene/2` for the event's own scene. It does not log the event in the composite parent scene — that is gates' responsibility, and only through declared inward gates.

---

## Constraints

- Do not implement probes, lifecycle, or projections — those are Sessions 5–7.
- The only modification to `engine/provenance.pl` is replacing the `provenance_chain/2` stub. No other predicates in that file change.
- Do not modify any test file from Sessions 1–3.
- `world_step/0` advances the clock exactly once per call, before `advance_world/1`. The clock does not advance inside the fixpoint loop.
- All predicate names must match the specification exactly.

---

## Acceptance criteria

The session is complete when:

1. `swipl -g "run_tests" -t halt tests/log_tests.pl` — all 9 pass.
2. `swipl -g "run_tests" -t halt tests/provenance_tests.pl` — all 11 pass.
3. `swipl -g "run_tests" -t halt tests/gate_tests.pl` — all 13 pass.
4. `swipl -g "run_tests" -t halt tests/fixpoint_tests.pl` — all 13 pass (T7 and T7b count separately).
5. No `arrived/5` fact is retracted at any point during any test run.
6. The `provenance_chain/2` stub comment is removed from `engine/provenance.pl`.
7. `docs/session_logs/session_04.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_04.md`:

```
# Session 4 Report — Fixpoint

## Files created
- engine/fixpoint.pl
- tests/fixpoint_tests.pl

## Files modified
- engine/provenance.pl (stub removal: provenance_chain/2 extended to multi-hop)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed
- tests/fixpoint_tests.pl: 13 passed, 0 failed

## Stubs left for future sessions
(none expected)

## Anomalies, surprises, questions
(anything unexpected encountered during implementation)
```

Do not produce the report until all tests pass.

---

## Ambiguity resolution

If something is unclear: session prompt first, then `docs/implementation_plan.md`, then `docs/conceptual_guide.md`. If genuine ambiguity remains, make the most conservative choice and leave a `% DECISION:` comment.
