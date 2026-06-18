#!/usr/bin/env bash
# PreToolUse(Bash) gate: block `gh pr create` / `gh pr ready` until a
# grumpy-review has been recorded for the current commit. Scoped to the
# loancrate repo via .claude/settings.local.json (where the grumpy-review
# skill lives). A new commit invalidates the marker, forcing a re-review
# of the exact state being shipped.

set -euo pipefail

# Self-gate on the command so we never block unrelated Bash calls. Match
# `gh pr create` / `gh pr ready` only when it is an actual invocation:
# at the start of the command or right after a shell separator
# (; & | && ||). This deliberately does NOT match the phrase inside a
# quoted argument (e.g. git commit -m "... gh pr create ...").
payload="$(cat)"
command="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
if ! printf '%s' "$command" | grep -Eq '(^|[;&|]|&&|\|\|)[[:space:]]*gh[[:space:]]+pr[[:space:]]+(create|ready)([[:space:]]|$)'; then
  exit 0
fi

sha="$(git rev-parse HEAD 2>/dev/null || true)"

# Not a git repo / no commits yet: nothing to review against, allow.
if [ -z "$sha" ]; then
  exit 0
fi

marker="$HOME/.claude/.grumpy-review-passed/${sha}"
if [ -f "$marker" ]; then
  exit 0
fi

reason='Project rule: run the grumpy-review skill against the current branch
changes before opening this PR.

  1. Run /grumpy-review and address (or consciously accept) its findings.
  2. Record that the review passed for THIS commit:
       mkdir -p ~/.claude/.grumpy-review-passed \
         && touch ~/.claude/.grumpy-review-passed/$(git rev-parse HEAD)
  3. Re-run the gh pr command.

Any new commit needs a fresh review (the marker is keyed to the commit
SHA being shipped).'

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
exit 0
