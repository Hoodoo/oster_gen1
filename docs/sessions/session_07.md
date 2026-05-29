# Session 7 — Projections

## What this session is

You are building Session 7 of the Oster implementation. You are building only
what is listed here. Do not read ahead or implement anything from future
sessions.

At the end of this session, all tests must be green, the session report must be
written to `docs/session_logs/session_07.md`, and no files outside the listed
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
swipl -g "run_tests" -t halt tests/probe_tests.pl
swipl -g "run_tests" -t halt tests/lifecycle_tests.pl
```

All tests must pass. If any fail, stop and report — do not proceed.

---

## Testing convention (in force for all sessions)

PLUnit runs test bodies in an isolated module (`plunit_*`). Any `assertz/1`
or `retractall/1` call inside a test body targeting a dynamic fact owned by an
engine module must be module-qualified. The `reset_engine` helper in
`setup(...)` blocks is unaffected.

---

## Clarification: `arrived/5` fifth argument (C-001)

The `Tier` argument in `arrived(EventId, Scene, Term, Clock, Tier)` is always
written as `hot` by `inject_event/3` and **never updated**. Current tier is
tracked exclusively in `tier_status(EventId, Tier)`. Do not query the fifth
argument of `arrived/5` to determine current tier — use `tier_status/2`
instead. This affects `post_fixpoint_summary/2` directly; see the specification
below.

---

## Context: what this session builds

Sessions 1–6 built the engine and its lifecycle layer. Everything works but
nothing is easily queryable from the outside. Raw Prolog facts are there for
anyone who knows how to ask — but an interface layer, a player, or an AI
collaborator needs structured answers to specific questions.

This session builds the four named projections the guide specifies as
first-class predicates. They are the engine's answer to:

- **What can I do here?** — `legal_actions/2`
- **Why didn't that work?** — `why_blocked/3`
- **What just happened?** — `post_fixpoint_summary/2`
- **Why does this fact exist?** — `investigation_chain/2`

These are not one-off queries. They are named, tested, stable predicates that
every future layer — the REPL, catalog tests, and eventually any interface —
will call. Get the interfaces right; the implementations can be refined later.

---

## Files to create

```
oster/
├── projections/
│   ├── legal_actions.pl    ← new
│   ├── why_blocked.pl      ← new
│   ├── post_fixpoint.pl    ← new
│   └── investigation.pl    ← new
└── tests/
    └── projection_tests.pl ← new
```

No existing files are modified in this session.

---

## Specification

### `projections/legal_actions.pl`

```prolog
:- use_module('../engine/gates').
:- use_module('../engine/probes').
```

#### `legal_actions/2`

```prolog
legal_actions(Scene, Actions) :-
    findall(
        action(GateId, DestScene, EventShape),
        (   gate(GateId, Scene, DestScene, _),
            gate_open(GateId),
            probe(DestScene, vocab(RuleHeads, _)),
            member(EventShape, RuleHeads)
        ),
        Actions
    ).
```

Returns the list of `action(GateId, DestScene, EventShape)` terms representing
events that are currently reachable and permitted from `Scene`. An action
appears in the list only if:

1. A gate exists from `Scene` to some `DestScene`.
2. That gate is currently open (`gate_open/1` succeeds).
3. The destination scene has a rule head that unifies with `EventShape`.

If a scene has open gates but the destination scene has no rules, no actions are
returned for those gates. If a scene has no open gates, returns `[]`.

**Note:** `legal_actions/2` answers "what is currently permitted and
vocabularised." It does not answer "what will definitely succeed" — gate
conditions can change between the query and the injection. It is a planning
aid, not a guarantee.

---

### `projections/why_blocked.pl`

```prolog
:- use_module('../engine/gates').
:- use_module('../engine/clock').
```

#### `why_blocked/3`

```prolog
why_blocked(Scene, EventTerm, Explanation) :-
    ( gate(GateId, Scene, _, _) ->
        ( \+ gate_open(GateId) ->
            first_failing_condition(GateId, EventTerm, Explanation)
        ;
            Explanation = gate_is_open(GateId)
        )
    ;
        Explanation = no_gate(Scene, EventTerm)
    ).
