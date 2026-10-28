# codegraph-helper

English | [中文](README.zh-CN.md)

![macOS](https://img.shields.io/badge/platform-macOS-lightgrey) ![Shell](https://img.shields.io/badge/shell-POSIX-green) ![Python](https://img.shields.io/badge/Python-3.7+-blue)

> Commit and forget — your [CodeGraph](https://github.com/colbymchenry/codegraph) index stays fresh automatically, in the background, without ever blocking a single `git` command.

**codegraph-helper** is a tiny local tool that keeps your CodeGraph indexes perfectly in sync with your code.

## Why

AI coding agents rely on CodeGraph indexes to understand your codebase — but an index only helps while it is **fresh**. Running `codegraph sync` by hand after every change is the kind of thing everyone forgets.

codegraph-helper watches your git activity and maintains every index for you:

- **Commit → synced.** Every `commit`, branch switch, `pull` and `rebase` triggers a background sync: incremental `sync` when an index exists, automatic `init` when a repo has none yet.
- **Never blocks git.** Hooks return in milliseconds; all the work happens asynchronously.
- **Sensible scoping.** Applies to all your repos by default; exclude any directory with one command.
- **Clear logs.** Every trigger and result is logged, together with its trigger source (commit / checkout / merge / rebase).
- **Your hooks stay intact.** Repo-local hooks are chained through, never overridden.

## Quick start

```bash
git clone https://github.com/bdefgman/codegraph-helper.git
cd codegraph-helper
git checkout macos-full      # full edition; or: macos-minimal
./install.sh
```

Done. The next time you commit (or switch branches, pull, rebase), the index updates itself in the background. Watch it live:

```bash
tail -f ~/Library/Logs/codegraph-helper.log
```

## Editions

| Branch | Edition | Stack | Best for |
| --- | --- | --- | --- |
| [`macos-full`](../../tree/macos-full) | Full edition — HTTP service, centralized queue, hot-reload config, rich logs | Python + launchd | many repos, centralized logs |
| [`macos-minimal`](../../tree/macos-minimal) | Minimal edition — no server, no port, no token, no daemon | Pure POSIX shell | single-user, minimal footprint |

Each branch ships its own README with complete install instructions and configuration details.
