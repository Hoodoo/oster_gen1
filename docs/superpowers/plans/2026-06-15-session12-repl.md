# Session 12 — REPL and Developer Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `repl/repl.pl`, a developer REPL that lets you interactively explore a running Oster tavern world — inject events, inspect logs, trace provenance, run contracts, query blocked actions.

**Architecture:** Single new file `repl/repl.pl` (module `repl`) that imports all existing engine, lifecycle, projection, and catalog modules and wires them together behind a `read_term`-based command loop. No new engine code; this is integration only. A `scene_projection/2` dynamic registry populated at world-load time lets `state/1` dispatch to the right projection without hardcoding scene names.

**Tech Stack:** SWI-Prolog modules, PLUnit (for prior tests only), `read_term/2`, `format/2`, `forall/2`, `msort/2`.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `repl/repl.pl` | Full REPL: module declaration, imports, registry, all command handlers |
| Create | `docs/session_logs/session_12.md` | Session report (written last, after verification) |

No existing files are modified.

---

## Task 1: Create branch

- [ ] **Step 1: Create and switch to the session branch**

```bash
git checkout -b session/12-repl
```

Expected: `Switched to a new branch 'session/12-repl'`

---

## Task 2: Run all prior tests

Run every test suite from previous sessions. All must pass before writing any code.

- [ ] **Step 1: Run all test suites**

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
swipl -g "run_tests" -t halt catalog/warrior/tests.pl
swipl -g "run_tests" -t halt catalog/tavern/tests.pl
```

Expected counts: 9, 11, 15, 13, 13, 13, 15, 15, 17, 12, 17 (all passing, 0 failed).

If any test fails, STOP. Do not write any code. Report the failure.

---

## Task 3: Create `repl/repl.pl`

- [ ] **Step 1: Create the file with module declaration and all imports**

Create `/home/hoooo/AISlop/codex/oster_gen1/repl/repl.pl`:

```prolog
:- module(repl, [start_repl/0]).

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
:- use_module('../verify/contracts').
:- use_module('../catalog/tavern/scene',  [declare_tavern_world/0,
                                           window_open/1]).
:- use_module('../catalog/tavern/gates',  [declare_tavern_gates/0]).
:- use_module('../catalog/deck/scene',    [current_order/2,
                                           deck_empty/1,
                                           deck_size/2]).
:- use_module('../catalog/warrior/scene', [current_hp/2,
                                           is_defeated/1]).

:- dynamic scene_projection/2.
% scene_projection(Scene, Goal)
% Goal is called to display state for Scene.
% Registered at world-load time by register_projections/0.

register_projections :-
    % Deck projections
    forall(
        ( scenes:scene(S), arrived(_, S, create(_), _, _) ),
        assertz(scene_projection(S, repl:print_deck_state(S)))
    ),
    % Warrior projections
    forall(
        ( scenes:scene(S), arrived(_, S, created(hp(_)), _, _) ),
        assertz(scene_projection(S, repl:print_warrior_state(S)))
    ).

print_deck_state(Scene) :-
    ( current_order(Scene, Order) ->
        format("  ~w order: ~w~n", [Scene, Order]),
        deck_size(Scene, N),
        format("  ~w size: ~w~n", [Scene, N])
    ;
        format("  ~w: no order established~n", [Scene])
    ).

print_warrior_state(Scene) :-
    current_hp(Scene, HP),
    format("  ~w hp: ~w~n", [Scene, HP]),
    ( is_defeated(Scene) ->
        format("  ~w: DEFEATED~n", [Scene])
    ;
        true
    ).

load_world :-
    declare_tavern_world,
    declare_tavern_gates,
    assertz(tavern_scene:window_open(tavern)),
    register_projections,
    format("World loaded: tavern (patron_a, patron_b, street, window open)~n").

start_repl :-
    format("~nOster REPL — developer interface~n"),
    format("Type 'help' for commands, 'quit' to exit.~n~n"),
    load_world,
    repl_loop.

repl_loop :-
    format("oster> "),
    ( read_term(Command, [variable_names(_)]) ->
        ( Command == end_of_file ->
            format("~nGoodbye.~n")
        ;
            catch(
                handle_command(Command),
                Error,
                format("Error: ~w~n", [Error])
            ),
            repl_loop
        )
    ;
        format("Parse error — try again~n"),
        repl_loop
    ).

handle_command(quit) :- !,
    format("Goodbye.~n"),
    halt.

handle_command(help) :- !,
    print_help.

handle_command(inject(Scene, Event)) :- !,
    inject_event(Scene, Event, injected(player)),
    world_step,
    clock_value(Clock),
    format("Injected ~w into ~w at clock ~w~n", [Event, Scene, Clock]).

