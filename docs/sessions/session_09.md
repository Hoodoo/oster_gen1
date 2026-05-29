# Session 9 — Catalog: Deck Scene

## What this session is

You are building Session 9 of the Oster implementation. This is the first
catalog entry — a standalone deck of cards. You are building only what is
listed here. Do not read ahead or implement anything from future sessions.

At the end of this session, all tests must be green, the session report must be
written to `docs/session_logs/session_09.md`, and no files outside the listed
scope may have been created or modified.

---

## Before you write a line of code

Run all prior session tests:

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
```

All tests must pass. If any fail, stop and report — do not proceed.

---

## Testing convention (in force for all sessions)

PLUnit runs test bodies in an isolated module (`plunit_*`). Any `assertz/1`
or `retractall/1` inside a test body targeting engine dynamic facts must be
module-qualified. Clock resets must use `clock:clock_counter`. The
`reset_engine` helper in `setup(...)` blocks is unaffected.

---

## Context: what this session builds

Sessions 1–8 built the engine and its tooling. This session uses it.

The deck is the first catalog entry: a leaf scene that models a deck of cards.
It demonstrates the most important pattern the engine supports that is not
obvious from the engine alone — **projection versus rule**.

A scene rule injects a new event into the log. A projection is a query against
the log that derives current state on demand. The deck has no rules that inject
events. Everything interesting about a deck — its current order, whether it is
empty — is derived by querying the log for the most recent relevant event.
The deck's vocabulary events (`create`, `draw`, `shuffle`, `sort`) arrive and
accumulate; the deck's state is always computed from that history, never stored
separately.

This is the guide's "derived state is always computed from the log on demand"
principle made concrete.

---

## Files to create

```
oster/
└── catalog/
    └── deck/
        ├── scene.pl   ← new
        └── tests.pl   ← new
```

No existing files are modified in this session.

---

## Specification

### `catalog/deck/scene.pl`

```prolog
:- module(deck, [
    declare_deck/1,
    current_order/2,
    deck_empty/1,
    deck_size/2
]).

:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/fixpoint').
```

---

#### `declare_deck/1`

```prolog
declare_deck(Name) :-
    declare_scene(Name).
```

Convenience wrapper. Declares the scene and nothing else — the deck's
vocabulary events are declared by the test or authoring layer using
`declare_scene_rule/4` after calling `declare_deck/1`.

---

#### Vocabulary

The deck responds to five event types. These are not declared by the engine —
they are conventions that authoring code declares as scene rules. The scene
file documents them:

```
create(Cards)   — establishes the initial card list
draw            — removes the top card from the current order
shuffle         — reverses the current order (deterministic for testing)
sort            — sorts the current order
```

**There are no scene rules in `scene.pl`.** Rules are declared by the author
(or the test) after calling `declare_deck/1`. The scene file provides only
projections — predicates that query the log to derive current state.

This is intentional. The deck scene is reusable precisely because it declares
no rules itself. Different games declare different rules for the same vocabulary.
A shuffle in one game reverses. In another it randomises. The engine is
indifferent.

---

#### `current_order/2`

```prolog
current_order(DeckScene, Order) :-
    most_recent_order_event(DeckScene, Event),
    order_from_event(DeckScene, Event, Order).
```

Returns the current card order by finding the most recent event that
establishes or modifies the order, then deriving the list from it.

```prolog
most_recent_order_event(DeckScene, Event) :-
    findall(
        Clock-Term,
        ( arrived(_, DeckScene, Term, Clock, _),
          order_establishing_event(Term)
        ),
        Pairs
    ),
    Pairs \= [],
    sort(0, @>=, Pairs, [_-Event|_]).

order_establishing_event(create(_)).
order_establishing_event(draw).
order_establishing_event(shuffle).
order_establishing_event(sort).
```

`most_recent_order_event/2` fails if no order-establishing events have arrived
yet (the deck has not been created). `current_order/2` inherits this failure —
calling it on an uncreated deck fails rather than throwing.

```prolog
order_from_event(DeckScene, create(Cards), Cards) :- !.
order_from_event(DeckScene, shuffle, Reversed) :-
    !,
    previous_order(DeckScene, shuffle, Prev),
    reverse(Prev, Reversed).
