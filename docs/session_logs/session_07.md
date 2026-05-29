# Session 7 Report — Projections

## Files created
- projections/legal_actions.pl
- projections/why_blocked.pl
- projections/post_fixpoint.pl
- projections/investigation.pl
- tests/projection_tests.pl

## Files modified
(none)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed
- tests/fixpoint_tests.pl: 14 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed
- tests/lifecycle_tests.pl: 13 passed, 0 failed
- tests/projection_tests.pl: 15 passed, 0 failed

## Stubs left for future sessions
(none)

## Anomalies, surprises, questions

**Clock reset bug in spec's reset_engine (DECISION applied):**
The session spec provides a `reset_engine` predicate that uses `retractall(log:clock_counter(_)), assertz(log:clock_counter(0))`. However, `clock_counter/1` is defined and owned by the `clock` module, not `log`. The `log` module never defines or re-exports `clock_counter`. As a result, the spec version silently fails to reset the clock between tests.

This bug is dormant in lifecycle_tests.pl (session 6) because none of those tests filter events by clock number — they match by event shape. It surfaces in projection_tests.pl because `post_fixpoint_summary(Clock, Summary)` explicitly filters by clock: after T8 (which calls `advance_clock`) increments the clock to 1, subsequent tests inject events at clock 1, making `post_fixpoint_summary(0, Summary)` return [] instead of the injected events.

Fix applied: `retractall(clock:clock_counter(_)), assertz(clock:clock_counter(0))` with a `% DECISION:` comment explaining the divergence. Documented here per session rules.

**T8 spec wording discrepancy (DECISION applied):**
The spec for T8 says "Call `post_fixpoint_summary(1, Summary)`. Assert `Summary` contains `change(room, alpha, _)`" but the explanatory comment says "beta arrived at clock 1, alpha at clock 0." Querying clock 1 would return beta, not alpha. The test intent is clearly to query clock 0 (matching T9 and T10 which both use `post_fixpoint_summary(0, ...)`). Implemented as `post_fixpoint_summary(0, Summary)` with a `% DECISION:` comment.

**choicepoint warning on T12:**
PLUnit reports "Test succeeded with choicepoint" for `investigation_chain_multi_hop`. This is harmless — it matches the pattern seen in probe_tests.pl and is a consequence of the rule condition `arrived(_, room, signal, _, hot)` leaving open alternatives. No action taken.

**fixpoint_tests.pl reports 14 tests, not 13:**
Pre-existing condition noted in session 5 and 6 reports; not introduced here.

**Path convention:**
As in all previous sessions, the spec references `oster/` paths but code lives in `scene_engine/` per established project convention.
