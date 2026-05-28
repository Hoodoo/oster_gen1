# The Scene System — Implementation Plan

*Companion to the Conceptual Guide. This document does not modify the guide — it translates it into a build sequence. Decisions made here that the guide leaves open are flagged explicitly.*

---

## Project layout

Derived from the model's primitives. Each directory has exactly one reason to exist.

```
scene_engine/
│
├── engine/
│   ├── log.pl               # arrived/5, tier management, append-only enforcement
│   ├── clock.pl             # clock_counter/1, advance_clock/0, clock_value/1
│   ├── provenance.pl        # caused_by/2, provenance chain traversal
│   ├── fixpoint.pl          # advance_world/1, depth guard, iteration loop
│   ├── gates.pl             # gate/4, gate_condition/2, gate_transform/3,
│   │                        #   gate_transformed/5, propagation logic
│   ├── scenes.pl            # scene/1, scene_parent/2, leaf/composite typing,
│   │                        #   scene_rule/3 evaluation
│   └── probes.pl            # probe/2, vocabulary surface query, side-effect-free
│
├── lifecycle/
│   ├── tiers.pl             # hot/cold/archived status, tier transitions
│   ├── closure.pl           # closed/2 event handling, cold promotion logic
│   └── compaction.pl        # assert_summary/4, authoring interface for summaries
│
├── projections/
│   ├── legal_actions.pl     # legal_actions/2 — current permitted actions from a scene
│   ├── why_blocked.pl       # why_blocked/3, gate_block_message/3, :why tracing
│   ├── post_fixpoint.pl     # post_fixpoint_summary/2 — what changed and why
│   └── investigation.pl     # investigation_chain/2 — full provenance traversal
│
├── catalog/
│   ├── deck/
│   │   ├── scene.pl
│   │   └── tests.pl
│   ├── warrior/
│   │   ├── scene.pl
│   │   └── tests.pl
│   ├── tavern/
│   │   ├── scene.pl
│   │   ├── gates.pl
│   │   └── tests.pl
│   └── README.md
│
├── verify/
│   ├── contracts.pl         # verify_contracts/0 — termination, monotonicity checks
│   ├── propagation.pl       # propagation coverage tests per gate
│   └── invariants.pl        # formal invariant assertions
│
├── repl/
│   └── repl.pl              # developer REPL: inject_event/2, :why, world display
│
└── tests/
    ├── fixpoint_tests.pl
    ├── gate_tests.pl
    ├── log_tests.pl
    └── provenance_tests.pl
```

---

## Design decisions

These are places where the guide is insufficiently precise to make an implementation decision. Each is stated and resolved here so Claude Code sessions do not need to re-derive them.

**D1 — Event identity.** The guide flags deduplication by `(Target, Source, Clock, Term)` as unsettled, especially for sub-simulation cases. Decision: use a monotonically assigned `EventId` atom (e.g. `evt_001`) as the canonical identity handle, with a separate `arrived_key/4` index fact for deduplication lookups. This separates identity from deduplication and makes edge cases explicit rather than hidden.

**D2 — Clock retraction.** The log is append-only and the engine never retracts. Exception: the clock counter. `clock_counter/1` is a single dynamic fact that is retracted and reasserted on each `advance_clock/0` call. This is the only retraction in the engine. It is isolated to `clock.pl`.

**D3 — Rules as data.** The guide says rules "declare events" and "the engine takes the declared event and injects it." Decision: `scene_rule(Scene, Conditions, ConsequenceEvent)` is a dynamic fact whose `Conditions` argument is a callable Prolog goal restricted to log queries and arithmetic. The engine calls `call(Conditions)` to evaluate, then injects the consequence if grounding succeeds. Rules are inspectable as data, enabling `verify_contracts` and probes. The safe-predicate restriction is enforced by `verify_contracts`, not at runtime.

