# Session 13 Report — REPL Introspection and Renaming

## Files created
- `playtest_guide.md` (see Anomalies — spec said modify, but file did not exist)

## Files modified
- `repl/repl.pl`

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

## Manual verification transcript

```
Oster REPL — developer interface
Type 'help' for commands, 'quit' to exit.

World loaded: tavern (patron_a, patron_b, street, window open)
oster> Commands (all require trailing period):
  inject(Scene, Event)         — inject event (source: player) and step world
  inject(Scene, Event, Source)  — inject event with an explicit source
  log(Scene)                   — show arrived facts for scene
  state(Scene)                 — show derived state for scene
  probe(Scene)                 — show vocabulary surface
  legal(Scene)                 — show currently legal actions
  outbound(Scene, Event)        — would this event leave Scene right now, and why not
  chain(EventId)                — show provenance chain
  summary                       — show what changed at the current clock
  scenes                        — list all scenes, hierarchically
  gates                         — list all gates, flat
  verify                        — run verify_contracts
  close(Scene)                  — declare closure for scene
  step                          — step world without injecting
  quit                          — exit
oster> Scenes:
tavern
  patron_a
  patron_b
  street
oster> Gates:
  patron_a_noise_to_tavern: patron_a -> tavern (upward, open)
  patron_b_noise_to_tavern: patron_b -> tavern (upward, open)
  tavern_noise_to_street: tavern -> street (downward, open)
oster> Injected strike(5) into patron_a at clock 1
oster> Changes at clock 1:
  noise(fight) in patron_a (cause: rule(patron_a,rule_noise_strike_patron_a))
  guards_alerted in street (cause: rule(street,rule_guards_alerted))
  noise(fight) in street (cause: gate(tavern_noise_to_street))
  noise(fight) in tavern (cause: gate(patron_a_noise_to_tavern))
oster> noise(fight) leaving patron_a: gate_is_open(patron_a_noise_to_tavern)
oster> noise(fight) leaving street: no_gate(street,noise(fight))
oster> Injected taunt into patron_b (source: player_2) at clock 2
oster> Log for patron_b:
  [1] evt_6 taunt (hot)
  [2] evt_11 noise(fight) (hot)
oster> Provenance chain for evt_1:
  evt_1 in patron_a: strike(5) (cause: injected(player))
oster> Goodbye.
```

### `why` is gone

```
oster> Unknown command: why(patron_a,noise(fight))
Type 'help' for available commands.
```

## Stubs left for future sessions
(none)

## Anomalies, surprises, questions

1. **`playtest_guide.md` did not exist** — The session prompt listed it under "Files to modify" with "No files are created." The file did not exist in the repo. It was created with the already-corrected content (A2 using `outbound`, B1 using the three-scene door pattern). The spec's "Two corrections" framing implies a pre-existing file; the most likely explanation is the file was expected to be created in an earlier session that was never run.

2. **`tab(Depth * 2)` bug in spec** — The spec's `print_scene_node/2` code contains `tab(Depth * 2)`. SWI-Prolog's `tab/1` requires an evaluated integer; `Depth * 2` is a compound term `*(Depth, 2)` and throws a type error at runtime. Fixed to `Spaces is Depth * 2, tab(Spaces)`. This was caught during a code quality review pass; the spec will need a correction note.

3. **`:- discontiguous handle_command/1.` added** — `print_scene_node/2` is defined between `handle_command(scenes)` and `handle_command(gates)`, which SWI-Prolog warns about as non-contiguous clauses of `handle_command/1`. Added `:- discontiguous handle_command/1.` alongside the existing `:- dynamic scene_projection/2.` declaration to keep the file warning-clean. This is not in the spec but is the idiomatic Prolog fix and has no behavioral effect.

4. **`summary` output ordering** — The cascade from `inject(patron_a, strike(5))` surfaces four changes at clock 1: the directly-derived noise in `patron_a`, plus the gate propagations to `tavern` and `street`, plus `guards_alerted` in `street`. The `post_fixpoint_summary/2` predicate uses `msort` so the ordering is deterministic but may look non-causal (e.g., `guards_alerted` appears before `noise(fight) in street`). This is a pre-existing property of `post_fixpoint_summary/2`, not introduced here.
