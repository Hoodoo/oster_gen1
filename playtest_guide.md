# Oster Playtest Guide

A reference for authors playtesting scenes in the Oster REPL.

## A — Basic Playtest Sequence

Start the REPL:

```bash
swipl -g "use_module(repl/repl), start_repl" -t halt
```

**A1 — Explore the topology**

```prolog
scenes.
gates.
```

Confirm the scene tree and all declared gates with their open/closed status.

**A2 — Inject an event and check outbound routing**

```prolog
inject(patron_a, strike(5)).
summary.
outbound(patron_a, noise(fight)).
```

`outbound/2` shows whether `noise(fight)` would currently leave `patron_a` through a gate, and if not, why not. After the strike, the cascade produces noise — confirm it propagated.

**A3 — Inspect a scene**

```prolog
log(patron_a).
log(tavern).
log(street).
```

**A4 — Check provenance**

```prolog
chain(evt_1).
```

---

## B — Authoring Patterns

**B1 — Locked door (gate with a third-party condition)**

A common mistake: modelling a locked door as a self-loop gate (`door, door, lateral`).
That conflates the door's own history with the two rooms it separates.

The correct pattern uses three scenes — the door's own log, plus the two rooms it connects:

```prolog
% Declare scenes: the door's own history, and the two rooms it separates
declare_scene(door).
declare_scene(hallway).
declare_scene(study).

% A key_used event unlocks the door — this is the door's own history,
% independent of any particular gate.
declare_scene_rule(r_unlock, door,
    arrived(_, door, key_used, _, _),
    unlocked).

% Gate: enter may only cross from hallway into study if the door is unlocked.
% The condition reads a third scene's log, not either endpoint's.
declare_gate(g_open, hallway, study, lateral).
assertz(gates:gate_condition(g_open,
    arrived(_, door, unlocked, _, _))).
assertz(gates:gate_term_filter(g_open, enter)).
```

Playtest sequence:

```prolog
inject(hallway, enter).   % should be blocked
outbound(hallway, enter).
inject(door, key_used).   % unlocks it
inject(hallway, enter).   % should now cross
log(study).
```

**What to look for:** After `key_used`, `outbound(hallway, enter)` should report `gate_is_open(g_open)` (meaning it would cross). After the second `inject(hallway, enter)`, `log(study)` should show the `enter` event arrived.

**What will probably crumble:** `check_rules_locality` does not flag gate conditions that read a scene other than the gate's source or destination. The condition above reads `door`, which is neither `hallway` nor `study`. This is intentional — gate conditions are explicitly allowed to reach into third-party scenes — but the locality checker does not track it.