```

Returns an `Explanation` term describing why `EventTerm` is blocked from
`Scene`. Three cases:

- `no_gate(Scene, EventTerm)` — no gate exists from `Scene` that could carry
  `EventTerm`. The event shape is not connected to any outgoing path.
- `blocked_by(GateId, ConditionGoal)` — a gate exists but a specific condition
  is failing. Returns the first failing condition.
- `gate_is_open(GateId)` — a gate exists and is currently open. The event is
  not blocked at the gate level; if the action still failed, the cause is
  elsewhere (e.g. rule grounding).

#### `first_failing_condition/3`

```prolog
first_failing_condition(GateId, _EventTerm, blocked_by(GateId, Cond)) :-
    gate_condition(GateId, Cond),
    \+ call(Cond),
    !.
first_failing_condition(GateId, _EventTerm, blocked_by(GateId, unknown)) :-
    \+ gate_open(GateId).
```

Finds the first `gate_condition` for `GateId` that fails and returns it as the
explanation. The cut after the first match ensures only one failing condition is
reported. If no specific condition can be identified (the gate is closed but
`gate_condition` has no facts), returns `blocked_by(GateId, unknown)`.

#### `why_blocked_history/3`

```prolog
why_blocked_history(GateId, EventId, Clock) :-
    gate_blocked(GateId, EventId, Clock).
```

Read-only query over historical block records. Succeeds for each historical
blocking of `GateId`. Used by the REPL's `:why` command (Session 12) to show
blocking history, not just the current state.

---

### `projections/post_fixpoint.pl`

```prolog
:- use_module('../engine/log').
:- use_module('../engine/provenance').
```

#### `post_fixpoint_summary/2`

```prolog
post_fixpoint_summary(Clock, Summary) :-
    findall(
        change(Scene, Term, Cause),
        (   arrived(EventId, Scene, Term, Clock, _),
            tier_status(EventId, hot),
            caused_by(EventId, Cause)
        ),
        Unsorted
    ),
    msort(Unsorted, Summary).
```

Collects all hot events that arrived at `Clock`, pairs each with its provenance,
and returns them sorted by scene. The sort is by the full term — events from the
same scene will group together.

**Important:** This predicate joins `arrived/5` with `tier_status/2` rather than
matching on the fifth argument of `arrived/5` (C-001). Only events currently
marked `hot` in `tier_status` are included — events promoted to cold since
arrival are excluded. This is correct: `post_fixpoint_summary` reports what is
live at the time of the query, not what was live at injection.

`msort/2` is used rather than `sort/2` to preserve duplicate terms if they
arrive in different scenes.

---

### `projections/investigation.pl`

```prolog
:- use_module('../engine/log').
:- use_module('../engine/provenance').
```

#### `investigation_chain/2`

```prolog
investigation_chain(EventId, Chain) :-
    arrived(EventId, Scene, Term, _Clock, _),
    provenance_chain(EventId, ProvenanceSteps),
    enrich_chain(ProvenanceSteps, Scene, Term, Chain).

enrich_chain([], _Scene, _Term, []).
enrich_chain([step(EId, Cause)|Rest], _Scene, _Term, [step(EId, S, T, Cause)|Enriched]) :-
    ( arrived(EId, S, T, _, _) -> true ; S = unknown, T = unknown ),
    enrich_chain(Rest, _, _, Enriched).
