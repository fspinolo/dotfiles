---
name: dev-session
description: Create a dev session (git worktree + tmux) for a task in the loancrate monorepo, optionally seeded from a Linear ticket with a handoff brief. Use when asked to "create/spin up a dev session", "start a session off <ticket>", or "start work on LC-XXXX in a worktree".
---

# Create a dev session

Felipe works one task per git worktree at
`~/Development/loancrate-worktrees/<task>` on branch `felipe/<task>`,
with a tmux session named `dev-<task>`. The interactive entry points
are the `dev`/`devbrief` zsh functions in `~/.config/zsh/work.zsh`;
this skill replicates them non-interactively, plus the Linear and
handoff-brief bookkeeping. Companion teardown skill:
`clean-dev-sessions`.

## 0. Gather inputs

- **Ticket** (optional): if given a Linear URL/key, fetch it with the
  Linear MCP `get_issue` — the description usually defines scope.
- **Task name**: short kebab-case, 2–4 words (e.g.
  `temporal-history-archival`), NOT Linear's long `gitBranchName`.
  Derive from the ticket title; confirm only if genuinely ambiguous.
- **Session flavor**: plain session, or brief-seeded (default when
  there's a ticket or context from the current conversation worth
  carrying over — worktrees are a *different Claude project*, so this
  project's memory does NOT follow; anything the new session needs
  must go in the brief).

## 1. Create the worktree

```bash
~/.local/bin/lc-worktree <task>
```

Run in background — it fetches origin, creates/reuses branch
`felipe/<task>` from origin/master, copies gitignored `.env` files,
and runs `pnpm install` (first run takes ~1 min+). It's idempotent.
Watch its warnings: an existing branch ahead of master is reused
as-is.

## 2. Write the handoff brief (brief-seeded sessions)

Write `<worktree>/.handoff.md`. Make sure `.handoff.md` is listed in
`~/Development/loancrate/.git/info/exclude` (append if missing —
worktrees share the main repo's exclude file).

Brief contents — write for a fresh Claude with zero context:

- Ticket link + faithful restatement of scope.
- Felipe's framing/directive in this conversation (e.g. "decision is
  made, just stand it up") — this often overrides the ticket's
  literal wording.
- Prior-work facts **inlined**, not referenced: related merged PR
  numbers, verified values, recipes from memory. Cite where each was
  verified and when.
- Concrete file/dir pointers to start from.
- Open design questions to answer.
- Expected deliverable, and a reminder to keep Linear updated.

Note: the `devbrief` zsh function also pre-writes
`.claude/settings.local.json` with read-only Bash allows. Do NOT
write that file yourself — the auto-mode classifier denies it as
self-modification (widening permission grants). Skip it (the new
session will just prompt) or ask Felipe to run
`! devbrief <task> <brief-file>` himself.

## 3. Start the tmux session

```bash
# brief-seeded (Claude pane boots in plan mode reading .handoff.md):
tmuxinator start devbrief --no-attach task=<task> workdir=$HOME/Development/loancrate-worktrees/<task>

# plain:
tmuxinator start devtree --no-attach task=<task> workdir=...
# app/package-focused variants: devapp <app> / devpkg <pkg> templates
```

`--no-attach` is required from a non-tty. Verify with
`tmux ls` — expect `dev-<task>`. Felipe attaches via Warp or
`tmux a -t dev-<task>` (always the abbreviated form when surfacing
the attach command).

### Per-worktree stacks (worktree isolation)

Worktree isolation is enabled machine-wide (opted in 2026-06-12 via
`pnpm worktree:enable`; `scripts/worktree.sh` is the source of
truth, documented in the repo CLAUDE.md "Worktree isolation"
section). Every worktree can run its own full `pnpm dev` stack
concurrently: isolated Postgres database, Redis/OpenSearch/Kafka
prefixes, Temporal namespace, and a stable port block — all against
the single shared docker stack. `devroot` (the main checkout) is
never isolated and keeps default ports/data.

Still don't auto-start the stack when creating a session — that's
the new session's call when it needs a running app. Facts it (or a
brief) may need:

- `pnpm dev` in the worktree auto-bootstraps its resources and
  prints its URLs; client is at the port block's base, API at
  base+1. Full env/port mapping: `./scripts/worktree.sh env`
  (allocations cached in `~/.loancrate/ports/<task>.conf`).
- Anything started **outside** `pnpm dev` (e2e tests, `reset-db`,
  seeds, arena) must be wrapped — `./scripts/worktree.sh run <cmd>`
  — or it silently targets the main checkout's DB and ports.
- First `pnpm dev` in a fresh worktree creates + migrates + seeds
  its own database, so expect a slower first boot.
- Full-infra alternative for branches that change docker-compose or
  infra versions: the OrbStack runner (`scripts/orb/README.md`,
  one VM + own compose stack per worktree). Heavier; conflicts with
  native stacks (its Caddy owns localhost:3000/4000), so not the
  default.

## 4. Linear bookkeeping

If the session is for a ticket: move it to **Eng in Progress**
(assignee stays/becomes Felipe). Surface key + URL in the summary.

## 5. Report

Session name, worktree path, branch, what the brief covers, ticket
status change, and the attach command.
