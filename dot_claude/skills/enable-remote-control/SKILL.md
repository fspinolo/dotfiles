---
name: enable-remote-control
description: Turn on Claude Code Remote Control for a running dev session by driving its tmux pane, so it can be monitored/steered from the phone (Claude app → Code) or claude.ai/code. Use when asked to "enable remote control", "turn on rc", "make this/that session remote-controllable", or "drive the dev session from my phone". Returns the session's claude.ai/code URL.
---

# Enable Remote Control for a dev session

Claude Code **Remote Control** (`/remote-control`) is **off by default and
per-session**. Our `dev-*` sessions launch plain `claude` in a tmux pane (via the
`devbrief`/`devtree` tmuxinator templates), so they boot WITHOUT rc. This skill
flips it on by sending `/remote-control` into the session's Claude pane over
tmux — no need to attach — and returns the URL to drive it from the phone.

This is intentionally **opt-in per session** (rather than baking
`claude --remote-control` into the template) — run it on the sessions you actually
want to drive remotely.

## 1. Resolve the target session
- If given a name (`dev-foo`, or bare `foo` → `dev-foo`), use that.
- Else default to the current session:
  `tmux display-message -p -t "$TMUX_PANE" '#{session_name}'` when invoked inside
  tmux; otherwise `tmux ls` and pick the most-recently-active `dev-*` session
  (ask if genuinely ambiguous).
- Verify: `tmux has-session -t <session>` (error out clearly if missing).

## 2. Find the Claude pane
`tmux list-panes -s -t <session> -F '#{pane_id} #{pane_current_command}'`

The Claude pane is the one whose `pane_current_command` is the Claude CLI — it
shows as a **semver-ish version string** (e.g. `2.1.195`) or `node`, NOT
`vim`/`nvim`/`zsh`/`bash`/`fish`/`tmux`. Take that `%NNN` pane id. If two
candidates, `capture-pane` each and pick the one showing the Claude UI
("Claude Code v…" banner / the `❯` prompt).

## 3. Check pane state BEFORE sending
`tmux capture-pane -p -t <pane> | tail -30`
- If it's showing a **permission / selection prompt** ("Do you want to proceed?",
  "❯ 1. Yes", "Esc to cancel"): do NOT send the command — keystrokes would land in
  that prompt, not toggle rc. Surface the prompt to the user and let them resolve
  it (don't silently answer their work decisions), then retry. Only answer it
  yourself if they've explicitly said to keep the session unblocked AND it's an
  obviously-safe read-only action.
- If it's at the `❯` prompt OR actively working (`✻ …`): fine. `/remote-control`
  is a client-side toggle that activates whether idle or mid-turn, without
  interrupting the current work.

## 4. Turn it on
`tmux send-keys -t <pane> '/remote-control' Enter`

## 5. Verify + return the URL
Wait a few seconds (`perl -e 'select(undef,undef,undef,4)'` — the Bash tool blocks
the bare `sleep` binary), then:
`tmux capture-pane -p -t <pane> | grep -iE 'remote-control is active|/rc active|claude.ai/code/session'`
- Success: `/remote-control is active · Continue here, on your phone, or at
  https://claude.ai/code/session_…`, plus a `/rc active` badge in the statusline.
  **Extract and report the `https://claude.ai/code/session_…` URL.**
- If it didn't activate (input landed in a prompt, or pane was misidentified),
  report what the pane shows and retry once the blocker clears.

## Recovering the URL for an already-active session (lost tab)

Common case: the user closed/lost the browser tab but the local session and RC
are still running. RC is **still active** — you just need to re-surface the URL,
NOT re-enable it. Do NOT re-cycle RC (toggle off→on) to mint a new link.

1. Find the Claude pane and confirm RC is active (`tmux capture-pane -p -t
   <pane> | tail` shows `/rc active` in the statusline).
2. The URL usually scrolled out of pane history — don't rely on grepping
   scrollback. Instead open the panel: `tmux send-keys -t <pane> '/rc' Enter`,
   wait ~3s, then `capture-pane`.
3. `/rc` on an already-active session **opens the Remote Control panel; it does
   NOT toggle RC off.** The panel prints "This session is available … at
   https://claude.ai/code/session_…" with options (Disconnect / Show QR code /
   Continue). Extract the URL.
4. Dismiss with **`tmux send-keys -t <pane> Escape`** (Esc = Continue, leaves RC
   connected). NEVER select "Disconnect this session".

(Alternative that needs no URL: the user rejoins via Claude app → Code tab,
session by name with a green dot.)

## Notes / constraints
- The local machine + tmux pane must stay running; a network outage >~10 min ends
  the remote session (rc is a tunnel to the local process, not cloud-persistent).
- Drive it from: **Claude app → Code tab** (session appears by name with a green
  dot) or the returned `claude.ai/code` URL.
- **A "stuck"/unsubmitting RC session is usually a stale client — refresh it
  first.** Confirmed 2026-06-27 on `dev-temporal-async-rfc`: a remote (phone/web)
  client whose typed lines sat unsent in the composer was fixed simply by
  **refreshing the claude.ai/code tab** (reopen in the app). The local process and
  the session were fine the whole time. So the first move when a remote-driven
  session looks frozen is always: have the user refresh/reopen the RC client —
  don't assume the session, the input, or "ownership" is broken.
- **Don't try to drive a live-RC session via local `tmux send-keys`.** While a
  remote client was attached, local keystrokes into the pane were observed to be
  ignored (even `Ctrl-U` didn't clear the composer) — most likely a symptom of the
  stale client above, not a hard rule. `capture-pane` to *read* state is fine, but
  to *submit*/clear/disconnect, have the user act from their device (after a
  refresh) or fulfil the intent out-of-band (e.g. run `git push` yourself).
  `send-keys` is reliable only for *turning rc on* (before any remote client
  attaches).
- **Enabling RC on a session blocked at a *permission prompt*:** you must clear
  the prompt before `/remote-control` will register (keys sent at a permission
  prompt answer the prompt, they don't toggle rc). In an autonomous dev session
  the auto-mode classifier will **refuse to let you answer the prompt** (even a
  benign "1"/Yes) — it can't verify the pending command and treats it as
  approving an unseen op. So: read the pending command, then get the user's
  **explicit, pane-scoped grant** (e.g. "approved — send 1 then /remote-control to
  pane %NNN; that command is read-only") and cite it. Then approve `1` (NOT "2 /
  don't ask again" — too broad), and `/remote-control`.
- **Approve→new-prompt race:** after you answer one prompt, the session often hits
  the *next* permission prompt within ~1-2s, so a `/remote-control` sent right
  after lands on the new prompt and doesn't toggle. Always `capture-pane` to
  verify rc activated; if a fresh prompt appeared, surface it and get a new grant.
- This skill file lives at `~/.claude/skills/enable-remote-control/` (unmanaged
  until `chezmoi add`ed). To persist it in dotfiles: `chezmoi status` first, then
  `chezmoi add ~/.claude/skills/enable-remote-control/SKILL.md`.
