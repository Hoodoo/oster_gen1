# Session 5 — Probes

## What this session is

You are building Session 5 of the Oster implementation. You are building only
what is listed here. Do not read ahead or implement anything from future
sessions.

At the end of this session, all tests must be green, the session report must be
written to `docs/session_logs/session_05.md`, and no files outside the listed
scope may have been created or modified.

---

## Before you write a line of code

Run all prior session tests:

```bash
cd oster
swipl -g "run_tests" -t halt tests/log_tests.pl
swipl -g "run_tests" -t halt tests/provenance_tests.pl
swipl -g "run_tests" -t halt tests/gate_tests.pl
swipl -g "run_tests" -t halt tests/fixpoint_tests.pl
```

All tests must pass. If any fail, stop and report — do not proceed.

---

## Testing convention (established Session 3, in force for all sessions)

PLUnit runs test bodies in an isolated module (`plunit_*`). Any `assertz/1`
call inside a test body targeting a dynamic fact owned by an engine module must
be module-qualified: `assertz(scenes:scene_rule(...))`,
`assertz(gates:gate(...))`, etc. The `reset_engine` helper in `setup(...)`
blocks is unaffected.

---

## Context: what this session builds

The engine can now run. Events arrive, rules fire, gates propagate, the fixpoint
stabilises. But there is currently no way to ask the engine what it knows how to
do — what events a scene responds to, what gates lead out of it — without
reading the raw dynamic facts directly.

Probes are the answer to that question. A probe is a shallow, read-only
vocabulary query: given a scene, what rule consequences are declared for it, and
what gates lead out of it? One step, no deeper. No gate conditions evaluated. No
log read. No side effects of any kind.

The guide is precise about what probes are not allowed to do:

> A probe does not log events, does not trigger rule evaluation, does not
> advance the clock, and does not alter any fact in the database. It is a
> read-only inspection of declared structure, not an action.

This session is short — one file, one test file, tightly bounded. The value is
in getting the invariants exactly right: a probe that accidentally reads
`arrived/5`, or that leaves any trace, is not a probe.

---

## Files to create

```
oster/
├── engine/
│   └── probes.pl          ← new
└── tests/
    └── probe_tests.pl     ← new
```

No existing files are modified in this session.

---

## Specification

### `engine/probes.pl`

```prolog
:- use_module(scenes).
:- use_module(gates).
```

Note the imports: `probes.pl` imports `scenes` and `gates` only. It does not
import `log`, `clock`, `provenance`, or `fixpoint`. This is enforced by the
side-effect tests — if a probe accidentally calls anything from those modules,
the tests will catch it.

---

#### `probe/2`

```prolog
probe(Scene, vocab(RuleHeads, OutgoingGates)) :-
    findall(Template,
            scene_rule(_, Scene, _, Template),
            RuleHeads),
    findall(gate_info(GateId, DestScene, Direction),
            gate(GateId, Scene, DestScene, Direction),
            OutgoingGates).
```

Returns the vocabulary surface of a scene as a `vocab/2` term:

- `RuleHeads` — the list of `ConsequenceEventTemplate` terms from all
  `scene_rule(_, Scene, _, Template)` facts for this scene. One entry per rule.
  Templates are returned as-is, uninstantiated variables included. They are
  not evaluated.
- `OutgoingGates` — the list of `gate_info(GateId, DestScene, Direction)` terms
  for all gates originating from this scene. Gate conditions are not evaluated
  (D10) — a gate appears in this list whether its conditions are currently open
  or closed.

If the scene has no rules and no gates, returns `vocab([], [])`.

`probe/2` must not call `arrived/5`, `inject_event/3`, `advance_clock/0`,
`advance_world/1`, `assertz/1`, or `retract/1`. The implementation above
satisfies this — do not add calls to those predicates.

---

#### `probe_reachable/2`

```prolog
probe_reachable(Scene, EventShape) :-
    probe(Scene, vocab(RuleHeads, OutgoingGates)),
    (   member(Template, RuleHeads),
        \+ \+ EventShape = Template    % unify without binding caller's variables
    ;   member(gate_info(_, _, _), OutgoingGates),
        % EventShape could cross any outgoing gate — depth 1 only
        true
    ).
```

Succeeds if `EventShape` unifies with any rule head in the scene's vocabulary,
or if any outgoing gate exists (any event could potentially cross it — we do not
evaluate what the gate accepts at depth 1).

**Note on `\+ \+` unification:** `probe_reachable/2` must not bind variables in
the caller's `EventShape`. The double negation `\+ \+ EventShape = Template`
checks unifiability without committing the binding. This preserves the
side-effect-free contract.

**Note on gate reachability:** At depth 1, any event shape is considered
reachable through any outgoing gate. A deeper analysis (what events does the
destination scene accept?) would require recursion into the destination scene's
vocabulary, which is explicitly out of scope for probes. If this behaviour seems
too permissive for a specific use case, that is an authoring concern, not an
engine bug.

---

#### `probe_vocabulary/2`

```prolog
probe_vocabulary(Scene, Templates) :-
    probe(Scene, vocab(Templates, _)).
```

Convenience predicate. Returns only the rule head templates, discarding gate
info.

---

#### `probe_gates/2`

```prolog
probe_gates(Scene, GateInfos) :-
    probe(Scene, vocab(_, GateInfos)).
```

Convenience predicate. Returns only the outgoing gate info, discarding rule
heads.

---

### `reset_engine` for probe tests

Probe tests do not need the full `reset_engine` — probes read declared
structure, not the log. However, they do need scenes, rules, and gates to be
reset between tests. Define this lighter helper in `probe_tests.pl`:

