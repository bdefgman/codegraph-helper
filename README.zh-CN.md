# codegraph-helper（macos-minimal 极简版）

[English](README.md) | 中文

一个零依赖的小工具：在 commit / 切分支 / pull / rebase 之后，自动在后台执行 `codegraph sync`（没有索引的仓库自动 `codegraph init`），让 [CodeGraph](https://github.com/colbymchenry/codegraph) 索引始终跟上代码。

本分支是**极简版**——没有 HTTP 服务、没有端口、没有 token、没有常驻进程、没有 Python，全部是 POSIX shell。完整版（带服务、集中排队、热更新配置）见 `macos-full` 分支。

## 工作原理

```
git commit / checkout / merge / rebase
        │
        ▼   全局 git hook（core.hooksPath → ~/.codegraph-helper/hooks）
        │   后台触发 run.sh，绝不阻塞 git
        ▼
~/.codegraph-helper/run.sh
        │  ① 仓库在黑名单（或非空白名单之外）→ 跳过
        │  ② 同仓库锁 + 补跑标记（连续触发自动合并）
        │  ③ 有 codegraph.db → sync，否则自动 init（可配置）
        ▼
codegraph sync / init
        │
        ▼
~/Library/Logs/codegraph-helper.log（只保留当天）
```

## 安装 / 卸载

```bash
./install.sh        # 幂等；升级时重跑即可，配置保留
./uninstall.sh
```

install.sh 只做三件事：拷贝文件、生成一份极简 shell 配置、设置 git 全局 `core.hooksPath`。

## 命令

```bash
codegraph-helper roots list              # 白名单（空 = 作用于所有 git 仓库）
codegraph-helper roots add ~/myRepo      # 只让某些目录生效
codegraph-helper roots remove ~/myRepo
codegraph-helper exclude list            # 黑名单
codegraph-helper exclude add ~/temp      # 该目录及其子目录不生效
codegraph-helper exclude remove ~/temp
codegraph-helper sync <仓库路径>          # 手动触发一次同步/初始化
codegraph-helper log                     # 查看日志
```

## 配置

全部在 `~/.codegraph-helper/` 下：

| 文件 | 用途 |
| --- | --- |
| `config` | shell 语法：`AUTO_INIT=1`、`SYNC_TIMEOUT=600`、`INIT_TIMEOUT=1800`、`CODEGRAPH_BIN=codegraph` |
| `roots` | 白名单，每行一个绝对路径；**为空 = 作用于所有 git 仓库** |
| `excludes` | 黑名单，每行一个绝对路径，含子目录 |

改动即时生效（无服务无需重启）。

## 日志

`~/Library/Logs/codegraph-helper.log`——每次触发/结果各一条，**只保留当天**（日期变化时自动清空）。

## 已知限制

- `git restore`、`git stash pop` 没有 git hook，无法覆盖；索引落后时可用 `codegraph-helper sync <仓库>` 手动补。
- 暂无自动化测试。macOS 为主平台（日志日期判断用了 `date -r`），Linux 需微调。
- 同仓库并发靠锁目录实现；`run.sh` 被强杀（SIGKILL）留下的陈旧锁会在下次触发时自动接管清理。

## 与完整版（`macos-full` 分支）的差异

| | macos-minimal（本分支） | 完整版（macos-full） |
| --- | --- | --- |
| 架构 | hook → run.sh（纯 shell） | hook → HTTP 服务（Python） |
| 端口 / token / 常驻 | 无 | 127.0.0.1:9377 + token + launchd |
| 并发控制 | 锁目录 + 补跑标记 | 服务内按仓库排队 |
| 日志保留 | 只留当天 | 不限 |
| 配置 | shell 文件 + 两个文本列表 | config.json |
| 依赖 | 仅 sh | python3 |
