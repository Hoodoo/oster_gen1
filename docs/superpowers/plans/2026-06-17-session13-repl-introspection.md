# Session 13 REPL Introspection and Renaming — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `scenes`, `gates`, `summary`, `inject/3`, and `outbound` to the REPL; rename `why` to `outbound`; fix the playtest guide.

**Architecture:** All changes are in `repl/repl.pl` (new clauses + updated help) and a new `playtest_guide.md`. No engine, projection, lifecycle, or catalog files change. `post_fixpoint_summary/2` already exists in `projections/post_fixpoint.pl` and just needs to be imported.

**Tech Stack:** SWI-Prolog modules, PLUnit for pre/post-session regression checks.

---

## Pre-flight: confirm baseline

- [ ] **Step 1: Run all 11 test suites from the project root**

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

Expected: all pass (Session 12 baseline was 151 tests, 0 failures). Stop and report if any fail.

---

## Task 1: Import post_fixpoint in repl.pl

**Files:**
- Modify: `repl/repl.pl:3-13` (import block)

- [ ] **Step 1: Add the import**

In `repl/repl.pl`, after the existing imports block (after line 13 `:- use_module('../projections/investigation').`), add:

```prolog
:- use_module('../projections/post_fixpoint').
```

The full import block should now read:

```prolog
:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').
:- use_module('../engine/probes').
:- use_module('../lifecycle/closure').
:- use_module('../projections/legal_actions').
:- use_module('../projections/why_blocked').
:- use_module('../projections/investigation').
:- use_module('../projections/post_fixpoint').
:- use_module('../verify/contracts').
```

- [ ] **Step 2: Load-check**

```bash
cd /home/hoooo/AISlop/codex/oster_gen1
swipl -g "use_module(repl/repl)" -t halt
```

Expected: exits with code 0, no errors.

---

## Task 2: Add `scenes` command

**Files:**
- Modify: `repl/repl.pl` — add two clauses before `handle_command(Unknown)`

- [ ] **Step 1: Add handle_command(scenes) and print_scene_node/2**

Insert after `handle_command(legal(Scene))` clause (currently around line 158) and before `handle_command(Unknown)`:

```prolog
handle_command(scenes) :- !,
    findall(Root, scene_root(Root), Roots),
    ( Roots == [] ->
        format("No scenes declared~n")
    ;
        format("Scenes:~n"),
        forall(member(Root, Roots), print_scene_node(Root, 0))
    ).

print_scene_node(Scene, Depth) :-
    tab(Depth * 2),
    format("~w~n", [Scene]),
    findall(Child, scene_parent(Child, Scene), Children),
    Depth1 is Depth + 1,
    forall(member(Child, Children), print_scene_node(Child, Depth1)).
```

- [ ] **Step 2: Load-check**

```bash
swipl -g "use_module(repl/repl)" -t halt
```

Expected: no errors.

---

## Task 3: Add `gates` command

**Files:**
- Modify: `repl/repl.pl` — add clause after `scenes` command

- [ ] **Step 1: Add handle_command(gates)**

Insert after `print_scene_node/2` and before `handle_command(Unknown)`:

```prolog
handle_command(gates) :- !,
    findall(g(GateId, Source, Dest, Direction),
            gate(GateId, Source, Dest, Direction),
            GateList),
    ( GateList == [] ->
        format("No gates declared~n")
    ;
        format("Gates:~n"),
        forall(
            member(g(GateId, Source, Dest, Direction), GateList),
            ( ( gate_open(GateId) -> Status = open ; Status = closed ),
              format("  ~w: ~w -> ~w (~w, ~w)~n",
                     [GateId, Source, Dest, Direction, Status])
            )
        )
    ).
```

- [ ] **Step 2: Load-check**

```bash
swipl -g "use_module(repl/repl)" -t halt
```

Expected: no errors.

---

## Task 4: Add `summary` command

**Files:**
- Modify: `repl/repl.pl` — add clause after `gates` command

- [ ] **Step 1: Add handle_command(summary)**

Insert after `handle_command(gates)` and before `handle_command(Unknown)`:

```prolog
handle_command(summary) :- !,
    clock_value(Clock),
    post_fixpoint_summary(Clock, Changes),
    ( Changes == [] ->
        format("No changes at clock ~w~n", [Clock])
    ;
        format("Changes at clock ~w:~n", [Clock]),
        forall(member(change(Scene, Term, Cause), Changes),
               format("  ~w in ~w (cause: ~w)~n", [Term, Scene, Cause]))
    ).
```

