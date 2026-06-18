#!/usr/bin/env bash
# Reflect Claude Code's lifecycle in the tmux session's @claude option,
# rendered as a trailing status glyph in the switcher and status bar
# (see ~/.tmux.conf). Wired into ~/.claude/settings.json hooks:
#   UserPromptSubmit -> working   Stop -> done
#   Notification     -> waiting   SessionEnd -> cleared
# Fire-and-forget: no-op outside tmux, sets one option, always exits 0
# with no stdout, so it can never block or alter Claude's behavior.

set -uo pipefail

state="${1:-}"

# Outside tmux there is nothing to update.
[ -n "${TMUX:-}" ] || exit 0

# Pin to this Claude process's own pane/session, not whichever client
# happens to be focused (the user may be looking at another session).
pane="${TMUX_PANE:-}"
if [ -n "$pane" ]; then
  session="$(tmux display-message -p -t "$pane" '#S' 2>/dev/null || true)"
else
  session="$(tmux display-message -p '#S' 2>/dev/null || true)"
fi

[ -n "$session" ] || exit 0

tmux set-option -t "$session" @claude "$state" 2>/dev/null || true
exit 0