**D4 — Gate direction encoding.** The guide describes inward (child→composite) and outward (composite→sibling/parent) surfaces. Decision: encode as `gate(GateId, SourceScene, DestScene, Direction)` where `Direction` is `upward`, `downward`, or `lateral`. Upward covers inward propagation; downward and lateral cover the outward surface.

**D5 — Absent gates.** The guide says absence of a gate is equivalent to a permanently closed gate and must not raise errors. Decision: `propagate_if_gate_exists/3` succeeds with no action when no matching gate exists. No error, no warning.

**D6 — Gate block logging.** The guide says gate failures are queryable but the resolver predicate is not implemented. Decision: assert `gate_blocked(GateId, EventId, Clock)` on every blocked propagation as part of Phase 3. `why_blocked.pl` reads these facts. This is the data half; the query half comes in Phase 7.

**D7 — Rule grounding.** If `call(Conditions)` binds variables in `ConsequenceEvent` but the term cannot be fully grounded, the rule does not fire and `rule_grounding_failed(RuleId, Clock)` is asserted. Ungroundable consequences are visible, not silent.

**D8 — Composite transit events.** The guide says "the guide assumes composite scenes do not log transit events but does not state it." Decision: events passing through a composite scene on their way to a leaf do not appear in the composite scene's `arrived` log. The composite scene only logs what inward gates deposit there directly. This is what makes the locality invariant hold cleanly.

**D9 — Sub-simulation identity (stub).** The guide defers this to Session 3. For now: a sub-simulation is a scene subtree with a `simulation_root(Scene)` declaration. Clock autonomy via `sub_clock(SimId, Value)`. Summary events crossing the boundary carry `caused_by(EventId, simulation_boundary(SimId))`. Retention policy is `simulation_retention(SimId, Policy)` where `Policy` is `discard`, `cold`, or `archive`. This is a stub sufficient to unblock Phase 4; the full answer is deferred.

**D10 — Probe visibility vs. permission.** The guide asks whether a gate that blocks propagation also blocks probe reachability. Decision: gates appear in probe results regardless of whether their conditions are currently open. The probe answers reachability, not permission. If the design question resolves differently, `probe/2` gains a filter parameter.

**D11 — Learned events.** The guide describes `learned(Agent, Fact, SourceClock)` as a normal event type requiring no special engine machinery. Decision: no special handling. A scene that models knowledge has a `scene_rule` matching `learned(...)` events. The engine is unaware these are epistemically distinct.

**D12 — Tier promotion mechanics.** `tier_status(EventId, Tier)` is a separate index fact that the fixpoint reads to decide whether to scan an event. Tier transitions are recorded as `tier_transition(EventId, From, To, Clock)` facts — never by retracting `arrived/5`. Archived tier uses `library(persistency)` for disk-backing; the in-memory `arrived/5` fact is retained but `tier_status(EventId, archived)` tells the fixpoint to skip it.

---

## Session breakdown

Each session is 1–2 hours of Claude Code work. Sessions are ordered by strict dependency. A session should not start until its predecessors are green in `tests/`.

---

### Session 1 — Log and clock

**Goal:** The foundational data layer. Everything else reads from the log.

**Files to create:**
- `engine/log.pl`
- `engine/clock.pl`
- `tests/log_tests.pl`

**Specification:**

`arrived(EventId, Scene, Term, Clock, Tier)` — central dynamic fact. All five arguments always present. `EventId` is a generated atom via a monotonic counter. `Tier` defaults to `hot` on arrival.

`arrived_key(Scene, Term, Clock, EventId)` — deduplication index. Asserted alongside every `arrived/5` fact. Before asserting a new arrived fact, check for an existing `arrived_key` with the same `(Scene, Term, Clock)`. If found, skip — do not assert a duplicate.

`tier_status(EventId, Tier)` — current tier of each event. Asserted on arrival as `hot`. Updated (by new assertion, not retraction of `arrived/5`) when tiers change.

`tier_transition(EventId, From, To, Clock)` — audit log of all tier changes. Append-only.

`clock_counter/1` — single dynamic fact. Starts at 0. `advance_clock/0` retracts and reasserts. `clock_value(V)` reads it.