handle_command(log(Scene)) :- !,
    print_scene_log(Scene).

handle_command(state(Scene)) :- !,
    print_scene_state(Scene).

handle_command(probe(Scene)) :- !,
    probes:probe(Scene, vocab(Heads, Gates)),
    format("Vocabulary for ~w:~n", [Scene]),
    format("  Rule heads: ~w~n", [Heads]),
    format("  Outgoing gates: ~w~n", [Gates]).

handle_command(:why(Scene, EventTerm)) :- !,
    % DECISION: : is an operator in SWI-Prolog so :why(S,E) parses as :(why(S,E)).
    % This clause matches that structure. If it fails to parse, use why(Scene, EventTerm).
    why_blocked(Scene, EventTerm, Explanation),
    format("~w in ~w: ~w~n", [EventTerm, Scene, Explanation]).

handle_command(chain(EventId)) :- !,
    ( investigation_chain(EventId, Chain) ->
        format("Provenance chain for ~w:~n", [EventId]),
        forall(member(step(EId, S, T, Cause), Chain),
               format("  ~w in ~w: ~w (cause: ~w)~n", [EId, S, T, Cause]))
    ;
        format("No chain found for ~w~n", [EventId])
    ).

handle_command(verify) :- !,
    ( verify_contracts ->
        true
    ;
        format("verify_contracts failed — see output above~n")
    ).

handle_command(close(Scene)) :- !,
    clock_value(Clock),
    declare_closure(Scene, Clock),
    world_step,
    format("Declared closure for ~w at clock ~w~n", [Scene, Clock]).

handle_command(step) :- !,
    world_step,
    clock_value(Clock),
    format("World stepped to clock ~w~n", [Clock]).

handle_command(legal(Scene)) :- !,
    legal_actions(Scene, Actions),
    format("Legal actions from ~w:~n", [Scene]),
    ( Actions = [] ->
        format("  (none)~n")
    ;
        forall(member(action(GateId, Dest, Shape), Actions),
               format("  ~w → ~w: ~w~n", [GateId, Dest, Shape]))
    ).

handle_command(Unknown) :-
    format("Unknown command: ~w~n", [Unknown]),
    format("Type 'help' for available commands.~n").

print_help :-
    format("Commands (all require trailing period):~n"),
    format("  inject(Scene, Event)  — inject event and step world~n"),
    format("  log(Scene)            — show arrived facts for scene~n"),
    format("  state(Scene)          — show derived state for scene~n"),
    format("  probe(Scene)          — show vocabulary surface~n"),
    format("  legal(Scene)          — show currently legal actions~n"),
    format("  :why(Scene, Event)    — explain why event is blocked~n"),
    format("  chain(EventId)        — show provenance chain~n"),
    format("  verify                — run verify_contracts~n"),
    format("  close(Scene)          — declare closure for scene~n"),
    format("  step                  — step world without injecting~n"),
    format("  quit                  — exit~n").

print_scene_log(Scene) :-
    findall(Clock-EventId-Term-Tier,
            ( arrived(EventId, Scene, Term, Clock, _),
              tier_status(EventId, Tier)
            ),
            Unsorted),
    msort(Unsorted, Sorted),
    ( Sorted = [] ->
        format("No events in ~w~n", [Scene])
    ;
        format("Log for ~w:~n", [Scene]),
        forall(
            member(Clock-EventId-Term-Tier, Sorted),
            format("  [~w] ~w ~w (~w)~n", [Clock, EventId, Term, Tier])
        )
    ).

print_scene_state(Scene) :-
    ( scene_projection(Scene, Goal) ->
        call(Goal)
    ;
        format("No state projections registered for ~w~n", [Scene]),
        format("(Use log(~w) to see raw arrived facts)~n", [Scene])
    ).
