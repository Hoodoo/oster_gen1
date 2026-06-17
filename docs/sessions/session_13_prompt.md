# Session 13 — REPL Introspection and Renaming

## What this session is

You are building only what is listed here. This session touches the REPL
only — no engine, projection, lifecycle, or catalog file changes. The goal
is closing gaps found during a real playtest: there was no way to see the
scene/gate topology from inside the REPL, no way to surface what just
happened after a step, no way to tag who or what caused an injection, and
one existing command (`why`) was discovered to be misleadingly named — it
answers "would this event currently leave this scene," not "why does this
fact exist" (that question belongs to `chain`).

This session does not change any engine predicate, does not touch the
tavern catalog, and does not add automated tests — same as Session 12,
the REPL is verified by manual transcript.

---

## Before you write a line of code

Run all existing test suites and confirm they still pass (this session
shouldn't change their outcome, but confirm the baseline):

```bash
cd oster
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

If any fail, stop and report — do not proceed.

---

## Files to modify

```
oster/
├── repl/
│   └── repl.pl
└── playtest_guide.md
```

No files are created. No engine, projection, lifecycle, or catalog files
are modified.

---

## Specification: `repl/repl.pl`

### New import

`post_fixpoint_summary/2` exists (Session 7) but was never wired into the
REPL. Add it to the existing import block:

```prolog
:- use_module('../projections/post_fixpoint').
```

### `scenes` — hierarchical scene listing

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

There can be more than one root (the engine doesn't enforce exactly one —
`verify_contracts` checks that separately). Print a tree for each.

### `gates` — flat gate listing

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

Deliberately flat — gates do not sit in the scene hierarchy, and this
listing should not imply otherwise. No filter/transform/condition detail
in this session; just identity, endpoints, direction, and current
open/closed status.

### `summary` — what just changed

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

Always reports the *current* clock. No historical form in this session —
if that turns out to be needed, it's a small follow-up, not a reason to
hold this one up.

### `inject/3` — explicit source

Keep the existing `inject/2` clause completely unchanged (byte-for-byte —
no reason to touch working, already-verified behaviour). Add a new clause
alongside it:

```prolog
handle_command(inject(Scene, Event, Source)) :- !,
    inject_event(Scene, Event, injected(Source)),
    world_step,
    clock_value(Clock),
    format("Injected ~w into ~w (source: ~w) at clock ~w~n",
           [Event, Scene, Source, Clock]).
```

`Source` is a free atom — `player_1`, `god`, `setup`, anything the author
wants. `caused_by/2` already accepts arbitrary `injected(_)` terms; this is
purely a REPL surface change, no engine change.

### `outbound` — replaces `why`

Remove the existing `handle_command(why(Scene, EventTerm))` clause and
replace it with:

```prolog
handle_command(outbound(Scene, EventTerm)) :- !,
    why_blocked(Scene, EventTerm, Explanation),
    format("~w leaving ~w: ~w~n", [EventTerm, Scene, Explanation]).
```

The underlying `why_blocked/3` predicate and `projections/why_blocked.pl`
are **not** renamed — only the REPL-facing verb and the printed wording
change (from "X in Scene: ..." to "X leaving Scene: ..."), to make the
outgoing-gate-only scope of this command legible from the output itself.

### `print_help/0`

Update to reflect all of the above:

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

---

## Specification: `playtest_guide.md`

Two corrections.

**A2** — replace the `why(patron_a, noise(fight))` reference with
`outbound(patron_a, noise(fight))`.

**B1** — the locked-door sketch currently models the door as a self-loop
gate (`door, door, lateral`), which conflates the door's own history with
being one of the two places it separates. Replace the sketch with a real
two-room gate and the door as a third-party condition host:

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

```prolog
inject(hallway, enter).   % should be blocked
outbound(hallway, enter).
inject(door, key_used).   % unlocks it
inject(hallway, enter).   % should now cross
log(study).
```

Update the "What to look for" line referencing `why` to reference
`outbound`. Keep the "What will probably crumble" note about
`check_rules_locality` not flagging gate conditions — it's still true,
and now more clearly illustrated: the condition reads a scene that is
neither the gate's source nor its destination.

---

## Design decisions in force for this session

**Renaming is REPL-only.** `why_blocked/3` keeps its name and module.
Only the user-typed verb and the printed wording change.

**`inject/2` is untouched.** The new source-tagging behaviour is additive
via a new `inject/3` clause, not a change to existing behaviour.

**`summary` has no historical form yet.** Current clock only. Don't add
parameterized history queries speculatively — wait until it's actually
needed.

**`scenes` and `gates` are 0-arity, full listings.** No per-scene filtering
in this session.

**The door fix is documentation only.** `playtest_guide.md`'s B1 sketch is
guidance for a playtester to author themselves — it was never shipped
catalog code, so this change carries no test risk.

---

## Constraints

- Do not modify any engine, projection, lifecycle, or catalog file.
- Do not add automated tests for the REPL — verified manually, as in
  Session 12.
- Do not rename `why_blocked/3` or move it to a different module.
- All command names must match exactly what's specified here:
  `scenes`, `gates`, `summary`, `inject/3`, `outbound`.

---

## Manual verification

```bash
swipl -g "use_module(repl/repl), start_repl" -t halt
```

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

Confirm: `scenes` prints the existing tavern tree (this session runs
before the Session 14 hierarchy reorg, so `tavern` is still root).
`gates` prints all three declared gates with correct open/closed status.
`summary` reflects the cascade from the strike. `outbound(patron_a, ...)`
reports `gate_is_open(patron_a_noise_to_tavern)`. `outbound(street, ...)`
reports `no_gate(street, noise(fight))` — same answer as before, now
worded to make the outgoing-only scope legible. The `player_2`-sourced
injection prints with its source and shows up correctly in `log` and
`chain`.

Record the transcript in `docs/session_logs/session_13.md`.

---

## Acceptance criteria

1. All eleven prior test suites listed above still pass, unchanged counts.
2. `scenes`, `gates`, `summary`, `inject/3`, and `outbound` all behave as
   specified above, confirmed via the manual verification transcript.
3. `why` no longer exists as a command; typing it produces "Unknown
   command."
4. `playtest_guide.md`'s A2 and B1 sections are updated as specified.
5. `docs/session_logs/session_13.md` exists and contains the transcript
   plus any anomalies encountered.
