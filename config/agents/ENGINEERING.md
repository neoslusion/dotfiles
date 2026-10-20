# Engineering Principles

Shared engineering defaults across projects and agents. Follow applicable
project instructions for conventions and required checks. Scale planning,
explanation, and verification to the task's complexity and consequences.

## Understand the task

- Read relevant code, tests, and instructions before editing. Check dependency
  docs and types before relying on unfamiliar behavior.
- Identify the intended outcome and how to verify it. For substantial work,
  give a short plan with checks.
- Investigate uncertainty first. Ask when an unresolved choice materially
  affects scope, behavior, compatibility, or risk. Otherwise, proceed with a
  reasonable, reversible choice; state consequential assumptions.
- Surface material tradeoffs and suggest simpler approaches when warranted.

## Implement simply

- Solve current requirements with the simplest clear implementation.
  Avoid speculative features, configuration, and abstractions.
- Build and verify working end-to-end increments. Do not defer required
  behavior; explain material limitations.
- Reuse suitable code and dependencies. Justify new dependencies by their
  benefit and maintenance cost. For significant design decisions, examine
  established approaches against the project's constraints.
- Group code that changes together. Split responsibilities when they have
  different reasons to change.
- Handle realistic failures where recovery, cleanup, or useful context is
  possible. Propagate errors; make fallback behavior visible. Never report
  success after a required step fails.

## Keep changes focused

- Every changed line should support the task. Match surrounding conventions;
  avoid unrelated refactors, cleanup, and formatting.
- Remove what your change makes unused. Mention unrelated dead code rather
  than deleting it.
- Preserve behavior and state outside the requested change. Base compatibility
  paths and migrations on identified consumers or existing state. Investigate
  usage before removing behavior.
- Preserve comments explaining constraints, gotchas, and durable rationale.
  Avoid restating code; keep task narration in responses or commit messages.

## Verify and finish

- Run relevant checks and project-required gates. Test observable behavior
  and invariants, not implementation details. For bugs, reproduce the failure
  when feasible and add a meaningful regression test.
- Review the final diff for unintended changes and unnecessary complexity.
  Do not weaken valid checks to make the change pass.
- Continue until the requested outcome is complete and verified, or a concrete
  blocker prevents progress. Complete independent work while blocked.
- Report what changed, what was verified, and remaining limitations. Include
  failing commands and relevant errors; say when checks could not run.
  Distinguish evidence from expectations.

Within task and project constraints, prioritize correctness and data
preservation, then simplicity and local consistency. Surface unresolved
conflicts rather than silently choosing.

**Working if:** changes stay focused, failures remain visible, verification
catches real defects, and routine work proceeds without unnecessary stops.
