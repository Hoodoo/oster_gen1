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

### N-003 — "most recent qualifying event" projection is duplicated across two gate conditions

**Identified:** Session 18
**Severity:** Low — duplication is intentional and documented inline

`window_is_open/1` and `amulet_is_charged/1` in `catalog/tavern/scene.pl`
share identical structure: findall over two event terms, msort, last check.
The abstraction was deliberately deferred in both sessions (16 and 18)
pending a third use case. Extract a shared `most_recent_state/3` helper
(or similar) when a third caller appears.

---

### N-001 — Probe predicates are non-deterministic

**Identified:** Session 5, no specific commit
**Severity:** Low — tests pass, behaviour correct

PLUnit emits choicepoint warnings on several probe tests. `probe/2` and the
convenience predicates (`probe_vocabulary/2`, `probe_gates/2`) are
non-deterministic as written. If strict determinism is needed, wrapping calls
in `once/1` or adding cuts would resolve it. Defer until catalog sessions
reveal whether this matters in practice.

**Update (external review, Session 15):** The same class of warning also
appears in `fixpoint_tests.pl`'s `t11_provenance_chain_gate`,
`projection_tests.pl`'s `investigation_chain_multi_hop`, and
`verify_tests.pl`'s `provenance_chain_traverses_untransformed_gate`. All
harmless for the same reason as the probe predicates. If N-001 is ever
addressed, sweep all four locations in the same pass rather than just probes.

---

### N-002 — rule_trigger provenance may record a non-causal frontier event

**Identified:** External review (I-004 report), Session 17
**Severity:** Low — chains are traversable; recorded trigger is a peer
frontier event, not a fabricated one

`record_rule_trigger/3` stores whichever frontier event the fixpoint loop
happened to be iterating when a rule fired. Rule conditions never reference
that EventId — they query `arrived/5` directly — so when a rule has
multi-fact conditions the recorded trigger may be a peer event that
coincidentally triggered the same fixpoint pass, not the true causal
antecedent. Single-condition rules (the current common case) are unaffected.
Resolve if/when multi-condition rules become prevalent enough to make
incorrect trigger attribution noticeable in `chain` output.

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

### I-005 — `declare_closure` and `promote_to_cold` were disconnected

**Identified:** Playtest observation, Session 19
**Resolved:** Session 19, commit `e420db4`

**Problem:**
`declare_closure/2` injected `closed(Scene, clock(N))` as a normal event
but never called `promote_to_cold`. The REPL's `close(Scene)` command called
`declare_closure` and `world_step` but also never promoted events. The tier
promotion machinery (Session 6) was correct and complete but had no caller
on the closure path. `log(Scene)` after `close(Scene)` showed all prior
events still marked `hot`.

**Resolution:**
`promote_to_cold(Scene, Clock)` added to the REPL's `close(Scene)` handler,
after `world_step`, using the pre-step clock value so all events up to and
including the closure event itself are promoted. `declare_closure/2` itself
is unchanged — it remains a low-level primitive. A regression test (T14 in
`lifecycle_tests.pl`) confirms the combined pattern works.

### I-004 — Hot events re-fire rules and gates on every tick

**Identified:** External review, post-Session 15, commit `68222fe`
**Resolved:** Session 17, commit `0261896`

**Problem:**
`advance_world/1` consumed `hot_events/1`, which returns every hot-tier
event — not just newly arrived ones. Events stay hot until lifecycle
closure, so a single injected event re-fired its full rule and gate cascade
on every subsequent tick. This violated the guide's terminal-gate-failure
invariant ("gate failure is a terminal fact... the old failed event does not
resurrect") and caused unbounded log growth with zero input.

**Resolution:**
`unprocessed/1` added to `engine/log.pl` as a frontier marker, asserted in
`inject_event/3` and retracted by the fixpoint after processing. `advance_world/1`
now iterates over the frontier rather than the hot set. `process_hot_event/1`'s
tier-check coupling relaxed to `_`. All `reset_engine` helpers updated to
clear the frontier. Two regression tests added.

### I-003 — `provenance_acyclic/1` never traversed past the immediate cause

**Identified:** External review, confirmed against source
**Resolved:** Session 14, commit `fdee559`

**Problem:**
`provenance_acyclic/1` was left as a Session 2 stub ("leaf traversal only —
Session 4 extends") and never actually extended. Session 4 extended
`provenance_chain/2` to full multi-hop traversal but its prompt scoped that
session as the only permitted change to `engine/provenance.pl`, and
`provenance_acyclic/1` was never revisited. Its `Visited` accumulator was
passed but never grown — the predicate checked only the immediate event's
cause and returned, so `check_provenance_acyclic` in `verify_contracts`
succeeded unconditionally for any event with a `caused_by/2` fact, regardless
of whether the full chain contained a cycle. The existing T8 test only
exercised independently-injected events with no chain depth, so nothing
caught this.

**Resolution:**
`provenance_acyclic/1` now reuses the (correct) `provenance_chain/2`
traversal and fails if the resulting chain contains a `cycle_detected(_)`
step. The dead `provenance_acyclic_/2` helper was removed. A new test
hand-constructs a 2-cycle via direct `caused_by/2` and `gate_passed/3`
assertions and confirms the fixed predicate now correctly rejects it.

---

### I-002 — Inward gates carry all patron events; D8 violated for direct injections

**Identified:** Session 11 report
**Resolved:** Session 11b, commit `d1ad408`

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

### C-003 — Non-module test files mask missing imports
Identified: Session 12 report
Test files that don't declare a module (:- module(...)) run in the user module context where all imported predicates are globally visible. This means a missing use_module in an engine file won't surface as an error during testing if the predicate is imported elsewhere in the test run. The bug only appears when loading from a proper module context. When adding new imports to engine files, verify them by loading the file directly in isolation: swipl -g "use_module('engine/gates')" -t halt.
