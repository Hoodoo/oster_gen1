# Session 8 Report — verify_contracts and Invariant Checks

## Files created
- verify/contracts.pl
- verify/propagation.pl
- verify/invariants.pl
- tests/verify_tests.pl

## Files modified
- engine/gates.pl (I-001: added gate_passed/3; updated attempt_propagation/2)
- engine/provenance.pl (I-001: extended parent_event/3 for gate_passed)
- docs/deferred.md (I-001 marked resolved, commit c2b42ce)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed
- tests/fixpoint_tests.pl: 14 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed
- tests/lifecycle_tests.pl: 13 passed, 0 failed
- tests/projection_tests.pl: 15 passed, 0 failed
- tests/verify_tests.pl: 15 passed, 0 failed

## I-001 resolution
Commit hash: c2b42ce
gate_passed/3 asserted for all untransformed propagations.
parent_event/3 in provenance.pl now checks gate_passed/3 (then gate_transformed/5,
then falls back to unknown_gate_source as a defensive terminal).

## Stubs left for future sessions
None.

## Anomalies, surprises, questions

**clock_value vs source clock in attempt_propagation:**
The spec's attempt_propagation used `Clock` (the source event's clock) for the
arrived_key lookup after inject_event. This was always latently buggy for events
created in a prior world_step (different clock), but was not observable before
because the arrived_key lookup only executed for *transformed* propagations — and
in practice those source events were always created in the same world_step as the
propagation. Adding the arrived_key call for untransformed cases surfaced the bug
immediately (fixpoint tests T5, T6, T13 regressed). Fix: use clock_value/1
(current clock) for the lookup, matching what inject_event stamps on the dest
event. Added a DECISION comment in gates.pl.

**Circular import avoidance in provenance.pl:**
The spec says to add use_module(gates) to provenance.pl. But gates.pl already
imports provenance.pl, creating a circular dependency. Chose module-qualified
calls (gates:gate_transformed, gates:gate_passed) in provenance.pl instead — no
import change needed, no circular dependency. Added a DECISION comment.

**term_contains_functor and unbound variables:**
Conditions stored in scene_rule/4 facts may contain anonymous variables (from
assertz calls in test bodies). The spec's term_contains_functor called functor/3
on these without a guard, throwing "Arguments are not sufficiently instantiated"
when traversing a condition's arguments. Fixed: added nonvar(Term) guard on the
first clause. Added a DECISION comment.

**check_rule_conditions_safe calling convention:**
The spec's signature takes AllowedPreds and does member(F/A, AllowedPreds), but
verify_contracts passes default_safe_predicates (a predicate name, not a list).
The implementation calls AllowedPreds as a goal to retrieve the list. Added a
DECISION comment.

**Spec operator \=:= not valid in SWI-Prolog:**
invariants.pl spec uses \=:= for "not arithmetically equal". SWI-Prolog's
operator is =\=. Used =\= with a DECISION comment.

**Operator quoting in default_safe_predicates:**
Bare operators like =:= and =\= in a list context caused syntax errors because
SWI-Prolog's parser expects operands. All operator names in the safe list are
now quoted (e.g., '=:='/2). Added a DECISION comment.

**Fixpoint test count:**
fixpoint_tests.pl reports 14 passed (not 13 as listed in the acceptance
criteria). This was also the case before session 8 — the count was 14 in session
7 as well. Not a regression.
