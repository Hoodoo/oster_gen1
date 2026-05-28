# Session 0 — Project Scaffolding

## What this session is

You are setting up the repository for Oster before any implementation begins. This session creates directories, placeholder files, copies reference documents into their canonical locations, and establishes the conventions every future session will follow.

No engine code is written in this session. No tests are written. No Prolog is written.

At the end of this session, the directory tree exists, the reference documents are in place, and the project is ready for Session 1 to begin.

---

## What you are NOT doing in this session

- Writing any `.pl` files with logic
- Implementing any predicates
- Making any design decisions not already made in the reference documents
- Running any tests
- Installing SWI-Prolog (assume it is already available as `swipl`)
- Installing any dependencies beyond verifying they exist

If you find yourself writing Prolog, stop. That is Session 1's job.

---

## Reference documents

Three documents govern this project. They are read-only for all sessions including this one. You may read them. You may not modify them.

| Document | Canonical path after this session |
|---|---|
| Conceptual Guide | `docs/conceptual_guide.md` |
| Implementation Plan | `docs/implementation_plan.md` |
| Session 1 Prompt | `docs/sessions/session_01.md` |

These documents will be provided to you as files or inline content. Copy them verbatim to the paths above. Do not edit, summarise, reformat, or paraphrase them. SHA-checksums are not required but the content must be byte-for-byte identical to what was provided.

---

## Directory structure to create

Create the following structure under a root directory named `oster/`. Use `mkdir -p` for all directories. Use `touch` for all placeholder files.

```
oster/
│
├── docs/
│   ├── conceptual_guide.md          ← copy of the guide (read-only reference)
│   ├── implementation_plan.md       ← copy of the plan (read-only reference)
│   └── sessions/
│       ├── session_01.md            ← copy of Session 1 prompt
│       ├── session_02.md            ← placeholder (touch only)
│       ├── session_03.md            ← placeholder
│       ├── session_04.md            ← placeholder
│       ├── session_05.md            ← placeholder
│       ├── session_06.md            ← placeholder
│       ├── session_07.md            ← placeholder
│       ├── session_08.md            ← placeholder
│       ├── session_09.md            ← placeholder
│       ├── session_10.md            ← placeholder
│       ├── session_11.md            ← placeholder
│       └── session_12.md            ← placeholder
│
├── engine/                          ← placeholder directory only
├── lifecycle/                       ← placeholder directory only
├── projections/                     ← placeholder directory only
├── verify/                          ← placeholder directory only
├── repl/                            ← placeholder directory only
│
├── catalog/
│   ├── deck/                        ← placeholder directory only
│   ├── warrior/                     ← placeholder directory only
│   ├── tavern/                      ← placeholder directory only
│   └── README.md                    ← write content (see below)
│
├── tests/                           ← placeholder directory only
│
├── README.md                        ← write content (see below)
└── .gitignore                       ← write content (see below)
```

Placeholder directories need a `.gitkeep` file inside them so they are tracked by git. Example:

```bash
touch oster/engine/.gitkeep
```

Do this for every placeholder directory: `engine/`, `lifecycle/`, `projections/`, `verify/`, `repl/`, `tests/`, and all three catalog subdirectories.

---

## Files to write (not copy)

### `oster/README.md`

```markdown
# Oster

A SWI-Prolog simulation engine built around events, logs, and rules.

## Core idea

The world is a log. Nothing has mutable state. Events arrive, accumulate in an
append-only log, and all derived state is computed from that history on demand.

## Reference documents

- `docs/conceptual_guide.md` — the model, its invariants, and its open questions
- `docs/implementation_plan.md` — build sequence, design decisions, session breakdown

## Status

Session 0 complete. No engine code yet.

## Prerequisites

- SWI-Prolog 9.x (`swipl`)
- No other dependencies for Sessions 1–8
- `library(plunit)` for tests (ships with SWI-Prolog)
- `library(aggregate)` for log_count/1 (ships with SWI-Prolog)

## Running tests

    swipl -g "run_tests" -t halt tests/log_tests.pl

Replace `log_tests.pl` with the relevant test file for each session.
```

### `oster/catalog/README.md`

```markdown
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
```

### `oster/.gitignore`

```
# SWI-Prolog
*.qlf
.swipl-history

# macOS
.DS_Store

# Editor
.vscode/
*.swp
*~
```

---

## Verification steps

Run these after creating everything. All must pass before Session 0 is complete.

**V1 — Directory tree**

```bash
find oster/ -type f | sort
```

Expected output (order may vary):

