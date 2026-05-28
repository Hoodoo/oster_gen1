# Session 1 — Log and Clock

## Files created

- `scene_engine/engine/log.pl`
- `scene_engine/engine/clock.pl`
- `scene_engine/tests/log_tests.pl`

## Test results

9 passed, 0 failed. Tests are fully isolated (confirmed by running twice in sequence without resetting, identical results both runs).

## Stubs left for future sessions

- `caused_by/2` is declared as a `dynamic` fact in `log.pl` with a `% STUB: Session 2` comment. Session 2 (`provenance.pl`) will own this declaration; the temporary declaration in `log.pl` should be removed at that point.

## Anomalies, surprises, questions

- None. The specification was unambiguous and all design decisions (D1, D2, D12) were applied exactly as written.
- The `reset_log/0` helper in the test file uses `retractall/1` on `arrived/5` for test isolation. No production code ever retracts `arrived/5`; T4 confirms the log only grows during normal operation.
