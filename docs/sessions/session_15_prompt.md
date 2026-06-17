# Session 15 — Encoding Declarations and Dead Code Cleanup

## What this session is

Two small, independent, mechanical fixes found during external review, both
confirmed against source before this prompt was written: missing
`:- encoding(utf8).` directives across the files that need them, and one
vestigial line in `evaluate_rule/3`. Neither changes observable behaviour —
the first only affects how the reader decodes bytes under a non-UTF-8
locale, the second deletes a call whose result was never used and which
cannot fail in the position it occupies (confirmed by tracing
`inject_event/3`'s effect on `arrived_key/4` immediately before it). No new
tests are added; both changes are verified by confirming existing test
counts are unchanged.

This session is independent of Session 14 — different files, no shared
state, can be done in either order.

---

## Before you write a line of code

```bash
cd oster
swipl -g "run_tests" -t halt tests/log_tests.pl
swipl -g "run_tests" -t halt tests/provenance_tests.pl
swipl -g "run_tests" -t halt tests/gate_tests.pl
swipl -g "run_tests" -t halt tests/fixpoint_tests.pl
swipl -g "run_tests" -t halt tests/probe_tests.pl
swipl -g "run_tests" -t halt tests/lifecycle_tests.pl
swipl -g "run_tests" -t halt tests/projection_tests.pl
swipl -g "run_tests" -t halt tests/verify_tests.pl
swipl -g "run_tests" -t halt catalog/deck/tests.pl
swipl -g "run_tests" -t halt catalog/warrior/tests.pl
swipl -g "run_tests" -t halt catalog/tavern/tests.pl
```

All must pass with the counts already on record. If any fail, stop and
report — do not proceed. If Session 14 has already landed, the count for
`provenance_tests.pl` will be one higher than its historical value — that's
expected, not a regression.

---

## Files to modify

```
oster/
├── engine/
│   └── fixpoint.pl   ← remove one vestigial line in evaluate_rule/3
├── docs/
│   └── deferred.md    ← extend N-001
└── [any .pl file under oster/ found to contain non-ASCII bytes]
```

---

## Specification

### 1. Encoding declarations

From the repo root, find every `.pl` file containing non-ASCII bytes:

```bash
grep -rlP '[^\x00-\x7F]' --include='*.pl' .
```

For each file in that list that does not already have an `:- encoding(utf8).`
directive, add one. It must be the literal first line of the file — before
`:- module(...)`, before any other directive, and before any existing header
comment that itself contains a non-ASCII character. The directive only
affects how the reader decodes everything *after* it, so anything above it
is still read with the wrong assumption. If a file's existing header comment
contains the offending characters, move the directive above that comment
rather than below it.

Do not add the directive to files that contain no non-ASCII bytes — leave
pure-ASCII files untouched.

### 2. Dead code removal: `engine/fixpoint.pl`

In `evaluate_rule/3`, the line `arrived_key(Scene, Template, Clock,
_NewEventId)` immediately after `inject_event(Scene, Template, rule(Scene,
RuleId))` queries a fact that `inject_event/3` has just guaranteed holds (it
was reached precisely because the preceding `\+ arrived_key(Scene, Template,
Clock, _)` check failed, and `inject_event/3` always asserts
`arrived_key(Scene, Term, Clock, EventId)` before returning when that
happens). The query cannot fail in this position, and its binding
(`_NewEventId`) is never used — `record_rule_trigger/3` on the next line
uses `EventId`, the original argument, not this binding.

Before:

```prolog
evaluate_rule(EventId, Scene, RuleId) :-
    scene_rule(RuleId, Scene, Conditions, Template),
    clock_value(Clock),
    ( call(Conditions) ->
        ( ground(Template) ->
            ( \+ arrived_key(Scene, Template, Clock, _) ->
                inject_event(Scene, Template, rule(Scene, RuleId)),
                arrived_key(Scene, Template, Clock, _NewEventId),
                record_rule_trigger(RuleId, Scene, EventId)
            ;
                true
            )
        ;
            assertz(fixpoint:rule_grounding_failed(RuleId, Clock))
        )
    ;
        true
    ).
```

After:

```prolog
evaluate_rule(EventId, Scene, RuleId) :-
    scene_rule(RuleId, Scene, Conditions, Template),
    clock_value(Clock),
    ( call(Conditions) ->
        ( ground(Template) ->
            ( \+ arrived_key(Scene, Template, Clock, _) ->
                inject_event(Scene, Template, rule(Scene, RuleId)),
                record_rule_trigger(RuleId, Scene, EventId)
            ;
                true
            )
        ;
            assertz(fixpoint:rule_grounding_failed(RuleId, Clock))
        )
    ;
        true
    ).
```

Just the one line is removed. Nothing else in this predicate changes.

### 3. `docs/deferred.md` — extend N-001

Append this paragraph to the existing N-001 entry (do not create a new
entry, do not alter the existing text above it):

```markdown
**Update (external review, Session 15):** The same class of warning also
appears in `fixpoint_tests.pl`'s `t11_provenance_chain_gate`,
`projection_tests.pl`'s `investigation_chain_multi_hop`, and
`verify_tests.pl`'s `provenance_chain_traverses_untransformed_gate`. All
harmless for the same reason as the probe predicates. If N-001 is ever
addressed, sweep all four locations in the same pass rather than just probes.
```

---

## Design decisions in force for this session

**No new tests.** Encoding directives aren't behavior to unit-test, and the
dead-code removal is a no-op by construction — confirmed in the reasoning
above, and confirmed empirically by unchanged test counts.

**N-001 is extended, not duplicated or resolved.** This is a note expansion,
not a fix — the choicepoints themselves are still deferred.

---

## Constraints

- Do not change any file's logic other than the single line removed from
  `evaluate_rule/3`.
- Do not add `:- encoding(utf8).` to files that don't need it.
- Do not reorder existing comments except where required to place the
  encoding directive first.

---

## Manual verification

Run the full battery (the same list above) twice — once under the normal
environment, once under a deliberately non-UTF-8 locale:

```bash
LANG=C swipl -g "run_tests" -t halt tests/log_tests.pl
# ... repeat for all eleven suites
```

Before the fix, this should show roughly the warning count Opus reported.
After, it should be clean — zero "Illegal multibyte sequence" warnings —
while every suite's pass/fail counts stay identical to the normal-locale run.

---

## Acceptance criteria

1. All eleven suites pass under both the normal and `LANG=C` runs, with
   identical counts in both.
2. Zero encoding warnings under `LANG=C` after the fix (confirm there were
   some before, so this is a real before/after, not an already-clean repo).
3. `evaluate_rule/3` no longer contains the vestigial `arrived_key/4` call.
4. `docs/deferred.md`'s N-001 entry includes the new paragraph.
5. `docs/session_logs/session_15.md` is written, listing exactly which
   files received the encoding directive.
