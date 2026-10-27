#!/bin/sh
# codegraph-helper (minimal) CLI:
#   codegraph-helper roots list|add|remove [dir ...]
#   codegraph-helper exclude list|add|remove [dir ...]
#   codegraph-helper sync <repo-path>      # trigger one sync/init manually
#   codegraph-helper log [lines]           # view the log

HOME_DIR="${CODEGRAPH_HELPER_HOME:-$HOME/.codegraph-helper}"
LOG="${CODEGRAPH_HELPER_LOG:-$HOME/Library/Logs/codegraph-helper.log}"

usage() {
  cat <<EOF
usage: codegraph-helper <command> [args]

commands:
  roots list                 show whitelist (empty = all git repos)
  roots add <dir>...         add whitelist dirs
  roots remove <dir>...      remove whitelist dirs
  exclude list               show blacklist
  exclude add <dir>...       add blacklist dirs (subdirs included)
  exclude remove <dir>...    remove blacklist dirs
  sync <repo-path>           trigger sync/init manually
  log [lines]                view log (default 50 lines)
EOF
}

show_list() { # $1=file $2=title $3=empty-text
  echo "config file: $HOME_DIR/$1"
  echo "$2"
  if [ -f "$HOME_DIR/$1" ] && [ -s "$HOME_DIR/$1" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] && echo "  - $d"
    done < "$HOME_DIR/$1"
  else
    echo "  (empty: $3)"
  fi
}

edit_list() { # $1=file $2=add|remove then dirs...
  file="$HOME_DIR/$1"
  action="$2"
  shift 2
  mkdir -p "$HOME_DIR"
  touch "$file"
  for d in "$@"; do
    real=$(cd "$d" 2>/dev/null && pwd -P) || { echo "skip (dir missing): $d"; continue; }
    case "$action" in
      add)
        if grep -qxF "$real" "$file"; then
          echo "already present: $real"
        else
          echo "$real" >> "$file"
          echo "added: $real"
        fi
        ;;
      remove)
        if grep -qxF "$real" "$file"; then
          grep -vxF "$real" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
          echo "removed: $real"
        else
          echo "not in list: $real"
        fi
        ;;
    esac
  done
  echo "changes take effect immediately."
}

case "${1:-}" in
  roots)
    if [ -z "${2:-}" ] || [ "$2" = "list" ]; then
      show_list roots "whitelist:" "all git repos"
    else
      edit_list roots "$2" "${@:3}"
    fi
    ;;
  exclude)
    if [ -z "${2:-}" ] || [ "$2" = "list" ]; then
      show_list excludes "blacklist (dir and its subdirs):" "nothing excluded"
    else
      edit_list excludes "$2" "${@:3}"
    fi
    ;;
  sync)
    if [ -z "${2:-}" ]; then
      usage
      exit 1
    fi
    "$HOME_DIR/run.sh" "$2" manual
    tail -n 8 "$LOG" 2>/dev/null
    ;;
  log)
    tail -n "${2:-50}" "$LOG" 2>/dev/null
    ;;
  "" | help | -h | --help)
    usage
    ;;
  *)
    echo "unknown command: $1"
    usage
    exit 1
    ;;
esac
