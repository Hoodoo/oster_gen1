# Oster — Agent Rules

These rules apply to every Claude Code session in this project, starting from Session 0.

## Rule 1 — Reference documents are read-only

`docs/conceptual_guide.md`, `docs/implementation_plan.md`, and any `docs/sessions/session_N.md`
file that has been populated may not be modified. If you believe a document contains an error,
add a comment to your session report. Do not edit the document.

## Rule 2 — Stay in scope

Each session prompt specifies exactly which files to create or modify. Do not create files
outside that list. Do not modify files from previous sessions unless the current session prompt
explicitly says to. If you find a bug in a previous session's code, note it in your session
report and stop — do not fix it unless fixing it is listed in the current session's scope.

## Rule 3 — Green tests are the contract

Before starting any session, run the tests from all previous sessions. All must pass. If any
test fails before you write a line of new code, stop and report — do not proceed. At the end
of each session, all tests (previous and new) must pass.

## Rule 4 — Predicate names are fixed

The implementation plan specifies exact predicate names and arities. Do not rename, alias, or
refactor them. Future sessions depend on these interfaces. If a name seems wrong, note it in
your session report.

## Rule 5 — No forward implementation

Do not implement anything from a future session to make the current session easier. If the
current session needs something that doesn't exist yet, use a stub, a comment, or a temporary
declaration — and mark it with `% STUB: Session N will replace this`. The stub must be
minimal: just enough to make the current session's tests pass.

## Rule 6 — Decisions are made. Do not re-derive them.

The implementation plan contains 12 numbered design decisions (D1–D12). These resolved
ambiguities in the conceptual guide. Do not re-open them. If you encounter a situation that
seems to contradict a decision, add a `% DECISION:` comment explaining what you observed,
but implement according to the decision as written.

## Rule 7 — Ambiguity resolution order

If something is unclear: first check the session prompt, then the implementation plan, then
the conceptual guide. If genuine ambiguity remains after consulting all three, make the most
conservative choice (least new behaviour, smallest surface area) and leave a `% DECISION:`
comment.

## Rule 8 — Session reports

At the end of each session, produce a brief plain-text report:
- Session number and name
- Files created or modified
- Test results (N passed, 0 failed)
- Any stubs left for future sessions (with session numbers)
- Any anomalies, surprises, or questions for the human

Do not produce the report until all tests pass. The report is the signal that the session is done.

## Division of responsibility

- **Claude Code** works within a defined scope, with fixed interfaces, with tests as the
  acceptance criterion. It should not make design decisions.
- **Claude (conversation interface)** holds the design context across sessions, writes session
  prompts, and reviews session reports. It does not write engine code.

When you reach the boundary of your session scope, stop. The human will bring the session
report to the conversation interface, and the next session prompt will be written there before
you proceed.

## Brainstorming note

If design questions arise during implementation, do not resolve them unilaterally. Flag them
in the session report. The human prefers to brainstorm in the conversation-oriented interface,
not inline during code sessions.
