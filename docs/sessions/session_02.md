# Session 2 — Scenes and Provenance

## What this session is

You are building Session 2 of the Oster implementation. You are building only what is listed here. Do not read ahead or implement anything from future sessions.

At the end of this session, all tests must be green, the session report must be written to `logs/session_02.md`, and no files outside the listed scope may have been created or modified.

---

## Before you write a line of code

Run the Session 1 tests:

```bash
cd oster
swipl -g "run_tests" -t halt tests/log_tests.pl
```

All 9 tests must pass. If any fail, stop and report — do not proceed.

---

## Context: what this session builds

Session 1 built the log and clock — the data layer. This session builds the two things that give that data meaning:

**Scenes** are the named containers events arrive in. A scene declaration says "this named thing exists in the world." Scene rules say "when these conditions hold over this scene's log, this event should exist here." Neither the scene nor its rules act — they declare structure that the fixpoint (Session 4) will evaluate.

**Provenance** is the causal record. Every event in the log has a cause. Provenance makes that cause explicit and traversable. It is what makes "why does this fact exist?" answerable.

These two modules are Session 4's direct dependencies. The fixpoint needs to know what scenes exist, what rules they declare, and how to follow causal chains.

---

## Files to create

```
oster/
├── engine/
│   ├── scenes.pl          ← new
│   └── provenance.pl      ← new
└── tests/
    └── provenance_tests.pl  ← new
```

Also: **remove the temporary `caused_by/2` declaration from `engine/log.pl`** and replace it with a proper `:- use_module` reference. See the stub removal section below.

---

## Stub removal: `caused_by/2` in `log.pl`

Session 1 declared `caused_by/2` temporarily in `engine/log.pl` with a comment marking it for removal here. Now that `engine/provenance.pl` will own the declaration, do the following:

1. Remove the temporary dynamic declaration of `caused_by/2` from `engine/log.pl`.
2. Add `:- use_module(provenance)` to `engine/log.pl` so `inject_event/3` can still assert `caused_by/2` facts.
3. Confirm that all 9 Session 1 tests still pass after this change.

This is the only modification permitted to `engine/log.pl` in this session.

---

## Specification

### `engine/scenes.pl`

#### `scene/1`

```prolog
:- dynamic scene/1.
% scene(Name)
```

Static declaration. Asserted at world-load time. `Name` is an atom. Never retracted during engine evaluation.

Provide a convenience predicate:

```prolog
declare_scene(Name) :-
    ( scene(Name) -> true ; assertz(scene(Name)) ).
```

Idempotent — declaring the same scene twice is not an error.

#### `scene_parent/2`

```prolog
:- dynamic scene_parent/2.
% scene_parent(Child, Parent)
```

Static declaration. Asserted at world-load time. Never retracted during engine evaluation. A scene may have at most one parent. Declaring a second parent for the same child is an error — `declare_scene_parent/2` should throw `error(duplicate_parent(Child), _)` if a parent is already declared.

```prolog
declare_scene_parent(Child, Parent) :-
    ( scene_parent(Child, _) ->
        throw(error(duplicate_parent(Child), context(declare_scene_parent/2, '')))
    ;
        assertz(scene_parent(Child, Parent))
    ).
```

#### `scene_type/2`

```prolog
scene_type(Scene, composite) :-
    scene(Scene),
    scene_parent(_, Scene), !.
scene_type(Scene, leaf) :-
    scene(Scene).
```

Computed, not stored. A scene is composite if any other scene declares it as its parent. Otherwise leaf. Note the cut in the composite clause — a scene is composite if at least one child exists; we do not need to enumerate all children.

#### `scene_root/1`

```prolog
scene_root(Scene) :-
    scene(Scene),
    \+ scene_parent(Scene, _).
```

A scene with no declared parent. In a well-formed world there is exactly one. This is not enforced — `verify_contracts` (Session 8) will check it.

#### `scene_ancestors/2`

```prolog
scene_ancestors(Scene, Ancestors) :-
    scene_ancestors_(Scene, [], Ancestors).

scene_ancestors_(Scene, Acc, Ancestors) :-
    ( scene_parent(Scene, Parent) ->
        scene_ancestors_(Parent, [Parent|Acc], Ancestors)
    ;
        reverse(Acc, Ancestors)
    ).
```

Returns the list of ancestors from immediate parent to root, in root-first order. Used by gate propagation (Session 3) and projection queries (Session 7).

#### `scene_rule/4`

```prolog
:- dynamic scene_rule/4.
% scene_rule(RuleId, Scene, Conditions, ConsequenceEventTemplate)
```

Static declaration. `RuleId` is a unique atom. `Conditions` is a callable Prolog goal — it will be passed to `call/1` by the fixpoint. `ConsequenceEventTemplate` is a Prolog term, possibly with unbound variables that `Conditions` is expected to bind.

