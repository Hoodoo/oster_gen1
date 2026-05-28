All projects
PGE Implementation Plan


How can I help you today?

    Prolog simulation and storytelling engine architecture
    Last message 8 hours ago

Memory
Only you

Project memory will show here after a few chats.
Instructions

Add instructions to tailor Claude’s responses
Files
1% of project capacity used

conceptual_guide_final.md

56.25 KB •422 linesFormatting may be inconsistent from source
# The Scene System — A Conceptual Guide

*This document describes a system under active design. The core model is sound and has been validated through two proof-of-concept sessions. Several load-bearing design questions remain open — they are listed honestly in the unsolved problems section at the end. A reader who stops before that section will think this engine is more complete than it is.*

---

## The central idea

Most game engines and simulations are built around objects and time. Things exist, they have state, they act, time passes, state changes. You write code that says: at each tick, for each object, do this.

This engine is built around a different idea: **events and logs**.

Nothing acts. Nothing has state in the conventional sense. Instead, things *happen* — events arrive, accumulate, and the current state of the world is always derived from that history on demand. The log is not a record of what happened to the world. The log *is* the world.

This is a profound shift and it takes time to internalise. Everything else in this guide follows from it.

---

## Events

An event is just a Prolog term — a structured piece of data that describes something that happened. `strike(8)`, `drawn(card(3))`, `murdered(greedypants, weapon(dagger))`, `shuffled([card(2), card(7), card(1)])`. Events have no behaviour of their own. They are inert data. They do not cause anything directly. They simply exist in the log, and rules read them.

Events are not commands. They are not method calls. They are facts about what happened.

---

## Scenes

A scene is a named boundary within which events accumulate. That is the complete definition. A scene does not act, decide, or do anything. It is a container for history.

A deck of cards is a scene. A warrior is a scene. A tavern room is a scene. A human mind is a scene. A murder investigation is a scene. The thing they have in common is not their subject matter — it is that events arrive inside them and accumulate, and rules fire against that accumulation.

**Leaf scenes** are scenes with no children. They are the nouns of the system. A deck declares what events it knows how to respond to: `create`, `draw`, `shuffle`, `sort`, `order`. It does not know what game it is in. It does not know what other scenes exist. It just declares its vocabulary — the events that are meaningful to it — and the rules that fire when those events arrive.

**Composite scenes** are scenes that contain other scenes as children. Their primary mechanical role is as a **propagation boundary** with two surfaces:

**The inward surface** — what propagates upward from children into the composite scene's own log, governed by gates between child and parent. The composite scene's log contains only what these inward gates permitted to arrive. Not all child events, not no events — exactly what the gates declared.

**The outward surface** — what propagates from the composite scene outward to siblings or parents, also governed by gates.

A composite scene's rules fire against its own log — the filtered aggregate of what arrived through inward gates. This is conditional aggregation: the composite scene does aggregate child events, but only through declared gate channels. It is not a transparent window into its children's logs, and it is not sealed off from them. The gates define the relationship precisely.

The tavern fight makes this concrete. The fight accumulates in patron scenes — strikes, dodges, taunts. The tavern as composite scene does not fire rules about the fight directly. But `noise(fight)` events can propagate upward through an inward gate into the tavern's log. From there, an outward gate with an open-window condition routes the noise to the street scene where the guards are. The tavern's role is not to know about the fight — it is to be the named boundary through which the fight's noise either escapes or doesn't.

Three useful consequences follow from this mechanical role:

**Authoring scope.** A composite scene is a convenient unit of design. The tavern — with its interior, exterior, cellar, and the gates between them — is a thing you design as a whole before thinking about how it connects to the rest of the world.

**Discovery boundaries for the player.** You know the tavern exists before you know what's inside it. Entering a scene is crossing a gate. Discovery is gate traversal from the player's perspective.

**Propagation containment.** Events stay inside unless an inward gate carries them up and an outward gate carries them further. The fight is local until the noise gate opens.

What composite scenes are not: transparent aggregators of all child events. Rules at the composite level read only what inward gates permitted to arrive — the locality guarantee holds. A composite scene's rule is still strictly local to its own log.

Scenes form a hierarchy through `scene_parent` declarations. Every scene has a parent, up to the root of the world. This hierarchy is the structure of the simulation.

---

## The log

The log is the append-only record of everything that has ever arrived anywhere. It never shrinks. Facts are never deleted. The past is permanent.

This is not a limitation — it is the source of the engine's power. Because the log is permanent and complete, you can ask questions about any moment in history. What was the deck's order at turn 3? What events had arrived at the warrior scene before the fatal blow? Who knew what, and when? These questions are always answerable, because the evidence never disappears.

Derived state — the deck's current order, a warrior's current HP, whether a door is locked — is always computed from the log on demand. There is no "current state" object sitting somewhere being updated. There is only the log and the rules that read it.

This means the engine has no concept of mutation. When the deck is shuffled, the old order is not overwritten. A new `shuffle` event arrives, and the derived projection `deck_order` now returns the new order because it finds the most recent shuffle event. The old order is still in the log, still queryable, still part of the history.

---

## Gates

If scenes are nouns and events are the things that happen to them, gates are the verbs — the relationships between scenes that give events direction and meaning.

A gate sits between two scenes and declares which events can pass between them, in which direction, under what conditions, and in what form. A gate between a deck and a hand says: `drawn(Card)` events can cross from deck to hand. A gate between two warriors says: `strike(D)` events can cross in both directions, but the damage is reduced by the destination warrior's armour before it arrives.

