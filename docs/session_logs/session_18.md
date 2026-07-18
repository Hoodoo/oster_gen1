# Session 18 — Barkeeper's Amulet

## Files modified

- `catalog/tavern/scene.pl` — added `barkeeper` and `mob_lair` scenes and their
  parents (`barkeeper` under `tavern`, `mob_lair` under `world`); added
  `declare_barkeeper_rules/0` (`rule_alert_sent`) and `declare_mob_lair_rules/0`
  (`rule_mob_mobilized`); added `amulet_is_charged/1`; added `amulet_charged`
  setup injection; exported `amulet_is_charged/1`
- `catalog/tavern/gates.pl` — imported `amulet_is_charged/1`; added the
  one-directional `barkeeper_amulet_alert` gate (`barkeeper → mob_lair`,
  lateral) with an `alert_sent` term filter and an `amulet_is_charged(barkeeper)`
  condition
- `catalog/tavern/tests.pl` — added T20, T21, T22 (see Anomalies for a fix to
  T22 as specified)
- `repl/repl.pl` — imported `window_is_open/1` and `amulet_is_charged/1` from
  the tavern scene module; updated `load_world/0`'s banner message to reflect
  the expanded hierarchy
- `docs/deferred.md` — added N-003 (duplicated "most recent qualifying event"
  pattern between `window_is_open/1` and `amulet_is_charged/1`)

No engine, projection, lifecycle, or verify file was touched. `catalog/deck/`
and `catalog/warrior/` were not touched. No return gate was declared from
`mob_lair`.

## Test results

All 11 suites pass. 158 tests total (was 155 at baseline; `catalog/tavern/tests.pl`
went from 19 to 22, +3 as specified).

| Suite | Tests |
|---|---|
| tests/log_tests.pl | 9 |
| tests/provenance_tests.pl | 12 |
| tests/gate_tests.pl | 15 |
| tests/fixpoint_tests.pl | 15 |
| tests/probe_tests.pl | 13 |
| tests/lifecycle_tests.pl | 13 |
| tests/projection_tests.pl | 15 |
| tests/verify_tests.pl | 15 |
| catalog/deck/tests.pl | 17 |
| catalog/warrior/tests.pl | 12 |
| catalog/tavern/tests.pl | 22 (+3) |

## Manual REPL verification (acceptance criteria 2, 3, 4)

```
oster> scenes.
Scenes:
world
  tavern
    patron_a
    patron_b
    barkeeper
  street
  mob_lair
oster> gates.
Gates:
  patron_a_noise_to_tavern: patron_a -> tavern (upward, open)
  patron_b_noise_to_tavern: patron_b -> tavern (upward, open)
  tavern_noise_to_street: tavern -> street (lateral, open)
  barkeeper_amulet_alert: barkeeper -> mob_lair (lateral, open)
oster> step.
World stepped to clock 1
oster> inject(barkeeper, use_amulet).
Injected use_amulet into barkeeper at clock 2
oster> log(mob_lair).
Log for mob_lair:
  [2] evt_5 alert_sent (hot)
  [2] evt_6 mob_mobilized (hot)
oster> chain(evt_6).
Provenance chain for evt_6:
  evt_6 in mob_lair: mob_mobilized (cause: rule(mob_lair,rule_mob_mobilized))
  evt_5 in mob_lair: alert_sent (cause: gate(barkeeper_amulet_alert))
  evt_4 in barkeeper: alert_sent (cause: rule(barkeeper,rule_alert_sent))
  evt_3 in barkeeper: use_amulet (cause: injected(player))
```

`scenes` shows `mob_lair` and `barkeeper` in the correct hierarchy positions.
`gates` shows `barkeeper_amulet_alert` as `lateral`/`open`. `chain` from
`mob_mobilized` traces back to `injected(player)` for `use_amulet`.

Note: the `step.` before `inject(barkeeper, use_amulet).` is required in the
REPL transcript for the same reason it's required in T20–T22 (see the
"Watch out on clock sequencing" note in the session prompt) — without it, the
setup's `amulet_charged` injection is still on the frontier and gets processed
in the same `world_step` as `use_amulet`. This doesn't change T20–T22's
correctness (both events still land in the log and the gate condition still
evaluates the same way), but it does change what `chain` reports as the
immediate cause of `rule_alert_sent`'s firing: with a same-tick collision,
`record_rule_trigger/3` attributes the firing to whichever frontier event the
fixpoint loop was iterating (here, `amulet_charged`) rather than the event
that actually made the rule's condition true (`use_amulet`) — this is the
known N-002 limitation, not a new bug. Verified this directly: omitting the
`step.` produces a chain ending at `evt_2 amulet_charged (cause:
injected(setup))` instead of `use_amulet (cause: injected(player))`.

## Anomalies

**T22 as specified calls the wrong predicate for its assertion shape.** The
session prompt's T22 calls `provenance:provenance_chain(MobId, Chain)` but
asserts against `step(_, Scene, Term, Cause)` — a 4-arg shape. `provenance_chain/2`
actually returns 2-arg `step(EventId, Cause)` terms; T18 (existing, Session 16)
asserts exactly that 2-arg shape (`Chain = [step(WinId, injected(setup))]`),
confirming this is `provenance_chain/2`'s real, established contract. The 4-arg
enriched shape the T22 spec expects (`step(EventId, Scene, Term, Cause)`) is
what `investigation_chain/2` (`projections/investigation.pl`) produces — and
T12 (existing) already uses `investigation_chain/2` with exactly this pattern.

Per the spec-discrepancy precedent (test assertion shape is authoritative over
reference predicate choice), I changed T22 to call `investigation_chain/2`
instead of `provenance:provenance_chain/2`, keeping every assertion in the
spec unchanged. Verified in an isolated script before editing: `investigation_chain/2`
produces `[step(evt_6,mob_lair,mob_mobilized,rule(...)), step(evt_5,mob_lair,alert_sent,gate(...)),
step(evt_4,barkeeper,alert_sent,rule(...)), step(evt_3,barkeeper,use_amulet,injected(player))]`,
satisfying all three of T22's assertions. Documented inline with a `% DECISION:`
comment.

## Stubs left for future sessions

None.

## Questions for the human

None. The T22 predicate-name discrepancy was resolved conservatively (same
resolution pattern as prior sessions' spec/test conflicts — trust the
assertion shape, pick the predicate that actually produces it) and didn't
require any design judgment.