order_from_event(DeckScene, sort, Sorted) :-
    !,
    previous_order(DeckScene, sort, Prev),
    msort(Prev, Sorted).
order_from_event(DeckScene, draw, Rest) :-
    previous_order(DeckScene, draw, [_Top|Rest]).
order_from_event(_DeckScene, draw, []) :-
    % Draw from empty deck — top card does not exist, result is empty.
    true.
```

```prolog
previous_order(DeckScene, CurrentEvent, PrevOrder) :-
    arrived(_, DeckScene, CurrentEvent, CurrentClock, _),
    findall(
        Clock-Term,
        ( arrived(_, DeckScene, Term, Clock, _),
          order_establishing_event(Term),
          Clock < CurrentClock
        ),
        Pairs
    ),
    sort(0, @>=, Pairs, [_-PrevEvent|_]),
    order_from_event(DeckScene, PrevEvent, PrevOrder).
```

**Note on recursion:** `order_from_event/3` calls `previous_order/3` which
calls `order_from_event/3`. This recursion terminates because each call to
`previous_order/3` finds an event strictly earlier in clock time. The base
case is `create(Cards)` which does not recurse. If the clock history is
malformed (no `create` event before other order events), this will fail rather
than loop.

---

#### `deck_empty/1`

```prolog
deck_empty(DeckScene) :-
    current_order(DeckScene, []).
```

Succeeds if the current order is an empty list.

---

#### `deck_size/2`

```prolog
deck_size(DeckScene, N) :-
    current_order(DeckScene, Order),
    length(Order, N).
```

---

#### `standard_deck_rules/1`

```prolog
standard_deck_rules(DeckScene) :-
    % No standard rules — see module documentation.
    % This predicate exists as a hook for future authoring conventions.
    % Call declare_scene_rule/4 directly to declare deck behaviour.
    true.
```

Placeholder. Exists so authors can call `standard_deck_rules(my_deck)` as a
convention and extend it later. Does nothing in this session.

---

### `catalog/deck/tests.pl`

```prolog
:- use_module(library(plunit)).
:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/provenance').
:- use_module('../../engine/gates').
:- use_module('../../engine/fixpoint').
:- use_module('../../engine/probes').
:- use_module('../../verify/contracts').
:- use_module('../../verify/invariants').
:- use_module('deck_scene', [
    declare_deck/1,
    current_order/2,
    deck_empty/1,
    deck_size/2
]).
```

Use the full `reset_engine` helper. After reset, each test that exercises the
deck must call `declare_deck(deck)` and then inject a `create(Cards)` event
before testing projections.

```prolog
reset_engine :-
    retractall(log:arrived(_, _, _, _, _)),
    retractall(log:arrived_key(_, _, _, _)),
    retractall(log:tier_status(_, _)),
    retractall(log:tier_transition(_, _, _, _)),
    retractall(provenance:caused_by(_, _)),
    retractall(scenes:scene(_)),
    retractall(scenes:scene_parent(_, _)),
    retractall(scenes:scene_rule(_, _, _, _)),
    retractall(gates:gate(_, _, _, _)),
    retractall(gates:gate_condition(_, _)),
    retractall(gates:gate_transform(_, _, _)),
    retractall(gates:gate_blocked(_, _, _)),
    retractall(gates:gate_transformed(_, _, _, _, _)),
    retractall(gates:gate_passed(_, _, _)),
    retractall(fixpoint:rule_trigger(_, _, _)),
    retractall(fixpoint:fixpoint_depth_exceeded(_)),
    retractall(fixpoint:rule_grounding_failed(_, _)),
    retractall(log:event_counter(_)), assertz(log:event_counter(0)),
    retractall(clock:clock_counter(_)), assertz(clock:clock_counter(0)).
