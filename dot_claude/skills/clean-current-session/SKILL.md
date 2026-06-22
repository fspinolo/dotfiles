---
name: clean-current-session
description: Clean up the dev session you are CURRENTLY running inside (tmux session + git worktree + branch) after its PR merged — without killing your own process mid-cleanup. Use when asked to "clean up this session", "tear down the session I'm in", or to remove the current worktree/session after merge. For OTHER (not-current) stale sessions, use clean-dev-sessions instead.
---

# Clean up the session you're running in

`clean-dev-sessions` deliberately refuses to touch an **attached**
session. This skill is the opposite case: the session to remove is the
one your Claude process is living in (the `claude` pane of a
`dev-<task>` tmux session, cwd inside its worktree). The hazard is
self-termination — three actions will kill or strand you if done in the
wrong order:

1. **`tmux kill-session` on your own session kills your process.** Never
   run it inline. It must be the last thing, and detached (see §4).
2. **Removing the worktree deletes your shell's cwd.** The Bash tool
   starts each command in the worktree dir; once it's gone, every later
   Bash call fails with "no such file or directory." So the removal must
   run from a cwd _outside_ the worktree, and **no Bash may run after
   it** — bundle it as the final Bash command.
3. **A checked-out branch can't be deleted** until its worktree is
   removed.

Do the survivable, reversible work first; the self-destructive steps
last, in one shot, with the kill detached.

## 1. Confirm you're actually in the target session

The session is `dev-<task>` where `<task>` is the current worktree's
directory name. Sanity-check before destroying anything:

```bash
pwd                                   # should be the worktree
tmux display-message -p '#S' 2>/dev/null   # current session, if reachable
git rev-parse --show-toplevel         # the worktree root
```

If you're NOT in the session being cleaned, stop and use
`clean-dev-sessions` (it has the full inventory + multi-session flow).

## 2. Safety checks (same bar as clean-dev-sessions)

Keep the session and report instead of deleting if any fail. See
`clean-dev-sessions` for the squash-merge verification gotcha and the
details behind each check.

```bash
git status --porcelain                # only stray/ignored files → ok
git rev-list --count @{u}..HEAD       # >0 unpushed → keep
gh pr view <n> --json state --jq .state   # want MERGED

# Vim swap: existence ≠ unsaved work (a .swp exists for ANY open buffer,
# including a read-only view). Decide on vim's own dirty flag, not the
# match. For each matching swap, b0_dirty lives at offset 1007 of the
# classic-vim swap header: 0x55 = buffer modified (unsaved), else clean.
for swp in ~/.vim/swap/*<task-or-path>*; do
  [ -e "$swp" ] || continue
  if [ "$(xxd -s 2 -l 4 -p "$swp" 2>/dev/null)" != "56494d20" ]; then
    echo "NON-CLASSIC swap (neovim?/unknown) → surface: $swp"; continue
  fi
  case "$(xxd -s 1007 -l 1 -p "$swp" 2>/dev/null)" in
    55) echo "DIRTY (unsaved edits) → keep + surface: $swp" ;;
    *)  echo "clean view (safe to discard): $swp" ;;
  esac
done
```

**Vim swap file caveat:** the session's vim pane may hold an unsaved
buffer, and killing the session would lose it. But a swap file existing
only means a buffer is *open* — opening a file just to read it (e.g.
reviewing a merged change) leaves an identical `.swp`, so blocking on the
mere match is a false positive most of the time. The dirty flag above is
the real signal, and it's exact (verified against VIM 9.2: `0x55` when
modified, `0x00` for a clean view):

- **Any swap reads `DIRTY` (0x55), or `git status` shows the swapped path
  modified** → real unsaved work. Keep the session, surface it, get an
  explicit go-ahead.
- **All matches read clean** → vim just has the file open for viewing.
  Proceed; mention in the final report that a vim pane had `<file>` open
  (read-only) so the user has the ~30s kill window to object if that's
  somehow wrong.
- **A swap isn't classic-vim format** (neovim, or the header check fails)
  → can't read the flag; fall back to surfacing and asking.

## 3. Do everything survivable first

- **Linear / bookkeeping** — sweep the ticket to its terminal state now.
  This never risks your process; do it before any teardown.
- **Monorepo isolated resources** — if this is a monorepo worktree with
  worktree-isolation, run the destroy from _inside_ the worktree (it
  derives its slug from its own location), BEFORE you cd out:
  `./scripts/worktree.sh destroy --force`. Non-monorepo worktrees
  (infra, datadog-monitoring, …) have no such resources — skip it.

## 4. The final bundle (last Bash command — nothing runs after it)

One command that cd's out of the worktree, tears down git, and
**schedules** the session kill detached so your final report streams
before the session dies:

```bash
cd ~/Development/<repo-or-loancrate>          # OUT of the worktree first
wt=<absolute-worktree-path>
branch=felipe/<task>
session=dev-<task>
git worktree remove "$wt" 2>/dev/null || git worktree remove --force "$wt"
git worktree prune
git branch -d "$branch" 2>/dev/null || git branch -D "$branch"  # -D: squash-merged
git remote prune origin >/dev/null 2>&1 || true
# Detach the self-kill so it fires AFTER this turn ends. nohup + & makes
# it reparent to launchd and survive the pane's death; the delay must
# outlast your final message (~30s is safe).
nohup bash -c "sleep 30; tmux kill-session -t $session" \
  >/tmp/$session-kill.log 2>&1 &
disown 2>/dev/null || true
echo "worktree + branch removed; '$session' kill scheduled (~30s)"
```

Why each guard:

- `cd` out first — or removing `$wt` strands every later command.
- `worktree remove` before `branch -d` — the branch is checked out in
  `$wt` until it's gone.
- `|| --force` — a stray untracked file (e.g. `pbcopy`) makes the clean
  removal refuse; force is justified once the PR is MERGED.
- `-d || -D` — squash merges aren't ancestors of master, so `-d`
  refuses; `-D` is safe because §2 verified MERGED.
- detached kill — you cannot verify it succeeded (you'll be gone), hence
  the `/tmp` log for the user.

## 5. Final report (this is your last message)

After the bundle returns, you have ~one window to report before the
detached kill lands. State: ticket status, worktree/branch removed,
and that the session terminates in ~30s (ending this process). Do NOT
issue more Bash — the worktree cwd no longer exists.
