# Session 16: Tavern Hierarchy Reorg and Window Event-Sourcing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce `world` as the explicit root scene, make `street` a sibling of `tavern`, and replace the `window_open/1` dynamic fact with log-based event sourcing for window state.

**Architecture:** Four files change: `scene.pl` gains `world` as root and a `window_is_open/1` projection; `gates.pl` updates the direction label to `lateral` and adds a term filter; `tests.pl` updates five tests and adds one new; `repl.pl` drops the now-obsolete `assertz(window_open)`.

**Tech Stack:** SWI-Prolog, PLUnit test framework

## Global Constraints

- Working directory: `/home/hoooo/AISlop/codex/oster_gen1` (project root — there is no `oster/` subdirectory despite what the session prompt's `cd oster` suggests)
- Do NOT modify any engine, projection, lifecycle, or verify file
- Do NOT modify `catalog/deck/` or `catalog/warrior/`
- `scene.pl` must not declare any gates
- `gates.pl` must not declare any rules
- The `world` scene must have no rules and no outgoing gates
- `window_open/1` must not appear anywhere in the codebase after this session

---

### Task 1: Run Baseline Tests

**Files:**
- (read-only verification — no file modifications)

**Interfaces:**
- Produces: confirmation that all 11 test suites pass before any code is touched

- [ ] **Step 1: Run all test suites**

```bash
cd /home/hoooo/AISlop/codex/oster_gen1
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

Expected: All pass. If any fail, STOP and report — do not proceed.

---

### Task 2: Modify `catalog/tavern/scene.pl`

**Files:**
- Modify: `catalog/tavern/scene.pl`

**Interfaces:**
- Produces: `window_is_open/1` exported predicate; `declare_tavern_world/0` now declares `world` as root and injects `window_opened` at setup

- [ ] **Step 1: Replace the module declaration (remove `window_open/1`, add `window_is_open/1`)**

In `catalog/tavern/scene.pl`, replace lines 1–6:

Old:
```prolog
:- module(tavern_scene, [
    declare_tavern_world/0,
    declare_patron/1,
    declare_street/0,
    window_open/1
]).
```

New:
```prolog
:- module(tavern_scene, [
    declare_tavern_world/0,
    declare_patron/1,
    declare_street/0,
    window_is_open/1
]).
```

- [ ] **Step 2: Remove the `window_open/1` dynamic declaration and its comments**

Delete lines 13–16 entirely:
```prolog
:- dynamic window_open/1.
% window_open(TavernScene)
% Asserted by authoring code to open the window, allowing noise to reach the street.
% Retracted to close it.
```

- [ ] **Step 3: Replace `declare_tavern_world/0`**

Replace the existing predicate (currently lines 18–28):

Old:
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

New:
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

- [ ] **Step 4: Add `window_is_open/1` predicate at end of file**

Append after `declare_street/0`:
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

- [ ] **Step 5: Verify the file looks correct**

Full expected content of `catalog/tavern/scene.pl` after changes:

```prolog
:- module(tavern_scene, [
    declare_tavern_world/0,
    declare_patron/1,
    declare_street/0,
    window_is_open/1
]).

:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/fixpoint').

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

declare_patron(PatronScene) :-
    declare_scene(PatronScene),
    declare_patron_rules(PatronScene).

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

declare_street_rules :-
    declare_scene_rule(
        rule_guards_alerted,
        street,
        arrived(_, street, noise(fight), _, _),
        guards_alerted
    ).

declare_street :-
    declare_scene(street),
    declare_street_rules.

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

---

### Task 3: Modify `catalog/tavern/gates.pl`

**Files:**
- Modify: `catalog/tavern/gates.pl`

**Interfaces:**
- Consumes: `window_is_open/1` from `scene` (Task 2)
- Produces: `tavern_noise_to_street` gate with `lateral` direction and `noise(fight)` term filter

- [ ] **Step 1: Replace the `window_open/1` import with `window_is_open/1`**

Old (line 10):
```prolog
:- use_module(scene, [window_open/1]).
```

New:
```prolog
:- use_module(scene, [window_is_open/1]).
```

- [ ] **Step 2: Replace `declare_tavern_gates/0`**

Old:
```prolog
declare_tavern_gates :-
    % Inward gates: patron noise propagates upward to tavern
    declare_gate(patron_a_noise_to_tavern, patron_a, tavern, upward),
    declare_gate(patron_b_noise_to_tavern, patron_b, tavern, upward),
    % Term filter: only noise(fight) crosses the inward gates.
    % Without this filter, all patron events (including strike/taunt)
    % would appear in the tavern log, violating D8.
    declare_gate_term_filter(patron_a_noise_to_tavern, noise(fight)),
    declare_gate_term_filter(patron_b_noise_to_tavern, noise(fight)),

    % Outward gate: tavern noise propagates downward to street
    declare_gate(tavern_noise_to_street, tavern, street, downward),
    % Condition: window must be open
    % NOTE: window_open(tavern) is a plain dynamic fact, not an event.
    % This is a design tradeoff: authoring code asserts/retracts it directly.
    % The alternative — modelling window state as an event — is architecturally
    % cleaner but out of scope for this entry.
    assertz(gates:gate_condition(
        tavern_noise_to_street,
        tavern_scene:window_open(tavern)
    )).
```

New:
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

- [ ] **Step 3: Verify the file looks correct**

Full expected content of `catalog/tavern/gates.pl`:
```prolog
:- encoding(utf8).
:- module(tavern_gates, [
    declare_tavern_gates/0
]).

:- use_module('../../engine/gates').
% DECISION: spec says use_module(tavern_scene, ...) but the file is scene.pl.
% Using use_module(scene, ...) — relative to this file's directory — matching
% the warrior catalog pattern (catalog/warrior/tests.pl uses scene the same way).
:- use_module(scene, [window_is_open/1]).

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

---

### Task 4: Modify `repl/repl.pl`

**Files:**
- Modify: `repl/repl.pl`

**Interfaces:**
- Consumes: `declare_tavern_world/0` now injects `window_opened` internally — no external assertion needed

- [ ] **Step 1: Remove the `window_open/1` import from the module use_module line**

Old (lines 16–17):
```prolog
:- use_module('../catalog/tavern/scene',  [declare_tavern_world/0,
                                           window_open/1]).
```

New:
```prolog
:- use_module('../catalog/tavern/scene',  [declare_tavern_world/0]).
```

- [ ] **Step 2: Remove `assertz(tavern_scene:window_open(tavern))` from `load_world/0`**

Old (lines 61–66):
```prolog
load_world :-
    declare_tavern_world,
    declare_tavern_gates,
    assertz(tavern_scene:window_open(tavern)),
    register_projections,
    format("World loaded: tavern (patron_a, patron_b, street, window open)~n").
```

New:
```prolog
load_world :-
    declare_tavern_world,
    declare_tavern_gates,
    register_projections,
    format("World loaded: tavern (patron_a, patron_b, street, window open)~n").
```

---

### Task 5: Modify `catalog/tavern/tests.pl`

**Files:**
- Modify: `catalog/tavern/tests.pl`

**Interfaces:**
- Consumes: `window_is_open/1` from `scene` (Task 2); new hierarchy from Task 2; `lateral` gate direction from Task 3

- [ ] **Step 1: Remove `window_open/1` from the import and `reset_engine` cleanup**

Old import (lines 14–17):
```prolog
:- use_module(scene, [
    declare_tavern_world/0,
    window_open/1
]).
```

New:
```prolog
:- use_module(scene, [
    declare_tavern_world/0
]).
```

Old `reset_engine` line (line 41):
```prolog
    retractall(tavern_scene:window_open(_)),
```

Delete that line entirely (the window state is in the event log, already cleared by `retractall(log:arrived(...))`).

- [ ] **Step 2: Replace T1 to verify new hierarchy**

Old T1 (lines 52–59):
```prolog
% T1 — scene hierarchy declared correctly
test(t1_scene_hierarchy, [setup(reset_engine)]) :-
    setup_tavern,
    scenes:scene_type(tavern, composite),
    scenes:scene_type(patron_a, leaf),
    scenes:scene_type(patron_b, leaf),
    scenes:scene_type(street, leaf),
    scenes:scene_parent(patron_a, tavern),
    scenes:scene_parent(street, tavern).
```

New:
```prolog
% T1 — scene hierarchy declared correctly
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

- [ ] **Step 3: Replace T5 to use event-based window close**

Old T5 (lines 84–89):
```prolog
% T5 — noise blocked at street when window closed
test(t5_noise_blocked_window_closed, [setup(reset_engine)]) :-
    setup_tavern,
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    \+ log:arrived(_, street, noise(fight), _, _),
    gates:gate_blocked(tavern_noise_to_street, _, _).
```

New:
```prolog
% T5 — noise blocked at street when window closed
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

- [ ] **Step 4: Replace T6 to use injected setup state (no assertz needed)**

Old T6 (lines 92–99):
```prolog
% T6 — noise reaches street when window open
test(t6_noise_reaches_street_window_open, [setup(reset_engine)]) :-
    setup_tavern,
    assertz(tavern_scene:window_open(tavern)),
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    log:arrived(_, patron_a, noise(fight), _, _),
    log:arrived(_, tavern, noise(fight), _, _),
    log:arrived(_, street, noise(fight), _, _).
```

New:
```prolog
% T6 — noise reaches street when window open
test(t6_noise_reaches_street_window_open, [setup(reset_engine)]) :-
    setup_tavern,
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    log:arrived(_, patron_a, noise(fight), _, _),
    log:arrived(_, tavern, noise(fight), _, _),
    log:arrived(_, street, noise(fight), _, _).
```

- [ ] **Step 5: Replace T7 to remove `assertz(window_open)`**

Old T7 (lines 101–107):
```prolog
% T7 — guards_alerted fires when noise reaches street
test(t7_guards_alerted, [setup(reset_engine)]) :-
    setup_tavern,
    assertz(tavern_scene:window_open(tavern)),
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    log:arrived(_, street, guards_alerted, _, _).
```

New:
```prolog
% T7 — guards_alerted fires when noise reaches street
test(t7_guards_alerted, [setup(reset_engine)]) :-
    setup_tavern,
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    log:arrived(_, street, guards_alerted, _, _).
```

- [ ] **Step 6: Replace T8 to remove `assertz(window_open)`**

Old T8 (lines 109–117):
```prolog
% T8 — D8: strike does NOT appear in tavern log
% The inward gate term filter (noise(fight)) blocks strike(5) from crossing
% to tavern. Only noise(fight) — the patron rule's consequence — arrives there.
test(t8_d8_strike_not_in_tavern, [setup(reset_engine)]) :-
    setup_tavern,
    assertz(tavern_scene:window_open(tavern)),
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    \+ log:arrived(_, tavern, strike(5), _, _).
```

New:
```prolog
% T8 — D8: strike does NOT appear in tavern log
% The inward gate term filter (noise(fight)) blocks strike(5) from crossing
% to tavern. Only noise(fight) — the patron rule's consequence — arrives there.
test(t8_d8_strike_not_in_tavern, [setup(reset_engine)]) :-
    setup_tavern,
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    \+ log:arrived(_, tavern, strike(5), _, _).
```

- [ ] **Step 7: Replace T10 to use event-based window toggle**

Old T10 (lines 129–141):
```prolog
% T10 — window closed after being open: noise blocked again
test(t10_window_toggles, [setup(reset_engine)]) :-
    setup_tavern,
    assertz(tavern_scene:window_open(tavern)),
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,       % clock 1: noise reaches street (window open)
    log:arrived(_, street, noise(fight), _, _),
    fixpoint:world_step,       % advance clock (window still open)
    retractall(tavern_scene:window_open(_)),
    log:inject_event(patron_b, strike(5), injected(player)),
    fixpoint:world_step,       % patron_b's noise blocked at street (window closed)
    clock:clock_value(FinalClock),
    \+ log:arrived(_, street, noise(fight), FinalClock, _),
    gates:gate_blocked(tavern_noise_to_street, _, _).
```

New:
```prolog
% T10 — window closed after being open: noise blocked again
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

- [ ] **Step 8: Replace T11 to remove `assertz(window_open)`**

Old T11 (lines 143–154):
```prolog
% T11 — two patrons both contribute noise to tavern
test(t11_two_patrons_contribute, [setup(reset_engine)]) :-
    setup_tavern,
    assertz(tavern_scene:window_open(tavern)),
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,       % clock 1: patron_a noise in tavern
    log:inject_event(patron_b, taunt, injected(player)),
    fixpoint:world_step,       % clock 2: patron_b noise in tavern
    % Two noise(fight) events in tavern at different clock ticks
    log:arrived(_, tavern, noise(fight), C1, _),
    log:arrived(_, tavern, noise(fight), C2, _),
    C1 \= C2.
```

New:
```prolog
% T11 — two patrons both contribute noise to tavern
test(t11_two_patrons_contribute, [setup(reset_engine)]) :-
    setup_tavern,
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,       % clock 1: patron_a noise in tavern
    log:inject_event(patron_b, taunt, injected(player)),
    fixpoint:world_step,       % clock 2: patron_b noise in tavern
    % Two noise(fight) events in tavern at different clock ticks
    log:arrived(_, tavern, noise(fight), C1, _),
    log:arrived(_, tavern, noise(fight), C2, _),
    C1 \= C2.
```

- [ ] **Step 9: Replace T12 to remove `assertz(window_open)`**

Old T12 (lines 156–168):
```prolog
% T12 — investigation_chain from guards_alerted traces full causal path
test(t12_investigation_chain, [setup(reset_engine)]) :-
    setup_tavern,
    assertz(tavern_scene:window_open(tavern)),
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    log:arrived(AlertedId, street, guards_alerted, _, _),
    investigation_chain(AlertedId, Chain),
    Chain \= [],
    last(Chain, step(_, _, _, injected(player))),
    member(step(_, patron_a, _, _), Chain),
    member(step(_, tavern, _, _), Chain),
    member(step(_, street, _, _), Chain).
```

New:
```prolog
% T12 — investigation_chain from guards_alerted traces full causal path
test(t12_investigation_chain, [setup(reset_engine)]) :-
    setup_tavern,
    log:inject_event(patron_a, strike(5), injected(player)),
    fixpoint:world_step,
    log:arrived(AlertedId, street, guards_alerted, _, _),
    investigation_chain(AlertedId, Chain),
    Chain \= [],
    last(Chain, step(_, _, _, injected(player))),
    member(step(_, patron_a, _, _), Chain),
    member(step(_, tavern, _, _), Chain),
    member(step(_, street, _, _), Chain).
```

- [ ] **Step 10: Replace T17 to check `lateral` direction**

Old T17 (lines 202–206):
```prolog
% T17 — probe on tavern: no rules, one outward gate
test(t17_probe_tavern, [setup(reset_engine)]) :-
    setup_tavern,
    probes:probe(tavern, vocab(Heads, Gates)),
    Heads = [],
    member(gate_info(tavern_noise_to_street, street, downward), Gates).
```

New:
```prolog
% T17 — probe on tavern: no rules, one outward gate
test(t17_probe_tavern, [setup(reset_engine)]) :-
    setup_tavern,
    probes:probe(tavern, vocab(Heads, Gates)),
    Heads = [],
    member(gate_info(tavern_noise_to_street, street, lateral), Gates).
```

- [ ] **Step 11: Add T18 after T17 (before `:- end_tests(tavern).`)**

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

---

### Task 6: Run All Tests and Verify Constraints

**Files:**
- (read-only verification)

**Interfaces:**
- Produces: confirmation that 18 tavern tests pass plus all 11 prior suites

- [ ] **Step 1: Run all test suites**

```bash
cd /home/hoooo/AISlop/codex/oster_gen1
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

Expected: All pass. Tavern suite now shows 18 tests (was 17).

- [ ] **Step 2: Verify `window_open/1` is completely gone**

```bash
grep -r window_open . --include='*.pl'
```

Expected: no output. If any hits, fix them before proceeding.

---

### Task 7: Write Session Log

**Files:**
- Create: `docs/session_logs/session_16.md`

- [ ] **Step 1: Write the session report**

Create `docs/session_logs/session_16.md` with:
- Session number and name
- Files created or modified
- Test results (18 tavern tests passed, all 11 prior suites pass, 0 failed)
- Any divergences from spec (annotate with `% DECISION:` explanation)
- Any stubs left for future sessions
- Any anomalies or questions for the human

---

### Task 8: Commit

**Files:**
- All modified files above

- [ ] **Step 1: Stage and commit**

```bash
git add catalog/tavern/scene.pl catalog/tavern/gates.pl catalog/tavern/tests.pl repl/repl.pl docs/session_logs/session_16.md docs/sessions/session_16_prompt.md
git commit -m "Session 16: Tavern hierarchy reorg and window event-sourcing"
```

Note: `docs/sessions/session_16_prompt.md` is already untracked (per git status) and must be committed per project memory (prompt files are historical record).
