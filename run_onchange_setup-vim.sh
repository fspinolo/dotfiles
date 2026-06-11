#!/bin/sh
set -eu

# Vim setup that can't be expressed as a static file or a plain
# git-repo external:
#   - the swap directory referenced by ~/.vimrc must exist
#   - YouCompleteMe needs recursive submodules and a per-machine native
#     build (its compiled core is tied to this machine's Python + arch,
#     so it can never be synced as a file)
#
# Idempotent: clones only when missing, builds only when the compiled
# core is absent. nerdtree and fzf.vim are handled declaratively in
# .chezmoiexternal.toml instead.

mkdir -p "$HOME/.vim/swap"

# YCM requires a recent Python (>= 3.12 as of 2026), but macOS's
# path_helper can leave /usr/bin (system Python 3.9) ahead of Homebrew
# in the PATH this script runs with. Resolve Homebrew's interpreter
# explicitly and front-load its bin dir so cmake etc. are found too.
# ycmd records the interpreter used at build time, so vim launches the
# server with this same Python at runtime.
brew_bin="$(brew --prefix)/bin"
PATH="$brew_bin:$PATH"
ycm_python="$brew_bin/python3"

ycm_dir="$HOME/.vim/pack/vendor/start/ycm"

if [ ! -d "$ycm_dir/.git" ]; then
  git clone --recurse-submodules \
    https://github.com/ycm-core/YouCompleteMe.git "$ycm_dir"
fi

if ! ls "$ycm_dir"/third_party/ycmd/ycm_core.*.so >/dev/null 2>&1; then
  # Trim --all to specific completers (e.g. --ts-completer
  # --clangd-completer) if a toolchain for one language is missing.
  "$ycm_python" "$ycm_dir/install.py" --all
fi
