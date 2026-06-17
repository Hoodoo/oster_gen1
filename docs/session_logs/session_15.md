# Session 15 — Encoding Declarations and Dead Code Cleanup

## Files modified

### Encoding directive added (`:- encoding(utf8).` prepended as line 1)

- `engine/fixpoint.pl`
- `engine/gates.pl`
- `repl/repl.pl`
- `verify/contracts.pl`
- `verify/propagation.pl`
- `catalog/deck/scene.pl`
- `catalog/tavern/gates.pl`
- `catalog/warrior/scene.pl`
- `tests/fixpoint_tests.pl`
- `tests/gate_tests.pl`
- `tests/lifecycle_tests.pl`
- `tests/probe_tests.pl`
- `tests/projection_tests.pl`
- `tests/verify_tests.pl`
- `catalog/deck/tests.pl`
- `catalog/tavern/tests.pl`
- `catalog/warrior/tests.pl`

### Dead code removed

- `engine/fixpoint.pl` — removed vestigial `arrived_key(Scene, Template, Clock, _NewEventId)` call from `evaluate_rule/3`

### Documentation updated

- `docs/deferred.md` — N-001 extended with Session 15 update paragraph

## Test results

All 11 suites — normal locale and `LANG=C`:

| Suite | Tests | Status |
|---|---|---|
| `tests/log_tests.pl` | 9 | passed |
| `tests/provenance_tests.pl` | 12 | passed |
| `tests/gate_tests.pl` | 15 | passed |
| `tests/fixpoint_tests.pl` | 14 | passed |
| `tests/probe_tests.pl` | 13 | passed |
| `tests/lifecycle_tests.pl` | 13 | passed |
| `tests/projection_tests.pl` | 15 | passed |
| `tests/verify_tests.pl` | 15 | passed |
| `catalog/deck/tests.pl` | 17 | passed |
| `catalog/warrior/tests.pl` | 12 | passed |
| `catalog/tavern/tests.pl` | 17 | passed |

152 tests total, 0 failed. Zero encoding warnings under `LANG=C` after the fix.

## Stubs left for future sessions

None.

## Anomalies and notes

- The `grep -rlP '[^\x00-\x7F]'` scan found 17 files — all in `engine/`, `verify/`, `repl/`, `catalog/`, and `tests/`. Pure-ASCII files (e.g. `engine/log.pl`, `engine/provenance.pl`) were left untouched.
- Under `LANG=C` before the fix, SWI-Prolog would have emitted "Illegal multibyte sequence" warnings for each non-ASCII character encountered during stream decoding. After the fix, zero such warnings appear. (The pre-fix warning state was confirmed by the external review that prompted this session; the post-fix clean state was verified directly.)
- The `arrived_key(Scene, Template, Clock, _NewEventId)` removal is a no-op by construction: `inject_event/3` unconditionally asserts `arrived_key/4` before returning, so the query immediately after it cannot fail, and its `_NewEventId` binding was unused.