```

Traverses the provenance chain from `EventId` back to its root, enriching each
step with the scene and term from `arrived/5`. Returns a list of
`step(EventId, Scene, Term, Cause)` terms.

Deliberately reads across all tiers — hot, cold, and archived — because
investigation queries need complete history. This is the intended behaviour and
the known cost. A rule consulting cold or archived history pays a real access
cost; `investigation_chain/2` accepts this cost explicitly.

If an `EventId` in the provenance chain has no corresponding `arrived/5` fact
(e.g. `unknown_gate_source/1` terminal from Session 4), the step records
`step(EId, unknown, unknown, Cause)` rather than failing. This preserves the
chain's structure at the cost of some information at untransformed gate hops —
see `docs/deferred.md` I-001.

#### `chain_root/2`

```prolog
chain_root(EventId, RootEventId) :-
    investigation_chain(EventId, Chain),
    last(Chain, step(RootEventId, _, _, _)).
```

Convenience predicate. Returns the `EventId` at the root of the causal chain —
the original injected event.

---

### `reset_engine` for projection tests

Define this version in `projection_tests.pl`. Identical to the Session 6
version — no new dynamic facts were added in this session:

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
    retractall(fixpoint:rule_trigger(_, _, _)),
    retractall(fixpoint:fixpoint_depth_exceeded(_)),
    retractall(fixpoint:rule_grounding_failed(_, _)),
    retractall(log:event_counter(_)), assertz(log:event_counter(0)),
    retractall(log:clock_counter(_)), assertz(log:clock_counter(0)).
```

---

## Tests: `tests/projection_tests.pl`

```prolog
:- use_module(library(plunit)).
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/provenance').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').
:- use_module('../engine/probes').
:- use_module('../lifecycle/tiers').
:- use_module('../projections/legal_actions').
:- use_module('../projections/why_blocked').
:- use_module('../projections/post_fixpoint').
:- use_module('../projections/investigation').
```

**Required test cases:**

**T1 — legal_actions: open gate with vocabulary**
Declare scenes `patron`, `tavern`. Declare open gate `g_up` from `patron` to
`tavern`. Declare rule `r_noise` in `tavern` with consequence `noise(fight)`.
Call `legal_actions(patron, Actions)`. Assert `action(g_up, tavern, noise(fight))`
appears in `Actions`.

**T2 — legal_actions: closed gate excluded**
Same world as T1 but add `assertz(gates:gate_condition(g_up, fail))`. Call
`legal_actions(patron, Actions)`. Assert `Actions = []`.

**T3 — legal_actions: no gates returns empty**
Declare scene `isolated` with no gates. Call `legal_actions(isolated, Actions)`.
Assert `Actions = []`.

**T4 — why_blocked: no gate**
Declare scene `room` with no gates. Call
`why_blocked(room, any_event, Explanation)`. Assert
`Explanation = no_gate(room, any_event)`.

**T5 — why_blocked: gate closed, condition identified**
Declare scenes `src`, `dst`. Declare gate `g_check` from `src` to `dst`.
Add `assertz(gates:gate_condition(g_check, fail))`. Call
`why_blocked(src, signal, Explanation)`. Assert
`Explanation = blocked_by(g_check, fail)`.

**T6 — why_blocked: gate open**
Declare gate `g_open` from `src` to `dst` with no conditions. Call
`why_blocked(src, signal, Explanation)`. Assert
`Explanation = gate_is_open(g_open)`.

**T7 — why_blocked_history**
Declare gate `g_blocked` from `src` to `dst` with condition `fail`. Inject
`signal` into `src`. Call `attempt_propagation(EventId, g_blocked)`. Call
`why_blocked_history(g_blocked, EventId, _Clock)`. Assert it succeeds.

**T8 — post_fixpoint_summary: correct clock**
Inject event `alpha` into scene `room`. Call `advance_clock`. Inject event
`beta` into `room`. Call `post_fixpoint_summary(1, Summary)`. Assert `Summary`
contains `change(room, alpha, _)`. Assert `Summary` does not contain
`change(room, beta, _)` — `beta` arrived at clock 1, `alpha` at clock 0.

**T9 — post_fixpoint_summary: excludes cold events**
Inject two events into `room`. Call `promote_to_cold(room, 99)`. Call
`post_fixpoint_summary(0, Summary)`. Assert `Summary = []` — all events at
clock 0 are now cold, none are hot.