```
oster/.gitignore
oster/README.md
oster/catalog/.gitkeep        ← only if catalog/ itself has no subdirs with content
oster/catalog/README.md
oster/catalog/deck/.gitkeep
oster/catalog/tavern/.gitkeep
oster/catalog/warrior/.gitkeep
oster/docs/conceptual_guide.md
oster/docs/implementation_plan.md
oster/docs/sessions/session_01.md
oster/docs/sessions/session_02.md
oster/docs/sessions/session_03.md
oster/docs/sessions/session_04.md
oster/docs/sessions/session_05.md
oster/docs/sessions/session_06.md
oster/docs/sessions/session_07.md
oster/docs/sessions/session_08.md
oster/docs/sessions/session_09.md
oster/docs/sessions/session_10.md
oster/docs/sessions/session_11.md
oster/docs/sessions/session_12.md
oster/engine/.gitkeep
oster/lifecycle/.gitkeep
oster/projections/.gitkeep
oster/repl/.gitkeep
oster/tests/.gitkeep
oster/verify/.gitkeep
```

**V2 — SWI-Prolog available**

```bash
swipl --version
```

Must print a version string. If it fails, stop and report — do not attempt to install SWI-Prolog.

**V3 — plunit available**

```bash
swipl -g "use_module(library(plunit)), halt"
```

Must exit with code 0. If it fails, stop and report.

**V4 — Reference documents in place**

```bash
wc -l oster/docs/conceptual_guide.md
wc -l oster/docs/implementation_plan.md
wc -l oster/docs/sessions/session_01.md
```

All three must report non-zero line counts. If any is zero, the copy failed.

**V5 — No Prolog logic files exist**

```bash
find oster/ -name "*.pl" | grep -v ".gitkeep"
```

Must return nothing. No `.pl` files exist after Session 0.

---

## Rules for all sessions, established here

These apply to every Claude Code session in this project, starting now.

**Rule 1 — Reference documents are read-only.**
`docs/conceptual_guide.md`, `docs/implementation_plan.md`, and any `docs/sessions/session_N.md` file that has been populated may not be modified. If you believe a document contains an error, add a comment to your session report. Do not edit the document.

**Rule 2 — Stay in scope.**
Each session prompt specifies exactly which files to create or modify. Do not create files outside that list. Do not modify files from previous sessions unless the current session prompt explicitly says to. If you find a bug in a previous session's code, note it in your session report and stop — do not fix it unless fixing it is listed in the current session's scope.

**Rule 3 — Green tests are the contract.**
Before starting any session, run the tests from all previous sessions. All must pass. If any test fails before you write a line of new code, stop and report — do not proceed. At the end of each session, all tests (previous and new) must pass.

**Rule 4 — Predicate names are fixed.**
The implementation plan specifies exact predicate names and arities. Do not rename, alias, or refactor them. Future sessions depend on these interfaces. If a name seems wrong, note it in your session report.

**Rule 5 — No forward implementation.**
Do not implement anything from a future session to make the current session easier. If the current session needs something that doesn't exist yet, use a stub, a comment, or a temporary declaration — and mark it with `% STUB: Session N will replace this`. The stub must be minimal: just enough to make the current session's tests pass.

**Rule 6 — Decisions are made. Do not re-derive them.**
The implementation plan contains 12 numbered design decisions (D1–D12). These resolved ambiguities in the conceptual guide. Do not re-open them. If you encounter a situation that seems to contradict a decision, add a `% DECISION:` comment explaining what you observed, but implement according to the decision as written.

**Rule 7 — Ambiguity resolution order.**
If something is unclear: first check the session prompt, then the implementation plan, then the conceptual guide. If genuine ambiguity remains after consulting all three, make the most conservative choice (least new behaviour, smallest surface area) and leave a `% DECISION:` comment.

**Rule 8 — Session reports.**
At the end of each session, produce a brief plain-text report:
- Session number and name
- Files created or modified
- Test results (N passed, 0 failed)
- Any stubs left for future sessions (with session numbers)
- Any anomalies, surprises, or questions for the human

Do not produce the report until all tests pass. The report is the signal that the session is done.

---

## A note on AI-assisted authoring in this project

The conceptual guide addresses this directly. The relevant passage:

> A capable model in a focused session can meaningfully contribute to scene design, gate declarations, and rule authoring — but only within a scope where the human collaborator understands the failure modes well enough to evaluate the output.

This project uses Claude Code for implementation and Claude (this interface) for design, specification, and session prompt authoring. The division is deliberate:

- **Claude Code** works within a defined scope, with fixed interfaces, with tests as the acceptance criterion. It should not make design decisions.
- **Claude (this interface)** holds the design context across sessions, writes session prompts, and reviews session reports. It does not write engine code.

When you (Claude Code) reach the boundary of your session scope, stop. The human will bring the session report to this interface, and the next session prompt will be written here before you proceed.

This division is not about capability — it is about keeping design decisions visible and reviewable rather than embedded silently in implementation choices.
