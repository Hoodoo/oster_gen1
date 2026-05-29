# Session 9b — Repository Cleanup

## What this session is

This is a housekeeping session between Session 9 and Session 10. No new engine
code is written. No new tests are written. The goal is to normalise the
repository structure so that all future sessions work from a clean, unambiguous
layout.

At the end of this session, all existing tests must still pass, the repository
tree must match the canonical layout described below, and no source files may
have been lost or modified.

---

## Background: what happened

Session 0 created placeholder directories at the repository root using `oster/`
as the target. However, all implementation work from Sessions 1–9 went into
`scene_engine/` — the actual working directory Claude Code found itself in.
This left two parallel structures:

- **`scene_engine/`** — contains all real code, tests, and catalog entries
- **Root-level ghost directories** (`engine/`, `lifecycle/`, `projections/`,
  `verify/`, `repl/`, `tests/`, `catalog/`) — empty scaffolding with `.gitkeep`
  files only, never populated

Additionally:
- `docs/concept_guide.md` and `docs/conceptual_guide.md` are duplicates
- `docs/superpowers/` is an untracked artefact that does not belong in the
  canonical structure

The fix is: promote `scene_engine/` contents to the repository root, remove
the ghost directories and duplicate files, verify all imports still resolve,
and confirm all tests still pass.

---

## Canonical layout after this session

```
.
├── AGENTS.md
├── CLAUDE.md -> AGENTS.md
├── README.md
├── catalog/
│   ├── README.md
│   ├── deck/
│   │   ├── scene.pl
│   │   └── tests.pl
│   ├── tavern/         ← placeholder (.gitkeep)
│   └── warrior/        ← placeholder (.gitkeep)
├── docs/
│   ├── conceptual_guide.md
│   ├── deferred.md
│   ├── implementation_plan.md
│   ├── session_logs/
│   │   ├── session_01.md … session_09.md
│   └── sessions/
│       ├── session_00_prompt.md
│       ├── session_01.md … session_12.md
├── engine/
│   ├── clock.pl
│   ├── fixpoint.pl
│   ├── gates.pl
│   ├── log.pl
│   ├── probes.pl
│   ├── provenance.pl
│   └── scenes.pl
├── lifecycle/
│   ├── closure.pl
│   ├── compaction.pl
│   └── tiers.pl
├── projections/
│   ├── investigation.pl
│   ├── legal_actions.pl
│   ├── post_fixpoint.pl
│   └── why_blocked.pl
├── repl/               ← placeholder (.gitkeep)
├── tests/
│   ├── fixpoint_tests.pl
│   ├── gate_tests.pl
│   ├── lifecycle_tests.pl
│   ├── log_tests.pl
│   ├── probe_tests.pl
│   ├── projection_tests.pl
│   ├── provenance_tests.pl
│   └── verify_tests.pl
└── verify/
    ├── contracts.pl
    ├── invariants.pl
    └── propagation.pl
```

`scene_engine/` does not appear in this layout — it is removed entirely after
its contents are promoted.

---

## Steps

Execute in order. Do not proceed to the next step if a step fails.

### Step 1 — Copy source files from `scene_engine/` to repo root

The following copies move real files into their canonical locations. Use `cp`
not `mv` at this stage — keep `scene_engine/` intact until tests pass.

```bash
cp scene_engine/engine/*.pl engine/
cp scene_engine/lifecycle/*.pl lifecycle/
cp scene_engine/projections/*.pl projections/
cp scene_engine/verify/*.pl verify/
cp scene_engine/tests/*.pl tests/
cp scene_engine/catalog/deck/scene.pl catalog/deck/
cp scene_engine/catalog/deck/tests.pl catalog/deck/
```

### Step 2 — Fix relative imports in all copied files

Every `.pl` file uses relative `use_module` paths like `'../engine/log'`.
After promotion these paths are unchanged in depth for most files, but
`catalog/deck/scene.pl` and `catalog/deck/tests.pl` used
`'../../engine/...'` paths which are now correct since `catalog/deck/` is at
the same depth relative to `engine/` as before.

Audit every file for `use_module` paths and confirm they resolve correctly
from their new locations:

- `engine/*.pl` — no relative imports to other engine files beyond
  `use_module(library(...))` — no changes needed
- `lifecycle/*.pl` — imports `'../engine/...'` — correct, no change
- `projections/*.pl` — imports `'../engine/...'` and `'../lifecycle/...'`
  — correct, no change
- `verify/*.pl` — imports `'../engine/...'` — correct, no change
- `tests/*.pl` — imports `'../engine/...'`, `'../lifecycle/...'`,
  `'../projections/...'`, `'../verify/...'` — correct, no change
- `catalog/deck/scene.pl` — imports `'../../engine/...'` — correct, no change
- `catalog/deck/tests.pl` — imports `'../../engine/...'`, `'../../verify/...'`,
  and the deck scene module — verify the deck scene import path resolves

