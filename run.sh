#!/bin/sh
# codegraph-helper (minimal) core: runs `codegraph sync` / `codegraph init` for one repo.
# Called by git hooks in background. No server, no port, no token, no daemon, no Python.
# Usage: run.sh <repo-path> <trigger-source>
#
# - Per-repo lock dir + pending marker coalesce rapid consecutive triggers
# - Logs to ~/Library/Logs/codegraph-helper.log, kept for the current day only

HOME_DIR="${CODEGRAPH_HELPER_HOME:-$HOME/.codegraph-helper}"
LOG="${CODEGRAPH_HELPER_LOG:-$HOME/Library/Logs/codegraph-helper.log}"
[ -f "$HOME_DIR/config" ] && . "$HOME_DIR/config"

REPO=$1
SOURCE=${2:-manual}
CODEGRAPH_BIN=${CODEGRAPH_BIN:-codegraph}
AUTO_INIT=${AUTO_INIT:-1}
SYNC_TIMEOUT=${SYNC_TIMEOUT:-600}
INIT_TIMEOUT=${INIT_TIMEOUT:-1800}

[ -n "$REPO" ] && [ -d "$REPO" ] || exit 0
mkdir -p "$HOME_DIR/locks" "$(dirname "$LOG")"

log() {
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$SOURCE" "$*" >> "$LOG"
}

# Keep only today's log: truncate when the file is from an earlier day
TODAY=$(date '+%Y-%m-%d')
FILE_DAY=$(date -r "$LOG" '+%Y-%m-%d' 2>/dev/null)
[ "$FILE_DAY" != "$TODAY" ] && : > "$LOG"

# ---- directory gates: blacklist first, whitelist only when non-empty ----
in_list() { # $1=path $2=list-file
  [ -f "$2" ] || return 1
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case "$1" in
      "$d" | "$d"/*) return 0 ;;
    esac
  done < "$2"
  return 1
}

if in_list "$REPO" "$HOME_DIR/excludes"; then
  log "[$REPO] skipped: in excludes"
  exit 0
fi
if [ -s "$HOME_DIR/roots" ] && ! in_list "$REPO" "$HOME_DIR/roots"; then
  log "[$REPO] skipped: outside roots"
  exit 0
fi

# ---- per-repo lock: only one job at a time; later triggers mark pending ----
LOCK_ID=$(printf '%s' "$REPO" | tr '/' '_')
LOCK="$HOME_DIR/locks/$LOCK_ID.lock"
PENDING="$LOCK.pending"

if mkdir "$LOCK" 2>/dev/null; then
  echo $$ > "$LOCK/pid"
else
  LOCK_PID=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    : > "$PENDING"
    log "[$REPO] job already running, marked for one more run"
    exit 0
  fi
  rm -rf "$LOCK" # stale lock: previous owner is gone, take over
  if ! mkdir "$LOCK" 2>/dev/null; then
    : > "$PENDING"
    log "[$REPO] job already running, marked for one more run"
    exit 0
  fi
  echo $$ > "$LOCK/pid"
fi
trap 'rm -rf "$LOCK"' EXIT

command -v "$CODEGRAPH_BIN" >/dev/null 2>&1 || {
  log "[$REPO] $CODEGRAPH_BIN not found, aborting"
  exit 0
}

# ---- run an action with timeout; kill the child on timeout ----
run_action() { # $1=sync|init $2=timeout-seconds
  OUT=$(mktemp "/tmp/cgh-out.XXXXXX") || OUT=/dev/null
  START=$(date +%s)
  "$CODEGRAPH_BIN" "$1" >"$OUT" 2>&1 &
  BG_PID=$!
  ( sleep "$2"; kill -9 "$BG_PID" 2>/dev/null ) &
  TIMER=$!
  wait "$BG_PID"
  RC=$?
  kill "$TIMER" 2>/dev/null
  wait "$TIMER" 2>/dev/null
  ELAPSED=$(( $(date +%s) - START ))
  if [ "$RC" = "0" ]; then
    log "[$REPO] $1 done in ${ELAPSED}s"
  elif [ "$RC" = "137" ]; then
    log "[$REPO] $1 timed out after ${2}s, killed"
  else
    log "[$REPO] $1 failed (exit=$RC) after ${ELAPSED}s"
    tail -n 20 "$OUT" 2>/dev/null | while IFS= read -r line; do log "  | $line"; done
  fi
  rm -f "$OUT"
}

while :; do
  rm -f "$PENDING"
  if [ -f "$REPO/.codegraph/codegraph.db" ]; then
    run_action sync "$SYNC_TIMEOUT"
  elif [ "$AUTO_INIT" = "1" ]; then
    run_action init "$INIT_TIMEOUT"
  else
    log "[$REPO] skipped: no index and AUTO_INIT is off"
    break
  fi
  [ -f "$PENDING" ] || break
  log "[$REPO] pending trigger found, running once more"
done
exit 0