- [ ] **Step 2: Load-check**

```bash
swipl -g "use_module(repl/repl)" -t halt
```

Expected: no errors.

---

## Task 5: Add `inject/3` command

**Files:**
- Modify: `repl/repl.pl` — add new clause after existing `inject/2` clause

- [ ] **Step 1: Add handle_command(inject(Scene, Event, Source))**

The existing `inject/2` clause (around line 96) must stay byte-for-byte. Add a new clause directly after it:

```prolog
handle_command(inject(Scene, Event, Source)) :- !,
    inject_event(Scene, Event, injected(Source)),
    world_step,
    clock_value(Clock),
    format("Injected ~w into ~w (source: ~w) at clock ~w~n",
           [Event, Scene, Source, Clock]).
```

- [ ] **Step 2: Load-check**

```bash
swipl -g "use_module(repl/repl)" -t halt
```

Expected: no errors.

---

## Task 6: Replace `why` with `outbound`

**Files:**
- Modify: `repl/repl.pl` — replace the `why/2` clause

- [ ] **Step 1: Replace handle_command(why(...)) with handle_command(outbound(...))**

The existing `why` clause (around line 119) with its DECISION comment should be removed and replaced:

Remove:
```prolog
% DECISION: The prototype used ':why(Scene, EventTerm)' as the REPL command, relying on
% SWI-Prolog parsing ':why(S,E)' as ':(why(S,E))'. However, ':' as a prefix operator
% causes a syntax error in a clause head (Operator expected at column 16). Per task
% instructions, dropping ':' and using 'why(Scene, EventTerm)' instead. The help text
% still shows ':why' as the user-facing command name for documentation continuity.
handle_command(why(Scene, EventTerm)) :- !,
    why_blocked(Scene, EventTerm, Explanation),
    format("~w in ~w: ~w~n", [EventTerm, Scene, Explanation]).
```

Replace with:
```prolog
handle_command(outbound(Scene, EventTerm)) :- !,
    why_blocked(Scene, EventTerm, Explanation),
    format("~w leaving ~w: ~w~n", [EventTerm, Scene, Explanation]).
```

- [ ] **Step 2: Load-check**

```bash
swipl -g "use_module(repl/repl)" -t halt
```

Expected: no errors.

---

## Task 7: Update print_help/0

**Files:**
- Modify: `repl/repl.pl` — replace the `print_help/0` clause

- [ ] **Step 1: Replace print_help/0**

Replace the entire `print_help` clause with:

```prolog
print_help :-
    format("Commands (all require trailing period):~n"),
    format("  inject(Scene, Event)         — inject event (source: player) and step world~n"),
    format("  inject(Scene, Event, Source)  — inject event with an explicit source~n"),
    format("  log(Scene)                   — show arrived facts for scene~n"),
    format("  state(Scene)                 — show derived state for scene~n"),
    format("  probe(Scene)                 — show vocabulary surface~n"),
    format("  legal(Scene)                 — show currently legal actions~n"),
    format("  outbound(Scene, Event)        — would this event leave Scene right now, and why not~n"),
    format("  chain(EventId)                — show provenance chain~n"),
    format("  summary                       — show what changed at the current clock~n"),
    format("  scenes                        — list all scenes, hierarchically~n"),
    format("  gates                         — list all gates, flat~n"),
    format("  verify                        — run verify_contracts~n"),
    format("  close(Scene)                  — declare closure for scene~n"),
    format("  step                          — step world without injecting~n"),
    format("  quit                          — exit~n").
```

- [ ] **Step 2: Load-check**

```bash
swipl -g "use_module(repl/repl)" -t halt
```

Expected: no errors.

---

## Task 8: Create playtest_guide.md

**Note:** `playtest_guide.md` does not exist in the repo. The session prompt says to "modify" it with corrections to sections A2 and B1, so the file must be created with the already-corrected content. This is an anomaly to note in the session report.

**Files:**
- Create: `playtest_guide.md`

- [ ] **Step 1: Create playtest_guide.md with corrected content**

Create `/home/hoooo/AISlop/codex/oster_gen1/playtest_guide.md` with the following content:

