# Session 11b Report — Gate Term Filtering and D8 Fix

## Files modified
- engine/gates.pl (gate_term_filter/2, updated attempt_propagation/2,
  updated propagate_from_scene/2, added declare_gate_term_filter/2)
- catalog/tavern/gates.pl (added term filter declarations)
- catalog/tavern/tests.pl (restored T8 to correct assertion, added gate_term_filter to reset_engine)
- tests/gate_tests.pl (added T14, T15, gate_term_filter in reset_engine)
- docs/deferred.md (I-002 marked resolved)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 15 passed, 0 failed
- tests/fixpoint_tests.pl: 14 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed
- tests/lifecycle_tests.pl: 13 passed, 0 failed
- tests/projection_tests.pl: 15 passed, 0 failed
- tests/verify_tests.pl: 15 passed, 0 failed
- catalog/deck/tests.pl: 17 passed, 0 failed
- catalog/warrior/tests.pl: 12 passed, 0 failed
- catalog/tavern/tests.pl: 17 passed, 0 failed

## I-002 resolution
Commit hash: (fill in after commit)

## Anomalies, surprises, questions

**attempt_propagation/2 now fails on term filter rejection.**
The new behaviour is a deliberate contract change: the predicate fails when a
term filter rejects an event (recording gate_blocked as a side effect before the
cut+fail). propagate_from_scene/2 was updated to wrap each call with
(... -> true ; true) so it continues iterating gates even when one rejects. The
existing gate tests (T7: condition-blocked gate) were unaffected because the old
gate_blocked path still succeeds — only the new term-filter path fails.

**fixpoint_tests.pl count is 14, not 13.**
The acceptance criteria listed 13; the actual count has been 14 since before this
session. Pre-existing discrepancy, not introduced here.