```

**Required test cases:**

**T1 — create establishes order**
Declare deck `deck`. Inject `create([card(1), card(2), card(3)])` at clock 0.
Call `current_order(deck, Order)`.
Assert `Order = [card(1), card(2), card(3)]`.

**T2 — draw removes top card**
Declare deck `deck`. Inject `create([card(1), card(2), card(3)])` at clock 0.
Advance clock to 1. Inject `draw` at clock 1.
Call `current_order(deck, Order)`.
Assert `Order = [card(2), card(3)]`.

**T3 — shuffle reverses order**
Declare deck `deck`. Inject `create([card(1), card(2), card(3)])` at clock 0.
Advance clock to 1. Inject `shuffle` at clock 1.
Call `current_order(deck, Order)`.
Assert `Order = [card(3), card(2), card(1)]`.

**T4 — sort orders cards**
Declare deck `deck`. Inject `create([card(3), card(1), card(2)])` at clock 0.
Advance clock to 1. Inject `sort` at clock 1.
Call `current_order(deck, Order)`.
Assert `Order = [card(1), card(2), card(3)]`.

**T5 — multiple operations in sequence**
Declare deck `deck`. Inject `create([card(1), card(2), card(3)])` at clock 0.
Advance clock. Inject `shuffle` (reverses to `[card(3), card(2), card(1)]`).
Advance clock. Inject `draw` (removes `card(3)`).
Call `current_order(deck, Order)`.
Assert `Order = [card(2), card(1)]`.

**T6 — deck_empty: non-empty deck fails**
Declare deck `deck`. Inject `create([card(1)])` at clock 0.
Assert `deck_empty(deck)` fails.

**T7 — deck_empty: empty after drawing all cards**
Declare deck `deck`. Inject `create([card(1)])` at clock 0.
Advance clock. Inject `draw`.
Assert `deck_empty(deck)` succeeds.

**T8 — deck_size**
Declare deck `deck`. Inject `create([card(1), card(2), card(3)])` at clock 0.
Call `deck_size(deck, N)`. Assert `N = 3`.

**T9 — draw from empty deck does not crash**
Declare deck `deck`. Inject `create([])` at clock 0.
Advance clock. Inject `draw`.
Assert the engine does not throw. Assert `current_order(deck, Order)` succeeds
with `Order = []`. No `rule_grounding_failed` is expected here — the
projection handles the empty case gracefully.

**T10 — current_order fails on uncreated deck**
Declare deck `deck` but do not inject `create`. Call `current_order(deck, _)`.
Assert it fails (does not throw).

**T11 — fixpoint terminates within 5 iterations for create**
Declare deck `deck`. Record `log:log_count(Before)`. Inject `create([card(1)])`.
Call `advance_world(5)`. Assert `fixpoint:fixpoint_depth_exceeded(_)` does not
hold. Assert `log:log_count(After)`, `After >= Before` (monotonicity).

**T12 — fixpoint terminates within 5 iterations for draw**
Same pattern as T11 but inject `draw` after `create`.
Assert `fixpoint_depth_exceeded` does not hold.

**T13 — fixpoint terminates within 5 iterations for shuffle**
Same pattern, inject `shuffle`. Assert no depth exceeded.

**T14 — fixpoint terminates within 5 iterations for sort**
Same pattern, inject `sort`. Assert no depth exceeded.

**T15 — verify_contracts passes on deck world**
Declare deck `deck`. Inject `create([card(1), card(2)])`. Call
`verify_contracts`. Assert it succeeds. The deck has no rules that could
trigger self-generation or safety violations — this is a baseline green run.

**T16 — probe returns vocabulary surface**
Declare deck `deck`. Call `probe(deck, vocab(Heads, Gates))`. Assert
`Gates = []` (no gates declared). `Heads` may be empty (no rules declared by
`declare_deck/1` itself) — assert the call succeeds without error. Note:
if the test layer declares rules for the deck before calling probe, Heads
will reflect those rules.

**T17 — provenance chain from draw event**
Declare deck `deck`. Inject `create([card(1), card(2)])` at clock 0 with cause
`injected(player)`. Advance clock. Inject `draw` at clock 1 with cause
`injected(player)`. Find the EventId of the `draw` event. Call
`investigation_chain(DrawId, Chain)`. Assert the chain is non-empty and
terminates at `injected(player)`.

---

## Design decisions in force for this session

**Projection vs. rule.** The deck has no `scene_rule/4` declarations in
`scene.pl`. All deck behaviour is expressed as projection predicates that query
the log. If you find yourself writing `declare_scene_rule` inside `scene.pl`,
stop — that belongs in the test or in authoring code.

**Deterministic shuffle.** `order_from_event(_, shuffle, Reversed)` uses
`reverse/2`. This is intentional for testability. A random shuffle using
`random_permutation/2` is a one-line change; the test suite depends on
determinism.

**Draw from empty deck.** `order_from_event(_, draw, [])` returns an empty
list when the previous order is empty. This is a graceful no-op — the deck
stays empty. It does not inject an error event or assert a failure fact. The
caller is responsible for checking `deck_empty/1` before injecting `draw` if
they want to handle the empty case explicitly.

**No gates in this catalog entry.** The deck is standalone. Propagation
coverage tests are not applicable here. The guide notes this explicitly.

**S-001 in force.** `catalog/deck/scene.pl` imports engine modules. If any
import creates a cycle, use module-qualified calls.

---

## Constraints

- `catalog/deck/scene.pl` must not declare any `scene_rule/4` facts.
- `catalog/deck/scene.pl` must not import `verify`, `projections`, or
  `lifecycle` modules.
- Do not modify any existing engine, lifecycle, verify, or test file.
- All predicate names must match the specification exactly.
- `current_order/2` must not throw — it must fail gracefully when the deck
  has no history.

---

## Acceptance criteria

The session is complete when:

1. `swipl -g "run_tests" -t halt tests/log_tests.pl` — all 9 pass.
2. `swipl -g "run_tests" -t halt tests/provenance_tests.pl` — all 11 pass.
3. `swipl -g "run_tests" -t halt tests/gate_tests.pl` — all 13 pass.
4. `swipl -g "run_tests" -t halt tests/fixpoint_tests.pl` — all 13 pass.
5. `swipl -g "run_tests" -t halt tests/probe_tests.pl` — all 13 pass.
6. `swipl -g "run_tests" -t halt tests/lifecycle_tests.pl` — all 13 pass.
7. `swipl -g "run_tests" -t halt tests/projection_tests.pl` — all 15 pass.
8. `swipl -g "run_tests" -t halt tests/verify_tests.pl` — all 15 pass.
9. `swipl -g "run_tests" -t halt catalog/deck/tests.pl` — all 17 pass.
10. No `arrived/5` fact is retracted at any point during any test run.
11. `docs/session_logs/session_09.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_09.md`:

```
# Session 9 Report — Catalog: Deck Scene

## Files created
- catalog/deck/scene.pl
- catalog/deck/tests.pl

## Files modified
(none)

## Test results
- tests/log_tests.pl: 9 passed, 0 failed
- tests/provenance_tests.pl: 11 passed, 0 failed
- tests/gate_tests.pl: 13 passed, 0 failed
- tests/fixpoint_tests.pl: 13 passed, 0 failed
- tests/probe_tests.pl: 13 passed, 0 failed
- tests/lifecycle_tests.pl: 13 passed, 0 failed
- tests/projection_tests.pl: 15 passed, 0 failed
- tests/verify_tests.pl: 15 passed, 0 failed
- catalog/deck/tests.pl: 17 passed, 0 failed

## Stubs left for future sessions
- standard_deck_rules/1: placeholder only, does nothing

## Anomalies, surprises, questions
(anything unexpected)
```

Do not produce the report until all tests pass.

---

## Ambiguity resolution

If something is unclear: session prompt first, then `docs/implementation_plan.md`,
then `docs/conceptual_guide.md`. If genuine ambiguity remains, make the most
conservative choice and leave a `% DECISION:` comment.
