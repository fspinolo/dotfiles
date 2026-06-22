---
name: clean-dev-sessions
description: Clean up stale `dev <task>` tmux sessions, their git worktrees, isolated dev resources (worktree.sh destroy), and merged local/remote branches in the loancrate monorepo. Use when asked to "clean up dev sessions", "clean up stale sessions/worktrees", or after a batch of PRs merge.
---

# Clean up stale dev sessions

Felipe's `dev <task>` alias creates a tmux session + git worktree at
`~/Development/loancrate-worktrees/<task>` on branch `felipe/<task>`.
When the task's PR merges, the session, worktree, and branch linger.
This skill identifies the stale ones, verifies they're safe to remove,
and cleans them up.

## Background by default (non-blocking)

**Always** run this in the background — dispatch a background subagent
(`Agent`, `subagent_type: "general-purpose"`, `run_in_background: true`)
to do the inventory, assessment, and cleanup (§1–§5), so Felipe keeps
working while it runs. The harness notifies on completion; relay the
agent's keep/remove report then. The prompt must be self-contained:
tell it to read and follow this skill
(`~/.claude/skills/clean-dev-sessions/SKILL.md`) end to end. Only run
inline if Felipe explicitly asks to do it in the foreground. (Note:
`clean-current-session` is the opposite — it must NEVER background,
since it tears down the session this process runs inside.)

## Never touch

- `devroot` — the main-checkout session running the `pnpm dev` stack.
- Any currently **attached** session (check `tmux list-sessions`).
- Anything with an open PR, dirty files, unpushed commits, or open
  vim buffers — keep it and report why.

## 1. Inventory

```bash
tmux list-sessions
git -C ~/Development/loancrate worktree list
git -C ~/Development/loancrate branch --list 'felipe/*' --format='%(refname:short) %(worktreepath)'
ls ~/.loancrate/ports/   # worktree-isolation port allocations
```

Gotchas:

- A worktree's branch can differ from its directory name (worktrees
  get reused for follow-up tickets). Always read the actual branch.
- Also check for dangling `felipe/*` branches with no worktree —
  they're part of the same cleanup.
- A `~/.loancrate/ports/<slug>.conf` whose slug matches no current
  worktree means a worktree was removed without
  `worktree.sh destroy` — its isolated dev resources (database,
  indexes, topics, Redis keys, Temporal namespace) leaked. See the
  orphaned-slug note in step 4.

## 2. Assess each worktree

For each worktree (and dangling branch):

```bash
git -C <wt> status --porcelain          # dirty? non-empty → keep
git -C <wt> rev-list --count @{u}..HEAD # unpushed? >0 → keep (no upstream is fine — merged PRs auto-delete the remote branch)
gh pr list --repo loancrate/loancrate --head <branch> --state all \
  --json number,title,state,mergedAt
```

Stale = clean tree + nothing unpushed + PR `MERGED` (or branch is an
ancestor of `origin/master`). An open PR, dirty tree, or unpushed
commits → keep.

### Squash-merge verification gotcha

Squash merges break ancestry checks: `merge-base --is-ancestor` says
no, `rev-list --count origin/master..branch` shows commits "ahead",
and `git cherry origin/master <branch>` only matches single-commit
branches (a multi-commit branch squashed into one master commit
matches **nothing** — every commit shows `+`). Don't conclude
"unmerged content" from those signals alone. Verify instead by
finding the squash commit on master and comparing its diffstat to the
branch's merge-base diff:

```bash
git log origin/master --oneline --grep='<TICKET-or-PR#>'
git show <squash-sha> --stat
git diff origin/master...<branch> --stat   # three-dot = branch's own changes
```

Matching file list + line counts (and the later commits' messages
folded into the squash body) = fully landed.

## 3. Check for unsaved vim buffers

The vimrc sets `directory=~/.vim/swap//`, so every open buffer in any
vim has a swap file there:

```bash
ls ~/.vim/swap/
```

Empty (or no entries matching the worktree path) → no open/unsaved
buffers in that session's vim. If a matching swap file exists, keep
the session and report it.

## 4. Clean up (per stale task, in this order)

Run as separate commands, not one bundled script — and don't reach
for `--force`/`-D` until the non-force variant has demonstrated the
need (bundling force flags pre-emptively gets denied by the
permission classifier, and the non-force failures are themselves a
useful safety check):

```bash
tmux kill-session -t dev-<task>
~/Development/loancrate-worktrees/<task>/scripts/worktree.sh destroy --force
# ^ MUST run before worktree remove: destroy derives its slug from
#   the directory it lives in; there is no destroy-by-slug. --force
#   is required from a non-tty (the prompt reads EOF and aborts) —
#   the documented exception to the no-preemptive-force rule. Needs
#   the shared docker stack up (it execs into compose containers);
#   if docker is down, bring it up first or report the skipped
#   destroy as a leak.
git -C ~/Development/loancrate worktree remove ~/Development/loancrate-worktrees/<task>
# worktree remove without --force refusing = tree wasn't clean; stop and re-check
git -C ~/Development/loancrate branch -d <branch>
# -d refusing on a *verified* squash-merged branch is expected; then:
git -C ~/Development/loancrate branch -D <branch>
```

Worktrees created before worktree isolation was enabled
(2026-06-12) may have no `~/.loancrate/ports/<task>.conf` and
nothing bootstrapped — `destroy` is still safe to run (its drops are
idempotent). If the worktree predates the script entirely (no
`scripts/worktree.sh` in it) **and** has no port conf, nothing was
ever bootstrapped — skip the destroy step. Don't run the main
checkout's copy against another worktree: the script derives its
slug from its own location, so that would target the wrong (main)
environment.

For an **orphaned slug** (port conf exists but the worktree is
already gone), there's no worktree to run `destroy` from. Clean up
manually: drop the `<slug>` Postgres database, `<slug>_*` OpenSearch
indexes, `<slug>-*` Kafka topics, `<slug>-bull*` Redis keys, and the
`<slug>` Temporal namespace, then `rm ~/.loancrate/ports/<slug>.conf`
— mirror what `cmd_destroy` in
`~/Development/loancrate/scripts/worktree.sh` does, reading it first
in case it has changed.

Then once at the end:

```bash
git -C ~/Development/loancrate worktree prune
git -C ~/Development/loancrate remote prune origin
```

GitHub auto-deletes merged PR branches on origin, so remote deletion
is normally unnecessary — `remote prune` just clears the stale
tracking refs.

## 5. Report

Summarize: what was removed (session, worktree, branch, merged-PR
evidence per task) and what was kept and why (open PR, unpushed
commits, dirty tree, open buffers).