```

- [ ] **Step 2: Verify the file loads without errors**

```bash
cd /home/hoooo/AISlop/codex/oster_gen1 && swipl -g "use_module(repl/repl)" -t halt
```

Expected: exits 0, no errors or warnings. If there are module/predicate errors, fix them before proceeding.

---

## Task 4: Manual verification

The REPL must be tested interactively. Use piped input to simulate the session.

- [ ] **Step 1: Run the manual verification sequence**

```bash
cd /home/hoooo/AISlop/codex/oster_gen1 && printf 'help.\nlog(patron_a).\ninject(patron_a, strike(5)).\nlog(patron_a).\nlog(tavern).\nlog(street).\nstate(patron_a).\nprobe(patron_a).\nlegal(patron_a).\nstep.\nverify.\nclose(patron_a).\nlog(patron_a).\nquit.\n' | swipl -g "use_module(repl/repl), start_repl" -t halt 2>&1
```

Confirm:
- `help.` prints the command list
- `log(patron_a).` before inject says "No events in patron_a"
- `inject(patron_a, strike(5)).` says "Injected strike(5) into patron_a at clock N"
- `log(patron_a).` after inject shows the arrived event(s)
- `log(tavern).` shows events that propagated through gates
- `log(street).` shows events or says "No events"
- `state(patron_a).` shows HP or "No state projections"
- `probe(patron_a).` shows vocabulary/gates
- `legal(patron_a).` shows actions or "(none)"
- `step.` steps the clock
- `verify.` runs contracts without crashing
- `close(patron_a).` declares closure
- `log(patron_a).` shows events including after closure

- [ ] **Step 2: Test :why command**

```bash
cd /home/hoooo/AISlop/codex/oster_gen1 && printf ':why(patron_a, noise(fight)).\nquit.\n' | swipl -g "use_module(repl/repl), start_repl" -t halt 2>&1
```

Expected: reports either that no gate exists from patron_a for that term, or that the gate is open.

- [ ] **Step 3: Test chain command**

From the `log(patron_a)` output after inject, pick an EventId (e.g. `evt_3`). Then:

```bash
cd /home/hoooo/AISlop/codex/oster_gen1 && printf 'inject(patron_a, strike(5)).\nlog(patron_a).\nchain(evt_1).\nquit.\n' | swipl -g "use_module(repl/repl), start_repl" -t halt 2>&1
```

The exact EventId depends on the log output — adjust as needed. The chain should be non-trivial after a strike (cause chain from the injected event through any gate-propagated events).

Capture all output for the session report.

---

## Task 5: Confirm all prior tests still pass

- [ ] **Step 1: Re-run all test suites**

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

All must pass (same counts as Task 2). If anything broke, diagnose — do not skip.

---

## Task 6: Write session report

Only write the report after all tests pass and manual verification is complete.

- [ ] **Step 1: Write `docs/session_logs/session_12.md`**

Fill in the actual manual verification output captured in Task 4.

```markdown
# Session 12 Report — REPL and Developer Tooling

## Branch
session/12-repl

## Files created
- repl/repl.pl

## Files modified
(none)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 15 passed, 0 failed
- tests/fixpoint_tests.pl: 13 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed
- tests/lifecycle_tests.pl: 13 passed, 0 failed
- tests/projection_tests.pl: 15 passed, 0 failed
- tests/verify_tests.pl: 15 passed, 0 failed
- catalog/deck/tests.pl: 17 passed, 0 failed
- catalog/warrior/tests.pl: 12 passed, 0 failed
- catalog/tavern/tests.pl: 17 passed, 0 failed

## Manual verification
[paste actual output from Task 4 here]

## Stubs left for future sessions
(none — this is the final planned session)

## Anomalies, surprises, questions
[anything unexpected]
```

---

## Task 7: Commit, open PR

- [ ] **Step 1: Stage and commit**

```bash
cd /home/hoooo/AISlop/codex/oster_gen1
git add repl/repl.pl docs/session_logs/session_12.md
git commit -m "$(cat <<'EOF'
Session 12: REPL and developer tooling

Adds repl/repl.pl — an interactive loop for injecting events, inspecting
logs, tracing provenance, running contracts, and querying blocked actions
against a live tavern world.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 2: Open PR**

```bash
cd /home/hoooo/AISlop/codex/oster_gen1 && gh pr create --title "Session 12: REPL and developer tooling" --body "$(cat docs/session_logs/session_12.md)"
```

---

## Known risks / design notes

- **`:why` operator parsing**: In SWI-Prolog, `:` is an operator so `:why(S,E)` parses as `:(why(S,E))`. The `handle_command(:why(Scene, EventTerm))` clause should match it. If it doesn't, rename to `why(Scene, EventTerm)` and add a `% DECISION:` comment.
- **`register_projections/0` timing**: It's called after `load_world`, which calls `declare_tavern_world`. The `arrived/5` facts from world declaration must be present before `register_projections` queries them. `declare_tavern_world` asserts those facts, so the ordering in `load_world` is correct.
- **`tavern_scene:window_open(tavern)`**: The module is `tavern_scene` (from `catalog/tavern/scene.pl`). The assertz must use this module qualifier exactly, as the dynamic fact is declared in that module.
- **No test file**: Per the session spec, the REPL is verified interactively only. Do not create a test file.