**The deck scene import in `catalog/deck/tests.pl`:** Session 9 resolved the
`deck_scene` vs `scene.pl` ambiguity with a `% DECISION:` comment. Check what
was actually written and confirm the import resolves from the new location.
If it uses a file path like `use_module(scene, [...])` or
`use_module('scene', [...])`, this is correct. If it uses a module name that
doesn't resolve, fix it to use the relative file path.

### Step 3 — Run all tests from the new locations

```bash
swipl -g "run_tests" -t halt tests/log_tests.pl
swipl -g "run_tests" -t halt tests/provenance_tests.pl
swipl -g "run_tests" -t halt tests/gate_tests.pl
swipl -g "run_tests" -t halt tests/fixpoint_tests.pl
swipl -g "run_tests" -t halt tests/probe_tests.pl
swipl -g "run_tests" -t halt tests/lifecycle_tests.pl
swipl -g "run_tests" -t halt tests/projection_tests.pl
swipl -g "run_tests" -t halt tests/verify_tests.pl
swipl -g "run_tests" -t halt catalog/deck/tests.pl
```

All tests must pass before proceeding. If any fail due to import path issues,
fix the paths in the affected file and re-run. If any fail for any other
reason, stop and report — do not proceed to Step 4.

### Step 4 — Remove ghost directories and `scene_engine/`

Only after all tests pass in Step 3:

```bash
# Remove ghost root-level placeholders (now superseded)
# These were empty .gitkeep directories from Session 0 — the real files
# are now at these paths, so the .gitkeep files need to go first
find engine lifecycle projections verify tests repl -name ".gitkeep" -delete

# Remove scene_engine/ entirely
rm -rf scene_engine/
```

`catalog/tavern/` and `catalog/warrior/` keep their `.gitkeep` files —
they are genuinely empty placeholders for future sessions.
`repl/` keeps its `.gitkeep` — it is a real future placeholder.

### Step 5 — Remove duplicate and stray files

```bash
# Remove duplicate guide (keep conceptual_guide.md, remove concept_guide.md)
rm docs/concept_guide.md

# Remove superpowers artefact directory
rm -rf docs/superpowers/
```

### Step 6 — Run all tests one final time

```bash
swipl -g "run_tests" -t halt tests/log_tests.pl
swipl -g "run_tests" -t halt tests/provenance_tests.pl
swipl -g "run_tests" -t halt tests/gate_tests.pl
swipl -g "run_tests" -t halt tests/fixpoint_tests.pl
swipl -g "run_tests" -t halt tests/probe_tests.pl
swipl -g "run_tests" -t halt tests/lifecycle_tests.pl
swipl -g "run_tests" -t halt tests/projection_tests.pl
swipl -g "run_tests" -t halt tests/verify_tests.pl
swipl -g "run_tests" -t halt catalog/deck/tests.pl
```

All must pass. This is the acceptance gate.

### Step 7 — Verify final tree

```bash
find . -not -path './.git/*' -not -name '.gitkeep' | sort
```

The output must match the canonical layout above. No `scene_engine/`,
no `docs/concept_guide.md`, no `docs/superpowers/`.

---

## What NOT to do

- Do not modify any `.pl` file's logic, predicates, or behaviour — only
  `use_module` import paths if they fail to resolve.
- Do not rename any predicate, fact, or module declaration.
- Do not touch `AGENTS.md`, `CLAUDE.md`, or `README.md`.
- Do not modify anything in `docs/` except removing `concept_guide.md`
  and `docs/superpowers/`.
- Do not commit until all tests pass and the tree is clean.

---

## Acceptance criteria

1. All 9 test suites pass from their canonical locations.
2. `scene_engine/` does not exist.
3. `docs/concept_guide.md` does not exist.
4. `docs/superpowers/` does not exist.
5. No `.gitkeep` files exist inside `engine/`, `lifecycle/`, `projections/`,
   `verify/`, or `tests/` — these directories now contain real files.
6. `docs/session_logs/session_09b.md` exists and contains the session report.

---

## Session report format

Save as `docs/session_logs/session_09b.md`:

```
# Session 9b Report — Repository Cleanup

## Changes made
- Promoted scene_engine/ contents to repo root
- Removed scene_engine/
- Removed docs/concept_guide.md (duplicate)
- Removed docs/superpowers/ (stray artefact)
- Removed .gitkeep files from now-populated directories

## Import path fixes
(list any use_module paths that required updating, or "none")

## Test results (final run)
- tests/log_tests.pl: N passed, 0 failed
- tests/provenance_tests.pl: N passed, 0 failed
- tests/gate_tests.pl: N passed, 0 failed
- tests/fixpoint_tests.pl: N passed, 0 failed
- tests/probe_tests.pl: N passed, 0 failed
- tests/lifecycle_tests.pl: N passed, 0 failed
- tests/projection_tests.pl: N passed, 0 failed
- tests/verify_tests.pl: N passed, 0 failed
- catalog/deck/tests.pl: N passed, 0 failed

## Anomalies, surprises, questions
(anything unexpected)
```

Do not produce the report until all tests pass and the tree is clean.
