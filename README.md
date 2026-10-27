# codegraph-helper (macos-minimal)

English | [中文](README.zh-CN.md)

A tiny, dependency-free tool that keeps [CodeGraph](https://github.com/colbymchenry/codegraph) indexes fresh automatically: after every commit / branch switch / pull / rebase, it runs `codegraph sync` (or `codegraph init` for repos without an index) in the background.

This is the **minimal edition** — no HTTP server, no port, no token, no daemon, no Python. Everything is POSIX shell. For the full edition (server-based, with centralized queue, hot config and richer logs), see the `macos-full` branch.

## How it works

```
git commit / checkout / merge / rebase
        │
        ▼   global git hook (core.hooksPath → ~/.codegraph-helper/hooks)
        │   fires run.sh in the background, never blocks git
        ▼
~/.codegraph-helper/run.sh
        │  ① skip if repo is in the blacklist (or outside a non-empty whitelist)
        │  ② per-repo lock + pending marker (rapid consecutive triggers coalesce)
        │  ③ codegraph.db exists → sync, else auto init (configurable)
        ▼
codegraph sync / init
        │
        ▼
~/Library/Logs/codegraph-helper.log (kept for the current day only)
```

## Install / uninstall

```bash
./install.sh        # idempotent; re-run to upgrade, config is kept
./uninstall.sh
```

install.sh only copies files, writes a tiny shell config and sets git's global `core.hooksPath`. Nothing else.

## CLI

```bash
codegraph-helper roots list              # whitelist (empty = all git repos)
codegraph-helper roots add ~/myRepo      # limit to certain dirs
codegraph-helper roots remove ~/myRepo
codegraph-helper exclude list            # blacklist
codegraph-helper exclude add ~/temp      # dir and its subdirs are ignored
codegraph-helper exclude remove ~/temp
codegraph-helper sync <repo-path>        # trigger sync/init manually
codegraph-helper log                     # view the log
```

## Config

All files live in `~/.codegraph-helper/`:

| File | Purpose |
| --- | --- |
| `config` | shell syntax: `AUTO_INIT=1`, `SYNC_TIMEOUT=600`, `INIT_TIMEOUT=1800`, `CODEGRAPH_BIN=codegraph` |
| `roots` | whitelist, one absolute path per line; empty = all git repos |
| `excludes` | blacklist, one absolute path per line; subdirs included |

Changes take effect immediately (no daemon to restart).

## Log

`~/Library/Logs/codegraph-helper.log` — one line per trigger/result, kept for the current day only (auto-truncated when the date changes).

## Known limitations

- `git restore` and `git stash pop` have no git hooks, so they are not covered; use `codegraph-helper sync <repo>` if the index falls behind.
- No automated tests yet. macOS is the primary platform (uses `date -r`); Linux needs a small tweak.
- Per-repo locking uses a lock directory; a hard kill (SIGKILL) of `run.sh` mid-run leaves a stale lock that is auto-recovered on the next trigger.

## Difference from the full edition (`main` branch)

| | macos-minimal (this branch) | full (macos-full) |
| --- | --- | --- |
| Architecture | hooks → run.sh (shell) | hooks → HTTP server (Python) |
| Port / token / daemon | none | 127.0.0.1:9377 + token + launchd |
| Concurrency | lock dir + pending marker | in-process per-repo queue |
| Log retention | today only | unlimited |
| Config | shell file + two text lists | config.json |
| Dependencies | sh only | python3 |