**Gates declare possibility, not inevitability.** An event that could cross a gate will only cross it if the gate is open. Gates can have conditions — rules that must hold for the gate to permit passage. A tavern door is closed after midnight. A portcullis is raised only when the lever has been pulled. The condition is evaluated at the moment the event tries to cross. If it fails, the event stays where it is.

**Possibility lives in the scene, permission lives in the gate, legality is the intersection.** A leaf scene declares what events are possible — the full vocabulary of things it can respond to. A gate declares what is permitted to cross between two scenes, and under what conditions. What is currently legal is the intersection of both: the event must be in the scene's vocabulary, and a gate must currently permit it to arrive. Possibility is static; permission is dynamic; legality is derived.

This separation is important. The deck does not know whether drawing is currently legal. It just knows what `draw` means and how to respond to it. The gate knows whether drawing is permitted right now — whether the game has started, whether it is the player's turn, whether cards remain. The scene and the gate have different concerns and neither needs to know about the other's.

**Gate failure is a terminal fact, not a pending state.** When an event reaches a gate and the gate's conditions are not met, the event does not wait, queue, or retry. It is recorded in the log as a failed propagation — with provenance showing what triggered it and which gate blocked it — and the fixpoint cascade terminates there. If conditions change later and the action becomes legal, a new event must be injected. The old failed event does not resurrect.

This means gate failures are queryable. "Why didn't this work?" has an answer in the log. The failed event exists, its provenance shows what triggered it, and the gate condition that blocked it is part of the record.

**The absence of a gate is not a misconfiguration.** It is equivalent to a permanently closed gate. A scene whose vocabulary is never reached by any gate is valid — it describes possibilities that the current world does not permit. You can declare a full scene vocabulary speculatively, before any gate connects it, and the engine will not complain. The scene sits there, coherent and complete, waiting for a gate to give it a role.

**Gates are authored relationships.** They do not belong to either scene they connect. A deck does not declare its gate to a hand. A hand does not declare its gate to a deck. The gate is declared separately, by whatever world is assembling these scenes into a simulation. This means scenes are genuinely reusable. The same deck scene can appear in a gambling game, a magic ritual, a card-sorting puzzle, or a chaos room where a firehose occasionally shuffles it. The deck is untouched in every case. Only the gates change.

**Gate transforms** are a special power: a gate can rewrite an event in transit. A `strike(8)` crosses the gate between two warriors and arrives as `strike(3)` because the gate applied the destination warrior's armour. The source scene emitted `strike(8)`. The destination scene received `strike(3)`. The gate is the entire explanation for the difference.

---

## Scene rules

A scene rule is a declaration of consequence. It says: when these conditions hold over this scene's log, this event should exist here.

A scene rule is not code that runs. It is a fact that the engine reads. The engine asks: are this rule's conditions currently satisfied by this scene's log? If yes, the declared event is generated and injected into this scene. Gate topology then determines where it propagates from there.

Rules are strictly local. A rule has no view of the world — it has a view of one scene's log. This is not a limitation; it is the model's core property. The sophistication of the world emerges entirely from the gate topology, not from rules that scan across scenes.

Consider ten thefts at ten different markets. Whether those thefts accumulate into a branding sentence depends entirely on whether the gate topology routes theft events to a scene that has a rule firing on ten accumulated thefts. No central surveillance scene exists unless the author declares it and connects it with gates. The guard who caught you at one market has a local rule that fires on one theft. The city registry has a rule that fires on ten — but only if ten reports actually arrived there through gates. No gates, no aggregation, no consequence. The complexity lives in the topology.

This also means gate failure and gate conditions do real narrative work. A city where guards don't share information is a city where no gate routes theft events to a central registry. The branding rule exists but never fires — not because it's disabled, but because the information never arrives. The same rule in a city with a working registry and open gates produces a very different world. The rules are identical; the topology is different.

**Scene rules are joins. Write them accordingly.** A rule with multiple conditions is a join across multiple sets of facts. If the conditions are not selective — if the first condition matches many facts before the second prunes them — you pay for every unification before the cut. Prolog has no query planner. It executes in the order you wrote the clauses. SQL will at least attempt to find the cheapest join order; Prolog will not.

For most story-scale content this doesn't matter — the fact sets are small and joins are trivially cheap. It matters when rules join across deep history with low selectivity. "Has this entity ever encountered this bloodline" is a scan. "What is this entity's disposition toward this faction given everything it has witnessed" is a multi-way join. Written naively against a large uncompacted log, those rules will hurt.

The mitigation is compaction used diligently. The pre-apocalypse dagger works because the author compacted its history at meaningful closure boundaries — rules fire against a single profile fact, not against raw history. The King Lich hurts if the author doesn't do the same. His disposition toward the Northern kingdoms should be summarised when that chapter of his history closes. Rules fire against the summary. The raw history goes cold. The join stays small.

Compaction is therefore not just a performance optimisation — it is the authorial act that keeps rules correct and tractable as history accumulates. An author who never compacts is an author whose joins will eventually explode. The engine evaluates them; they do not directly mutate the world. They declare events; they do not assert facts, modify state, or call procedures. The engine takes the declared event, injects it into the rule's scene, and gate topology handles propagation from there. The rule's job ends at declaration.

---

## The clock

The clock is a single integer that advances in discrete steps. It is the world's definition of time.

The clock orders actions — it annotates when something happened in the world's terms. It does not drive the simulation and it does not order consequences. That is provenance's job.

