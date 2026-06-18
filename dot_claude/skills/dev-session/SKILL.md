---
name: dev-session
description: Create a dev session (git worktree + tmux) for a task in the loancrate monorepo or another loancrate repo (e.g. infra, datadog-monitoring), optionally seeded from a Linear ticket with a handoff brief. Use when asked to "create/spin up a dev session", "start a session off <ticket>", or "start work on LC-XXXX in a worktree".
---

# Create a dev session

Felipe works one task per git worktree on branch `felipe/<task>`, with a
tmux session named `dev-<task>`. The common case is the **monorepo**
(`~/Development/loancrate-worktrees/<task>`), driven by the `dev`/`devbrief`
zsh functions in `~/.config/zsh/work.zsh`; this skill replicates them
non-interactively, plus the Linear and handoff-brief bookkeeping. The same
conventions extend to **other loancrate repos** (e.g. `infra`,
`datadog-monitoring`) — only the worktree creation differs (§1). Companion
teardown skill: `clean-dev-sessions`.

## 0. Gather inputs

- **Ticket** (optional): if given a Linear URL/key, fetch it with the
  Linear MCP `get_issue` — the description usually defines scope.
- **Target repo**: the monorepo unless the task clearly lives elsewhere
  (an `infra`/terraform change, a `datadog-monitoring`/Pulumi change,
  etc.). Default to monorepo; the work itself usually makes it obvious.
- **Task name**: short kebab-case, 2–4 words (e.g.
  `temporal-history-archival`), NOT Linear's long `gitBranchName`.
  Derive from the ticket title; confirm only if genuinely ambiguous.
- **Session flavor**: plain session, or brief-seeded (default when
  there's a ticket or context from the current conversation worth
  carrying over — worktrees are a *different Claude project*, so this
  project's memory does NOT follow; anything the new session needs
  must go in the brief).

## 1. Create the worktree

**Monorepo (the common case):**

```bash
~/.local/bin/lc-worktree <task>
```

Run in background — it fetches origin, creates/reuses branch
`felipe/<task>` from origin/master, copies gitignored `.env` files,
and runs `pnpm install` (first run takes ~1 min+). It's idempotent.
Watch its warnings: an existing branch ahead of master is reused
as-is.

**Another loancrate repo** (`infra`, `datadog-monitoring`, …) — same
worktree/branch/tmux conventions, but `lc-worktree` is monorepo-only, so
set it up by hand. The base clone lives at `~/Development/<repo>` and its
worktrees at `~/Development/<repo>-worktrees/<task>`:

```bash
repo=infra   # i.e. github.com/loancrate/<repo>
# clone the base checkout once if it's missing:
[ -d ~/Development/$repo ] || git clone git@github.com:loancrate/$repo.git ~/Development/$repo
git -C ~/Development/$repo fetch origin --quiet
# default branch is usually master — confirm with:
#   git -C ~/Development/$repo symbolic-ref --short HEAD
git -C ~/Development/$repo worktree add -b felipe/<task> \
  ~/Development/$repo-worktrees/<task> origin/master
```

No `pnpm install` or monorepo bootstrap — these repos bring their own
tooling (infra = terraform/JSON, datadog-monitoring = Pulumi). Only copy
gitignored env files if that repo actually uses them.

## 2. Write the handoff brief (brief-seeded sessions)

Write `<worktree>/.handoff.md`. Make sure `.handoff.md` is listed in the
base clone's exclude file (worktrees share their base repo's exclude) —
`~/Development/loancrate/.git/info/exclude` for the monorepo, or
`~/Development/<repo>/.git/info/exclude` for another repo. Append if
missing.

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

Monorepo only — other repos have their own run story (terraform plan,
pulumi preview, etc.), so skip this section for them.

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

Session name, worktree path (and repo, if not the monorepo), branch,
what the brief covers, ticket status change, and the attach command.
