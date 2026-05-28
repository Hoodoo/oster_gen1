# Session 5 Report — Probes

## Files created
- engine/probes.pl
- tests/probe_tests.pl

## Files modified
(none)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed
- tests/fixpoint_tests.pl: 14 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed

## Stubs left for future sessions
(none)

## Anomalies, surprises, questions

- The fixpoint tests report 14 passed (not 13 as the session prompt expected). This was the case before Session 5 started — it is not a regression introduced here.

- Several probe tests trigger PLUnit choicepoint warnings (e.g., `Test rule_heads_returned: Test succeeded with choicepoint`). These are warnings, not failures. They arise because `probe/2`, `probe_reachable/2`, etc. are non-deterministic in some test arrangements (e.g., `member/2` leaving choicepoints). All 13 tests pass. The choicepoints do not affect correctness for this read-only query predicate; if determinism is desired in future, `once/1` wrappers could be added to the convenience predicates.

- The session prompt references the `oster/` directory in the file paths, but the actual engine code lives in `scene_engine/`. Files were created in `scene_engine/engine/probes.pl` and `scene_engine/tests/probe_tests.pl` as per established project convention.