`inject_event(Scene, Term, Cause)` — the single entry point for adding events. Generates `EventId`, asserts `arrived/5`, asserts `arrived_key/4`, asserts `tier_status/2` as `hot`, asserts `caused_by(EventId, Cause)`. Does not advance the clock — the caller decides when to advance.

**Invariants to test:**
- Injecting the same `(Scene, Term, Clock)` twice results in exactly one `arrived` fact.
- `arrived/5` is never retracted (test by asserting a hook on retract and confirming it never fires during normal operation).
- `clock_value/1` reflects `advance_clock/0` calls correctly.
- `tier_transition` log grows monotonically.

---

### Session 2 — Scenes and provenance

**Goal:** Static world structure and causal record.

**Files to create:**
- `engine/scenes.pl`
- `engine/provenance.pl`
- `tests/provenance_tests.pl`

**Specification:**

`scene(Name)` and `scene_parent(Child, Parent)` — static declarations. Asserted at world-load time, never changed during evaluation.

`scene_type(Scene, leaf)` — a scene with no children declared via `scene_parent`. Computed, not declared.
`scene_type(Scene, composite)` — a scene that appears as a parent in at least one `scene_parent` fact.

`scene_rule(RuleId, Scene, Conditions, ConsequenceEventTemplate)` — static declaration. `RuleId` is a unique atom for traceability. `Conditions` is a callable goal. `ConsequenceEventTemplate` may contain unbound variables that `call(Conditions)` is expected to bind.

`caused_by(EventId, Cause)` — Cause is one of:
- `injected(player)`
- `injected(author)`
- `rule(Scene, RuleId)`
- `gate(GateId)`
- `simulation_boundary(SimId)`

`provenance_chain(EventId, Chain)` — recursively follows `caused_by` links. Terminates at `injected(...)` or `simulation_boundary(...)`. Returns the ordered list from the event back to its root cause.

`provenance_acyclic(EventId)` — succeeds if the chain from `EventId` contains no repeated `EventId`. Used by `verify_contracts`.

**Invariants to test:**
- Every `arrived` event has exactly one `caused_by` fact.
- `provenance_chain` terminates for all events in the log.
- No chain contains a repeated `EventId`.
- `scene_type` correctly classifies scenes based on `scene_parent` declarations.

---

### Session 3 — Gates

**Goal:** The propagation layer. Events get direction.

**Files to create:**
- `engine/gates.pl`
- `tests/gate_tests.pl`

**Specification:**

`gate(GateId, SourceScene, DestScene, Direction)` — static declaration.

`gate_condition(GateId, ConditionGoal)` — zero or more per gate. All must succeed for the gate to be open. No conditions = always open.

`gate_transform(GateId, InputTerm, OutputTerm)` — zero or one per gate. If absent, the event crosses unchanged. `InputTerm` is matched against the arriving event term; `OutputTerm` is what arrives at the destination.

`gate_open(GateId)` — succeeds if all `gate_condition` goals for `GateId` currently succeed. Fails (does not throw) if any condition fails.

`attempt_propagation(EventId, GateId)` — the core propagation predicate:
1. Reads `arrived(EventId, SourceScene, Term, Clock, _)`.
2. Checks `gate(GateId, SourceScene, DestScene, _)`.
3. Evaluates `gate_open(GateId)`. If closed: assert `gate_blocked(GateId, EventId, Clock)`, succeed (no event injected, no error).
4. If open: apply transform if declared, producing `OutTerm`. Inject `OutTerm` into `DestScene` via `inject_event/3` with `caused_by = gate(GateId)`.
5. If a transform was applied: assert `gate_transformed(GateId, EventId, NewEventId, Term, OutTerm)`.

`propagate_from_scene(Scene, EventId)` — finds all gates with `SourceScene = Scene` and calls `attempt_propagation/2` for each. Succeeds vacuously if no gates exist (D5).