Provide a convenience predicate:

```prolog
declare_scene_rule(RuleId, Scene, Conditions, Template) :-
    ( scene_rule(RuleId, _, _, _) ->
        throw(error(duplicate_rule_id(RuleId), context(declare_scene_rule/4, '')))
    ;
        assertz(scene_rule(RuleId, Scene, Conditions, Template))
    ).
```

`RuleId` must be unique across all scenes. Declaring a duplicate is an error.

#### `rules_for_scene/2`

```prolog
rules_for_scene(Scene, Rules) :-
    findall(rule(RuleId, Conditions, Template),
            scene_rule(RuleId, Scene, Conditions, Template),
            Rules).
```

Returns all rules declared for a scene. Used by the fixpoint.

---

### `engine/provenance.pl`

#### `caused_by/2`

```prolog
:- dynamic caused_by/2.
% caused_by(EventId, Cause)
```

This is the declaration that was temporarily in `log.pl`. Move it here.

`Cause` is one of:
- `injected(player)` — initiated by a player action
- `injected(author)` — initiated by authoring or backfill
- `rule(Scene, RuleId)` — generated by a scene rule firing
- `gate(GateId)` — generated by gate propagation
- `simulation_boundary(SimId)` — crossed in from a sub-simulation

Exactly one `caused_by` fact exists per `EventId`. This is asserted by `inject_event/3` in `log.pl` and never retracted.

#### `provenance_chain/2`

```prolog
provenance_chain(EventId, Chain) :-
    provenance_chain_(EventId, [EventId], Chain).

provenance_chain_(EventId, Visited, Chain) :-
    caused_by(EventId, Cause),
    ( Cause = injected(_) ->
        Chain = [step(EventId, Cause)]
    ; Cause = simulation_boundary(_) ->
        Chain = [step(EventId, Cause)]
    ; Cause = rule(_, _) ->
        caused_by(EventId, rule(Scene, RuleId)),
        % Find the triggering event: the most recent hot event in Scene
        % that caused this rule to fire. For now, record the rule as the cause.
        % Full trigger linkage is Session 4's responsibility.
        Chain = [step(EventId, Cause)]
    ; Cause = gate(GateId) ->
        % Find the source event: the arrived fact that was propagated through GateId
        % to produce EventId. gate_transformed/5 records this (Session 3).
        % For now, record the gate as the cause.
        Chain = [step(EventId, Cause)]
    ;
        Chain = [step(EventId, Cause)]
    ).
```

**Note on this session's scope:** Full multi-hop chain traversal depends on `gate_transformed/5` (Session 3) and rule trigger linkage (Session 4). In this session, `provenance_chain/2` returns a single-step chain — the immediate cause of the event. The predicate signature and data contract are established here. Session 4 will extend the implementation to traverse multi-hop chains.

Mark this clearly in the code:

```prolog
% STUB: Session 4 will extend provenance_chain/2 to traverse multi-hop chains.
% Currently returns single-step provenance only.
```

#### `provenance_acyclic/1`

```prolog
provenance_acyclic(EventId) :-
    provenance_acyclic_(EventId, []).

provenance_acyclic_(EventId, Visited) :-
    \+ member(EventId, Visited),
    ( caused_by(EventId, injected(_)) -> true
    ; caused_by(EventId, simulation_boundary(_)) -> true
    ; caused_by(EventId, Cause),
      ( Cause = rule(_, _) -> true  % leaf for now
      ; Cause = gate(_) -> true     % leaf for now
      ; true
      )
    ).
```

Succeeds if the chain from `EventId` contains no repeated `EventId`. Used by `verify_contracts` (Session 8). As with `provenance_chain/2`, the full traversal is deferred — but the predicate must exist and must succeed for all events created by `inject_event/3`.

#### `assert_provenance/2`

```prolog
assert_provenance(EventId, Cause) :-
    assertz(caused_by(EventId, Cause)).
```

Thin wrapper. Exists so `log.pl` calls a named predicate rather than asserting directly into a foreign module's dynamic fact. Makes the dependency explicit.

---

## Tests: `tests/provenance_tests.pl`

```prolog
:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/provenance').
```

Use the same `reset_engine` helper from `log_tests.pl`, extended to also retract all `scene/1`, `scene_parent/2`, and `scene_rule/4` facts. Define it here too — do not import it from `log_tests.pl`.

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
    retractall(event_counter(_)), assertz(event_counter(0)),
    retractall(clock_counter(_)), assertz(clock_counter(0)).
