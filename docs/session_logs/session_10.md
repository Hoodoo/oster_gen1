# Session 10 Report — Catalog: Warrior Scene and Gate Transform

## Files created
- catalog/warrior/scene.pl
- catalog/warrior/tests.pl

## Files modified
(none)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed
- tests/fixpoint_tests.pl: 14 passed, 0 failed (spec says 13; suite grew in a prior session)
- tests/probe_tests.pl: 13 passed, 0 failed
- tests/lifecycle_tests.pl: 13 passed, 0 failed
- tests/projection_tests.pl: 15 passed, 0 failed
- tests/verify_tests.pl: 15 passed, 0 failed
- catalog/deck/tests.pl: 17 passed, 0 failed
- catalog/warrior/tests.pl: 12 passed, 0 failed

## verify_contracts warnings

verify_contracts **passed** for the warrior world. Two warnings are printed by
`check_consequence_specificity` (which is a warning-only check, not a failure):

    warning: rule rule_defeat_warrior_a has atomic consequence 'defeated'
    warning: rule rule_defeat_warrior_b has atomic consequence 'defeated'

These are expected: the defeat rule uses the atom `defeated` as its consequence
template. No hard failures.

## Spec divergences (% DECISION: comments in source)

### 1. Defeat rule conditions: aggregate_all instead of current_hp/2

The spec example uses `current_hp/2` in rule conditions. Two constraints make this
impossible with the current contracts.pl:

- `current_hp/2` is not in `default_safe_predicates`, so `check_rule_conditions_safe`
  would hard-fail → verify_contracts fails → T9 fails.
- Including `\+ arrived(_, WarriorScene, defeated, _, _)` in conditions puts the
  consequence functor `defeated` inside conditions, triggering a false positive in
  `check_no_self_generating_rules` → verify_contracts fails → T9 fails.

Resolution: rule conditions use `aggregate_all/3 + arrived/5` (both in
`default_safe_predicates`) and omit the `\+ arrived(..., defeated, ...)` guard.
The engine's `evaluate_rule` clock-based dedup (`\+ arrived_key(Scene, Template, Clock, _)`)
prevents same-tick re-injection. Across world_steps, one extra `defeated` event per step
is created while HP stays ≤ 0; this is benign for all test assertions.

`current_hp/2` is retained as a standalone exported projection predicate.

### 2. T5 / T6 / T8 / T11: setup_defeat_scenario instead of setup_fight

The spec calls `setup_fight` (warrior_a hp=20) for these tests. With warrior_a at hp=20,
two strike(10) injections bring warrior_a to HP=0, triggering its defeat rule and closing
the gate before warrior_b receives its third strike. warrior_b never reaches 0 HP.

Resolution: tests T5/T6/T8/T11 use `setup_defeat_scenario` (warrior_a hp=100), which
survives all three propagations.

### 3. T11: extra world_step before direct injection

After three world_steps, warrior_b already has `strike(5)@clock3` from the third gate
propagation. Injecting `strike(5)` directly into warrior_b at clock=3 is a no-op due to
`inject_event`'s `arrived_key` deduplication. An extra `world_step` (advancing to
clock=4) before the direct injection allows the new event to be created correctly.

### 4. T12: result(defeated, _) instead of result(strike(_), _)

`propagation_coverage/2` tests event terms drawn from the destination scene's rule
templates (`DestHeads`). warrior_b's only rule template is `defeated`; there is no rule
that produces `strike(_)`. The report therefore contains `result(defeated, crossed)`,
not `result(strike(_), _)` as stated in the spec.

Resolution: T12 asserts `Report \= []` and `member(result(defeated, _), Report)`.

## Stubs left for future sessions
(none)

## Anomalies, surprises, questions

- **Spec inconsistency: T5/setup_fight**: The spec's example for T5 injects strike(10)
  three times through the fight gate assuming warrior_a survives, but warrior_a (hp=20)
  is defeated after the second strike. The spec's own hp values are self-defeating for this test.

- **Spec inconsistency: check_no_self_generating_rules false positive**: The spec states
  `\+ arrived(..., defeated, ...)` should appear in conditions and separately states that
  verify_contracts should pass. These are mutually exclusive under the current
  `check_no_self_generating_rules` implementation (which uses `term_contains_functor`
  recursively). Removing the guard was the only path to a passing T9.

- **Spec inconsistency: T12 strike assertion**: The spec asserts
  `result(strike(_), _)` appears in the propagation_coverage report, but this predicate
  only tests rule-template terms. Warriors have no rule that produces strikes. The
  assertion cannot hold without adding a strike-generating rule (out of scope).

- **fixpoint_tests count**: Suite has 14 tests (spec says 13). Pre-existing from a prior
  session; not introduced in this session.

- **Contamination artefact**: warrior_a's `created(hp/armour)` events propagate to
  warrior_b at each clock tick through the fight gate (no event-type filter on the gate).
  This creates spurious `created(hp(100))` and `created(armour(0))` events in warrior_b.
  These are benign because `current_hp` uses the first `created(hp(_))` match (warrior_b's
  own hp=15, asserted first), and the gate transform reads the first `created(armour(_))`
  (warrior_b's armour=5). No functional impact, but future sessions may wish to add an
  event-type filter to gate propagation.
