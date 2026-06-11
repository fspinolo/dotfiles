# Loancrate hooks for the shared dev-session core (dev-core.zsh).
# dev                 -> devroot session on the main checkout; owns the
#                        dev stack (pnpm dev), which can only run once
#                        (shared docker + ports)
# dev <task>          -> repo root session in worktree <task>
# dev <task> <name>   -> apps/<name> session in that worktree, falling
#                        back to packages/<name>
# dev rm <task>       -> kill its tmux sessions, remove worktree + branch
# Worktrees live in ~/Development/loancrate-worktrees/<task> on branch
# felipe/<task>; lc-worktree (in ~/.local/bin) creates and prepares them.

_dev_default() {
  tmuxinator start dev session=devroot \
    workdir="$HOME/Development/loancrate" stack_cmd="pnpm dev"
}

_dev_workdir() {
  local task="$1"
  local workdir="$HOME/Development/loancrate-worktrees/$task"
  lc-worktree "$task" >&2 || return 1
  if [[ -z "$2" ]]; then
    printf '%s\t%s\n' "$task" "$workdir"
  elif [[ -d "$workdir/apps/$2" ]]; then
    printf '%s\t%s\n' "$task" "$workdir/apps/$2"
  elif [[ -d "$workdir/packages/$2" ]]; then
    printf '%s\t%s\n' "$task" "$workdir/packages/$2"
  else
    echo "dev: no such app or package: $2" >&2
    echo "available apps:" >&2
    ls "$workdir/apps" >&2
    echo "available packages:" >&2
    ls "$workdir/packages" >&2
    return 1
  fi
}

_dev_rm_extra() {
  local repo_dir="$HOME/Development/loancrate"
  local worktrees_dir="$HOME/Development/loancrate-worktrees"
  local task="$1"
  local workdir="$worktrees_dir/$task"
  local branch
  if [[ "$task" == */* ]]; then
    branch="$task"
  else
    branch="felipe/$task"
  fi
  if [[ -d "$workdir" ]]; then
    git -C "$repo_dir" worktree remove "$workdir" || {
      echo "dev: worktree has uncommitted changes; to discard them run:" >&2
      echo "  git -C $repo_dir worktree remove --force $workdir" >&2
      return 1
    }
    echo "dev: removed worktree $workdir"
  fi
  if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch"; then
    if git -C "$repo_dir" branch -d "$branch" 2>/dev/null; then
      echo "dev: deleted branch $branch"
    else
      # branch -d refuses squash-merged branches, so trust the PR
      # state instead: a merged PR means the work is on master.
      local pr_state
      pr_state=$(cd "$repo_dir" && gh pr view "$branch" \
        --json state --jq .state 2>/dev/null)
      if [[ "$pr_state" == "MERGED" ]]; then
        git -C "$repo_dir" branch -D "$branch" >/dev/null
        echo "dev: deleted branch $branch (its PR is merged)"
      else
        echo "dev: branch $branch not fully merged" \
          "(PR state: ${pr_state:-no PR found}); to discard it run:" >&2
        echo "  git -C $repo_dir branch -D $branch" >&2
      fi
    fi
  fi
}