```prolog
reset_declarations :-
    retractall(scenes:scene(_)),
    retractall(scenes:scene_parent(_, _)),
    retractall(scenes:scene_rule(_, _, _, _)),
    retractall(gates:gate(_, _, _, _)),
    retractall(gates:gate_condition(_, _)),
    retractall(gates:gate_transform(_, _, _)).
```

Note: no log, clock, or counter resets needed. Use `reset_declarations` in
`setup(...)` blocks for all probe tests.

---

## Tests: `tests/probe_tests.pl`

```prolog
:- use_module(library(plunit)).
:- use_module('../engine/scenes').
:- use_module('../engine/gates').
:- use_module('../engine/probes').
:- use_module('../engine/log').    % for log_count/1 and clock_value/1 only
:- use_module('../engine/clock').  % for clock_value/1 only
```

**Required test cases:**

**T1 — Empty scene returns empty vocabulary**
Declare scene `empty_room`. Call `probe(empty_room, V)`. Assert
`V = vocab([], [])`.

**T2 — Rule heads returned**
Declare scene `deck`. Declare rules with consequences `drawn(card(1))` and
`shuffled`. Call `probe(deck, vocab(Heads, _))`. Assert both `drawn(card(1))`
and `shuffled` appear in `Heads`.

**T3 — Outgoing gates returned**
Declare scenes `patron`, `tavern`. Declare gate `g_up` from `patron` to
`tavern`, direction `upward`. Call `probe(patron, vocab(_, Gates))`. Assert
`gate_info(g_up, tavern, upward)` appears in `Gates`.

**T4 — Closed gate still appears in probe results**
Declare gate `g_closed` from `patron` to `tavern` with condition
`assertz(gates:gate_condition(g_closed, fail))`. Call
`probe(patron, vocab(_, Gates))`. Assert `gate_info(g_closed, tavern, _)`
appears in `Gates`. Gate conditions are not evaluated (D10).

**T5 — probe does not alter log count**
Declare a scene with rules and gates. Record `log_count(Before)`. Call
`probe/2` three times. Record `log_count(After)`. Assert `Before =:= After`.

**T6 — probe does not alter clock**
Record `clock_value(Before)`. Call `probe/2` on any scene. Record
`clock_value(After)`. Assert `Before =:= After`.

**T7 — probe called twice returns identical results**
Declare a scene with two rules and one gate. Call `probe(Scene, V1)`. Call
`probe(Scene, V2)`. Assert `V1 = V2`.

**T8 — probe_reachable: rule head match**
Declare scene `warrior` with rule consequence `defeated`. Call
`probe_reachable(warrior, defeated)`. Assert it succeeds.

**T9 — probe_reachable: no match**
Declare scene `warrior` with rule consequence `defeated` and no gates. Call
`probe_reachable(warrior, invisible)`. Assert it fails.

**T10 — probe_reachable: gate present means reachable**
Declare scene `patron` with no rules but with one outgoing gate. Call
`probe_reachable(patron, anything)`. Assert it succeeds — any event shape is
reachable at depth 1 if a gate exists.

**T11 — probe_reachable does not bind caller variables**
Declare scene `deck` with rule consequence `drawn(Card)` where `Card` is
unbound in the template. Call `probe_reachable(deck, drawn(X))` where `X` is
unbound. Assert it succeeds. Assert `X` remains unbound after the call.

**T12 — probe_vocabulary convenience predicate**
Declare scene `room` with two rules. Call `probe_vocabulary(room, Templates)`.
Assert both rule consequence templates appear in `Templates` and nothing else.

**T13 — probe_gates convenience predicate**
Declare scene `room` with two outgoing gates. Call `probe_gates(room, Gates)`.
Assert both `gate_info` terms appear in `Gates` and nothing else.

---

## Design decisions in force for this session

**D10 — Probe visibility vs. permission.** Gate conditions are not evaluated by
`probe/2`. A gate appears in probe results regardless of whether it is currently
open. The probe answers reachability, not permission.

---

## Constraints

- `probes.pl` must not import `log`, `clock`, `provenance`, or `fixpoint`.
- `probe/2` must not call `arrived/5`, `inject_event/3`, `advance_clock/0`,
  `advance_world/1`, `assertz/1`, or `retract/1`. T5 and T6 verify this
  behaviourally; treat any violation as a bug.
- `probe_reachable/2` must not bind variables in its `EventShape` argument.
  T11 verifies this.
- Do not modify any existing engine or test file.
- All predicate names must match the specification exactly.

---

## Acceptance criteria

The session is complete when:

1. `swipl -g "run_tests" -t halt tests/log_tests.pl` — all 9 pass.
2. `swipl -g "run_tests" -t halt tests/provenance_tests.pl` — all 11 pass.
3. `swipl -g "run_tests" -t halt tests/gate_tests.pl` — all 13 pass.
4. `swipl -g "run_tests" -t halt tests/fixpoint_tests.pl` — all 13 pass.
5. `swipl -g "run_tests" -t halt tests/probe_tests.pl` — all 13 pass.
6. No `arrived/5` fact is retracted at any point during any test run.
7. `docs/session_logs/session_05.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_05.md`:

```
# Session 5 Report — Probes

## Files created
- engine/probes.pl
- tests/probe_tests.pl

## Files modified
(none)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed
- tests/fixpoint_tests.pl: 13 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed

## Stubs left for future sessions
(none expected)

## Anomalies, surprises, questions
(anything unexpected encountered during implementation)
```

Do not produce the report until all tests pass.

---

## Ambiguity resolution

If something is unclear: session prompt first, then `docs/implementation_plan.md`,
then `docs/conceptual_guide.md`. If genuine ambiguity remains, make the most
conservative choice and leave a `% DECISION:` comment.
