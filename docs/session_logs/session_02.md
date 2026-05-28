# Session 2 Report — Scenes and Provenance

## Files created
- scene_engine/engine/scenes.pl
- scene_engine/engine/provenance.pl
- scene_engine/tests/provenance_tests.pl

## Files modified
- scene_engine/engine/log.pl (stub removal: caused_by/2 moved to provenance.pl; :- use_module(provenance) added)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed

## Stubs left for future sessions
- provenance_chain/2: single-step only. Session 4 extends to multi-hop traversal.
- provenance_acyclic/1: leaf traversal only. Session 4 extends.

## Anomalies, surprises, questions

**scene_ancestors/2 spec code bug:** The spec provides a reference implementation using `reverse(Acc, Ancestors)` at the base case. However, the accumulator naturally builds ancestors in root-first order (each parent is prepended, so the root ends up at the head). Calling `reverse/2` would invert this to leaf-first order `[tavern, city]`, which contradicts the spec's own description ("root-first order") and the test assertion `Ancestors = [city, tavern]`. The fix was to use `Ancestors = Acc` directly (no reverse). A `% DECISION:` comment marks the divergence from the spec code.

Accepted by human reviewer.

**Engine directory:** The session spec references `oster/engine/` but the actual directory used in this project is `scene_engine/engine/`. Files were created in the correct location.