When a player acts, the clock advances. Everything the fixpoint derives from that action — every consequence, every triggered rule, every gate crossing — is stamped at the same clock tick as the action that caused it. The cheat and the catching both land at tick 40. The clock does not say which came first. Provenance does: "caught cheating" has provenance pointing to "cheat" as its cause. That causal chain is the ordering that matters.

This means two events at the same clock tick are either causally related — in which case provenance orders them — or causally independent — in which case their relative order genuinely does not matter, and treating them as unordered is correct rather than ambiguous.

The clock and provenance answer different questions. The clock tells you when something happened in the world's terms. Provenance tells you why it exists at all. Neither needs to do the other's job.

Different parts of the simulation can advance the clock at different rates. A player turn might advance it by 600 (ten minutes). A combat exchange advances it by 10. A sub-simulation running at high resolution might advance it by 1 per internal step. Time is unidirectional — the clock never goes backward. But events can be recorded with past clock values: a sub-simulation that runs and produces results can inject those results into the parent world with the clock values from when they happened inside the simulation. The log is not a tape that plays in real time. It is a complete record that is always fully queryable.

---

## The fixpoint

The fixpoint is how the engine finds the stable state of the world after something changes.

When an event arrives, it might trigger scene rules that generate more events, which cross gates into other scenes, which trigger more scene rules, which generate more events. This cascade continues until no new events are generated — until the world is stable. That stable state is the fixpoint.

The engine runs this cascade automatically. You do not write the cascade. You declare the rules and the gates, and the engine finds the fixpoint for you. At the logical level, consequences fire in the right order: a rule cannot fire until its input facts exist in the scene's log, so causal dependencies enforce ordering. "Caught cheating" cannot arrive before "cheat" because it exists only in "cheat's" provenance chain — the dependency is logical, not temporal. The clock does not enforce this order; provenance does.

What the model guarantees and what Prolog's execution model guarantees are different things. The logical ordering guarantee is real. Prolog's clause execution order is not automatically optimal — a rule with multiple conditions executes them in the order written, and poorly ordered conditions produce redundant unification before the fixpoint stabilises. This is the join problem described in the scene rules section. The fixpoint finds the right answer; how expensively it does so depends on how the author wrote the rules.

The fixpoint can fail to terminate if rules generate an infinite cascade — rule A produces event X, which triggers rule B, which produces event Y, which triggers rule A again with a fresh term, forever. The engine has a depth guard against this. The right protection is authoring discipline: rules should converge, not amplify.

---

## Provenance

Provenance is the answer to "why does this fact exist?"

Every event in the log has a cause. A `drawn(card(3))` arrived because a scene rule fired. That scene rule fired because a `draw` event arrived. That `draw` event arrived because the player issued a command. The chain from cause to effect is the provenance.

The engine records provenance through a companion fact alongside every arrived event: what generated it, what triggered the generation, what simulation it came from. This is what makes investigation possible. A detective does not query timestamps — they query provenance chains. "Why is Greedypants dead?" is a question about causality, not about clock values. The provenance record is the answer.

Provenance also distinguishes events that look identical but have different origins. Two `drawn(card(3))` events might exist in two different hands. One arrived because a scene rule fired autonomously. The other arrived because the player issued a command. The events are the same shape. Their provenance is different. A cheat-detector queries provenance, not event shape.

---

## Sub-simulations

A sub-simulation is a scene graph that runs semi-independently from the main world. It has its own scenes, its own gates, its own scene rules, and potentially its own clock resolution. Its results cross a boundary gate into the parent world as summary events — projections of what happened inside, at whatever resolution the author chose to preserve.

A murder scene runs as a sub-simulation. Inside it, events accumulate at high resolution: the argument, the provocation, the strike, the fall. The parent world receives a single summary event: `murdered(greedypants, weapon(dagger))`. The internal detail may be retained for investigation or discarded for compaction. The parent world reasons from the summary. An investigator with access to the sub-simulation log can follow the provenance chain deeper.

Sub-simulations are the engine's answer to the Dwarf Fortress problem: how do you simulate something in detail without burdening the main world with all that detail? You run it separately, project the outcome upward, and discard or archive the internal log according to the story's needs.

---

## The author and player interaction model

The author's role is world-builder, not programmer. Pick the scenes, wire the gates, declare the initial conditions, provide the starting canonical log. The simulation does the rest. That is a meaningful and bounded creative responsibility — the author is not writing behavior, they are declaring structure and initial state.

The system is self-documenting by design. Command discovery is a query against what gates are currently open and what vocabularies are reachable from the player's current position in the scene hierarchy. Validation is gate conditions. Failure is a logged fact with provenance. Success is an event in the log with a causal chain. None of this requires a separate interaction layer — it is all already in the log and the topology.

The player interacts by injecting events. A command is an event injection. The fixpoint does the rest. Command success, failure, and consequence are all readable from the log after the fact — or queryable in advance from the gate topology.

**The projection interface is the primary open design problem.** The model is sound; the gap is not conceptual but ergonomic. Getting Prolog to surface the right structured information at the right granularity — for any interface layer to present a coherent experience — is the real engineering challenge. A Python or other wrapper is trivial; the hard part is defining the set of named projections that give the interface enough structured information to work with. Probably something like:

- Current legal actions in this scene context
- Why a given action is currently blocked
- What just changed and why (post-fixpoint summary)
- What is knowable from the player's current position in the hierarchy

