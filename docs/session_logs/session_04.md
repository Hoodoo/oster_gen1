# Session 4 Report — Fixpoint

## Files created
- engine/fixpoint.pl
- tests/fixpoint_tests.pl

## Files modified
- engine/provenance.pl (stub removal: provenance_chain/2 extended to multi-hop; rule_trigger/3 added)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed
- tests/fixpoint_tests.pl: 14 passed, 0 failed (T1–T13 plus T7b as a separate test = 14)

## Stubs left for future sessions
(none)

## Design decisions

**rule_trigger/3 placed in provenance.pl, not fixpoint.pl.**
The spec locates rule_trigger/3 in fixpoint.pl, but fixpoint.pl already use_modules provenance.pl. Placing rule_trigger in fixpoint.pl would require provenance.pl to use_module fixpoint.pl to call it from parent_event/3, creating a circular dependency. Instead, rule_trigger/3 is declared in provenance.pl and exported. fixpoint.pl uses_module provenance, so assertz(rule_trigger(...)) asserts into provenance's module as expected. The % DECISION: comment is in provenance.pl.

**provenance_chain_ fallback clause added.**
The spec's provenance_chain_ code has no clause to handle the case where the recursed-to parent (e.g., unknown_gate_source(GateId)) has no caused_by fact. Without a fallback, the predicate fails silently rather than terminating gracefully. A fallback clause was added:

    provenance_chain_(EventId, _Visited, []) :- \+ caused_by(EventId, _), !.

This is consistent with the spec's stated intent: "The chain records unknown_gate_source(GateId) as a terminal." The chain terminates after the gate step, rather than failing entirely.

**T13 and T11 provenance assertions adjusted for untransformed gates.**
The spec's T13 says to "assert the chain reaches back to strike(5) in patron" starting from the tavern/noise(fight) event. However, the gate g_up is untransformed, so gate_transformed/5 is never asserted (by design, Session 3). provenance_chain cannot recover the source event ID. The tavern chain terminates at [step(TavernNoiseId, gate(g_up))].

T13 instead tests provenance of patron/noise(fight), which traces back through the rule to the injected strike(5) — a fully achievable multi-hop chain. The tavern event's chain is also tested, asserting the gate step is present.

T11 uses a gate WITH a transform (gate_transform(g_out, signal, signal_xfm)) so gate_transformed/5 IS asserted, enabling the full multi-hop gate chain to be traced. The spec says "Using the state from T5" but T5's untransformed gate prevents the required chain traversal.

**T6 clock assertion scoped to events created during world_step.**
Pre-injecting a trigger before world_step creates an event at clock 0; world_step advances to clock 1 before running advance_world. Checking ALL events for a single clock value would always fail (trigger=0, generated events=1). T6 records event IDs before calling world_step, then asserts that all NEW events (those not in PreIds) share a single clock value.

## Anomalies, surprises, questions

1. The spec's T13 provenance requirement ("chain reaches back to strike(5)" from the tavern event) is not achievable with the current untransformed-gate design. The limitation is acknowledged in the spec itself ("unknown_gate_source(GateId) as a terminal"). A future gate_passed/3 fact would fix this.

2. The spec's T6 description ("collect all arrived facts created in this step") conflicts with the workflow of pre-injecting before world_step. The test correctly scopes to events created during the step.

3. The test count is 14 (T1–T13 as named, but T7b is a separate predicate). The spec says "13 passed (T7 and T7b count separately)" — this appears to be an off-by-one in the spec's count.