```markdown
# Oster Playtest Guide

A reference for authors playtesting scenes in the Oster REPL.

## A — Basic Playtest Sequence

Start the REPL:

```bash
swipl -g "use_module(repl/repl), start_repl" -t halt
```

**A1 — Explore the topology**

```prolog
scenes.
gates.
```

Confirm the scene tree and all declared gates with their open/closed status.

**A2 — Inject an event and check outbound routing**

```prolog
inject(patron_a, strike(5)).
summary.
outbound(patron_a, noise(fight)).
```

`outbound/2` shows whether `noise(fight)` would currently leave `patron_a` through a gate, and if not, why not. After the strike, the cascade produces noise — confirm it propagated.

**A3 — Inspect a scene**

```prolog
log(patron_a).
log(tavern).
log(street).
```

**A4 — Check provenance**

```prolog
chain(evt_1).
```

---

## B — Authoring Patterns

**B1 — Locked door (gate with a third-party condition)**

A common mistake: modelling a locked door as a self-loop gate (`door, door, lateral`).
That conflates the door's own history with the two rooms it separates.

The correct pattern uses three scenes — the door's own log, plus the two rooms it connects:

```prolog
% Declare scenes: the door's own history, and the two rooms it separates
declare_scene(door).
declare_scene(hallway).
declare_scene(study).

% A key_used event unlocks the door — this is the door's own history,
% independent of any particular gate.
declare_scene_rule(r_unlock, door,
    arrived(_, door, key_used, _, _),
    unlocked).

% Gate: enter may only cross from hallway into study if the door is unlocked.
% The condition reads a third scene's log, not either endpoint's.
declare_gate(g_open, hallway, study, lateral).
assertz(gates:gate_condition(g_open,
    arrived(_, door, unlocked, _, _))).
assertz(gates:gate_term_filter(g_open, enter)).
```

Playtest sequence:

```prolog
inject(hallway, enter).   % should be blocked
outbound(hallway, enter).
inject(door, key_used).   % unlocks it
inject(hallway, enter).   % should now cross
log(study).
```

**What to look for:** After `key_used`, `outbound(hallway, enter)` should report `gate_is_open(g_open)` (meaning it would cross). After the second `inject(hallway, enter)`, `log(study)` should show the `enter` event arrived.

**What will probably crumble:** `check_rules_locality` does not flag gate conditions that read a scene other than the gate's source or destination. The condition above reads `door`, which is neither `hallway` nor `study`. This is intentional — gate conditions are explicitly allowed to reach into third-party scenes — but the locality checker does not track it.
```

---

## Post-flight: confirm tests still pass

- [ ] **Step 1: Run all 11 test suites**

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

Expected: same counts as baseline, 0 failures.

---

## Manual Verification

- [ ] **Step 1: Run the REPL verification sequence**

```bash
cd /home/hoooo/AISlop/codex/oster_gen1
swipl -g "use_module(repl/repl), start_repl" -t halt
```

Run these commands in order:

```prolog
help.
scenes.
gates.
inject(patron_a, strike(5)).
summary.
outbound(patron_a, noise(fight)).
outbound(street, noise(fight)).
inject(patron_b, taunt, player_2).
log(patron_b).
chain(evt_1).
quit.
```

**What to confirm:**
- `help.` — shows new command list including `outbound`, `summary`, `scenes`, `gates`, `inject/3`; does NOT mention `why`
- `scenes.` — prints the tavern scene tree (tavern as root, patron_a, patron_b, street as children)
- `gates.` — lists all 3 tavern gates with open/closed status
- `summary.` (after inject strike) — shows cascade changes at current clock
- `outbound(patron_a, noise(fight)).` — reports `gate_is_open(patron_a_noise_to_tavern)`
- `outbound(street, noise(fight)).` — reports `no_gate(street, noise(fight))`
- `inject(patron_b, taunt, player_2).` — prints "Injected taunt into patron_b (source: player_2) at clock N"
- `log(patron_b).` — shows taunt event with evt_N id
- `chain(evt_1).` — shows the chain for the strike event
- `quit.` — exits

- [ ] **Step 2: Confirm `why` is gone**

```bash
swipl -g "use_module(repl/repl), start_repl" -t halt
```

```prolog
why(patron_a, noise(fight)).
quit.
```

Expected output: `Unknown command: why(patron_a,noise(fight))`

- [ ] **Step 3: Record transcript in docs/session_logs/session_13.md**

Create `/home/hoooo/AISlop/codex/oster_gen1/docs/session_logs/session_13.md` with the actual transcript output and any anomalies.