**T10 — post_fixpoint_summary: includes cause**
Inject `trigger` into `room` with `injected(player)`. Call
`post_fixpoint_summary(0, Summary)`. Assert `Summary` contains
`change(room, trigger, injected(player))`.

**T11 — investigation_chain: single hop**
Inject `signal` into `room` with cause `injected(player)`. Find `EventId`.
Call `investigation_chain(EventId, Chain)`. Assert
`Chain = [step(EventId, room, signal, injected(player))]`.

**T12 — investigation_chain: multi-hop through rule**
Declare scene `room` with rule `r_echo`: conditions
`arrived(_, room, signal, _, hot)`, consequence `echo`. Inject `signal`. Call
`world_step`. Find `EchoId` via `arrived_key(room, echo, _, EchoId)`. Call
`investigation_chain(EchoId, Chain)`. Assert the chain contains both the `echo`
step and the `signal` step, with the `signal` step showing
`injected(player)` cause.

**T13 — investigation_chain: reads cold events**
Inject `signal` into `room`. Find `EventId`. Call `promote_to_cold(room, 99)`.
Call `investigation_chain(EventId, Chain)`. Assert it succeeds and returns a
non-empty chain. Cold events must remain traversable.

**T14 — chain_root: returns root event**
Using state from T12: call `chain_root(EchoId, RootId)`. Assert `RootId` is
the `EventId` of the original `signal` injection.

**T15 — post_fixpoint_summary sorted by scene**
Inject events into scenes `z_scene` and `a_scene`. Call
`post_fixpoint_summary(0, Summary)`. Assert events from `a_scene` appear before
events from `z_scene` in the list — `msort/2` sorts by full term, and
`change(a_scene, ...)` sorts before `change(z_scene, ...)`.

---

## Design decisions in force for this session

**C-001 — `arrived/5` fifth argument is immutable.** Never query the fifth
argument to determine current tier. Always use `tier_status(EventId, Tier)`.
`post_fixpoint_summary/2` joins on `tier_status` for this reason.

**I-001 — Untransformed gate hops in investigation chains.** When
`investigation_chain/2` reaches an `unknown_gate_source(GateId)` terminal, it
records `step(EId, unknown, unknown, Cause)` and continues. Do not fail. Do not
attempt to look up the source event by any other means. See `docs/deferred.md`.

---

## Constraints

- The four projection modules must not import each other.
- `legal_actions.pl` imports only `gates` and `probes`.
- `why_blocked.pl` imports only `gates` and `clock`.
- `post_fixpoint.pl` imports only `log` and `provenance`.
- `investigation.pl` imports only `log` and `provenance`.
- Do not modify any existing engine, lifecycle, or test file.
- All predicate names must match the specification exactly.

---

## Acceptance criteria

The session is complete when:

1. `swipl -g "run_tests" -t halt tests/log_tests.pl` — all 9 pass.
2. `swipl -g "run_tests" -t halt tests/provenance_tests.pl` — all 11 pass.
3. `swipl -g "run_tests" -t halt tests/gate_tests.pl` — all 13 pass.
4. `swipl -g "run_tests" -t halt tests/fixpoint_tests.pl` — all 13 pass.
5. `swipl -g "run_tests" -t halt tests/probe_tests.pl` — all 13 pass.
6. `swipl -g "run_tests" -t halt tests/lifecycle_tests.pl` — all 13 pass.
7. `swipl -g "run_tests" -t halt tests/projection_tests.pl` — all 15 pass.
8. No `arrived/5` fact is retracted at any point during any test run.
9. `docs/session_logs/session_07.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_07.md`:

```
# Session 7 Report — Projections

## Files created
- projections/legal_actions.pl
- projections/why_blocked.pl
- projections/post_fixpoint.pl
- projections/investigation.pl
- tests/projection_tests.pl

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
