# Git Commit Convention

Use short, concise, technical commit messages.

The default format is:

```text
type: description
```

Examples:

```text
feat: add JsonTreeCore virtualization
fix: handle empty response bodies
test: cover JSON path formatting
docs: update session handover protocol
refactor: render JsonTreeCore from flat rows
chore: update extension dependencies
```

## Rules

- Keep the subject line short and specific.
- Use lowercase commit types.
- Use an imperative description when possible.
- Do not add a period at the end of the subject.
- Describe what changed, not every detail of how it changed.
- Keep one commit focused on one logical change.
- Do not mix unrelated code, docs, tests, and cleanup in one commit.

## Commit Types

Use these types:

```text
feat      New feature or user-visible capability
fix       Bug fix
refactor  Code restructuring without intended behavior change
test      Test additions or test-only changes
docs      Documentation-only changes
chore     Tooling, dependency, config, or maintenance change
style     Formatting or CSS-only change
perf      Performance improvement
build     Build pipeline, package, or bundling change
```

## Optional Scope

Use a scope only when it makes the commit clearer:

```text
type(scope): description
```

Examples:

```text
feat(tree): add active search match styling
fix(parser): reject oversized payloads before parsing
test(panel): cover search match navigation
```

Good scopes for this project:

```text
tree
parser
panel
content
popup
devtools
settings
build
docs
```

## Body

Most commits should only need the subject line.

Add a body only when the reasoning matters, such as:

- permission-sensitive extension behavior
- browser API limitations
- migration notes
- non-obvious tradeoffs
- important follow-up work

Body format:

```text
feat(tree): add virtualization

Render large visible row sets with TanStack Virtual while keeping small trees
on the normal render path. This preserves testability and avoids unnecessary
scroll containers for small JSON payloads.
```

## Project Guidance

- Prefer small commits after each clean checkpoint.
- Run the relevant checks before committing:

```sh
npm run lint
npm run test
npm run build
```

## Quality Check

Before committing, the message should answer:

- What category of change is this?
- What changed?
- Is the description specific enough to understand later?

If the answer is unclear, rewrite the subject before committing.
