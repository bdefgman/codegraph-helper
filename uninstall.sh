#!/bin/sh
# codegraph-helper 卸载脚本：
#   1) 停止并移除 launchd 服务
#   2) 移除 git 全局 core.hooksPath（仅当它指向本工具）
#   3) 可选删除安装目录 ~/.codegraph-helper/
set -e

INSTALL_DIR="${CODEGRAPH_HELPER_HOME:-$HOME/.codegraph-helper}"
PLIST="$HOME/Library/LaunchAgents/com.codegraph.helper.plist"

launchctl bootout "gui/$(id -u)/com.codegraph.helper" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "==> 已停止并移除 launchd 服务"

CURRENT_HOOKS=$(git config --global core.hooksPath || true)
if [ "$CURRENT_HOOKS" = "$INSTALL_DIR/hooks" ]; then
  git config --global --unset core.hooksPath
  echo "==> 已移除全局 core.hooksPath"
else
  echo "==> 全局 core.hooksPath 为 '$CURRENT_HOOKS'（非本工具设置），保持不变"
fi

printf "是否删除安装目录 %s ? [y/N] " "$INSTALL_DIR"
read -r answer
case "$answer" in
  y|Y) rm -rf "$INSTALL_DIR" && echo "==> 已删除 $INSTALL_DIR" ;;
  *) echo "==> 保留 $INSTALL_DIR" ;;
esac
echo "卸载完成"
