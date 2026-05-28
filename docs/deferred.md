# Oster — Deferred Decisions and Known Issues

This document tracks design gaps, known limitations, and deferred decisions that
are too significant to leave only in session logs but cannot be acted on
immediately. Each entry has a reference to where it was first identified, a
precise statement of the problem, and a note on what needs to exist before it
can be resolved.

Entries are never deleted. When resolved, they are marked with the resolving
commit and a brief note.

---

## Open

### I-001 — Untransformed gate propagation leaves provenance chain untraversable

**Identified:** Session 4 report, commit `af6851f` ("Session 4: Fixpoint")

**Problem:**
When a gate passes an event through without a transform, no `gate_transformed/5`
fact is asserted (by design — Session 3). This means `provenance_chain/2` cannot
recover the source event ID for that hop. The chain terminates with
`unknown_gate_source(GateId)` rather than continuing back to the originating
event.

In the tavern integration test, the `tavern/noise(fight)` event arrived via an
untransformed upward gate from `patron`. Its provenance chain can only go one
hop — to the gate — not back to `patron/strike(5)` where the chain actually
starts. The test was correctly scoped to the patron-side chain (rule-based, fully
traceable) to avoid asserting something the current design cannot deliver.

**Why it matters:**
Investigation queries — the guide's primary use case for provenance — need to
follow chains through untransformed propagations. A noise event reaching the
street cannot be traced back to the fight that caused it if any hop along the
way was untransformed. This undermines the "why does this fact exist?" guarantee
for a large class of worlds where transforms are the exception, not the rule.

**Prerequisite for resolution:**
The fixpoint trace mode (listed as the highest-value missing development tool in
the guide's unsolved problems section) would make this visible and debuggable.
More directly: a `gate_passed/3` fact asserted by `attempt_propagation/2`
whenever a gate propagates without a transform would close the gap cleanly.

```prolog
:- dynamic gate_passed/3.
% gate_passed(GateId, SourceEventId, DestEventId)
```

This is a small, non-breaking addition to `engine/gates.pl` and
`attempt_propagation/2`. `provenance_chain/2` in `provenance.pl` would then
have a second lookup path alongside `gate_transformed/5`.

**Blocking:** Session 8 (`verify_contracts`) or earlier if investigation queries
are needed for catalog testing. Latest acceptable deferral is Session 9
(deck catalog) where provenance chain correctness becomes observable in practice.

**Resolution:** —

---
### N-001 — Probe predicates are non-deterministic

Identified: Session 5, no specific commit
Severity: Low — tests pass, behaviour correct
Note: PLUnit emits choicepoint warnings on several probe tests. probe/2 and the convenience predicates (probe_vocabulary/2, probe_gates/2) are non-deterministic as written. If strict determinism is needed, wrapping calls in once/1 or adding cuts would resolve it. Defer until catalog sessions reveal whether this matters in practice.
## Resolved

*(none yet)*