Each of these is a projection of the log, and each needs to be designed as a first-class predicate, not a one-off query. This is listed separately in the unsolved problems as *query ergonomics* — it is the authoring interface problem, distinct from narration. Narration is what the player sees. This is what the system needs to expose for any interface to work at all.

A world is a hierarchy of scenes connected by gates. Leaf scenes declare vocabularies. Composite scenes declare relationships. Gates connect scenes and give events direction, conditions, and transforms. Scene rules declare consequences. The clock annotates when things happen. The fixpoint finds the stable state after each change. Provenance records why each fact exists.

The player — or the author, or an AI collaborator — interacts with the world by injecting events. A command is an event injection. A player issuing `draw_card` is asserting that a `draw` event has arrived at the deck scene. The fixpoint does the rest.

The world does not wait for instructions. It responds to its own history. The barkeeper does not decide to become suspicious — the scene rule fires when the log contains enough evidence of suspicion-worthy events. The warrior does not decide to fall — the defeat rule fires when the damage log crosses the threshold. The engine is not a loop that asks objects what to do next. It is a consequence machine that reads the log and finds what must follow.

---

## Probes

A probe is a shallow, read-only vocabulary query. It asks: what rule heads exist in this scene, and what gates lead out from here. One step, no deeper. No gate conditions are evaluated. No rules fire. Nothing is logged.

The scene's rules are its vocabulary declaration — there is no separate meta-fact listing what events a scene accepts. The probe reads rule head terms at depth 1 and surfaces them. This is the **vocabulary surface** of a scene: the set of event shapes a scene knows how to respond to. When you add a rule, you expand the vocabulary surface, and the full consequence space of that expansion is yours as the author.

What the probe returns is the scene's **reachability** — the set of rule heads visible from the current position. This is more precise than "possibility": possibility is a property of the rule; reachability is what the probe surfaces from a specific scene at a specific moment. The distinction matters because the same rule head may be reachable from one scene and not another depending on gate topology.

This is intentional on all three counts.

**Depth 1** eliminates recursion and cycle problems entirely. A probe does not traverse the topology — it looks one step out from the current position.

**No condition evaluation** means the probe answers "what is reachable" not "what is currently permitted." Permission is for gate conditions to govern when an event is actually injected. The probe does not pre-evaluate whether the attempt will succeed.

**No logging** means a probe cannot accidentally trigger the fixpoint or leave provenance traces. It is a read-only inspection of declared structure, not an action.

The practical consequence: the player can always be shown what vocabulary exists at their current scene and what gates lead out of it. Whether any given action will succeed depends on gate conditions at injection time — that is not the probe's concern. You can always tell the elven king you enjoy chopping down trees. The engine will record it faithfully and find the consequences. Discouraging you is not its responsibility.

**Unintended activation paths** are a first-class authoring concern, not a failure mode. If a player finds an event that satisfies a rule the author didn't expect to be reachable in this context and injects it successfully, that is not a bug — it is the model working correctly. The author declared the consequence; the player found an unexpected path to trigger it. The log records it with full provenance. The world responds. Authors are responsible for the full consequence space of every rule they write, not just the intended activation paths. The catalog's boundary tests deliberately probe unintended activation paths to verify that their consequences are either acceptable or intentionally left open as mechanics.

Probes complete the triad: probes expose reachability, gate conditions govern permission, the fixpoint enforces legality.

Whether visibility and propagation are the same gate property — whether a gate that blocks event propagation also blocks probe reachability — is an open question. An author may want gates that are topologically visible to a probe but conditionally closed to propagation, or gates that are invisible to a probe entirely. That distinction is not yet in the model.

---

**Investigation.** Because the log is permanent and provenance is recorded, any fact can be traced back to its causes. A detective story is just a world where the player's goal is to traverse provenance chains. The engine supports this natively — no special machinery required.

**Reusability.** Because scenes declare vocabularies and gates declare relationships, the same scene can appear in any world that needs it. A deck is a deck everywhere. The gambling room, the magic ritual, the chaos room — they all use the same deck scene, connected by different gates.

**AI-assisted authoring.** The engine's vocabulary is small but the authoring discipline is not. A capable model in a focused session can meaningfully contribute to scene design, gate declarations, and rule authoring — but only within a scope where the human collaborator understands the failure modes well enough to evaluate the output. The specific prerequisites are now nameable: understanding join order in rule conditions, recognizing unbounded cascade patterns, writing propagation tests at gate-authoring time, and understanding closure boundaries. That is not a general "systems intuition" — it is a specific set of concerns that must be understood before AI-assisted authoring produces reliable results rather than plausible-looking topology with dark reachability the author doesn't know exists.

This document's own development demonstrates what the collaboration looks like when the prerequisites are met. It does not demonstrate that the prerequisites can be skipped.

What this requires honestly: dedication, enough domain knowledge to evaluate what the model produces, and a well-scoped session. Global coherence remains the author's responsibility. Verification tooling — `verify_contracts` and the catalog as a test suite — reduces but does not remove that responsibility.

**Narration from the same substrate.** What the player sees is a projection of the log — filtered through gates, shaped by provenance. The narration layer does not need special access to world state. It reads the same log as everything else. "Your armour absorbed 5 points" is a query against `gate_transformed`. "The warrior falls" is a query against the defeat rule's output in `arrived`. The story is always already in the log.

---

## Log lifecycle and narrative closure

The log is append-only and permanent, but permanent does not mean every fact must be equally available to every query at every moment. For long-running simulations, scanning the entire log on every fixpoint evaluation is impractical. The solution is a tiered log lifecycle — but the tiers are not a technical optimisation. They are a first-class authoring concept.

