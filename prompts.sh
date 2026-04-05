#!/usr/bin/env bash
# prompts.sh — fzf-powered prompt manager
#
# Usage:
#   prompts              Browse/search all prompts
#   prompts <query>      Open browser pre-filtered by query
#   prompts -add         Add a new prompt via $EDITOR or stdin pipe
#   prompts -h|--help    Show this help

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
STORE_VERSION=1          # bump only when the store file format changes
MIN_COMPATIBLE_VERSION=1 # oldest store version this script can read without migration
PROMPTS_DIR="${PROMPTS_DIR:-$HOME/.config/prompts}"
PROMPTS_FILE="$PROMPTS_DIR/prompts.txt"
VERSION_FILE="$PROMPTS_DIR/.version"
LOCK_FILE="$PROMPTS_DIR/.lock"


# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
cmd_help() {
  cat <<EOF
prompts — fzf-powered prompt manager

Usage:
  prompts              Browse and search all prompts
  prompts <query>      Open browser pre-filtered by <query>
  prompts -add         Add a new prompt via \$EDITOR (or pipe via stdin)
  prompts -h|--help    Show this help

TUI keybindings:
  type                 Filter the list (exact substring match)
  enter                Copy selected prompt to clipboard and print to stdout
  ctrl-n               Add a new prompt via \$EDITOR
  ctrl-d               Delete selected prompt (with confirmation)
  esc / ctrl-c         Exit without selecting

Store:
  Prompts file:        ${PROMPTS_FILE}
  Store version:       ${STORE_VERSION}
  Min compat version:  ${MIN_COMPATIBLE_VERSION}
  Override dir:        set \$PROMPTS_DIR to use a different location
EOF
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
if ! command -v fzf &>/dev/null; then
  echo "Error: fzf is not installed." >&2
  echo "Install it with: brew install fzf" >&2
  exit 1
fi

# Ensure store dir + files exist
mkdir -p "$PROMPTS_DIR"
touch "$PROMPTS_FILE"

# Write version file on first run; check compatibility on subsequent runs
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "$STORE_VERSION" > "$VERSION_FILE"
else
  stored_version=$(cat "$VERSION_FILE")
  if (( stored_version > STORE_VERSION )); then
    echo "Error: store version (${stored_version}) is newer than this script (${STORE_VERSION})." >&2
    echo "Upgrade prompts.sh before continuing." >&2
    exit 1
  elif (( stored_version < MIN_COMPATIBLE_VERSION )); then
    echo "Error: store version (${stored_version}) is too old (minimum compatible: ${MIN_COMPATIBLE_VERSION})." >&2
    echo "Run the appropriate migration script before continuing." >&2
    exit 1
  fi
  # stored_version is between MIN_COMPATIBLE_VERSION and STORE_VERSION — compatible
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Acquire an exclusive write lock (releases automatically when subshell exits)
acquire_lock() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "Error: another prompts process is currently writing. Try again shortly." >&2
    exit 1
  fi
}

# Escape real newlines to literal \n for single-line storage
escape_newlines() {
  # Replace actual newline characters with the two-char sequence \n
  sed ':a;N;$!ba;s/\n/\\n/g'
}

# Unescape \n back to real newlines for output
unescape_newlines() {
  sed 's/\\n/\n/g'
}

# Add a prompt string (already a single line) to the store
save_prompt() {
  local prompt="$1"
  [[ -z "$prompt" ]] && { echo "Error: prompt is empty." >&2; exit 1; }
  acquire_lock
  echo "$prompt" >> "$PROMPTS_FILE"
  echo "Prompt saved." >&2
}

# Open $EDITOR, return the escaped content on stdout
edit_new_prompt() {
  local tmp
  tmp=$(mktemp /tmp/prompt.XXXXXX)
  trap 'rm -f "$tmp"' EXIT

  "${EDITOR:-vi}" "$tmp"

  local content
  content=$(cat "$tmp")
  [[ -z "$content" ]] && { echo "Error: no content entered." >&2; exit 1; }

  printf '%s' "$content" | escape_newlines
}

# Copy text to clipboard (macOS pbcopy; falls back to xclip/xsel on Linux)
copy_to_clipboard() {
  if command -v pbcopy &>/dev/null; then
    printf '%s' "$1" | pbcopy
  elif command -v xclip &>/dev/null; then
    printf '%s' "$1" | xclip -selection clipboard
  elif command -v xsel &>/dev/null; then
    printf '%s' "$1" | xsel --clipboard --input
  else
    echo "(clipboard not available — no pbcopy/xclip/xsel found)" >&2
  fi
}

# ---------------------------------------------------------------------------
# Add flow (non-TUI)
# ---------------------------------------------------------------------------
cmd_add() {
  local escaped

  if [[ ! -t 0 ]]; then
    # stdin is a pipe
    escaped=$(cat | escape_newlines)
  else
    escaped=$(edit_new_prompt)
  fi

  save_prompt "$escaped"
}

# ---------------------------------------------------------------------------
# TUI add (called from fzf bind — writes prompt then signals fzf to reload)
# ---------------------------------------------------------------------------
cmd_tui_add() {
  local escaped
  escaped=$(edit_new_prompt) || exit 0   # silently abort on empty
  save_prompt "$escaped"
}

# ---------------------------------------------------------------------------
# TUI delete (called from fzf bind with the selected line as argument)
# ---------------------------------------------------------------------------
cmd_tui_delete() {
  local line="$1"
  [[ -z "$line" ]] && exit 0
  read -r -p "Delete prompt? [y/N] " confirm </dev/tty
  [[ "$confirm" != [yY] ]] && exit 0
  acquire_lock
  local tmp
  tmp=$(mktemp "$PROMPTS_DIR/.prompts.XXXXXX")
  # Remove the first exact match of the selected line
  awk -v target="$line" '!found && $0==target { found=1; next } { print }' \
    "$PROMPTS_FILE" > "$tmp"
  mv "$tmp" "$PROMPTS_FILE"
}

# ---------------------------------------------------------------------------
# Browse / TUI
# ---------------------------------------------------------------------------
cmd_browse() {
  local query="${1:-}"

  local reload_cmd="cat '$PROMPTS_FILE'"

  local selected
  selected=$(
    cat "$PROMPTS_FILE" \
    | fzf \
        --exact \
        --height=14 \
        --layout=reverse \
        --prompt="prompts> " \
        --query="$query" \
        --no-sort \
        --bind "ctrl-n:execute($0 --_tui-add)+reload($reload_cmd)" \
        --bind "ctrl-d:execute($0 --_tui-delete {})+reload($reload_cmd)" \
        --header $'enter: copy & print  |  ctrl-n: new  |  ctrl-d: delete' \
        --preview "echo {} | sed 's/\\\\n/\n/g'" \
        --preview-window=down:3:wrap \
    || true
  )

  [[ -z "$selected" ]] && exit 0

  local output
  output=$(printf '%s' "$selected" | unescape_newlines)

  copy_to_clipboard "$output"
  printf '%s\n' "$output"
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
case "${1:-}" in
  -add|--add)
    cmd_add
    ;;
  --_tui-add)
    cmd_tui_add
    ;;
  --_tui-delete)
    cmd_tui_delete "${2:-}"
    ;;
  -h|--help)
    cmd_help
    ;;
  -*)
    echo "Unknown option: ${1}. Run 'prompts --help' for usage." >&2
    exit 1
    ;;
  *)
    cmd_browse "${1:-}"
    ;;
esac
