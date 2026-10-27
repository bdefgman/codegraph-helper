# codegraph-helper

在 `git commit` 之后自动同步 codegraph 索引的本地服务。

## 功能

- 在 `git commit`、`git checkout`、`git merge`、`git pull`、`git rebase`、`git commit --amend` 之后触发索引同步
- 同步异步执行，不阻塞 git 操作
- 仅对已执行 `codegraph init` 的仓库生效，不会自动创建索引
- 同一仓库的重复触发合并为一次补跑，避免并发写同一份索引

## 工作原理

```
git commit / switch / pull / rebase
        │
        ▼  全局 git hook（core.hooksPath → ~/.codegraph-helper/hooks）
        │  HTTP 通知，3 秒超时
        ▼
本地服务 127.0.0.1:9377（launchd 托管，Python 标准库实现）
        │  校验 token → 校验仓库位于 repo_roots → 校验 .codegraph/ 存在
        ▼
codegraph sync（异步执行，单次超时 600 秒）
```

git hook 只负责发送通知并立即返回，实际同步由服务端执行，因此 `git commit` 的耗时不受索引影响。

## 环境要求

- macOS（使用 launchd 托管服务）
- Python 3.7 及以上
- git 2.13 及以上
- 已安装 `codegraph` 命令行工具

## 安装

```bash
./install.sh
```

安装脚本执行以下操作：

1. 将服务脚本与 hooks 复制到 `~/.codegraph-helper/`
2. 生成配置文件，token 随机生成
3. 注册 launchd 服务 `com.codegraph.helper`，`RunAtLoad` 与 `KeepAlive` 均为 true
4. 设置全局 `core.hooksPath` 指向 `~/.codegraph-helper/hooks`
5. 调用 `/health` 完成健康检查

脚本可重复执行，已存在的 `config.json` 不会被覆盖。

## 配置（可选，正常使用无需修改）

所有字段均有默认值，安装脚本自动生成（token 随机生成、`codegraph_bin` 自动探测为绝对路径），正常使用无需修改。只有需要调整时才编辑 `~/.codegraph-helper/config.json`，修改后需重启服务：

```bash
launchctl kickstart -k gui/$(id -u)/com.codegraph.helper
```

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `port` | `9377` | 监听端口，固定绑定 127.0.0.1 |
| `token` | 安装时随机生成 | 请求头 `X-Codegraph-Token` 的期望值；留空时所有 `/hook` 请求返回 401 |
| `codegraph_bin` | 安装时探测 | `codegraph` 可执行文件的绝对路径 |
| `require_codegraph_index` | `true` | 为 `true` 时，缺少 `.codegraph/` 的仓库直接跳过 |
| `repo_roots` | `[~/IdeaProjects]` | 允许同步的目录列表；为空数组时不放行任何仓库 |
| `sync_timeout_seconds` | `600` | 单次同步超时，超时后连同子进程一并终止 |

`repo_roots` 支持 `~` 与符号链接，服务启动时会展开为真实路径后比较。

## 触发范围

| 操作 | 是否同步 | 对应 hook |
| --- | --- | --- |
| `git commit`（命令行或 IDE） | 是 | `post-commit` |
| `git switch` / `git checkout <branch>` | 是 | `post-checkout` |
| `git checkout -- <file>` | 是 | `post-checkout` |
| `git pull` / `git merge` | 是 | `post-merge` |
| `git rebase` / `git commit --amend` | 是 | `post-rewrite` |
| `git restore` / `git stash pop` | 否 | git 未提供对应 hook，需手动执行 `codegraph sync` |

## 接口

### GET /health

返回服务状态。

```json
{"status": "ok"}
```

### POST /hook

触发指定仓库的索引同步。需携带 `X-Codegraph-Token` 请求头，仓库路径通过查询参数传入。

```bash
curl -G -X POST \
  -H "X-Codegraph-Token: $(cat ~/.codegraph-helper/token)" \
  --data-urlencode "repo=/abs/path/to/repo" \
  http://127.0.0.1:9377/hook
```

响应状态：

| HTTP | 含义 |
| --- | --- |
| 200 `started` | 已在后台启动同步 |
| 200 `queued` | 该仓库正在同步，本次请求已合并为补跑 |
| 200 `skipped` | 仓库缺少 `.codegraph/`，跳过 |
| 400 | 路径缺失、非绝对路径、目录不存在或不是 git 仓库 |
| 401 | token 缺失或不匹配 |
| 403 | 仓库不在 `repo_roots` 范围内，或 `repo_roots` 为空 |

## 日志与故障排查

- 运行日志：`~/Library/Logs/codegraph-helper.log`
- 异常栈：`~/Library/Logs/codegraph-helper.err.log`

排查顺序：

1. `launchctl list | grep codegraph` 确认服务进程存在
2. 检查日志中是否出现「跳过」或 `401`
3. 确认目标仓库位于 `repo_roots` 内，且已存在 `.codegraph/`

`codegraph_bin` 必须配置为绝对路径。launchd 的 `PATH` 与登录 shell 不同，仅写命令名通常无法解析。

## 已知限制

**未覆盖的 hook 会失效。** 设置全局 `core.hooksPath` 后，git 不再读取各仓库的 `.git/hooks`。本工具提供 8 个 hook 还原原有行为：

- 通知类：`post-commit`、`post-checkout`、`post-merge`、`post-rewrite`，先通知服务再转调仓库本地同名 hook
- 纯代理：`pre-commit`、`commit-msg`、`prepare-commit-msg`、`pre-push`，仅转调，行为与原来一致

其余 hook 名称（如 `pre-rebase`、`reference-transaction`）将不再生效。使用 husky 等依赖其他 hook 的工具时需提前确认。

**其他：**

- `git restore`、`git stash pop` 无对应 hook，索引会短暂落后
- 跨仓库同步无全局并发上限，批量操作时可能同时启动多个 `codegraph` 进程
- 同步被超时终止时，索引文件可能处于中间状态，需重新执行 `codegraph sync`

## 环境变量

| 变量 | 作用 |
| --- | --- |
| `CODEGRAPH_HELPER_CONFIG` | 服务读取的配置文件路径，默认 `~/.codegraph-helper/config.json` |
| `CODEGRAPH_HELPER_HOME` | `install.sh` 的安装目录，默认 `~/.codegraph-helper` |
| `CODEGRAPH_HELPER_PORT` | `install.sh` 生成配置时写入的端口 |
| `CODEGRAPH_HELPER_URL` | hook 覆盖服务地址 |
| `CODEGRAPH_HELPER_TOKEN` | hook 覆盖 token |

## 卸载

```bash
./uninstall.sh
```

卸载脚本执行以下操作：

1. 停止并移除 launchd 服务
2. 全局 `core.hooksPath` 指向本工具时清除，指向其他位置时保持不变
3. 询问是否删除安装目录，默认保留
