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
