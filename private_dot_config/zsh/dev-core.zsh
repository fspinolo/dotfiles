# Dev sessions (tmuxinator) — shared core for all machines.
# dev                 -> _dev_default (work: devroot stack session;
#                        personal: fzf picker over ~/Development)
# dev <name> [<sub>]  -> session dev-<name>[-<sub>] rooted at the dir
#                        _dev_workdir resolves
# dev rm <name>       -> kill its sessions, then _dev_rm_extra
# devbrief <name> [<brief-file>]   (or: devbrief <name> < brief.md)
#                     -> brief-seeded session: writes the brief to
#                        <workdir>/.handoff.md and launches claude in
#                        plan mode told to read it first — for spinning
#                        off a scoped task with context carried over
#                        from another session. Forking a project whose
#                        session is already running picks a free name
#                        (dev-<name>-2, -3, ...).
#
# Machine-specific behavior comes from hook functions defined in
# work.zsh (work) or dev-personal.zsh (personal):
#   _dev_workdir <name> [<sub>]  resolve (and create, if needed) the
#                                working dir; print "<canonical-name>\t<dir>"
#                                (canonical name may differ from <name>,
#                                e.g. personal unique-prefix matching)
#   _dev_default                 what bare `dev` does
#   _dev_rm_extra <name>         teardown after the sessions are killed
dev() {
  if [[ -z "$1" ]]; then
    _dev_default
    return
  fi
  if [[ "$1" == "rm" ]]; then
    local name="$2"
    if [[ -z "$name" ]]; then
      echo "usage: dev rm <name>" >&2
      local running
      running=$(tmux ls -F '#S' 2>/dev/null | grep '^dev-')
      if [[ -n "$running" ]]; then
        echo "running dev sessions:" >&2
        echo "$running" >&2
      fi
      return 1
    fi
    local session
    for session in $(tmux ls -F '#S' 2>/dev/null | grep -E "^dev-${name}(-|$)"); do
      tmux kill-session -t "$session" && echo "dev: killed tmux session $session"
    done
    _dev_rm_extra "$name"
    return
  fi
  local resolved name workdir
  resolved=$(_dev_workdir "$1" "$2") || return 1
  name="${resolved%%$'\t'*}"
  workdir="${resolved#*$'\t'}"
  local session="dev-$name"
  [[ -n "$2" ]] && session="dev-$name-$2"
  tmuxinator start dev session="$session" workdir="$workdir"
}

devbrief() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "usage: devbrief <name> <brief-file>  (or pipe the brief on stdin)" >&2
    return 1
  fi
  local resolved workdir
  resolved=$(_dev_workdir "$name") || return 1
  name="${resolved%%$'\t'*}"
  workdir="${resolved#*$'\t'}"
  local brief="$workdir/.handoff.md"
  if [[ -n "$2" ]]; then
    if [[ ! -f "$2" ]]; then
      echo "devbrief: brief file not found: $2" >&2
      return 1
    fi
    cp "$2" "$brief"
  elif [[ ! -t 0 ]]; then
    cat > "$brief"
  else
    echo "devbrief: provide a brief file or pipe one on stdin" >&2
    return 1
  fi
  # Keep the brief out of git status. --git-common-dir points at the
  # main repo's .git for worktrees (which share info/exclude) and the
  # plain .git dir otherwise; non-repos skip silently.
  local gitdir exclude
  gitdir=$(git -C "$workdir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [[ -n "$gitdir" ]]; then
    exclude="$gitdir/info/exclude"
    if [[ -f "$exclude" ]] && ! grep -qxF '.handoff.md' "$exclude"; then
      echo '.handoff.md' >> "$exclude"
    fi
  fi
  # The session runs Claude in plan mode (see dev.yml), which blocks
  # all file edits. Pre-approve mundane read-only commands so a background
  # planning session doesn't stall on permission prompts. Only written if
  # the workdir has no local settings yet, to avoid clobbering.
  local claude_local="$workdir/.claude/settings.local.json"
  if [[ ! -f "$claude_local" ]]; then
    mkdir -p "$workdir/.claude"
    cat > "$claude_local" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(git fetch:*)",
      "Bash(git log:*)",
      "Bash(git diff:*)",
      "Bash(git show:*)",
      "Bash(git status:*)",
      "Bash(git branch:*)",
      "Bash(git rev-parse:*)",
      "Bash(git remote:*)",
      "Bash(gh pr diff:*)",
      "Bash(gh pr view:*)",
      "Bash(gh pr list:*)",
      "Bash(gh api:*)",
      "Bash(grep:*)",
      "Bash(rg:*)",
      "Bash(find:*)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(wc:*)"
    ]
  }
}
JSON
  fi
  local session="dev-$name" n=2
  while tmux has-session -t "=$session" 2>/dev/null; do
    session="dev-$name-$n"
    (( n++ ))
  done
  echo "devbrief: wrote handoff brief to $brief"
  tmuxinator start dev session="$session" workdir="$workdir" brief=1
}