**A note on scale.** A single authored narrative — a murder mystery, a duel, a political intrigue — will typically produce a few hundred arrived facts. At roughly 200 bytes per Prolog dynamic fact, an entire Rex Stout Nero Wolfe novel modelled at reasonable granularity fits in under 100 kilobytes. The complete published corpus fits in under 2 megabytes. For story-scale content, the entire log lives comfortably in memory and the hot/cold/archived distinction is a narrative primitive, not a performance necessity. The cost semantics and tiering machinery become real in a different regime: a persistent world running for months with thousands of player interactions and accumulated history. Design for that regime if you are building that. Do not design for it if you are writing Fer-de-Lance.

Every event in the log exists in one of three states, each with different access costs:

**Hot.** The event is live for rule evaluation. The fixpoint scans hot events. Scene rules fire against them. This is the default state for any recently arrived event. Cheapest to query.

**Cold.** The event has been declared narratively settled for the current scope. The fixpoint does not scan cold events — they do not trigger rule evaluation. They are still in the log, still readable by rules as background context when a hot-triggered rule asks for them, still part of the provenance record. A rule fires because a hot event arrived; it may consult cold facts as part of its condition check. The cold fact is evidence, not a trigger. More expensive to query than hot — the cost is real and visible, not hidden.

**Archived.** The event has been explicitly closed and moved to disk-backed storage via `library(persistency)`. Not scanned, not consulted in normal queries, but permanently retained for investigation, provenance tracing, and backfill purposes. Pays a disk access cost when queried.

The tiers have different costs by design — this is not an implementation accident. An author writing a rule that consults cold or archived history is making an explicit choice with a known cost. The pre-apocalypse dagger's deep history lives in cold or archived storage; rules that need it pay accordingly. An entity like a King Lich whose conversational rules reach into archived storage on every interaction is supported — but the author allocates that complexity budget knowingly.

The transitions between these states — hot to cold, cold to archived — are declared by the author at meaningful story moments. Not computed. Not inferred from the rule dependency graph. Declared.

**Closure is an event, not a meta-operation.** It propagates through gates like any other event. A patron scene declaring closure produces a `closed(scene, clock(N))` event that travels the same inward gates that other events from that scene travel. A composite scene — the tavern — receives it and can fire rules on it, or not, if no rules care. This means closure is visible to the topology, subject to gate conditions, and carries provenance. A composite scene can know that a chapter of its children's history is closed and compact its own filtered aggregate accordingly. What it does with that knowledge is an authoring decision.

This is intentional. Whether a set of facts is "done" is not a technical question the engine can answer in general — it would require knowing all rules that will ever be authored, including rules not yet written. It is a narrative question: is this chapter closed for the story we are telling from this point forward? Only the author can answer that.

The right concept is therefore not stability but **closure**. A closure declaration says: for the simulation proceeding from this point, these events are settled. It does not say they are globally irrelevant or technically inert. It says the author is drawing a line, and consequences that cross that line travel as new events, not as re-evaluations of old ones.

A banishment, a confession, a regime change — these are narrative events that are already meaningful in the story. The author is not adding compaction machinery on top of the story. The closure *is* the story event. The engine records it as a canon fact with its own provenance, and from that point forward the settled facts are cold.

### Resurfacing closed facts

Closure is not permanent sealing. The log's past can become narratively relevant again in two legitimate ways.

**Investigation.** A faction learns you supported their opponents. A player discovers a pattern in old events. A detective queries the archive. In all these cases, the old facts do not change — and the engine does not re-run the fixpoint against them as if they were hot again. Instead, a new event arrives in the log: something like `learned(faction_a, supported(player, faction_b), clock(34))`. The fixpoint evaluates the consequences of that event — the consequences of the learning — not of the original. The old fact is evidence; the new event is what changes the world. The scope of re-evaluation is naturally bounded: only rules that fire on `learned(...)` events are in play.

**Backfill.** The author needs to construct history that was always implied but never explicitly logged — a satisfying explanation for a current state, a sub-simulation being resolved after the fact, a scene whose internal detail was deferred. The author injects past-timestamped events into the log. The engine supports this natively — events carry clock values and provenance, and an injected past event carries authoring provenance that makes its origin visible. The fixpoint does not re-run against backfilled events as live consequences; the author is declaring settled history, not triggering new propagation.

The distinction between backfill and retcon matters here. Backfill is filling in history that was always implied — the author is making legible what was always true in the world's terms, before any query depended on its absence. Retcon would be changing history that was already queried against and used to derive state. The engine's permanent log makes retcon visible as a contradiction rather than a seamless revision: the original events are still there, and any derived state computed from them is still in the provenance record. You cannot silently overwrite what was already logged.

## The learned pattern

When a closed fact becomes narratively relevant again, the mechanism is simple: `learned(Agent, Fact, SourceClock)` arrives as an event in the Agent's scene. Scene rules fire on it if they exist. If no rule in that scene cares about the fact, nothing happens. The matchbox collection arrives everywhere it could theoretically be learned, and produces no cascade, because no scene has a rule that makes matchbox collections consequential. That is not a limitation — it is the model working correctly.

The learned ruleset is not designed in advance as a general system. It emerges from the tension graph — which is the gate topology read from a different angle. A gate between two scenes is a declared relationship, and every relationship is a potential tension. The scenes reachable from a fact's origin through the gate topology are the scenes that can receive the fact. Of those, the ones with existing rules that care about the fact's domain are the ones that need `learned` rules if knowledge-activation matters.

