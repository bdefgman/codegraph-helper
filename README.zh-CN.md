# codegraph-helper

[English](README.md) | 中文

![macOS](https://img.shields.io/badge/platform-macOS-lightgrey) ![Shell](https://img.shields.io/badge/shell-POSIX-green) ![Python](https://img.shields.io/badge/Python-3.7+-blue)

> 提交即忘——你的 [CodeGraph](https://github.com/colbymchenry/codegraph) 索引在后台自动保持最新，绝不阻塞任何 git 命令。

**codegraph-helper** 是一个轻量的本地工具，让你的 CodeGraph 索引始终与代码同步。

## 为什么需要它

AI 编程助手依赖 CodeGraph 索引来理解代码库——但索引只有**新鲜**才有价值。每次改动后手动执行 `codegraph sync`，是所有人都会忘记的事。

codegraph-helper 监听你的 git 活动，替你维护所有索引：

- **提交即同步**：commit、切分支、pull、rebase 都会触发后台同步——有索引走增量 `sync`，没有索引自动 `init`
- **绝不阻塞 git**：hook 毫秒级返回，全部工作在后台异步执行
- **范围可控**：默认覆盖所有仓库，一条命令即可排除任意目录
- **日志清晰**：每次触发与结果都留痕，并标注触发来源（commit / checkout / merge / rebase）
- **不破坏你的 hooks**：仓库本地 hooks 原样转调，不会失效

## 快速开始

```bash
git clone https://github.com/bdefgman/codegraph-helper.git
cd codegraph-helper
git checkout macos-full      # 完整版；或：macos-minimal 极简版
./install.sh
```

搞定。下次 commit（或切分支、pull、rebase）时，索引会在后台自动更新。实时查看：

```bash
tail -f ~/Library/Logs/codegraph-helper.log
```

## 版本选择

| 分支 | 版本 | 技术栈 | 适用场景 |
| --- | --- | --- | --- |
| [`macos-full`](../../tree/macos-full) | 完整版：HTTP 服务、集中排队、热更新配置、丰富日志 | Python + launchd | 多仓库、想要集中日志 |
| [`macos-minimal`](../../tree/macos-minimal) | 极简版：无服务、无端口、无 token、无常驻进程 | 纯 POSIX shell | 单人使用、追求最小足迹 |

各分支自带完整 README（含安装说明与配置细节）。
