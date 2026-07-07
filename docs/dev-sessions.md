# dev sessions: one task = one worktree = one tmux session

A casual tour of how I run parallel tasks on the loancrate monorepo,
and which parts are worth stealing. Everything described here lives in
this repo — paths below are source paths, so you can crib piece by
piece.

## the idea

Every task gets its own git worktree, its own tmux session, its own
Claude pane, and (since
[loancrate#19006](https://github.com/loancrate/loancrate/pull/19006))
its own isolated dev stack. Typing `dev fix-thing` gets me from "I
should look at that" to a fully prepared workspace in seconds, and
`dev rm fix-thing` makes it disappear without archaeology. Six PRs in
flight means six sessions, not six rounds of stash/checkout/reset-db.

## fair warning: this is shaped like my hands

The visible surface of this setup is pure muscle memory — _my_ muscle
memory. Vim sits in the top pane at 40% because that's where my eyes
go. The bottom pane is where I poke at things. Sessions are named
`dev-<task>` because my fingers type `tmux a -t dev-` on autopilot
(never the full `tmux attach`, which is for cavemen — your own
abbreviations are exactly the muscle memory this section is about),
and my `.tmux.conf` pushes session names into Warp tab
titles so cmd-tabbing between tasks works without thinking. None of
that is the interesting part, and adopting my layout wholesale would
just give you someone else's calluses.

The interesting part is the plumbing underneath: idempotent worktree
prep, env seeding, templated sessions, briefed Claude handoffs, and
guilt-free teardown. Crib the plumbing, then bolt it to whatever your
own hands do on autopilot — VS Code windows, zellij tabs, a plain
`cd`, whatever. The primitives don't care.

## the pieces

**`dot_local/bin/executable_lc-worktree`** → `~/.local/bin/lc-worktree`

The foundation. Idempotently creates/prepares a worktree at
`~/Development/loancrate-worktrees/<task>` on branch `felipe/<task>`:
fetches origin first (so new branches start from latest master),
reuses existing branches with an ahead/behind warning, copies the
gitignored `.env` files from the main checkout, and runs
`pnpm install` only when `node_modules` is missing. Safe to run
twice; safe to run on a half-built worktree.

**`private_dot_config/zsh/work.zsh`** → `~/.config/zsh/work.zsh`

The entry points, all one word:

- `dev` — session on the main checkout (the "real" stack)
- `dev <task>` — worktree session at the repo root
- `dev <task> <name>` — same, but scoped to `apps/<name>` or
  `packages/<name>`
- `dev rm <task>` — kills the sessions, removes the worktree, deletes
  the branch. Knows that `git branch -d` refuses squash-merged
  branches, so it checks the PR state via `gh` before escalating to
  `-D`.
- `devbrief <task> <brief-file>` — the fun one, see below

This file is work-only: my universal `.zshrc` ends with a conditional
`source` of it, and `.chezmoiignore` only writes it out on machines
where `machine == "work"`.

**`private_dot_config/tmuxinator/*.yml`** → `~/.config/tmuxinator/`

Session templates. The core layout (`devtree.yml`): a `code` window
with vim on top and `claude` below it, a `shell` window, and a `git`
window that opens on `git status`. Variants: `devroot` (main
checkout), `devapp`/`devpkg` (scoped to one app/package), and
`devbrief`.

**`devbrief` — handoff briefs between Claude sessions**

`devbrief <task> <brief.md>` creates the worktree, drops the brief at
`<worktree>/.handoff.md` (kept out of git status via the repo's local
`info/exclude`), and boots the session with Claude in **plan mode**,
told to read the brief first. It also pre-writes a
`.claude/settings.local.json` allowing mundane read-only commands so
a background planning session doesn't stall on permission prompts.
This is how a long-running session spins off a scoped follow-up
without losing context: the old session writes the brief, the new one
wakes up already knowing the plan, the ticket, and the prior work.

That per-worktree settings file turned out to be the training wheels:
the durable version is a read-only allowlist in the **user-level**
`~/.claude/settings.json` (see `dot_claude/settings.json.tmpl`), which
covers every worktree and every repo without per-session setup. Mine
was built empirically — grep your session transcripts
(`~/.claude/projects/*/`) for the tools sessions actually use, allow
the read-only ones plus your build/test toolchain, keep anything
outward-facing (Slack sends, PR creation, deploys) prompting. Worth
doing once; it removed most of the stalls the local file papered over.

Gotcha that arrives with a checked-in repo `.claude/settings.json`:
the **first** Claude launch in each fresh worktree stops at a
folder-trust prompt (it's a per-directory trust decision about the
repo's settings + hooks — no allowlist can pre-grant it). One
keystroke when you're driving; when a background agent does the
spin-up, have it detect the prompt and report back instead of
guessing at it.

**`dot_claude/skills/{dev-session,clean-dev-sessions,clean-current-session,enable-remote-control}`** →
`~/.claude/skills/`

The same flows, packaged as Claude Code skills, so I can say "spin up
a session off LC-1234" and Claude does the whole dance: fetches the
Linear ticket, picks a task name, runs `lc-worktree`, writes the
handoff brief, starts the tmux session, and moves the ticket to in
progress — in the background, so the conversation that asked for it
keeps moving. `clean-dev-sessions` is the reverse: it sweeps stale
sessions after PRs merge, with the paranoid checks (dirty trees,
unpushed commits, open vim swap files, squash-merge verification)
written down so they actually happen every time.
`clean-current-session` is the same teardown for the session you're
_currently inside_ — sequenced so it doesn't kill its own process
mid-cleanup (and, unlike everything else here, never backgrounded).

**`enable-remote-control` — drive any session from your phone**

Claude Code's remote control is off by default and per-session, so
`dev-*` sessions boot without it. This skill flips it on for a running
session by sending `/remote-control` into the Claude pane over tmux —
no attach needed — and returns the `claude.ai/code` URL to drive that
session from a browser or the mobile app. When spinning up a session I
know I'll steer remotely, the spin-up folds this in so the join link
comes back in one pass. Two hard-won notes are written into the skill:
a "stuck" remote session is almost always a stale browser client
(refresh the tab before suspecting the session), and if you lose the
tab, `/rc` on an already-active session opens a panel showing the URL —
it's not a toggle, so it's safe to recover the link that way.

**`dot_tmux.conf`** → `~/.tmux.conf`

More load-bearing than it looks: `set-titles` pushes the session name
into the Warp tab, and it renders the two at-a-glance state signals
described below — each is just a tmux user option plus a format
conditional, no plugins.

**`dot_claude/{settings.json,hooks}`** → `~/.claude/`

`settings.json` wires Claude Code's lifecycle hooks (and the status
line); `hooks/tmux-claude-state.sh` is the fire-and-forget script they
call to reflect Claude's live state into the session. It's kept as a
chezmoi template so the absolute hook paths track `{{ .chezmoi.homeDir }}`
across machines.

## seeing state at a glance

Six sessions in flight is only useful if I can tell which one wants me
without attaching. Guiding rule: **clean = silent; any mark means "pay
attention."** Two independent signals ride along in the session switcher
(`prefix + s`) and the status bar:

**Workflow phase** — a colored dot _before_ the session name: green =
active, yellow = up for review, magenta = experimental. Set by hand only
(`C-a` active, `C-p` review, `C-e` experimental, `C-d` clear) — a
deliberate mark. I tried auto-setting it per session type and ripped it
out: it just rotted to "active" on everything and meant nothing. It's
the `@state` user option.

**Live Claude state** — a glyph _after_ the name, driven by Claude
Code's lifecycle hooks, and deliberately just two states that matter:
cyan `▶` while it's working, red `!` when it's blocked waiting on me to
approve something. A finished or idle session shows **nothing** — so a
glyph always means "this one needs me." (Earlier I had a green `✓` for
"done" too, but since that's the resting state between turns it was just
noise, so `Stop` now clears the glyph instead.) The hooks shell out to
`tmux-claude-state.sh`, which sets the `@claude` user option; no-op
outside tmux, so it's free when I'm not in a session.

Both signals are just tmux user options + format conditionals, so the
same trick renders anything you can compute per session.

## the stack part (lives in the monorepo, not here)

Per-worktree isolated `pnpm dev` is the monorepo's worktree-isolation
feature (`scripts/worktree.sh`, opt in once with
`pnpm worktree:enable`) — each worktree gets its own database,
prefixes, Temporal namespace, and port block against the shared
docker stack. After that, a session just runs `pnpm dev`. The
teardown skill runs `worktree.sh destroy` before removing a worktree
so none of those resources leak. Nothing in this dotfiles repo
implements that; the sessions just inherit it.

## how to crib

The loancrate-specific assumptions are deliberately few and live in
the first ~10 lines of each file: the repo path, the worktrees dir,
the `felipe/` branch prefix, and the `apps/`/`packages/` layout for
the scoped variants. Swap those and the rest travels.

- **If you use chezmoi**: the machine-split trick is the part worth
  copying — work-only files are committed to the repo but
  `.chezmoiignore` (itself a template) only writes them out when
  `machine == "work"`. One repo, every machine, no leaked work config
  on your personal laptop. See the README for the full mechanism.
- **If you don't**: just take `lc-worktree`, `work.zsh`, and the
  tmuxinator templates as plain files and adjust the obvious
  constants. None of them depend on chezmoi at runtime.
- **If your editor isn't vim or your multiplexer isn't tmux**: take
  `lc-worktree` and the brief/teardown ideas, ignore the rest. The
  worktree prep, `.handoff.md` convention, and merge-aware cleanup
  are editor-agnostic; the session templates are just the tmux
  rendering of them.