```

**Required test cases:**

**T1 — Scene declaration**
Declare a scene `deck`. Assert `scene(deck)` holds. Assert `scene_type(deck, leaf)` holds (no children declared).

**T2 — Scene type: composite**
Declare scenes `tavern`, `patron_a`. Declare `scene_parent(patron_a, tavern)`. Assert `scene_type(tavern, composite)`. Assert `scene_type(patron_a, leaf)`.

**T3 — Duplicate parent throws**
Declare `scene_parent(patron_a, tavern)`. Attempting to declare `scene_parent(patron_a, other_tavern)` must throw `error(duplicate_parent(patron_a), _)`.

**T4 — Scene rule declaration**
Declare a scene `warrior` and a rule `rule_defeat` for it with a trivially true condition and a consequence term `defeated`. Assert `scene_rule(rule_defeat, warrior, true, defeated)` holds. Assert `rules_for_scene(warrior, Rules)` returns a list containing `rule(rule_defeat, true, defeated)`.

**T5 — Duplicate rule ID throws**
Declare `rule_001` for scene `deck`. Attempting to declare another `rule_001` (for any scene) must throw `error(duplicate_rule_id(rule_001), _)`.

**T6 — caused_by asserted by inject_event**
Inject an event with cause `injected(player)`. Find the `EventId` via `arrived_key`. Assert `caused_by(EventId, injected(player))` holds.

**T7 — provenance_chain returns a step**
Inject an event with cause `injected(author)`. Call `provenance_chain(EventId, Chain)`. Assert `Chain = [step(EventId, injected(author))]`.

**T8 — provenance_acyclic succeeds for injected events**
Inject three events. Call `provenance_acyclic(EventId)` for each. All must succeed.

**T9 — scene_ancestors: leaf with parent**
Declare scenes `street`, `tavern`, `city`. Declare `scene_parent(street, tavern)`, `scene_parent(tavern, city)`. Call `scene_ancestors(street, Ancestors)`. Assert `Ancestors = [city, tavern]`.

**T10 — scene_ancestors: root has no ancestors**
Declare `city` with no parent. Call `scene_ancestors(city, Ancestors)`. Assert `Ancestors = []`.

**T11 — scene_root/1**
In a world with `city` as root (no parent) and `tavern` as child of `city`: assert `scene_root(city)` succeeds and `scene_root(tavern)` fails.

**T12 — Session 1 tests still pass after stub removal**
This is not a plunit test — it is a manual verification step. Run:
```bash
swipl -g "run_tests" -t halt tests/log_tests.pl
```
All 9 must still pass after the `caused_by/2` declaration was moved from `log.pl` to `provenance.pl`. Report the result in the session log.

---

## Design decisions in force for this session

**D3 — Rules as data.** `scene_rule/4` is a dynamic fact whose `Conditions` argument is a callable goal. The engine calls `call(Conditions)` at fixpoint time. Rules are data, not clauses.

**D8 — Composite transit events.** Not directly implemented here, but `scene_type/2` is the predicate the fixpoint will use to decide whether a scene is a propagation boundary. Get the typing right now.

**D9 — Sub-simulation identity (stub).** `simulation_boundary(SimId)` is a valid `Cause` in `caused_by/2`. No further sub-simulation machinery is built in this session.

---

## Constraints

- Do not implement `gate/4`, `gate_condition/2`, or any gate predicate — that is Session 3.
- Do not implement the fixpoint loop — that is Session 4.
- `provenance_chain/2` returns single-step chains only. The stub comment is required.
- The only modification to `engine/log.pl` is removing the temporary `caused_by/2` declaration and adding `:- use_module(provenance)`. Nothing else in `log.pl` changes.
- Do not create any files outside the listed scope.
- All predicate names must match the specification exactly.

---

## Acceptance criteria

The session is complete when:

1. `swipl -g "run_tests" -t halt tests/log_tests.pl` — all 9 pass.
2. `swipl -g "run_tests" -t halt tests/provenance_tests.pl` — all 11 plunit tests pass.
3. T12 (manual) — Session 1 tests confirmed green after stub removal.
4. No `arrived/5` fact is retracted at any point during the test runs.
5. The stub comment for `provenance_chain/2` is present in `engine/provenance.pl`.
6. `logs/session_02.md` exists and contains the session report.

---

## Session report format

Save as `logs/session_02.md`:

```
# Session 2 Report — Scenes and Provenance

## Files created
- engine/scenes.pl
- engine/provenance.pl
- tests/provenance_tests.pl

## Files modified
- engine/log.pl (stub removal: caused_by/2 moved to provenance.pl)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed

## Stubs left for future sessions
- provenance_chain/2: single-step only. Session 4 extends to multi-hop traversal.
- provenance_acyclic/1: leaf traversal only. Session 4 extends.

## Anomalies, surprises, questions
(anything unexpected encountered during implementation)
```

Do not produce the report until all tests pass.

---

## Ambiguity resolution

If something is unclear: session prompt first, then `docs/implementation_plan.md`, then `docs/conceptual_guide.md`. If genuine ambiguity remains, make the most conservative choice and leave a `% DECISION:` comment.
