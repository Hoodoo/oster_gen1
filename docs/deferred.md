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

### I-002 — Inward gates carry all patron events; D8 violated for direct injections

**Identified:** Session 11 report
**Resolved:** Session 11b, commit `(see session_11b.md)`

**Problem:**
`gate_open/1` received only the GateId — the event term being propagated was not
accessible to gate conditions. This made per-event term filtering impossible at
the gate API level. As a result, the tavern's inward gates carried every hot
event from patron scenes (including directly-injected `strike(5)`) into the tavern
log, violating D8 ("composite scenes only log what inward gates explicitly
deposit").

**Resolution:**
`gate_term_filter/2` added to `engine/gates.pl`. `attempt_propagation/2` checks
this filter before `gate_open/1`: if any filter is registered for a gate, only
events whose term unifies with a registered pattern may cross; others are recorded
as `gate_blocked` and the predicate fails. `propagate_from_scene/2` updated to
absorb that failure. `declare_gate_term_filter/2` added as the authoring
convenience predicate. Tavern inward gates now declare
`gate_term_filter(_, noise(fight))`, restoring D8 fully. T8 in
`catalog/tavern/tests.pl` asserts the correct `\+ arrived(_, tavern, strike(5), _, _)`.

---

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

### C-002 — Defeat-style rules and `check_no_self_generating_rules`

**Identified:** Session 10 report

A rule that uses `\+ arrived(_, Scene, ConsequenceTerm, _, _)` as a guard to
prevent re-firing will false-positive on `check_no_self_generating_rules`
because the consequence functor appears in the conditions. For example, a
defeat rule whose consequence is `defeated` and whose guard checks
`\+ arrived(_, Scene, defeated, _, _)` will be flagged even though the rule
is not genuinely self-generating — it fires once and the deduplication in
`inject_event/3` prevents re-injection at the same clock tick.

The pattern to prefer for defeat-style rules is to express the "not yet
triggered" guard through a different predicate (e.g. `aggregate_all/3` to
count existing consequence events) rather than directly matching the
consequence term in conditions. This avoids the false positive without
changing the rule's semantics.

Authors writing rules of the form "fire once when threshold crossed" should
be aware of this interaction with `check_no_self_generating_rules`.
