# codegraph-helper

English | [中文](README.zh-CN.md)

A local service that keeps [CodeGraph](https://github.com/colbymchenry/codegraph) indexes in sync automatically after git commits.

## Features

- Triggers index sync after `git commit`, `git checkout`, `git merge`, `git pull`, `git rebase`, `git commit --amend`
- Sync/init runs asynchronously, never blocks git operations
- Only affects repos initialized with `codegraph init`; with `auto_init` enabled, the first trigger runs `codegraph init` automatically
- Repeated triggers for the same repo coalesce into one follow-up run, avoiding concurrent writes to the same index

## How it works

```
git commit / switch / pull / rebase
        │
        ▼   global git hooks (core.hooksPath → ~/.codegraph-helper/hooks)
        │   HTTP notification, 3s timeout
        ▼
local service 127.0.0.1:9377 (launchd-managed, Python stdlib only)
        │   verify token → not blacklisted and within roots → .codegraph/ exists
        ▼
codegraph sync (async, 600s timeout per run)
```

The hook only sends a notification and returns immediately; the actual sync runs on the service, so commits are never slowed by indexing.

## Requirements

- macOS (launchd-managed service)
- Python 3.7+
- git 2.13+
- `codegraph` CLI installed

## Install

```bash
./install.sh
```

The installer:

1. copies the service script and hooks to `~/.codegraph-helper/`
2. generates the config with a random token
3. registers the launchd service `com.codegraph.helper` (`RunAtLoad` and `KeepAlive` both true)
4. points global `core.hooksPath` to `~/.codegraph-helper/hooks`
5. runs a `/health` check

Idempotent: re-run to upgrade; an existing `config.json` is kept.

## Config (optional — defaults just work)

All fields have defaults and are generated at install time (random token, `codegraph_bin` auto-detected as an absolute path). Edit `~/.codegraph-helper/config.json` only when needed, then restart the service:

```bash
launchctl kickstart -k gui/$(id -u)/com.codegraph.helper
```

| Field | Default | Description |
| --- | --- | --- |
| `port` | `9377` | listening port, bound to 127.0.0.1 |
| `token` | random at install | expected value of the `X-Codegraph-Token` header; empty rejects all `/hook` requests with 401 |
| `codegraph_bin` | detected at install | absolute path to the `codegraph` executable |
| `require_codegraph_index` | `true` | repos without a valid index (`.codegraph/codegraph.db`) are skipped or auto-initialized |
| `repo_roots` | `[]` | whitelist dirs; **empty = all git repos**, non-empty = only these dirs |
| `exclude_roots` | `[]` | blacklist dirs; repos inside them (including subdirs) are never triggered |
| `sync_timeout_seconds` | `600` | per-sync timeout; the process is killed on timeout |
| `auto_init` | `true` | repos without `.codegraph/` get `codegraph init` on first trigger (full build, slower) |
| `init_timeout_seconds` | `1800` | per-init timeout |

`repo_roots` / `exclude_roots` support `~` and symlinks (resolved before comparison). Changes take effect immediately — no restart needed.

## Directory management (CLI)

```bash
codegraph-helper roots list              # show whitelist (empty = all git repos)
codegraph-helper roots add ~/myRepo      # limit to certain dirs
codegraph-helper roots remove ~/myRepo

codegraph-helper exclude list            # show blacklist
codegraph-helper exclude add ~/temp      # exclude a dir (subdirs included)
codegraph-helper exclude remove ~/temp
```

- Empty whitelist = all git repos; the blacklist takes priority (sync and auto-init both respect it)
- The service reloads config on every request — changes apply immediately

## Triggers

| Operation | Syncs | Hook |
| --- | --- | --- |
| `git commit` (CLI or IDE) | yes | `post-commit` |
| `git switch` / `git checkout <branch>` | yes | `post-checkout` |
| `git checkout -- <file>` | yes | `post-checkout` |
| `git pull` / `git merge` | yes | `post-merge` |
| `git rebase` / `git commit --amend` | yes | `post-rewrite` |
| `git restore` / `git stash pop` | no | no git hook exists; run `codegraph sync` manually |

## HTTP API

### GET /health

Returns service status.

```json
{"status": "ok"}
```

### POST /hook

Triggers a sync for a repo. Requires the `X-Codegraph-Token` header; the repo path is passed as a query parameter.

```bash
curl -G -X POST \
  -H "X-Codegraph-Token: $(cat ~/.codegraph-helper/token)" \
  --data-urlencode "repo=/abs/path/to/repo" \
  http://127.0.0.1:9377/hook
```

Responses:

| HTTP | Meaning |
| --- | --- |
| 200 `started` | sync started in the background |
| 200 `queued` | a sync is already running; this trigger coalesced into a follow-up run |
| 200 `skipped` | repo has no valid index |
| 400 | missing path, non-absolute path, dir missing, or not a git repo |
| 401 | token missing or mismatched |
| 403 | repo outside `repo_roots` or in `exclude_roots` |

## Logs & troubleshooting

- Runtime log: `~/Library/Logs/codegraph-helper.log`
- Error log: `~/Library/Logs/codegraph-helper.err.log`

Troubleshooting order:

1. `launchctl list | grep codegraph` — is the service running?
2. Check the log for `skipped` or `401`
3. Confirm the repo is within `repo_roots` and has a valid `.codegraph/`

`codegraph_bin` must be an absolute path: launchd's `PATH` differs from the login shell, so a bare command name usually won't resolve.

## Known limitations

**Uncovered hooks stop working.** With a global `core.hooksPath`, git no longer reads each repo's `.git/hooks`. This tool ships 8 hooks to restore behavior:

- Notify: `post-commit`, `post-checkout`, `post-merge`, `post-rewrite` — notify the service, then chain to the repo-local hook
- Proxy only: `pre-commit`, `commit-msg`, `prepare-commit-msg`, `pre-push` — chain to the repo-local hook unchanged

Other hook names (e.g. `pre-rebase`, `reference-transaction`) no longer work. Verify before adopting tools like husky that rely on other hooks.

**Also:**

- `git restore` / `git stash pop` have no hook; the index may lag briefly
- No global concurrency limit across repos; bulk operations may start several `codegraph` processes at once
- When a sync is killed by timeout, the index may be left in an intermediate state; run `codegraph sync` again

## Environment variables

| Variable | Purpose |
| --- | --- |
| `CODEGRAPH_HELPER_CONFIG` | config file path used by the service, default `~/.codegraph-helper/config.json` |
| `CODEGRAPH_HELPER_HOME` | install dir used by `install.sh`, default `~/.codegraph-helper` |
| `CODEGRAPH_HELPER_PORT` | port written into the config at install time |
| `CODEGRAPH_HELPER_URL` | hook override for the service URL |
| `CODEGRAPH_HELPER_TOKEN` | hook override for the token |

## Uninstall

```bash
./uninstall.sh
```

The uninstaller:

1. stops and removes the launchd service
2. clears the global `core.hooksPath` only if it points to this tool
3. asks whether to delete the install dir (kept by default)
