#!/usr/bin/env bash
# godot-env.sh — resolve Godot binary, project path, and log dir per-OS.
#
# Source this from command scripts:  . "$(dirname "$0")/godot-env.sh"
# or, from a known repo:             source .claude/scripts/godot-env.sh
#
# Exports: GODOT_BIN, GODOT_PROJECT, GODOT_PROC_PAT, LOG_DIR, GODOT_LOG
# Honors pre-set GODOT_BIN / GODOT_PROJECT env overrides if they are valid.

# --- Project path: repo root is two levels up from this script (.claude/scripts) ---
if [ -z "${GODOT_PROJECT:-}" ] || [ ! -f "${GODOT_PROJECT}/project.godot" ]; then
  _gd_self="${BASH_SOURCE[0]:-$0}"
  _gd_dir="$(cd "$(dirname "$_gd_self")" >/dev/null 2>&1 && pwd)"
  GODOT_PROJECT="$(cd "$_gd_dir/../.." >/dev/null 2>&1 && pwd)"
fi

# --- Godot binary: honor override, then PATH, then per-OS well-known locations ---
if [ -n "${GODOT_BIN:-}" ] && [ -x "${GODOT_BIN}" ]; then
  :
elif command -v godot >/dev/null 2>&1; then
  GODOT_BIN="$(command -v godot)"
elif command -v godot4 >/dev/null 2>&1; then
  GODOT_BIN="$(command -v godot4)"
else
  case "$(uname -s)" in
    Darwin)
      for _c in \
        "/Applications/Godot.app/Contents/MacOS/Godot" \
        "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
        [ -x "$_c" ] && { GODOT_BIN="$_c"; break; }
      done
      ;;
    *)
      for _c in /usr/local/bin/godot /usr/bin/godot /opt/godot/godot; do
        [ -x "$_c" ] && { GODOT_BIN="$_c"; break; }
      done
      ;;
  esac
fi

if [ -z "${GODOT_BIN:-}" ]; then
  echo "godot-env: could not locate a Godot binary (set GODOT_BIN to override)" >&2
fi

# --- Process-match pattern for pkill: match this project's running instance ---
GODOT_PROC_PAT="Godot.*$(basename "$GODOT_PROJECT")"

# --- Log directory: prefer /var/tumu/logs, fall back to /tmp ---
LOG_DIR="/var/tumu/logs"
if [ ! -d "$LOG_DIR" ]; then
  mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
fi
GODOT_LOG="$LOG_DIR/godot_debug.log"

export GODOT_BIN GODOT_PROJECT GODOT_PROC_PAT LOG_DIR GODOT_LOG
