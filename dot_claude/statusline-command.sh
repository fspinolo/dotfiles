#!/bin/sh
# Claude Code status line — mirrors p10k classic style (dir, git, user@host)
# plus Claude-specific context (model, context window usage, PR CI dot).
# The PR number itself is rendered by Claude Code's own footer line, so
# this script adds only the CI status dot next to the branch.
#
# Colors sourced from ~/.p10k.zsh (nerdfont-v3 + classic/dark theme):
#   context (user@host) : 256-color 180 (warm tan/gold)
#   dir                 : 256-color  31 (teal-blue); anchor 39 (cyan)
#   vcs clean           : 256-color  76 (green)
#   vcs modified        : 256-color 178 (amber)
#   vcs conflicted      : 256-color 196 (red)
#   model / meta        : 256-color 244 (mid-grey, matches p10k right-prompt)
#   ctx usage           : 256-color 248 (light-grey, matches execution_time)

# c256 FG <n>  — emit ESC[38;5;<n>m
c256() { printf '\033[38;5;%sm' "$1"; }
# bold — emit ESC[1m
bold() { printf '\033[1m'; }
# reset — clear all attributes
reset() { printf '\033[0m'; }

input=$(cat)

user=$(whoami)
host=$(hostname -s)
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
short_dir=$(echo "$dir" | sed "s|$HOME|~|")

branch=$(git -C "$dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# PR CI dot — cached per repo+branch, refreshed in the background every 45s.
# Never blocks: reads a stale cache file and fires an async refresh when due.
pr_badge=""
if [ -n "$branch" ] && command -v gh >/dev/null 2>&1; then
  # Derive a cache key from the remote URL + branch so different repos don't
  # collide even when they share a branch name.
  remote_url=$(git -C "$dir" --no-optional-locks remote get-url origin 2>/dev/null)
  cache_key=$(printf '%s\n%s' "$remote_url" "$branch" \
    | cksum | awk '{print $1}')
  cache_file="/tmp/claude-sl-pr-${cache_key}"
  now=$(date +%s)

  # Determine when the cache was last written (0 if it doesn't exist yet).
  if [ -f "$cache_file" ]; then
    cache_mtime=$(stat -f '%m' "$cache_file" 2>/dev/null \
      || stat -c '%Y' "$cache_file" 2>/dev/null || echo 0)
  else
    cache_mtime=0
  fi

  cache_age=$((now - cache_mtime))

  # Trigger a background refresh when the cache is stale (>45 s) or absent.
  # The subshell runs with stdin/stdout closed so it never blocks the parent.
  if [ "$cache_age" -gt 45 ]; then
    (
      # Touch immediately so concurrent renders don't all spawn a fetch.
      touch "$cache_file" 2>/dev/null

      # Resolve the open PR number for this branch (5 s hard timeout).
      # macOS has no `timeout` binary; perl's alarm is the portable
      # equivalent and perl ships with the OS.
      pr_num=$(cd "$dir" && perl -e 'alarm shift; exec @ARGV' 5 \
        gh pr view --json number --jq '.number' 2>/dev/null)

      if [ -n "$pr_num" ]; then
        # Fetch the aggregate CI state for the PR's head commit.
        # `bucket` groups check states: pass, fail, pending, skipping,
        # cancel (it is the only aggregate field `gh pr checks` offers).
        conclusion=$(cd "$dir" && perl -e 'alarm shift; exec @ARGV' 5 \
          gh pr checks "$pr_num" --json bucket \
          --jq '[.[] | select(.bucket != "skipping")] |
                if length == 0 then "pending"
                elif all(.bucket == "pass") then "success"
                elif any(.bucket == "fail" or .bucket == "cancel") then "failure"
                else "pending"
                end' 2>/dev/null)

        # Wrap the dot in an OSC 8 hyperlink so terminals that support
        # it (e.g. Warp) make it clickable. Terminals without OSC 8
        # support render the plain symbol unchanged.
        repo_https=$(printf '%s' "$remote_url" \
          | sed -e 's|^git@github.com:|https://github.com/|' \
                -e 's|\.git$||')
        link_open=$(printf '\033]8;;%s/pull/%s\033\\' "$repo_https" "$pr_num")
        link_close=$(printf '\033]8;;\033\\')

        # Map conclusion → colored symbol (written as literal ESC sequences so
        # the cache file contains ready-to-print colored text).
        case "$conclusion" in
          success) printf ' %s\033[38;5;76m✓\033[0m%s'  "$link_open" "$link_close" > "$cache_file" ;;
          failure) printf ' %s\033[38;5;196m✗\033[0m%s' "$link_open" "$link_close" > "$cache_file" ;;
          *)       printf ' %s\033[38;5;178m●\033[0m%s' "$link_open" "$link_close" > "$cache_file" ;;
        esac
      else
        # No open PR — write an empty marker so we don't keep polling.
        printf '' > "$cache_file"
      fi
    ) </dev/null >/dev/null 2>&1 &
  fi

  # Read whatever the cache currently holds (may be empty on first render).
  if [ -f "$cache_file" ]; then
    pr_badge=$(cat "$cache_file")
  fi
fi

# Build the status line using printf so ANSI escape sequences render correctly.

# user@host  — p10k context foreground 180 (warm tan/gold)
printf '%b%s@%s%b' "$(c256 180)" "$user" "$host" "$(reset)"

# directory  — p10k dir foreground 31 (teal-blue), anchor bold+39 (cyan)
printf '  %b%b%s%b' "$(bold)" "$(c256 39)" "$short_dir" "$(reset)"

# git branch (and optional PR CI dot) when available
# vcs clean color: 76 (green), matching POWERLEVEL9K_VCS_CLEAN_FOREGROUND
if [ -n "$branch" ]; then
  printf '  %b%s%b' "$(c256 76)" "$branch" "$(reset)"
  if [ -n "$pr_badge" ]; then
    # pr_badge already contains embedded ANSI color codes from the cache
    printf '%s' "$pr_badge"
  fi
fi

# model — p10k metadata grey 244 (matches right-prompt meta style)
if [ -n "$model" ]; then
  printf '  %b%s%b' "$(c256 244)" "$model" "$(reset)"
fi

# context usage — p10k execution_time grey 248
if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")
  printf '  %bctx:%s%%%b' "$(c256 248)" "$used_int" "$(reset)"
fi
