#!/bin/sh
# codegraph-helper (minimal) uninstaller.
set -e

INSTALL_DIR="${CODEGRAPH_HELPER_HOME:-$HOME/.codegraph-helper}"

for dir in /opt/homebrew/bin /usr/local/bin "$HOME/.npm-global/bin"; do
  rm -f "$dir/codegraph-helper" 2>/dev/null || true
done
echo "==> removed command entry"

CURRENT_HOOKS=$(git config --global core.hooksPath || true)
if [ "$CURRENT_HOOKS" = "$INSTALL_DIR/hooks" ]; then
  git config --global --unset core.hooksPath
  echo "==> removed global core.hooksPath"
else
  echo "==> global core.hooksPath is '$CURRENT_HOOKS' (not ours), left untouched"
fi

printf "Delete %s ? [y/N] " "$INSTALL_DIR"
read -r answer
case "$answer" in
  y|Y) rm -rf "$INSTALL_DIR" && echo "==> removed $INSTALL_DIR" ;;
  *) echo "==> kept $INSTALL_DIR" ;;
esac
echo "uninstalled"
