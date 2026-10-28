# codegraph-helper

A tiny local tool that keeps [CodeGraph](https://github.com/colbymchenry/codegraph) indexes fresh automatically — after every commit / branch switch / pull / rebase, it runs `codegraph sync` (or `codegraph init` for repos without an index) in the background, without ever blocking git.

**English** · [中文说明](./README.zh-CN.md)

## Branches

| Branch | Edition | Stack |
| --- | --- | --- |
| [`macos-full`](../../tree/macos-full) | Full edition: HTTP service, centralized queue, hot config, rich logs | Python + launchd (macOS only) |
| [`macos-minimal`](../../tree/macos-minimal) | Minimal edition: no server, no port, no token, no daemon | Pure POSIX shell |

Each branch has its own README with install instructions and details.