`gate_blocked(GateId, EventId, Clock)` — dynamic fact. Append-only. Records every blocked propagation attempt.

`gate_transformed(GateId, SourceEventId, DestEventId, InputTerm, OutputTerm)` — dynamic fact. Records every transform application.

**Invariants to test:**
- Source events are never modified by transforms (the original `arrived` fact is unchanged after a transform).
- A closed gate produces a `gate_blocked` fact and no new `arrived` fact.
- An open gate with no transform produces a new `arrived` fact with identical term.
- An open gate with a transform produces a new `arrived` fact with the transformed term and a `gate_transformed` record.
- No gate produces an error when absent (`propagate_from_scene` on a scene with no declared gates succeeds silently).

---

### Session 4 — Fixpoint

**Goal:** The engine's consequence machine. This is the first session where the engine can actually run.

**Files to create:**
- `engine/fixpoint.pl`
- `tests/fixpoint_tests.pl`

**Specification:**

`advance_world(MaxDepth)` — outer loop:
1. Record the current count of `arrived` facts.
2. Collect all events where `tier_status(EventId, hot)`.
3. For each such event in each scene: evaluate all `scene_rule(_, Scene, Conditions, Template)` facts. If `call(Conditions)` succeeds and fully grounds `Template`: call `inject_event(Scene, Template, rule(Scene, RuleId))` if not already present (deduplication via `arrived_key`). If `Template` cannot be grounded: assert `rule_grounding_failed(RuleId, Clock)` (D7).
4. For each newly arrived event, call `propagate_from_scene(Scene, EventId)`.
5. Count `arrived` facts again. If the count did not increase, the fixpoint is stable — halt.
6. If the count increased, recurse. If `MaxDepth` iterations pass without stabilising: assert `fixpoint_depth_exceeded(Clock)`, halt.

All events generated within one `advance_world/1` call receive the clock value current at call entry — the clock is not advanced during fixpoint evaluation.

`world_step` — convenience predicate: advance the clock, then call `advance_world(100)`. This is the normal single-action entry point.

`fixpoint_depth_exceeded(Clock)` — dynamic fact. Asserted when the depth guard fires. Signals a probable unbounded cascade.

`rule_grounding_failed(RuleId, Clock)` — dynamic fact. Signals that a rule's consequence could not be grounded.

**Invariants to test:**
- The fixpoint terminates for the deck scene (draw, shuffle, sort) within 10 iterations.
- The fixpoint never retracts any `arrived` fact (monotonicity).
- All events generated within one `world_step` carry the same clock value.
- `fixpoint_depth_exceeded` is asserted when a deliberately looping rule is installed.
- A world with no rules and no gates reaches fixpoint in 1 iteration.

**This is the first integration test.** Load the deck scene (even hand-written as a stub), inject a `draw` event, call `world_step`, assert the expected arrived facts.

---

### Session 5 — Probes

**Goal:** Read-only vocabulary surface. No side effects.

**Files to create:**
- `engine/probes.pl`

**Specification:**

`probe(Scene, VocabularySurface)` — returns a term `vocab(RuleHeads, OutgoingGates)` where:
- `RuleHeads` is the list of `ConsequenceEventTemplate` terms from all `scene_rule(_, Scene, _, Template)` facts. One entry per rule. Templates are not evaluated — they are returned as-is, possibly with unbound variables.
- `OutgoingGates` is the list of `gate_info(GateId, DestScene, Direction)` terms for all `gate(GateId, Scene, DestScene, Direction)` facts. Gate conditions are not evaluated (D10).

`probe_reachable(Scene, EventShape)` — succeeds if `EventShape` unifies with any rule head in the scene's vocabulary surface, or if it unifies with an event type that any outgoing gate could carry (determined by checking gates from the scene, depth 1 only).

The probe predicate must not:
- Assert or retract any fact
- Call `advance_world` or `inject_event`
- Call `advance_clock`
- Read `arrived/5` facts (the probe reads declared structure, not the log)

