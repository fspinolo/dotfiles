---
name: revive-dev-sessions
description: Revive lost dev sessions after a reboot/crash — find the worktrees that had a live Claude session, recreate each dev-<task> tmux session, and resume its Claude conversation. Use when asked to "revive/restore my sessions", "bring back my tmux sessions", or after a restart wiped the tmux server. Companion to dev-session and clean-dev-sessions.
---

# Revive lost dev sessions

A system restart (or tmux server crash) loses every running `dev-<task>`
session Felipe had open — the git worktrees and Claude conversation logs
survive on disk, but the tmux sessions and Claude processes are gone.
This skill finds the sessions that were genuinely live, recreates each
tmux session in its `devtree` layout, and relaunches its Claude pane on
the **same conversation** (not a blank Claude). Sibling skills:
`dev-session` (create), `clean-dev-sessions` (tear down).

## First: is tmux-resurrect handling it?

`~/.tmux.conf` now runs `tmux-resurrect` + `tmux-continuum` (installed
2026-07-10). Continuum auto-saves every 15 min and **auto-restores on
tmux server start**, relaunching each pane's `vim` and re-running Claude
as `claude -c` (continue that worktree's latest conversation). So after a
normal reboot the sessions usually come back on their own.

Use this skill when auto-restore didn't cover it:

- The crash predated the first continuum save, or the save is stale/
  missing (`ls ~/.local/share/tmux/resurrect/last`).
- Sessions died between saves and weren't in the snapshot.
- Felipe wants a **curated subset** revived, not everything that was
  alive at save time (resurrect is all-or-nothing).
- He wants a pane resumed on a **specific** session id, not `claude -c`.

## Never touch

- `devroot` — the main-checkout session (recreated manually; runs the
  `pnpm dev` stack on default ports).
- Any session that already exists (`tmux has-session`). Reviving is
  additive; never kill a live session to "refresh" it.
- The `.claude/worktrees/agent-*` worktrees — those are Agent-tool
  isolation worktrees, not dev sessions. Skip them.

## 1. Inventory the worktrees

```bash
git -C ~/Development/loancrate worktree list   # live worktrees on disk
tmux list-sessions 2>/dev/null                 # what's already back
```

Candidates are the linked worktrees under
`~/Development/loancrate-worktrees/<task>` (the same conventions apply to
other loancrate repos — `infra`, `datadog-monitoring`). Each worktree
maps to a Claude **project dir** whose name is the worktree path with `/`
replaced by `-`, e.g.
`~/.claude/projects/-Users-felipespinolo-Development-loancrate-worktrees-<task>`.

## 2. Differentiate live sessions from cruft

Not every worktree on disk was a live session — merged/abandoned tasks
leave worktrees behind (that's `clean-dev-sessions`' job). Two signals
separate "was a live session worth reviving" from "leftover cruft":

- **Claude activity recency.** A worktree with a recent conversation was
  a real session. CRITICAL: use the **last `"timestamp"` inside the
  newest `.jsonl`**, NOT the file mtime — Claude Code rewrites every
  project log on startup, so after a reboot all mtimes clump at boot
  time and are worthless. Read the internal timestamp:

  ```bash
  proj="$HOME/.claude/projects"
  for wt in ~/Development/loancrate-worktrees/*/; do
    task=$(basename "$wt")
    pdir="$proj/$(echo "${wt%/}" | sed 's#/#-#g')"
    [ -d "$pdir" ] || { echo "$task  NO-CLAUDE (cruft candidate)"; continue; }
    newest=""; newestts=""
    for f in "$pdir"/*.jsonl; do
      [ -e "$f" ] || continue
      ts=$(grep -o '"timestamp":"[^"]*"' "$f" | tail -1 | sed 's/.*:"//; s/"//')
      [ -z "$newestts" ] || [[ "$ts" > "$newestts" ]] && { newestts="$ts"; newest="$f"; }
    done
    echo "$task  last=$newestts  id=$(basename "${newest%.jsonl}")"
  done
```

- **Working state.** Dirty tree or an open PR = mid-flight work, revive
  it. Query per worktree with `git -C <wt> status --porcelain` and
  `gh pr list --head <branch> --state all`. Do NOT use
  `git log --branches --not --remotes` for "unpushed" — `--branches`
  spans every branch in the shared worktree repo and reports the same
  bogus count for all of them; check the worktree's own `@{u}..HEAD`.

Cruft = no Claude log + a merged/closed PR + clean tree. Recommend those
for `clean-dev-sessions`, don't revive them.

## 3. Confirm the set with Felipe

Present the candidates (task, last-activity, dirty, PR state) and let him
choose which to revive — he rarely wants all of them. Reviving spins up a
real Claude process per session, so this is his call, not a default.

## 4. Revive each chosen session

For each `<task>`, resolve the session id to resume (the newest `.jsonl`
by internal timestamp from step 2), then rebuild the `devtree` layout by
hand. Build it manually rather than via `tmuxinator start devtree`: the
template hard-codes a *fresh* `claude`, and doing it by hand lets the
Claude pane launch with `--resume <id>`.

```bash
revive() {
  local task="$1" id="$2"
  local S="dev-${task}"
  local WT="$HOME/Development/loancrate-worktrees/${task}"
  tmux new-session -d -s "$S" -c "$WT" -n code   # -d: never steal focus
  tmux send-keys -t "${S}:code.1" 'vim' Enter
  tmux split-window -v -t "${S}:code.1" -c "$WT"
  tmux select-layout -t "${S}:code" main-horizontal
  tmux set-option -t "$S" main-pane-height 40%
  tmux select-layout -t "${S}:code" main-horizontal
  tmux send-keys -t "${S}:code.2" "claude --resume ${id}" Enter
  tmux new-window -t "$S" -n shell -c "$WT"
  tmux new-window -t "$S" -n git -c "$WT"
  tmux send-keys -t "${S}:git" 'git status' Enter
  tmux select-window -t "${S}:code"
  tmux select-pane  -t "${S}:code.2"
}
revive temporal-async-rfc 633173c1-dfe9-48a1-999d-0ca07038f6fd
```

Gotchas:

- **Brace the target: `"${S}:code"`, never `"$S:code"`.** zsh applies its
  `:c` modifier to `$S:code`, turning `dev-foo` into `dev-fooode` and
  every `tmux -t` call fails with "can't find window".
- **Panes are 1-indexed** (`base-index`/`pane-base-index` are 1 in the
  config); the layout puts vim in `.1` (top, ~40%) and claude in `.2`.
- **Folder trust:** worktrees that ran Claude before are already trusted,
  so `claude --resume` boots straight into the session. A brand-new
  worktree would stop at the folder-trust dialog — see the `dev-session`
  skill's standing grant for answering it.

## 5. Verify and report

Give Claude a few seconds to boot, then confirm each pane resumed the
real conversation (not a fresh session or a trust prompt):

```bash
sleep 8
tmux capture-pane -p -t "dev-${task}:code.2" | grep -v '^$' | tail -20
```

Look for the session's recap / prior turns. Report each revived session,
the conversation it came back on, its dirty/PR state, and the attach
command (`tmux a -t dev-<task>`). List anything you skipped as cruft.
