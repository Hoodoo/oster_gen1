# Catalog

The catalog is where the engine meets the world. Each subdirectory is a
reference scene or gate pattern that demonstrates the engine's expressive
range, stress-tests its guarantees, and gives authors a vocabulary to
build from.

## Catalog entries

| Entry | Session | Status |
|---|---|---|
| deck/ | Session 9 | not started |
| warrior/ | Session 10 | not started |
| tavern/ | Session 11 | not started |

## What a finished catalog entry contains

- `scene.pl` — scene declarations, vocabulary, projections
- `gates.pl` — gate declarations (composite scenes only)
- `tests.pl` — plunit tests including propagation coverage

A catalog entry without propagation tests is not a finished entry.
