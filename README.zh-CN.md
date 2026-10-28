# codegraph-helper

一个本地小工具：commit / 切分支 / pull / rebase 后自动在后台执行 `codegraph sync`（无索引的仓库自动 `codegraph init`），让 [CodeGraph](https://github.com/colbymchenry/codegraph) 索引始终跟上代码，绝不阻塞 git。

[English](./README.md) · **中文**

## 分支

| 分支 | 版本 | 技术栈 |
| --- | --- | --- |
| [`macos-full`](../../tree/macos-full) | 完整版：HTTP 服务、集中排队、热更新配置、丰富日志 | Python + launchd（仅 macOS） |
| [`macos-minimal`](../../tree/macos-minimal) | 极简版：无服务、无端口、无 token、无常驻进程 | 纯 POSIX shell |

两个分支各有独立的 README（含安装说明与细节）。
