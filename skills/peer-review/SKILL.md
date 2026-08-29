---
name: peer-review
description: >
  Run a continuous-peer-review pass over the current changes to prevent fragmentation
  and drift before completion. Orchestrates the pattern-guardian and style-enforcer
  specialists plus a general code-review pass, then consolidates only the blocking
  items. Use after a batch of edits and before declaring a non-trivial change done.
---

# Peer Review Pass

Catch consistency, style, and correctness issues while they're cheap to fix — not after
the codebase has already drifted.

## When to use

After implementing a non-trivial change and before you declare it done, or whenever the
user asks for a review of the current changes.

## Steps

1. **Scope the change.** Determine exactly what changed:
   ```bash
   git --no-pager diff --staged
   git --no-pager diff
   # if the tree is clean, review the branch: git --no-pager diff main...HEAD
   ```
   If there is nothing to review, say so and stop.

2. **Run the specialists in parallel.** Delegate each as a subagent, giving each the
   diff scope and the relevant file paths. On Claude Code the specialists are namespaced
   — pass `dev-framework:pattern-guardian` and `dev-framework:style-enforcer` as the
   subagent type; on Copilot CLI use the bare names:
   - **pattern-guardian** — duplication, re-invented helpers, divergent conventions, a
     second way to do a thing, unjustified new dependencies.
   - **style-enforcer** — adherence to the project style guide / lint config / local
     conventions on the changed files.
   - **code review** — bugs, logic errors, security, resource/concurrency issues. Use
     the built-in `code-review` agent on Copilot CLI, or a plain subagent briefed to do
     the same on Claude Code. High bar, high signal only.

3. **Consolidate.** Merge their findings. Drop duplicates and anything non-actionable.
   Group by severity: **Blocking**, **Should-fix**, **Note**.

4. **Act, don't summarize.** For every Blocking and Should-fix item: fix it now, or
   state precisely why it does not apply. Do not produce a report of issues you then
   leave unaddressed.

5. **Confirm.** Re-run the relevant specialist if you made non-trivial fixes, until no
   blocking items remain.

## Output

A short consolidated list (Blocking / Should-fix / Note) and, for each, the action you
took. If the specialists found nothing, say "Peer review clean — no blocking issues."
