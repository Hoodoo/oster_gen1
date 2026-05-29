# Oster — Deferred Decisions and Known Issues

This document tracks design gaps, known limitations, and deferred decisions that
are too significant to leave only in session logs but cannot be acted on
immediately. Each entry has a reference to where it was first identified, a
precise statement of the problem, and a note on what needs to exist before it
can be resolved.

Entries are never deleted. When resolved, they are marked with the resolving
commit and a brief note.

Entry types:
- **I-NNN** — tracked issues with a blocking condition
- **N-NNN** — low-priority notes, no blocking condition
- **C-NNN** — clarifications of design intent, not problems
- **S-NNN** — structural constraints on the codebase

---

## Open

### N-001 — Probe predicates are non-deterministic

**Identified:** Session 5, no specific commit
**Severity:** Low — tests pass, behaviour correct

PLUnit emits choicepoint warnings on several probe tests. `probe/2` and the
convenience predicates (`probe_vocabulary/2`, `probe_gates/2`) are
non-deterministic as written. If strict determinism is needed, wrapping calls
in `once/1` or adding cuts would resolve it. Defer until catalog sessions
reveal whether this matters in practice.

---

### S-001 — Circular import between `gates` and `provenance`

**Identified:** Session 8, commit `c2b42ce`
**Severity:** Structural constraint — not a bug, but affects all future sessions

`engine/provenance.pl` cannot use `:- use_module(gates)` because
`engine/gates.pl` imports `provenance` (for `assert_provenance/2`). The cycle
is resolved by module-qualified calls in `provenance.pl`:
`gates:gate_passed(...)`, `gates:gate_transformed(...)`. If either module needs
to call the other's predicates in future sessions, the solution is always
module-qualified calls — never a new `use_module` between these two modules.

---

## Resolved

### I-001 — Untransformed gate propagation leaves provenance chain untraversable

**Identified:** Session 4 report, commit `af6851f` ("Session 4: Fixpoint")

**Problem:**
When a gate passes an event through without a transform, no `gate_transformed/5`
fact is asserted (by design — Session 3). This means `provenance_chain/2` cannot
recover the source event ID for that hop. The chain terminated with
`unknown_gate_source(GateId)` rather than continuing back to the originating
event.

In the tavern integration test, the `tavern/noise(fight)` event arrived via an
untransformed upward gate from `patron`. Its provenance chain could only go one
hop — to the gate — not back to `patron/strike(5)` where the chain actually
started. The test was correctly scoped to the patron-side chain (rule-based,
fully traceable) to avoid asserting something the design could not deliver.

**Why it mattered:**
Investigation queries — the guide's primary use case for provenance — need to
follow chains through untransformed propagations. A noise event reaching the
street could not be traced back to the fight that caused it if any hop along
the way was untransformed.

**Resolution:** Session 8, commit `c2b42ce`. `gate_passed/3` added to
`engine/gates.pl`; asserted by `attempt_propagation/2` for all untransformed
propagations. `parent_event/3` in `provenance.pl` extended to check
`gate_passed/3` before falling back to `unknown_gate_source`. Fully traversable
chains are now the expected behaviour for all gate hops.

---

## Clarifications

### C-001 — `arrived/5` fifth argument is immutable

**Identified:** Session 6 report

The `Tier` argument in `arrived(EventId, Scene, Term, Clock, Tier)` is always
written as `hot` by `inject_event/3` and never updated. Current tier is tracked
exclusively in `tier_status(EventId, Tier)`. Query `tier_status` to determine
current tier — the fifth argument of `arrived/5` is unreliable for this purpose
after promotion.
