# Session 19 — Closure Tier Wiring and Minor Cleanup

## Files modified

- `repl/repl.pl` — added `:- use_module('../lifecycle/tiers').`; added
  `promote_to_cold(Scene, Clock)` (pre-step clock value) to the
  `handle_command(close(Scene))` handler, after `world_step`
- `tests/log_tests.pl` — normalised `retractall(unprocessed(_))` to
  `retractall(log:unprocessed(_))`
- `tests/provenance_tests.pl` — same normalisation
- `tests/gate_tests.pl` — same normalisation
- `tests/fixpoint_tests.pl` — same normalisation
- `tests/lifecycle_tests.pl` — added T14
  (`t14_closure_demotes_events_to_cold`), confirming that after
  `declare_closure` + `world_step` + `promote_to_cold`, no `hot` events
  remain in the closed scene
- `docs/deferred.md` — added I-005 (resolved): `declare_closure` and
  `promote_to_cold` were disconnected

No engine, projection, lifecycle, verify, or catalog file was touched.
`declare_closure/2` (`lifecycle/closure.pl`) and `promote_to_cold/2`
(`lifecycle/tiers.pl`) are both unchanged.

## Test results

All 11 suites pass. 159 tests total (was 158 at baseline; `tests/lifecycle_tests.pl`
went from 13 to 14, +1 as specified).

| Suite | Tests |
|---|---|
| tests/log_tests.pl | 9 |
| tests/provenance_tests.pl | 12 |
| tests/gate_tests.pl | 15 |
| tests/fixpoint_tests.pl | 15 |
| tests/probe_tests.pl | 13 |
| tests/lifecycle_tests.pl | 14 (+1) |
| tests/projection_tests.pl | 15 |
| tests/verify_tests.pl | 15 |
| catalog/deck/tests.pl | 17 |
| catalog/warrior/tests.pl | 12 |
| catalog/tavern/tests.pl | 22 |

## Manual REPL verification

```
oster> inject(patron_a, strike(5)).
Injected strike(5) into patron_a at clock 1
oster> log(tavern).
Log for tavern:
  [0] evt_1 window_opened (hot)
  [1] evt_5 noise(fight) (hot)
oster> close(tavern).
Declared closure for tavern at clock 1
oster> log(tavern).
Log for tavern:
  [0] evt_1 window_opened (cold)
  [1] evt_5 noise(fight) (cold)
  [1] evt_8 closed(tavern,clock(1)) (cold)
oster> inject(patron_a, taunt).
Injected taunt into patron_a at clock 3
oster> log(tavern).
Log for tavern:
  [0] evt_1 window_opened (cold)
  [1] evt_5 noise(fight) (cold)
  [1] evt_8 closed(tavern,clock(1)) (cold)
  [3] evt_11 noise(fight) (hot)
```

Confirms all three acceptance points: (1) all events present before
`close(tavern)` show `(cold)` afterward, (2) the injection after closure
arrives `(hot)` while prior events stay `(cold)`, (3) `closed(tavern,
clock(1))` itself shows `(cold)`.

## Anomalies

None. The change was exactly the one-line addition specified; the clock
sequencing behaved as the prompt predicted (the closure event lands at the
pre-step clock and is included in the promotion range; the post-closure
injection's rule-triggered `noise(fight)` echo lands at clock 3, two ticks
later, consistent with existing multi-hop propagation timing seen in prior
sessions — not a new behavior).

## Stubs left for future sessions

None.

## Questions for the human

None.
