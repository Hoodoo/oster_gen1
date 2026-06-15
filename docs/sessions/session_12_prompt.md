# Session 12 — REPL and Developer Tooling

## What this session is

You are building Session 12 of the Oster implementation — the final session.
This session builds the developer REPL: an interactive loop for authoring,
debugging, and exploring a running world. You are building only what is listed
here.

At the end of this session, all tests must be green, the session report must
be written to `docs/session_logs/session_12.md`, and no files outside the
listed scope may have been created or modified.

---

## Branch convention (standing rule, established this session)

Create a branch before writing any code:

```bash
git checkout -b session/12-repl
```

Work entirely on this branch. The session report must include the branch name.
Open a PR when all tests pass — the PR description is the session report. The
merge commit hash is what gets recorded in `docs/deferred.md` resolutions and
session logs going forward.

This convention applies to all future sessions.

---

## Before you write a line of code

Run all prior session tests:

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

All must pass before you touch anything.

---

## Conventions in force (accumulated across all sessions)

**Module qualification in test bodies.** PLUnit runs test bodies in an
isolated module. Any `assertz/1` or `retractall/1` targeting engine dynamic
facts must be module-qualified. Clock resets use `clock:clock_counter`.

**S-001.** `engine/provenance.pl` cannot `use_module(gates)` — use
module-qualified calls instead.

**C-001.** Never query the fifth argument of `arrived/5` for current tier.
Use `tier_status(EventId, Tier)`.

**C-002.** Defeat-style rules should not use `\+ arrived(..., ConsequenceTerm,
...)` as a guard — use `aggregate_all` instead.

**Gate term filters.** Gates that should only carry specific event shapes must
declare `gate_term_filter/2`. Without a filter, all events from the source
scene cross the gate.

---

## Context: what this session builds

The REPL is a developer tool — not a player interface, not a narration layer.
It prints raw Prolog terms. Its job is to make the engine explorable
interactively: inject events, inspect the log, trace provenance, run
contracts, open closures, and query why things are blocked.

Everything the REPL calls already exists. This session is integration work,
not new engine design. The one non-trivial design question is `state/1`:
how does the REPL know which projection predicates are available for a given
scene without hardcoding catalog knowledge? The answer is a registry —
see below.

The REPL also loads a world on startup. Rather than starting from a blank
slate, it loads the tavern world (the most complete catalog entry) so there
is something to interact with immediately.

---

## Files to create

```
repl/
└── repl.pl    ← new
```

No existing files are modified in this session. No test file is required —
the REPL is tested interactively. See the manual verification section.

---

## Specification

### `repl/repl.pl`

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
```

---

#### State projection registry

The `state/1` command needs to know what projections exist for a given scene
without hardcoding scene names into the dispatch logic. Use a registry:

```prolog
:- dynamic scene_projection/2.
% scene_projection(Scene, Goal)
% Goal is called to display state for Scene.
% Registered at world-load time by register_projections/0.
```

```prolog
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
```

`register_projections/0` is called after `load_world/0`. It inspects the log
to infer what kind of scene each declared scene is, then registers the
appropriate projection goal. This is heuristic — it works for the current
catalog entries.

```prolog
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
```

---

#### `load_world/0`

```prolog
load_world :-
    declare_tavern_world,
    declare_tavern_gates,
    assertz(tavern_scene:window_open(tavern)),
    register_projections,
    format("World loaded: tavern (patron_a, patron_b, street, window open)~n").
```

Called once at REPL startup. Loads the tavern world with the window open.

---

#### `start_repl/0`

```prolog
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
```

Uses `read_term/2` to read standard Prolog terms from stdin. Commands are
Prolog terms — `inject(patron_a, strike(5))` is parsed as a compound term.
This means the user types syntactically valid Prolog, including the trailing
period.

---

#### `handle_command/1`

```prolog
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
```

---

#### `print_help/0`

```prolog
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
```

---

#### `print_scene_log/1`

```prolog
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
```

Groups by clock tick naturally through `msort/2`. Tier is read from
`tier_status/2`, not from the fifth argument of `arrived/5` (C-001).

---

#### `print_scene_state/1`

```prolog
print_scene_state(Scene) :-
    ( scene_projection(Scene, Goal) ->
        call(Goal)
    ;
        format("No state projections registered for ~w~n", [Scene]),
        format("(Use log(~w) to see raw arrived facts)~n", [Scene])
    ).
