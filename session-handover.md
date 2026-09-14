# Session Handover Protocol

This document defines how to conclude a work session so the next session can
continue without depending on the previous context window.

At the end of every meaningful session, create a handover file inside the
`sessions/` folder. The handover must be detailed enough that a new agent or
developer can resume work as if the previous session had not ended.

## When To Create A Handover

Create a handover whenever:

- The context window is close to ending.
- A session is paused before the task is fully complete.
- Any non-trivial decisions, implementation work, debugging, research, or
  tradeoffs occurred.
- The user asks to stop, resume later, switch tasks, or continue in a new
  session.
- Work touched project architecture, code structure, dependencies, settings,
  tests, release process, permissions, or browser-extension behavior.

For very small interactions that do not change project understanding, a
handover is optional. If there is any doubt, create one.

## File Location And Name

Place handovers in:

```text
sessions/
```

Use this filename format:

```text
sessions/YYYY-MM-DD-HHMM-short-topic.md
```

Examples:

```text
sessions/2026-09-01-1530-architecture-open-questions.md
sessions/2026-09-01-1745-devtools-panel-prototype.md
sessions/2026-09-01-1910-json-tree-virtualization.md
```

Use the local project timezone when naming files unless the user explicitly
requests another timezone.

## Core Rule

The handover must record not only the final result, but also the path taken:

- What the user asked for.
- What was read.
- What was changed.
- What was tried.
- What failed.
- What was decided.
- Why decisions were made.
- What remains unresolved.
- How to verify or continue the work.

Do not only summarize outcomes. Include enough small details that the next
session can reconstruct the working state, reasoning, assumptions, and pending
risks without guessing.

## Required Sections

Every handover should use the following structure.

```md
# Session Handover: <Short Topic>

## Session Metadata

- Date:
- Timezone:
- Repository:
- Branch:
- Commit at start:
- Commit at end:
- Working tree status at end:
- Session trigger:

## User Requests

Record each user request in chronological order. Preserve the exact intent,
constraints, preferences, and any corrections from the user.

## Project Context Learned

Document what was learned about the project during the session.

Include:

- Relevant architecture.
- Important files and folders.
- Existing conventions.
- Technologies, frameworks, and build tools.
- Permission, security, or product constraints.
- Any assumptions that were confirmed or rejected.

## Files Read

List every meaningful file read, with a short note explaining why it mattered.

Example:

- `ARCHITECTURE.md` - Established the two-surface Chrome extension design and
  open architectural questions.

## Files Changed

List every file changed, added, moved, or deleted.

For each file, include:

- What changed.
- Why it changed.
- Any important implementation details.
- Whether the change is complete or partial.

## Commands Run

List relevant commands, especially commands that affected understanding,
generated files, installed dependencies, ran tests, built the project, or
produced errors.

For each command, include:

- Command.
- Purpose.
- Result.
- Important output or failure details.

Do not paste huge logs. Summarize the important lines and mention where full
logs can be found if they were saved.

## Decisions Made

Record all decisions, including small ones.

Each decision should include:

- Decision.
- Reasoning.
- Alternatives considered.
- Consequences or follow-up work.

## Implementation Details

Describe the actual approach used.

Include:

- Data flow.
- Component boundaries.
- APIs used.
- State shape.
- Error handling.
- Performance considerations.
- Security/privacy considerations.
- Compatibility constraints.

This section should be specific enough that the next session can continue the
implementation without rediscovering the design.

## Testing And Verification

Record what was tested and what was not tested.

Include:

- Commands run.
- Manual checks performed.
- Browser or extension checks performed.
- Screenshots or visual checks, if any.
- Known gaps in verification.
- Any flaky or environment-dependent behavior.

If tests could not be run, explain exactly why.

## Current State

Describe the project state at the end of the session.

Include:

- What is complete.
- What is partially complete.
- What is known to be broken.
- What is staged or unstaged.
- Any generated files or local-only artifacts.
- Any long-running processes that were started or stopped.

## Open Questions

List unresolved questions and why they matter.

If a recommendation exists, include it, but clearly mark it as a recommendation
instead of a settled decision.

## Next Steps

Provide a concrete continuation plan.

Use ordered steps when sequence matters. Each step should be actionable and
specific enough for a new session to start immediately.

## Risks And Watchouts

Call out anything the next session should be careful about.

Examples:

- User changes that must not be overwritten.
- Permission-sensitive extension behavior.
- Browser API limitations.
- Performance risks.
- Incomplete assumptions.
- Files that look unrelated but are actually important.

## Useful References

Include references that would help the next session.

Examples:

- Local files.
- Documentation URLs.
- Relevant browser APIs.
- Prior handover files.
- Issue or PR references.

## Resume Prompt

End with a short prompt the next session can use to resume.

Example:

Continue from `sessions/YYYY-MM-DD-HHMM-short-topic.md`. First read
`ARCHITECTURE.md` and this handover, then inspect the current working tree.
Resume at the first item under "Next Steps" while preserving all decisions and
watchouts from the handover.
```

## Detail Requirements

The handover should include small details that are easy to lose between
sessions, such as:

- Exact names of files, functions, components, hooks, and modules discussed.
- Why a specific approach was preferred.
- Why another approach was rejected.
- User preferences about scope, quality, architecture, UX, or MVP shortcuts.
- Any wording the user cared about.
- Any dependency or browser API constraints discovered.
- Any command failures and what they imply.
- Any environment facts, such as current working directory or available files.
- Any assumptions made because the user did not specify something.
- Any follow-up that depends on unresolved product or architecture decisions.

Prefer precise, concrete notes over polished narrative.

## Quality Bar

A good handover lets the next session answer these questions immediately:

- What was the user trying to accomplish?
- What is the current state of the repository?
- What changed during the session?
- Why were those changes made?
- What did the previous session learn?
- What should happen next?
- What should not be changed or repeated?
- What risks or open questions remain?

If the next session would need to ask the user to repeat context that was
already available, the handover is not detailed enough.

## Practical Checklist

Before ending the session:

- Read the current working tree status.
- Record files changed and files read.
- Record important commands and outcomes.
- Record decisions and reasoning.
- Record unresolved questions.
- Record exact next steps.
- Create the `sessions/` folder if it does not exist.
- Save the handover file under `sessions/`.
- Mention the handover path in the final response.

## Suggested Command Sequence

Use commands like these to gather final state:

```sh
git status --short
git branch --show-current
git rev-parse HEAD
```

If relevant, also inspect:

```sh
git diff --stat
git diff -- <file>
```

Do not use destructive git commands while preparing a handover.