**Invariants to test:**
- `probe/2` called on a freshly loaded scene with no arrived events returns the full vocabulary.
- `probe/2` called twice returns identical results (no side effects).
- `probe/2` does not alter the count of `arrived` facts.
- `probe/2` does not alter `clock_value`.
- A scene with no rules and no gates returns `vocab([], [])`.

---

### Session 6 — Log lifecycle

**Goal:** Tier management and closure as events.

**Files to create:**
- `lifecycle/tiers.pl`
- `lifecycle/closure.pl`
- `lifecycle/compaction.pl`

**Specification:**

**tiers.pl**

`promote_to_cold(Scene, UpToClock)` — for all hot events in `Scene` with `Clock =< UpToClock`: assert `tier_transition(EventId, hot, cold, CurrentClock)`, assert `tier_status(EventId, cold)`. Does not retract `arrived/5`.

`promote_to_archived(Scene, UpToClock)` — same pattern, cold→archived. For archived events, use `library(persistency)` for disk-backing if available; degrade gracefully to in-memory-only if not. Asserts `tier_status(EventId, archived)`.

The fixpoint's hot-event scan (Session 4) already reads `tier_status` to skip non-hot events. No fixpoint changes required.

**closure.pl**

Closure is a normal event type, not a meta-operation (per the guide). A `closed(Scene, clock(N))` event is injected like any other event and propagates through gates.

`scene_rule` for closure response: when `closed(Scene, clock(N))` arrives at a composite scene, a rule may fire to promote the composite's own filtered aggregate to cold. This rule is authored, not engine-built. The engine just needs to not special-case the `closed` term.

`declare_closure(Scene, Clock)` — authoring convenience: calls `inject_event(Scene, closed(Scene, clock(Clock)), injected(author))`. That's all. The fixpoint and gates handle the rest.

**compaction.pl**

`assert_summary(Scene, ProjectionName, SummaryTerm, Clock)` — injects `summary(ProjectionName, SummaryTerm)` as an event into `Scene` with `caused_by = injected(author)`, then calls `promote_to_cold(Scene, Clock)` for the events that the summary replaces. The caller decides which events to cold-promote — the predicate takes `Clock` as the boundary.

**Invariants to test:**
- `promote_to_cold` does not retract any `arrived` fact.
- After `promote_to_cold`, the promoted events are skipped by the fixpoint hot-event scan.
- Cold events are still readable by direct `arrived/5` queries (evidence is not erased).
- `declare_closure` produces an `arrived` fact for `closed(...)` with correct provenance.
- `assert_summary` produces a summary event and transitions underlying events to cold, without retracting them.

---

### Session 7 — Projections

**Goal:** The four named projections the guide specifies as first-class predicates.

**Files to create:**
- `projections/legal_actions.pl`
- `projections/why_blocked.pl`
- `projections/post_fixpoint.pl`
- `projections/investigation.pl`

**Specification:**

`legal_actions(Scene, Actions)` — collects all open gates from `Scene` (calls `gate_open/1` for each), finds vocabulary terms reachable through them via the destination scene's `probe/2`, and returns the intersection of open gates and reachable vocabulary. This is the "what can the player do here" query.

`why_blocked(Scene, EventTerm, Explanation)` — finds the gate that would handle `EventTerm` from `Scene`, evaluates each `gate_condition` individually, and returns `blocked_by(GateId, ConditionGoal)` for the first condition that failed. Also checks `gate_blocked/3` facts for historical blocking records. If no matching gate exists at all: returns `no_gate(Scene, EventTerm)`.

`post_fixpoint_summary(Clock, Summary)` — collects all `arrived(EventId, Scene, Term, Clock, hot)` facts from the given clock tick, pairs each with its `caused_by` provenance, and returns `Summary` as a list of `change(Scene, Term, Cause)` terms, sorted by scene. This is what an interface layer reads after `world_step`.

