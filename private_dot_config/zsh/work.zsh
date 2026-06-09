# Loancrate dev sessions (tmuxinator)
# dev                 -> dev stack session on the main checkout
#                        (devroot.yml, runs pnpm dev — the one stack)
# dev <task>          -> repo root session in worktree <task> (devtree.yml)
# dev <task> <name>   -> apps/<name> session in that worktree (devapp.yml),
#                        falling back to packages/<name> (devpkg.yml)
# dev rm <task>       -> kill its tmux sessions, remove worktree + branch
# Worktrees live in ~/Development/loancrate-worktrees/<task> on branch
# felipe/<task>; lc-worktree (in ~/.local/bin) creates and prepares them.
dev() {
  local repo_dir="$HOME/Development/loancrate"
  local worktrees_dir="$HOME/Development/loancrate-worktrees"
  if [[ -z "$1" ]]; then
    tmuxinator start devroot
    return
  fi
  if [[ "$1" == "rm" ]]; then
    local task="$2"
    if [[ -z "$task" ]]; then
      echo "usage: dev rm <task>" >&2
      if [[ -d "$worktrees_dir" && -n "$(ls "$worktrees_dir" 2>/dev/null)" ]]; then
        echo "existing worktrees:" >&2
        ls "$worktrees_dir" >&2
      fi
      return 1
    fi
    local workdir="$worktrees_dir/$task"
    local branch
    if [[ "$task" == */* ]]; then
      branch="$task"
    else
      branch="felipe/$task"
    fi
    local session
    for session in $(tmux ls -F '#S' 2>/dev/null | grep -E "^dev-${task}(-|$)"); do
      tmux kill-session -t "$session" && echo "dev: killed tmux session $session"
    done
    if [[ -d "$workdir" ]]; then
      git -C "$repo_dir" worktree remove "$workdir" || {
        echo "dev: worktree has uncommitted changes; to discard them run:" >&2
        echo "  git -C $repo_dir worktree remove --force $workdir" >&2
        return 1
      }
      echo "dev: removed worktree $workdir"
    fi
    if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$repo_dir" branch -d "$branch" 2>/dev/null && {
        echo "dev: deleted branch $branch"
      } || {
        echo "dev: branch $branch not fully merged (normal with squash" >&2
        echo "merges); if its PR is merged/abandoned, run:" >&2
        echo "  git -C $repo_dir branch -D $branch" >&2
      }
    fi
    return 0
  fi
  local task="$1"
  local workdir="$worktrees_dir/$task"
  lc-worktree "$task" || return 1
  if [[ -z "$2" ]]; then
    tmuxinator start devtree task="$task" workdir="$workdir"
  elif [[ -d "$workdir/apps/$2" ]]; then
    tmuxinator start devapp "$2" task="$task" workdir="$workdir"
  elif [[ -d "$workdir/packages/$2" ]]; then
    tmuxinator start devpkg "$2" task="$task" workdir="$workdir"
  else
    echo "dev: no such app or package: $2" >&2
    echo "available apps:" >&2
    ls "$workdir/apps" >&2
    echo "available packages:" >&2
    ls "$workdir/packages" >&2
    return 1
  fi
}

# devbrief <task> <brief-file>   (or: devbrief <task> < brief.md)
# Like `dev <task>`, but seeds the worktree with a handoff brief and
# launches Claude told to read it first — for spinning off a scoped
# follow-on task with full context carried over from another session.
# The brief lands at <worktree>/.handoff.md (kept out of git status via
# the repo's local info/exclude).
devbrief() {
  local repo_dir="$HOME/Development/loancrate"
  local worktrees_dir="$HOME/Development/loancrate-worktrees"
  local task="$1"
  if [[ -z "$task" ]]; then
    echo "usage: devbrief <task> <brief-file>  (or pipe the brief on stdin)" >&2
    return 1
  fi
  local workdir="$worktrees_dir/$task"
  lc-worktree "$task" || return 1
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
  local exclude="$repo_dir/.git/info/exclude"
  if [[ -f "$exclude" ]] && ! grep -qxF '.handoff.md' "$exclude"; then
    echo '.handoff.md' >> "$exclude"
  fi
  # The session runs Claude in plan mode (see devbrief.yml), which blocks
  # all file edits. Pre-approve mundane read-only commands so a background
  # planning session doesn't stall on permission prompts. Only written if
  # the worktree has no local settings yet, to avoid clobbering.
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
  echo "devbrief: wrote handoff brief to $brief"
  tmuxinator start devbrief task="$task" workdir="$workdir"
}