```

---

## Manual verification

No automated test file is written for the REPL. Instead, verify interactively
by loading and running:

```bash
swipl -g "use_module(repl/repl), start_repl" -t halt
```

Run this sequence of commands and confirm each produces sensible output:

```prolog
help.
log(patron_a).
inject(patron_a, strike(5)).
log(patron_a).
log(tavern).
log(street).
state(patron_a).
probe(patron_a).
legal(patron_a).
step.
verify.
close(patron_a).
log(patron_a).
```

Then confirm `:why` works for a blocked action:

```prolog
:why(patron_a, noise(fight)).
```

(Should report the gate is open or that no gate exists from patron_a for
that term directly — since the gate carries noise upward, not downward.)

Then find an EventId from the log output and run:

```prolog
chain(evt_3).
```

Record the output in the session report. The chain should be non-trivial
after injecting a strike.

---

## Design decisions in force for this session

**REPL reads `tier_status/2` for tier display**, not the fifth argument of
`arrived/5` (C-001). `print_scene_log/1` does this correctly as specified.

**`read_term/2` requires trailing period.** This is standard SWI-Prolog
interactive term reading. The help text must say so. Users unfamiliar with
Prolog will forget the period — the error handler catches parse errors
gracefully.

**`state/1` uses a registry, not hardcoded dispatch.** `scene_projection/2`
is populated at world-load time. If a scene has no registered projection,
`state/1` tells the user to use `log/1` instead. This is correct — the REPL
does not need to know about every possible catalog entry.

**The REPL loads the tavern world on startup.** This is a developer tool
decision — starting with an empty world is less useful than starting with
something to explore. The tavern is the most complete entry.

**No narration.** Raw Prolog terms throughout. This is stated explicitly in
the implementation plan and is intentional.

---

## Constraints

- Do not modify any existing engine, lifecycle, verify, projection, or catalog
  file.
- Do not create a test file — the REPL is verified interactively.
- The `:why` command parses as a term because `:` is an operator in SWI-Prolog.
  `handle_command(:why(Scene, EventTerm))` should work as written. If it
  doesn't parse correctly, use `why(Scene, EventTerm)` instead and document
  with a `% DECISION:` comment.
- All predicate names must match the specification exactly.

---

## Acceptance criteria

1. All prior test suites pass unchanged:
   - `tests/log_tests.pl` — 9
   - `tests/provenance_tests.pl` — 11
   - `tests/gate_tests.pl` — 15
   - `tests/fixpoint_tests.pl` — 13
   - `tests/probe_tests.pl` — 13
   - `tests/lifecycle_tests.pl` — 13
   - `tests/projection_tests.pl` — 15
   - `tests/verify_tests.pl` — 15
   - `catalog/deck/tests.pl` — 17
   - `catalog/warrior/tests.pl` — 12
   - `catalog/tavern/tests.pl` — 17
2. `swipl -g "use_module(repl/repl), start_repl" -t halt` starts without
   error and accepts commands.
3. The manual verification sequence produces sensible output for all commands.
4. No `arrived/5` fact is retracted at any point.
5. Branch is `session/12-repl`. PR is open with session report as description.
6. `docs/session_logs/session_12.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_12.md`:

```
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
(paste the output of the command sequence here)

## Stubs left for future sessions
(none — this is the final planned session)

## Anomalies, surprises, questions
(anything unexpected)
```

Do not produce the report until all tests pass and manual verification is
complete.

---

## Ambiguity resolution

If something is unclear: session prompt first, then `docs/implementation_plan.md`,
then `docs/conceptual_guide.md`. If genuine ambiguity remains, make the most
conservative choice and leave a `% DECISION:` comment.