`investigation_chain(EventId, Chain)` — traverses `caused_by/2` recursively. Reads hot, cold, and archived events (intentionally pays tier-crossing cost). Returns the full list of `step(EventId, Scene, Term, Cause)` terms from the queried event back to its root. Uses `provenance_chain/2` from `provenance.pl` as its backbone.

**Invariants to test:**
- `legal_actions` returns only actions where the gate is currently open (insert a gate with a failing condition, confirm it is absent from results).
- `why_blocked` correctly identifies a condition that blocks a gate.
- `why_blocked` returns `no_gate` when no gate exists for the term.
- `post_fixpoint_summary` returns exactly the events from the specified clock tick.
- `investigation_chain` reaches the root cause for a multi-hop provenance chain.
- `investigation_chain` terminates for archived events.

---

### Session 8 — verify_contracts and invariant checks

**Goal:** The engine's self-test layer. Enables safe catalog authoring.

**Files to create:**
- `verify/contracts.pl`
- `verify/propagation.pl`
- `verify/invariants.pl`

**Specification:**

**contracts.pl**

`verify_contracts` — runs all checks below. Prints a report. Fails if any check fails.

Termination heuristics (directional, not proven — these are the guide's candidates):
- `check_no_self_generating_rules` — for each `scene_rule(RuleId, Scene, _, Template)`: the functor of `Template` must not appear as a condition in the same rule's `Conditions`. (Rule output type ≠ input type heuristic.)
- `check_consequence_specificity` — flagged as unproven in the guide. Implemented as a warning, not a hard failure.

Provenance checks:
- `check_provenance_acyclic` — calls `provenance_acyclic(EventId)` for every event in the log.

Rule safety:
- `check_rule_conditions_safe(AllowedPredicates)` — inspects each `scene_rule` Conditions goal and confirms it only calls predicates in `AllowedPredicates` (a declared list: log query predicates, arithmetic, basic control). This is a static analysis on the term structure of the Conditions goal.

**propagation.pl**

`propagation_coverage(GateId, Report)` — for a given gate, enumerates the event types declared in the source scene's vocabulary, injects each into a minimal test world (source scene only, the gate, destination scene), runs the fixpoint, and reports which events crossed, which were blocked, and which generated no gate interaction. This is the "propagation test" the guide says every catalog entry must ship with.

`assert_propagation_test(GateId, EventTerm, ExpectedOutcome)` — declares an expected propagation result. `verify_contracts` checks all declared tests against the current world.

**invariants.pl**

Formal invariant checks, runnable at any time:
- `check_log_append_only` — compares the current `arrived` count to a previously recorded baseline. Warns if count decreased (would indicate illegal retraction). The baseline is set by calling `record_log_baseline` before a test sequence.
- `check_probes_side_effect_free` — calls `probe/2` on every declared scene, records log count before and after, asserts equality.
- `check_gates_never_mutate_source` — for every `gate_transformed` fact, confirms the source `arrived` fact still has the original term.
- `check_rules_locality` — inspects `scene_rule` Conditions for any calls to `arrived(_, OtherScene, _, _, _)` where `OtherScene` is not bound to the rule's own scene. Reports violations.

---

### Session 9 — Catalog: deck scene

**Goal:** First complete catalog entry. Proves the engine runs end-to-end.

**Files to create:**
- `catalog/deck/scene.pl`
- `catalog/deck/tests.pl`

**Specification:**

The deck is a leaf scene. Vocabulary: `create(Cards)`, `draw`, `shuffle`, `sort`, `order(Cards)`.

Scene rules:
- When `create(Cards)` arrives: derive the initial `order(Cards)` projection (this is a projection, not a new event — the deck's current order is computed from the most recent `create` or `shuffle` event).
- When `shuffle` arrives: the new order is a permutation of the current order. For testing purposes, a deterministic shuffle (reverse) is acceptable. A random shuffle uses `random_permutation/2`.
- When `sort` arrives: the new order is the sorted order of the current deck.
- When `draw` arrives: the top card is removed from the current order.

**Design note:** The deck has no rules that inject new events — it has projections. The distinction: a projection is a query against the log that returns derived state. A scene rule injects a new event. The deck's `current_order(DeckScene, Order)` is a projection predicate in `catalog/deck/scene.pl`, not a scene rule. This is the first example of the projection pattern described in the guide ("derived state is always computed from the log on demand").

Propagation tests: no gates in this catalog entry (standalone deck). Tests verify fixpoint termination within 5 iterations for each vocabulary event type.

**Tests to write:**
- Inject `create([card(1), card(2), card(3)])`, assert `current_order` returns the correct list.
- Inject `shuffle`, assert `current_order` returns a permuted list.
- Inject `draw`, assert `current_order` loses the top card.
- Inject `draw` when the deck is empty, assert no crash and a `gate_blocked`-equivalent fact (or a rule_grounding_failed fact, since there's nothing to draw).
- Assert fixpoint terminates in ≤ 5 iterations for each.

---

### Session 10 — Catalog: warrior scene and gate transform

**Goal:** First gate with a transform. Proves `gate_transformed` mechanics.

**Files to create:**
- `catalog/warrior/scene.pl`
- `catalog/warrior/tests.pl`

**Specification:**

The warrior is a leaf scene. Vocabulary: `strike(Damage)`, `dodge`, `defeated`.

Projections:
- `current_hp(WarriorScene, HP)` — sums all `strike(D)` events that arrived, subtracts from a base HP value declared at scene creation. (The base HP arrives as a `created(hp(N))` event.)
- `is_defeated(WarriorScene)` — succeeds if a `defeated` event is present in the log.

Scene rules:
- When `current_hp` would be ≤ 0 and no `defeated` event yet exists: inject `defeated` into this scene.

Gate (the interesting part): declare a gate `warrior_vs_warrior(warrior_a, warrior_b, lateral)` with a transform: `strike(D)` crosses from warrior_a to warrior_b, arriving as `strike(D2)` where `D2 = max(0, D - Armour)`. Armour is a value from warrior_b's log (a `created(armour(N))` event).

This gate has a condition: both warriors must not be defeated.

`gate_transform` for this gate reads warrior_b's armour from the log to compute the reduced damage. This is the first example of a transform that reads the destination scene's log.

**Tests to write:**
- Warrior A strikes warrior B for 8 damage; warrior B has armour 5; `arrived` at warrior_b shows `strike(3)` with a `gate_transformed` record.
- The original `arrived` at warrior_a still shows `strike(8)`.
- Warrior B is defeated when HP reaches 0; the gate is then closed (condition fails); further strikes from warrior_a produce `gate_blocked` facts.
- `investigation_chain` on warrior_b's `defeated` event traces back through the strikes to the root injected action.

---

### Session 11 — Catalog: tavern composite scene

**Goal:** Composite scene with inward and outward gates. Proves the propagation boundary mechanics.

**Files to create:**
- `catalog/tavern/scene.pl`
- `catalog/tavern/gates.pl`
- `catalog/tavern/tests.pl`

**Specification:**

Scene hierarchy:
- `tavern` (composite, parent of `patron_a`, `patron_b`, `street`)
- `patron_a` (leaf, child of tavern)
- `patron_b` (leaf, child of tavern)
- `street` (leaf, child of tavern — for this catalog entry)

Patron vocabulary: `strike(D)`, `taunt`, `noise(fight)`.

Scene rule in patron: when `strike(_)` or `taunt` arrives, inject `noise(fight)` into the same patron scene.

Inward gate: `patron_noise_to_tavern(patron_a, tavern, upward)` — carries `noise(fight)` upward. No condition (always open).

Outward gate: `tavern_noise_to_street(tavern, street, downward)` — carries `noise(fight)` from tavern to street. Condition: `window_open(tavern)` — a fact asserted by the author to simulate the open window scenario from the guide.

Street vocabulary: `noise(fight)`, `guards_alerted`.

Scene rule in street: when `noise(fight)` arrives, inject `guards_alerted`.

The tavern scene itself has no rules — it is purely a propagation boundary in this catalog entry.

**Tests to write:**
- Inject `strike(5)` into `patron_a`. Assert `noise(fight)` arrives at `patron_a`, then at `tavern` (inward gate), but NOT at `street` (outward gate condition fails — window not open).
- Assert `gate_blocked` fact for the tavern→street gate.
- Assert `window_open(tavern)`, inject `strike(5)` into `patron_b`. Assert `noise(fight)` arrives at `patron_b`, `tavern`, and `street`. Assert `guards_alerted` arrives at `street`.
- Assert that `patron_b`'s `strike(5)` event is NOT present in the `tavern` log (transit events do not appear in composite scene logs — D8).
- Run `propagation_coverage(patron_noise_to_tavern, _)` and assert the report is non-empty.

---

### Session 12 — REPL and developer tooling

**Goal:** A usable developer interface for interactive authoring and debugging.

**Files to create:**
- `repl/repl.pl`

**Specification:**

`start_repl` — enters an interactive loop reading commands from stdin.

Commands:
- `inject(Scene, Event)` — calls `inject_event(Scene, Event, injected(player))` then `world_step`.
- `log(Scene)` — prints all `arrived/5` facts for `Scene`, grouped by tier, sorted by clock.
- `state(Scene)` — calls any available projection predicates for `Scene` (deck: `current_order`; warrior: `current_hp`, `is_defeated`; etc.) and prints results.
- `:why(Scene, EventTerm)` — calls `why_blocked(Scene, EventTerm, Explanation)` and prints.
- `probe(Scene)` — calls `probe/2` and prints the vocabulary surface.
- `chain(EventId)` — calls `investigation_chain(EventId, Chain)` and prints the causal chain.
- `verify` — calls `verify_contracts` and prints the report.
- `close(Scene)` — calls `declare_closure(Scene, CurrentClock)`.
- `step` — calls `world_step` without injecting a new event (allows re-evaluating the fixpoint if rules or gates were manually asserted).
- `quit` — exits.

The REPL does not implement narration policy — it prints raw Prolog terms. That is intentional. It is a developer tool, not a player interface.

---

## Dependency graph

```
Session 1 (log, clock)
    └── Session 2 (scenes, provenance)
            └── Session 3 (gates)
                    └── Session 4 (fixpoint)  ← first runnable engine
                            ├── Session 5 (probes)
                            ├── Session 6 (lifecycle)
                            │       └── Session 7 (projections)
                            │               └── Session 8 (verify_contracts)
                            │                       └── Session 9 (deck)
                            │                               └── Session 10 (warrior)
                            │                                       └── Session 11 (tavern)
                            │                                               └── Session 12 (REPL)
                            └── (Sessions 5 and 6 can run in parallel after Session 4)
```

Sessions 5 and 6 are independent of each other after Session 4. Everything else is strictly sequential.

---

## What Claude Code needs at the start of each session

Each session should begin with:
1. A copy of this document.
2. The conceptual guide.
3. The current state of `tests/` — green tests are the contract; the session must not break them.
4. The specific session number and its "Files to create" list.

Claude Code should not read ahead to future sessions. The specifications above are intentionally forward-referenced only where dependency requires it.

---

## Open problems not addressed in this plan

These are carried forward from the guide's unsolved problems section. They do not block any session above but will need sessions of their own when the guide resolves them:

- **Fixpoint trace mode** — the highest-value missing development tool. A flag that logs every rule evaluation attempt in causal order.
- **Full sub-simulation boundaries** — Session 9 stub is sufficient to proceed; the full answer awaits the guide's Session 3.
- **Epistemic state model** — deferred in the guide; deferred here. Load-bearing for hidden-information stories.
- **Composite closure propagation** — the full specification of what a composite scene does when a child declares closure.
- **Query ergonomics** — the projections in Session 7 are a first answer; a meta-predicate or named projection library is the eventual target.
- **Confidence and source extension to `learned`** — deferred in the guide as a catalog candidate, not an engine primitive.