A gate that routes theft events to a city registry declares a surveillance relationship. That relationship implies a tension. The `learned` rule for that tension is a natural part of authoring the registry scene — not a separate overhead. Gates and tensions are the same artifacts read from two angles.

**The confidence and source extension is deferred research, not deferred repair.** The basic `learned(Agent, Fact, SourceClock)` pattern is sufficient to build on. Extending it to `learned(Agent, Fact, Source, Confidence)` is not a patch for a known deficiency — it opens a design space that warrants its own catalog section when a concrete story demands it. An agent whose belief state is a log of learned events — with sources, confidence levels, and provenance — can have contradictory beliefs, be deliberately misinformed, discover that a source lied, and update accordingly. All of that falls out of the same log-accumulation model without new engine primitives.

The mechanics that follow are genuinely interesting and are catalog candidates:

- A forged document is a `learned` event with false provenance
- A retraction is a new `learned` event that contradicts an earlier one
- An unreliable narrator is a gate condition on source credibility
- Espionage is a `learned` event arriving through a path the topology wasn't supposed to permit

None of this requires the engine to understand truth. It requires the log to contain enough provenance that a rule — or a player — can evaluate source credibility from evidence.

---

## The catalog

The catalog is where the engine meets the world. The primitives are small and general; the catalog is where their expressive range is demonstrated. It is the set of reference scenes, gates, and rule patterns that show what the engine can model, stress-test its guarantees, and give authors a vocabulary to build from rather than starting from first principles.

It serves three audiences:

**Engine developers.** Each catalog entry is a test case for the fixpoint, provenance, closure, and gate behavior. The catalog is simultaneously a design tool and a test suite.

**Authors.** Each entry is a proven pattern: this is how you model surveillance, this is how sound propagates, this is how a reputation system works, this is what learned rules you need if you use this gate. The richer the catalog, the more expressive the authoring becomes without requiring new engine primitives.

**The engine's honest limits.** Catalog entries make explicit what the engine enables and what the author must provide. A gate that routes gossip exists in the catalog as a pattern. Whether gossip matters in a given world depends on what rules the author writes. The catalog shows the mechanism; the author provides the meaning. A gate declares a potential tension — whether it produces tension depends on what rules the receiving scene has. The catalog should never imply that gates automatically generate drama.

**Propagation tests are load-bearing catalog documentation.** A catalog entry without propagation coverage — tests that enumerate what event types reach which scenes under which conditions — is not a finished entry. Catalog tests validate known behavior; propagation tests make the topology's implications visible before a novel world assembles them in unexpected ways. The composition problem — unit tests don't cover emergent behavior at integration — is real and is addressed by shipping propagation tests with every gate, not by trusting that the parts behave as expected when combined.

The catalog is never complete, by design. It grows as the engine is used. New scenes and gates added to it are contributions to the authoring vocabulary, not patches to the engine. That distinction keeps the engine stable while the expressive range expands.

The catalog will eventually be its own document. For now it lives in the `scenes/` and `gates/` directories — each POC scene and gate is a catalog entry in embryonic form.

---

## Authoring warnings

These are not formal guarantees — they are patterns that tend to cause problems, translated into story terms. They apply equally to human authors and AI collaborators. No CS degree required to recognise them.

**The echo chamber.** A rule that generates an event of the same type it responds to. The tavern gets louder because it's loud, which makes it louder. Gossip spreading through a network is fine — gossip amplifying itself without a floor is not. If your rule's output looks like its input, ask: what in story terms makes this stop? If you can't answer that, the rule isn't finished. A riot that escalates because there's a riot has no natural floor. A riot that escalates until the guard arrives does.

**The open cascade.** A chain of rules where each consequence enables the next and you haven't defined an end condition. A reputation system that recalculates reputation from reputation. A suspicion that deepens because someone is acting suspicious because they're under suspicion. If you can't name the story condition under which the cascade settles — the arrest, the apology, the death, the treaty — the rule set is incomplete. The end condition is part of the design, not an afterthought.

**The omniscient rule.** A single rule whose conditions span too many scenes simultaneously. If firing correctly requires knowing the dagger's history, the lich's disposition, the player's lineage, and the current state of three factions, the rule will either explode combinatorially or produce surprising results when any one of those scenes is sparse or cold. Decompose it. A rule that needs to know everything probably should be several rules that each know one thing, connected by intermediate events.

**The invisible route.** A gate you added for one purpose that transitively connects scenes you didn't intend to connect. Undetected because no rule currently fires on the routed event — until one does. The engine will gleefully do exactly what you told it to do. Propagation tests written at gate-authoring time catch this. Propagation tests written after the world is large don't, because you no longer know what "unexpected" looks like. Every gate added to the catalog ships with propagation coverage as part of what makes it a valid entry. An entry without propagation tests is not a finished catalog entry.

**The symptom to watch for.** The fixpoint depth guard triggering is a bug report, not a safety feature. If it fires, something in the rule set is poorly bounded. Note which rule triggered the cascade and what the chain looked like — that information is worth reporting. The guard exists to prevent a hang; it does not explain or fix the underlying problem.

The fixpoint has three distinct failure modes during development:

**Infinite cascade.** A rule generates an event that triggers itself, directly or through a chain. The depth guard catches it by exhaustion, producing a hang followed by cryptic termination with no indication of which rule started the cycle. Prevention: write a termination test for every new rule at authoring time — inject a single event and assert the fixpoint terminates within N steps. Make this a required catalog entry component.

