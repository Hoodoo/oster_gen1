# Session 12 Report — REPL and Developer Tooling

## Branch
session/12-repl

## Files created
- repl/repl.pl

## Files modified
(none)

## Test results

| Suite | Tests | Failures |
|---|---|---|
| log_tests.pl | 9 | 0 |
| provenance_tests.pl | 11 | 0 |
| gate_tests.pl | 15 | 0 |
| fixpoint_tests.pl | 14 | 0 |
| probe_tests.pl | 13 | 0 |
| lifecycle_tests.pl | 13 | 0 |
| projection_tests.pl | 15 | 0 |
| verify_tests.pl | 15 | 0 |
| catalog/deck/tests.pl | 17 | 0 |
| catalog/warrior/tests.pl | 12 | 0 |
| catalog/tavern/tests.pl | 17 | 0 |
| **Total** | **151** | **0** |

## Manual verification

### Main sequence (help, log, inject, state, probe, legal, step, verify, close)

```
Oster REPL — developer interface
Type 'help' for commands, 'quit' to exit.

World loaded: tavern (patron_a, patron_b, street, window open)
oster> Commands (all require trailing period):
  inject(Scene, Event)  — inject event and step world
  log(Scene)            — show arrived facts for scene
  state(Scene)          — show derived state for scene
  probe(Scene)          — show vocabulary surface
  legal(Scene)          — show currently legal actions
  why(Scene, Event)     — explain why event is blocked
  chain(EventId)        — show provenance chain
  verify                — run verify_contracts
  close(Scene)          — declare closure for scene
  step                  — step world without injecting
  quit                  — exit
oster> No events in patron_a
oster> Injected strike(5) into patron_a at clock 1
oster> Log for patron_a:
  [0] evt_1 strike(5) (hot)
  [1] evt_2 noise(fight) (hot)
oster> Log for tavern:
  [1] evt_3 noise(fight) (hot)
oster> Log for street:
  [1] evt_4 noise(fight) (hot)
  [1] evt_5 guards_alerted (hot)
oster> No state projections registered for patron_a
(Use log(patron_a) to see raw arrived facts)
oster> Vocabulary for patron_a:
  Rule heads: [noise(fight),noise(fight)]
  Outgoing gates: [gate_info(patron_a_noise_to_tavern,tavern,upward)]
oster> Legal actions from patron_a:
  (none)
oster> World stepped to clock 2
oster>   [ok] no self-generating rules
  warning: rule rule_guards_alerted has atomic consequence 'guards_alerted' (consider structured term)
  [ok] consequence specificity
  [ok] provenance acyclic
  [ok] rule conditions safe
verify_contracts: all checks passed
oster> Declared closure for patron_a at clock 2
oster> Log for patron_a:
  [0] evt_1 strike(5) (hot)
  [1] evt_2 noise(fight) (hot)
  [2] evt_10 closed(patron_a,clock(2)) (hot)
  [2] evt_6 noise(fight) (hot)
  [3] evt_11 noise(fight) (hot)
oster> Goodbye.
```

### why command

```
Oster REPL — developer interface
Type 'help' for commands, 'quit' to exit.

World loaded: tavern (patron_a, patron_b, street, window open)
oster> Injected strike(5) into patron_a at clock 1
oster> noise(fight) in patron_a: gate_is_open(patron_a_noise_to_tavern)
oster> Goodbye.
```

### chain command

```
Oster REPL — developer interface
Type 'help' for commands, 'quit' to exit.

World loaded: tavern (patron_a, patron_b, street, window open)
oster> Injected strike(5) into patron_a at clock 1
oster> Provenance chain for evt_2:
  evt_2 in patron_a: noise(fight) (cause: rule(patron_a,rule_noise_strike_patron_a))
  evt_1 in patron_a: strike(5) (cause: injected(player))
oster> Goodbye.
```

## Stubs left for future sessions
(none — this is the final planned session)

## Anomalies, surprises, questions

1. **:why command** — The spec used `:why(Scene, EventTerm)` as the command syntax, relying on
   SWI-Prolog parsing `:why(S,E)` as `:(why(S,E))`. This causes a syntax error at load time:
   `Syntax error: Operator expected`. The command was renamed to `why(Scene, EventTerm)` with
   a `% DECISION:` comment. Help text updated accordingly. (The `:why` convention was noted as
   a prototype carry-over that can be dropped.)

2. **gates:clock_value/1 not visible** — `gates.pl` calls `clock_value/1` unqualified but does
   not import the `clock` module. This is a pre-existing issue that is accidentally masked in
   non-module test files (where `use_module(clock)` imports into `user`, globally visible).
   Since `repl.pl` is a module file, its `use_module(clock)` imports only into the `repl`
   module. The fix: added `:- assertz((gates:clock_value(V) :- clock:clock_value(V))).` to
   `repl.pl` with a `% DECISION:` comment. This resolves the existence error without modifying
   `gates.pl`.

3. **state(patron_a) shows "No state projections"** — The `register_projections/0` heuristic
   inspects `arrived/5` for `create(_)` and `created(hp(_))` events to identify deck/warrior
   scenes. The tavern world uses neither; patron scenes have no deck or warrior semantics.
   This is correct behaviour: the fallback message directs the user to `log/1`.

4. **fixpoint_tests.pl count** — Reports 14 tests, not 13 as listed in the session spec.
   This is a pre-existing discrepancy (not introduced by session 12).

5. **verify warning** — `verify_contracts` prints a warning about `rule_guards_alerted` having
   an atomic consequence `guards_alerted`. This is a pre-existing condition from the tavern
   catalog; all checks pass.
