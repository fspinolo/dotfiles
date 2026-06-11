# Personal hooks for the shared dev-session core (dev-core.zsh).
# Projects are plain directories under ~/Development; names resolve by
# exact match, then unique prefix (dev dnd -> dndsheetz). Bare `dev`
# opens an fzf picker. No worktrees or branches, so rm has no teardown.

_dev_default() {
  local name
  name=$(print -rl -- "$HOME"/Development/*(N/:t) | fzf) || return
  dev "$name"
}

_dev_workdir() {
  local dev_dir="$HOME/Development"
  local name="$1"
  local dir="$dev_dir/$name"
  if [[ ! -d "$dir" ]]; then
    local -a matches
    matches=("$dev_dir/$name"*(N/))
    if (( ${#matches} == 1 )); then
      dir="${matches[1]}"
      name="${dir:t}"
    elif (( ${#matches} > 1 )); then
      echo "dev: ambiguous project name: $name" >&2
      print -rl -- ${matches:t} >&2
      return 1
    else
      echo "dev: no such project: $name" >&2
      echo "available projects:" >&2
      print -rl -- "$dev_dir"/*(N/:t) >&2
      return 1
    fi
  fi
  if [[ -n "$2" ]]; then
    if [[ -d "$dir/$2" ]]; then
      dir="$dir/$2"
    else
      echo "dev: no such subdirectory in $name: $2" >&2
      return 1
    fi
  fi
  printf '%s\t%s\n' "$name" "$dir"
}

_dev_rm_extra() {
  return 0
}