**Silent incompleteness.** The fixpoint terminates correctly but doesn't produce the expected consequences. No error, no warning — just missing events. This happens when a gate condition silently fails, when rule conditions are ordered poorly and never unify, or when a closure declaration moved facts to cold before a rule that needed them fired. This is the most dangerous failure mode because it is invisible — the world appears to work, it just doesn't do what was intended. Prevention: post-fixpoint summary projections that enumerate what rules fired and what didn't. Without this you are debugging by absence.

**Correct but expensive.** The fixpoint finds the right answer but takes unacceptable time because a rule joins across cold or archived history with low selectivity. Invisible at development scale, painful as history accumulates. Prevention: compaction at closure boundaries from the start, and explicit cost annotations in catalog entries for rules that consult cold history.

All three failure modes share a common cause: the fixpoint is a black box during development. The single highest-value development tool is a fixpoint trace mode — a flag that logs every rule evaluation attempt, every gate condition check, every event generated, in causal order. This is listed separately in the unsolved problems section.

---

This is a living design. The following problems are known, named, and deferred — not forgotten.

**Log tiering implementation.** SWI-Prolog provides two storage tiers natively: in-memory dynamic facts (hot and cold) via standard `assertz/retract`, and disk-backed persistent facts (archived) via `library(persistency)`. What it does not provide is automatic tier management — promoting facts from hot to cold to archived based on declared policies is engine work. The storage primitives exist; the policy layer is ours to implement. Cold facts are not free to read: a rule consulting cold history pays a real cost that a rule consulting only hot facts does not. Archived facts pay a disk access cost. Rules that span tiers should be declared as such — not forbidden, but deliberate. The King Lich problem is now precisely stated: an entity whose conversational rules reach into archived storage on every interaction is supported by the engine but the author pays a known cost. The catalog will document what that cost looks like in practice and how to manage it through compaction and summary projections.

**Rule termination discipline.** This is the one open problem with a non-graceful failure mode. Every other unresolved item — query ergonomics, narration policy, tiering implementation — fails by being incomplete or inconvenient. Unterminated fixpoint evaluation hangs or crashes the engine. That is a different category of failure.

The current depth guard in `advance_world/1` is a blunt instrument: it stops the cascade at `MaxDepth` iterations regardless of why it is still running. It catches infinite loops by exhaustion, not by detecting them. A defined termination contract — one that makes authoring discipline checkable — does not yet exist.

The following heuristics are directional but unproven. They are candidates for future `verify_contracts` rules:

- Rules should not generate events of the same type as their triggering condition
- Events generated by a rule should be strictly more specific than the events that triggered them
- Gate transforms should reduce or preserve event specificity, not amplify it

The catalog is the right place to stress-test these. A rule that violates one of them is a test case for the depth guard. Until a termination contract is defined and checkable, the depth guard is a ceiling on how badly things can go wrong — not a guarantee that they won't.

**Event identity and deduplication.** The engine deduplicates arrived facts by `(Target, Source, Clock, Term)`. This works for ground terms but has edge cases when terms contain variables or when two logically identical events arrive via different paths. The right identity model for events — especially for sub-simulation injected events — is not yet settled.

**Fixpoint trace mode.** The single highest-value development tool not yet built. A flag that logs every rule evaluation attempt, every gate condition check, and every event generated during fixpoint evaluation, in causal order. Without it, debugging silent incompleteness — the most dangerous failure mode — requires reasoning from outputs alone. SWI-Prolog's existing spy/trace machinery may provide enough of this for simple cases; whether it is sufficient for the full fixpoint evaluation loop is untested. This is a development tool, not a production requirement, but its absence makes the fixpoint a black box during authoring. Nothing currently prevents an author from declaring closure on facts that active rules still depend on. The engine will not warn. The verify_contracts predicate is mentioned in the context of rule termination heuristics, not closure correctness. A closure that severs a dependency silently produces incorrect rule behaviour without any signal. The propagation tests discussed in the catalog section help with gate topology; they do not obviously extend to closure correctness. This is a known gap with no current mitigation beyond authoring discipline.

**Composite scene closure propagation.** When a child scene declares closure, the implications for a composite scene that has been conditionally aggregating that child's events are not fully specified. The model says closure is an event that propagates upward through inward gates — the composite scene receives a closed(...) event and can respond to it. Whether that response should include compacting the composite scene's own filtered aggregate, and how that interacts with the sub-simulation boundary problem, is open. This maps directly onto the sub-simulation boundary question listed separately. When an event crosses a gate through a composite scene on its way to a leaf scene, it is currently unspecified whether the composite scene's log receives that event. This matters for the fixpoint: if composite scenes log transit events, rules declared at the composite level could fire on them. If they don't, composite scenes are purely structural. The guide assumes the latter but does not state it.

**Epistemic state model.** "What is knowable from the player's current position in the scene hierarchy" is listed as a projection interface concern but is actually a core model question. What the player can know determines what actions are meaningful. The current model has no account of player epistemic state — what scenes are visible, what events are knowable versus merely present in the log. This is deferred but it is load-bearing for any authored story with hidden information, which is most stories. Causally dependent events at the same clock tick are ordered by provenance — the causal chain is the ordering relation. Causally independent events at the same tick are genuinely unordered, which is correct rather than ambiguous. The remaining open question is whether the engine needs to enforce that rules declare their causal dependencies explicitly, or whether the provenance record is sufficient as a post-hoc ordering mechanism.

