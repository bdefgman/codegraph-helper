#!/bin/sh
# codegraph-helper (minimal) installer:
#   1) copy run.sh / cli.sh / hooks to ~/.codegraph-helper/
#   2) generate config (no token, no port)
#   3) set git global core.hooksPath
# No daemon, no launchd, no Python required.
set -e

INSTALL_DIR="${CODEGRAPH_HELPER_HOME:-$HOME/.codegraph-helper}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

command -v git >/dev/null 2>&1 || { echo "ERROR: git not found"; exit 1; }

echo "==> installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/hooks"
cp "$SCRIPT_DIR/run.sh" "$SCRIPT_DIR/cli.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR"/hooks/* "$INSTALL_DIR/hooks/"
chmod +x "$INSTALL_DIR/run.sh" "$INSTALL_DIR/cli.sh" "$INSTALL_DIR"/hooks/*

if [ -f "$INSTALL_DIR/config" ]; then
  echo "==> keeping existing config: $INSTALL_DIR/config"
else
  CODEGRAPH_BIN=$(command -v codegraph || echo codegraph)
  cat > "$INSTALL_DIR/config" <<EOF
# codegraph-helper (minimal) config
AUTO_INIT=1
SYNC_TIMEOUT=600
INIT_TIMEOUT=1800
CODEGRAPH_BIN=$CODEGRAPH_BIN
EOF
  echo "==> generated config: $INSTALL_DIR/config"
fi
touch "$INSTALL_DIR/roots" "$INSTALL_DIR/excludes"

echo "==> setting global core.hooksPath = $INSTALL_DIR/hooks"
git config --global core.hooksPath "$INSTALL_DIR/hooks"

CLI_LINK=""
for dir in /opt/homebrew/bin /usr/local/bin "$HOME/.npm-global/bin"; do
  if [ -d "$dir" ] && [ -w "$dir" ]; then
    CLI_LINK="$dir/codegraph-helper"
    break
  fi
done
if [ -n "$CLI_LINK" ]; then
  ln -sf "$INSTALL_DIR/cli.sh" "$CLI_LINK"
  echo "==> command entry: $CLI_LINK"
else
  echo "WARN: no writable dir on PATH; use: sh $INSTALL_DIR/cli.sh"
fi

echo ""
echo "installed. log: $HOME/Library/Logs/codegraph-helper.log (kept for today only)"
echo "uninstall: $SCRIPT_DIR/uninstall.sh"
