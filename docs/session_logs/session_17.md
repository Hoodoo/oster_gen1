# Session 17 — Frontier Tracking Fix (I-004)

## Files modified

- `engine/log.pl` — added `unprocessed/1` dynamic declaration and export, asserted in `inject_event/3`
- `engine/fixpoint.pl` — replaced `advance_world/1` with frontier iteration; relaxed `process_hot_event/1`'s tier-check argument from `hot` to `_`
- `tests/log_tests.pl` — `reset_log`: added `retractall(unprocessed(_))`
- `tests/provenance_tests.pl` — `reset_engine`: added `retractall(unprocessed(_))`
- `tests/gate_tests.pl` — `reset_engine`: added `retractall(unprocessed(_))`
- `tests/fixpoint_tests.pl` — `reset_engine`: added `retractall(unprocessed(_))`; added regression test `t_no_rederivation_on_subsequent_steps`
- `tests/lifecycle_tests.pl` — `reset_engine`: added `retractall(log:unprocessed(_))`
- `tests/projection_tests.pl` — `reset_engine`: added `retractall(log:unprocessed(_))`
- `tests/verify_tests.pl` — `reset_engine`: added `retractall(log:unprocessed(_))`
- `catalog/deck/tests.pl` — `reset_engine`: added `retractall(log:unprocessed(_))`
- `catalog/warrior/tests.pl` — `reset_engine`: added `retractall(log:unprocessed(_))`
- `catalog/tavern/tests.pl` — `reset_engine`: added `retractall(log:unprocessed(_))`; added regression test T19 (`t19_blocked_event_does_not_resurrect`), with a corrected clock sequence relative to the session prompt's draft (see Anomalies)
- `docs/deferred.md` — added I-004 as resolved; added N-002 as open

`tests/probe_tests.pl` was not modified — it uses `reset_declarations`, which never calls `inject_event`, per the session prompt's note.

## Test results

All 11 suites pass. 155 tests total (was 152 at baseline; +1 in `fixpoint_tests.pl`, +2 in `catalog/tavern/tests.pl` — the prompt's tavern count of 17 was already stale at baseline, actual baseline was 18; T19 brings it to 19).

| Suite | Tests |
|---|---|
| tests/log_tests.pl | 9 |
| tests/provenance_tests.pl | 12 |
| tests/gate_tests.pl | 15 |
| tests/fixpoint_tests.pl | 15 (+1) |
| tests/probe_tests.pl | 13 |
| tests/lifecycle_tests.pl | 13 |
| tests/projection_tests.pl | 15 |
| tests/verify_tests.pl | 15 |
| catalog/deck/tests.pl | 17 |
| catalog/warrior/tests.pl | 12 |
| catalog/tavern/tests.pl | 19 (+1 from this session; baseline was 18, not 17) |

No prior test's assertions needed updating — the buggy re-firing behaviour was never directly asserted by an existing test (T12 in `fixpoint_tests.pl`, "monotonicity," only asserts `>=`, which the fix still satisfies since it holds trivially at zero growth).

## Regression tests (acceptance criteria 2 and 3)

- **Test A** (`t_no_rederivation_on_subsequent_steps`, `tests/fixpoint_tests.pl`): log count identical after steps 2 and 3 relative to step 1. Passed as specified.
- **Test B** (T19, `catalog/tavern/tests.pl`): a strike blocked at the street gate (window closed) does not cross when the window is later reopened with no new strike injected. Passed after a fix to the test's clock sequencing (see Anomalies).

## Frontier empty check (acceptance criterion 4)

Manual REPL session (`swipl` loading the tavern catalog directly):

```
declare_tavern_world, declare_tavern_gates,
world_step,
inject_event(patron_a, strike(5), injected(player)),
world_step,
findall(E, log:unprocessed(E), Frontier).
```

Result: `Frontier = []` immediately after the completed `world_step`. A further no-op `world_step` also left the frontier empty and `log_count` unchanged (6), confirming no re-derivation.

## Anomalies

The session prompt's draft for T19 injects `window_closed` immediately after `setup_tavern`, with no intervening `world_step`. `declare_tavern_world` injects `window_opened` at clock 0 without advancing the clock, so without a `world_step` first, `window_closed` also lands at clock 0 — a tie. `window_is_open/1` (in `catalog/tavern/scene.pl`, Session 16) explicitly documents that ties resolve in favour of `window_opened`, so the window read as open throughout and the test failed (street received noise on the first cascade, before the "does it resurrect" question was even reachable).

The prompt's own "Watch out" note anticipated this general area ("verify the clock values are as expected") but its stated conclusion — that `window_closed` would be "more recent" — assumed a clock advance that wasn't actually in the test body. Fixed by adding `fixpoint:world_step` right after `setup_tavern`, matching the idiom already established by T5, T10, and T14 in the same file (all of which advance the clock past the setup injection before closing the window). Documented inline with a `% DECISION:` comment per Rule 7. Verified the corrected clock sequence in an isolated REPL trace before editing the test file.

## Stubs left for future sessions

None.

## Questions for the human

None — the T19 discrepancy was resolved conservatively using an existing in-file idiom, not a new design choice.
