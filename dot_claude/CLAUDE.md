# tmux panes

In my `dev-*` tmux sessions (layout: vim on top, work pane on the bottom), when I ask for a new pane, split the **bottom pane horizontally** so the new pane sits side-by-side with it — never stack a new full-width pane below. Find the bottom pane via `tmux list-panes -F '#{pane_id} #{pane_current_command} top=#{pane_top}'` (the non-vim pane with the highest `top`), then `tmux split-window -d -h -t <pane_id> '<command>'` (`-d` to avoid stealing focus).

# Terminal

I use Warp + tmux; `~/.tmux.conf` sets `set-titles` so Warp tabs show the tmux session name. I like Warp's auto-title behavior outside tmux — never suggest `WARP_DISABLE_AUTO_TITLE`.

# Missing auth

When a tool/CLI fails for lack of authentication (`bk`, `gh`, `aws sso`, etc.), stop and prompt me to authenticate — give the exact command, suggesting the `! <command>` form for interactive logins. Don't silently work around missing auth with local repros or scraping; I'd rather provide the credential.

# Drafting Slack messages for me

Purely technical and conversational: lead with the symptom + the concrete technical question; lowercase, brief, low-pressure. No ownership/process framing ("who should own this?"), no Linear ticket citations in casual messages. Let the team self-organize. (Deletions from my edits are the reliable signal — I cut process scaffolding, keep technical content.)

# Durable artifacts (PRs, RFCs, docs, Linear)

- **PR descriptions describe the change only** — what, why, verification, links. Review logistics/scheduling/personnel availability go in Slack or the ticket, never the PR body.
- **Never frame findings around employee departures** ("unowned since X left") in RFCs/Linear/Slack/docs — state the structural gap neutrally. Crediting a person's idea or prior work is fine.
- **Hyperlink citations inline at point of mention** (Linear keys, PR numbers, Slack permalinks; code links pinned to a commit SHA so line anchors don't rot). A trailing References section only for material with no natural inline home.

# Reviewer notifications (loancrate)

Konstantin ("Tony", KonstantinSimeonov) doesn't watch GitHub notifications — after requesting his review, ping him on Slack once CI is green (skip if the PR already has an approval). Nate Diamond (nediamond) watches GitHub — review request suffices, no ping.

# Machine reference pointers

Detailed notes live in the loancrate project memory (`~/.claude/projects/-Users-felipespinolo-Development-loancrate/memory/`):
- Dotfiles are managed by **chezmoi** (`dotfiles-chezmoi.md`) — before any `chezmoi add`, run `chezmoi status` first (add clobbers unapplied source changes).
- Claude Code statusline script details (`statusline-pr-badge.md`) — note: this Mac has no `timeout`/`gtimeout` binary; use `perl -e 'alarm shift; exec @ARGV' <secs> <cmd>`.
