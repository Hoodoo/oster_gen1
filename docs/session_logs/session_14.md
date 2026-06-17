# Session 14 — Provenance Acyclic Check Fix

## Files modified

- `engine/provenance.pl` — replaced broken `provenance_acyclic/1` + dead `provenance_acyclic_/2` with one-liner delegating to `provenance_chain/2`
- `tests/provenance_tests.pl` — added `use_module('../engine/gates')`, extended `reset_engine` with `retractall(gates:gate_passed(_,_,_))`, added T12 regression test
- `docs/deferred.md` — added I-003 entry under Resolved

## Test results

All 11 suites pass. `tests/provenance_tests.pl` now reports 12 tests (was 11); all others unchanged.

| Suite | Tests |
|---|---|
| tests/log_tests.pl | 9 |
| tests/provenance_tests.pl | 12 (+1) |
| tests/gate_tests.pl | 15 |
| tests/fixpoint_tests.pl | 14 |
| tests/probe_tests.pl | 13 |
| tests/lifecycle_tests.pl | 13 |
| tests/projection_tests.pl | 15 |
| tests/verify_tests.pl | 15 |
| catalog/deck/tests.pl | 17 |
| catalog/warrior/tests.pl | 12 |
| catalog/tavern/tests.pl | 17 |

## Regression check (acceptance criterion 2)

Temporarily restored the old `provenance_acyclic_/2` implementation and ran T12 in isolation. Result: **FAILED** — `provenance_acyclic(evt_loop_a)` succeeded with the buggy implementation (the `\+` in the test body failed), confirming the old code did not detect the cycle. Reapplied the fix; T12 **passed**.

## Stubs left for future sessions

None.

## Anomalies

`provenance_tests.pl` did not import `engine/gates`, which meant `gates:gate_transformed/5` was an unknown procedure when T12 called `provenance_chain` on an event with a `gate(_)` cause. Added `use_module('../engine/gates')` to the test file. This is required for `retractall(gates:gate_passed(_,_,_))` in `reset_engine` to be safe as well. No other test files were affected. This is consistent with C-003 (non-module test files masking missing imports).