**Sub-simulation boundaries.** The primitive model does not yet have a clean answer for what distinguishes a scene from a sub-simulation from a simulation boundary. The `scene_parent` hierarchy handles structure; it does not handle identity, retention policy, or clock autonomy. This is Session 3's primary question.

**Query ergonomics.** Querying the log directly in SWI-Prolog is tractable for a developer but not for a player or an AI collaborator generating narration. What a convenient query interface looks like — whether it is a library of named projections, a meta-predicate, or something else — is not yet designed.

**Narration policy.** What the player sees is a projection of the log. But which projections, filtered how, rendered in what form, at what level of detail — these are authoring decisions that the engine makes no attempt to govern. The narration layer is intentionally out of scope for now, but its absence means the gap between "engine works correctly" and "game is playable" is currently bridged by the REPL's raw output.

**Gate block messages and `:why` tracing.** When a gate blocks, the failure is currently silent. `gate_block_message/3` is declared but the resolver predicate is not implemented. The `:why` diagnostic — a unified query that explains a gate's full behaviour, what blocked it, what it rewrote, and why — is the planned solution but is not yet built.

---

## Formal invariants

These hold throughout the system. They are not implementation goals — they are properties the engine must maintain for the model to be coherent. If an implementation violates any of these, the model's reasoning guarantees break down.

**The log is append-only.** Facts are never deleted or overwritten. Closure moves facts to cold or archived status — it does not remove them. Retraction is not available as an authoring primitive.

**Provenance chains are acyclic.** An event's provenance points to its causes, which point to their causes. This chain always terminates at a player action, an authoring injection, or a simulation boundary. A cycle in the provenance graph means an event is its own cause, which is not permitted.

**Probes are side-effect free.** A probe does not log events, does not trigger rule evaluation, does not advance the clock, and does not alter any fact in the database. A probe that has side effects is not a probe — it is an action.

**Gates never mutate source events.** A gate transform produces a new event term for the destination scene. The original event in the source scene's log is unchanged. `gate_transformed/5` records the rewrite; it does not alter the arrived fact that triggered it.

**Fixpoint evaluation is monotonic.** Each fixpoint iteration only adds facts — it never removes them. The arrived log grows until stable. A rule that retracts facts during evaluation breaks the monotonicity guarantee and makes termination unprovable.

**Closure never deletes evidence.** A closure event marks facts as cold or archived. It does not erase them. Provenance chains through closed facts remain traversable. Investigation queries can always reach archived history if the author chose to retain it.

**Scene rules read only their own scene's log.** A rule's conditions are evaluated against the facts arrived in the scene that owns the rule. Cross-scene reasoning happens through events crossing gates, not through rules querying foreign logs directly.

---

## What to keep in mind

The hardest intuition to shed is the actor. There are no actors in this engine. The deck does not draw cards. The warrior does not attack. The barkeeper does not decide. There are only events that arrived, rules that fire when conditions hold, and gates that control what propagates where. Everything that feels like an actor is a scene with rules. Its behaviour is the set of scene rules that read its log.

The second hardest intuition is mutation. Nothing is ever overwritten. The deck's order did not change when it was shuffled — a new shuffle event arrived, and the derived projection now returns a different answer. The old order is still there. The history is intact.

The third hardest is sequence. The fixpoint does not run in the order you wrote the rules. It finds the stable state. Dependencies define sequence implicitly — a consequence only fires when its inputs have already arrived. You declare what follows from what; the engine finds the order.

The fourth hardest intuition is revision. Nothing in the log can be silently overwritten. Old facts can be closed, surfaced as new knowledge, or explained by backfilled history — but the original record remains. If two versions of history coexist in the log, the contradiction is visible in the provenance record.

---

## Anti-goals

This engine does not do these things. If you find yourself expecting any of them, you are outside the model's scope.

**Not a planner.** The engine does not find sequences of actions that achieve goals. It finds the stable consequences of actions that were taken. Planning is an authoring or player concern, not an engine concern.

**Not an actor simulation.** There are no agents with internal decision loops, utility functions, or behavioural trees. An NPC that appears to decide is a scene with rules that fire when conditions hold. The NPC does not decide — the rules declare what follows.

**Not a physics engine.** The engine has no concept of space, position, collision, or continuous quantities. Events are discrete. Scenes are topological, not geometric. Distance is a gate condition, not a coordinate.

**Not globally optimized.** The fixpoint does not find the most efficient path to a stable state. It finds a stable state by iterating until nothing changes. Rule clause ordering is the author's responsibility. There is no query planner.

**Not an automatic narrative generator.** The engine records what happened and makes it queryable. It does not decide what to narrate, when to narrate it, or how to frame it for a player. Narration is a projection the author or a separate layer produces from the log.

**Not eventually consistent.** The fixpoint runs to completion within a clock tick before the next action is processed. There is no asynchronous propagation, no delayed consistency, no convergence window. The log is fully consistent at every fixpoint boundary.

**Not a consciousness simulator.** A scene that models a mind is still a scene with rules and a log. It does not have beliefs, intentions, or awareness in any meaningful sense. It has events that arrived and rules that fire. The appearance of mental states is an authoring effect, not an engine property.

**Not self-modifying.** The engine does not rewrite its own rules during evaluation. Scene rules are declared before the fixpoint runs. A rule that asserts new rules as part of its consequences is an authoring error, not a feature.

