#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""codegraph-helper 本地服务。

git 提交之后，全局 hook 会回调这里，服务在对应仓库里跑一次 `codegraph sync`。
只监听回环地址，请求要带 token；不在 repo_roots 里、或者没 .codegraph/ 的仓库直接跳过。
"""

import argparse
import hmac
import json
import secrets
import logging
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

CONFIG_PATH = Path(
    os.environ.get("CODEGRAPH_HELPER_CONFIG", "~/.codegraph-helper/config.json")
).expanduser()

DEFAULT_CONFIG = {
    "port": 9377,
    "token": "",
    "codegraph_bin": "codegraph",
    "require_codegraph_index": True,
    "auto_init": False,
    "exclude_roots": [],
    "sync_timeout_seconds": 600,
    "init_timeout_seconds": 1800,
}


def load_config():
    cfg = dict(DEFAULT_CONFIG)
    cfg["repo_roots"] = []  # 空 = 作用于所有 git 仓库
    if CONFIG_PATH.exists():
        try:
            cfg.update(json.loads(CONFIG_PATH.read_text(encoding="utf-8")))
        except Exception as exc:
            logging.warning("配置读不出来，先用默认值: %s (%s)", CONFIG_PATH, exc)

    # 配置里写 ~/xxx 或者软链路径都很常见，这里统一展开成真实路径。
    # 不展开的话，后面拿 resolve 过的仓库路径去比，永远比不上，全部 403。
    roots = []
    for item in cfg.get("repo_roots") or []:
        try:
            roots.append(str(Path(str(item)).expanduser().resolve()))
        except OSError:
            continue
    cfg["repo_roots"] = roots
    return cfg


def under_any(path, roots):
    """path 是否等于 roots 里的某一项，或者位于它下面。"""
    for root in roots:
        try:
            if os.path.commonpath([str(path), str(root)]) == str(root):
                return True
        except ValueError:
            # 一个绝对一个相对的时候 commonpath 会抛这个
            continue
    return False


class RepoSyncManager:
    """同一个仓库的 sync 串行跑。跑的过程中又来的请求只记一笔，跑完补一次。"""

    def __init__(self, cfg):
        self.cfg = cfg
        self._lock = threading.Lock()
        self._running = {}  # repo -> 正在跑的线程
        self._pending = {}  # repo -> 排队补跑的动作（"sync"/"init"）

    def submit(self, repo, source="unknown", action="sync"):
        with self._lock:
            if repo in self._running:
                # init 读的是实时工作区，正在 init 时新触发直接合并，不再排队一次 init
                if action == "init":
                    logging.info("[%s] %s 触发，初始化进行中，本次触发直接合并", repo, source)
                    return "queued"
                self._pending[repo] = action
                logging.info("[%s] %s 触发，已有同步在跑，排队补跑", repo, source)
                return "queued"
            logging.info(
                "[%s] %s 触发，开始%s",
                repo,
                source,
                "初始化" if action == "init" else "同步",
            )
            thread = threading.Thread(
                target=self._work, args=(repo, action), name="codegraph-sync", daemon=True
            )
            self._running[repo] = thread
            thread.start()
            return "started"

    def _work(self, repo, action):
        while True:
            self._sync_once(repo, action)
            with self._lock:
                action = self._pending.pop(repo, None)
                if action is None:
                    self._running.pop(repo, None)
                    return

    def _sync_once(self, repo, action):
        if action == "init":
            cmd = [self.cfg.get("codegraph_bin", "codegraph"), "init"]
            timeout = self.cfg.get("init_timeout_seconds", 1800)
        else:
            cmd = [self.cfg.get("codegraph_bin", "codegraph"), "sync"]
            timeout = self.cfg.get("sync_timeout_seconds", 600)
        start = time.time()
        logging.info("[%s] 执行: %s", repo, " ".join(cmd))

        try:
            # start_new_session 让子进程自成一组。codegraph 可能是包装脚本、下面还挂着
            # 别的进程，超时只 kill 直接子进程会留下孤儿继续写索引，和补跑的 sync 打架。
            proc = subprocess.Popen(
                cmd,
                cwd=repo,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                start_new_session=True,
            )
        except FileNotFoundError:
            logging.error(
                "[%s] 找不到命令 %s，确认 config.json 里的 codegraph_bin", repo, cmd[0]
            )
            return

        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.communicate()
            logging.error(
                "[%s] 超过 %ss 没跑完，连同子进程一起杀掉了；索引可能停在中间状态",
                repo,
                timeout,
            )
            return

        elapsed = time.time() - start
        if proc.returncode == 0:
            logging.info(
                "[%s] %s成功，耗时 %.1fs",
                repo,
                "初始化" if action == "init" else "同步",
                elapsed,
            )
            return

        detail = ((out or "") + (err or "")).strip()
        logging.error(
            "[%s] 失败 exit=%s，%.1fs%s",
            repo,
            proc.returncode,
            elapsed,
            ("\n" + detail[-2000:]) if detail else "",
        )


def make_handler(manager, cfg):
    """把配置和 manager 闭包进去，返回一个 Handler 类。"""

    class Handler(BaseHTTPRequestHandler):
        server_version = "codegraph-helper/1.0"

        def log_message(self, fmt, *args):
            logging.info("%s %s", self.address_string(), fmt % args)

        def _reply(self, code, obj):
            body = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path in ("/", "/health"):
                self._reply(200, {"status": "ok"})
            else:
                self._reply(404, {"error": "not found"})

        def do_POST(self):
            if self.path.split("?", 1)[0] != "/hook":
                self._reply(404, {"error": "not found"})
                return

            # 每次请求实时读配置：roots / token 改动无需重启服务
            current_cfg = load_config()

            # 拿 bytes 比，避免 header 里混进非 ASCII 时 compare_digest 直接抛异常
            supplied = (self.headers.get("X-Codegraph-Token") or "").encode()
            expected = str(current_cfg.get("token") or "").encode()
            if not expected or not hmac.compare_digest(supplied, expected):
                self._reply(401, {"error": "invalid token"})
                return

            query = parse_qs(urlparse(self.path).query)
            repo = (query.get("repo") or [None])[0]
            source = (query.get("source") or [None])[0] or "unknown"
            err = self._validate_repo(repo, current_cfg)
            if err:
                self._reply(err[0], {"error": err[1]})
                return

            repo_real = str(Path(repo).resolve())
            if current_cfg.get("require_codegraph_index", True) and not Path(repo_real).joinpath(
                ".codegraph", "codegraph.db"
            ).exists():
                if current_cfg.get("auto_init", False):
                    logging.info(
                        "[%s] 没有可用的 codegraph 索引，自动初始化（%s 触发）", repo_real, source
                    )
                    self._reply(
                        200,
                        {"status": manager.submit(repo_real, source, "init"), "repo": repo_real},
                    )
                else:
                    logging.info("[%s] 跳过（%s 触发）：没有可用的 codegraph 索引", repo_real, source)
                    self._reply(
                        200,
                        {"status": "skipped", "reason": "no .codegraph index", "repo": repo_real},
                    )
                return

            self._reply(200, {"status": manager.submit(repo_real, source), "repo": repo_real})

        def _validate_repo(self, repo, cfg):
            if not repo or not isinstance(repo, str):
                return 400, "missing repo path"
            path = Path(repo)
            if not path.is_absolute():
                return 400, "repo path must be absolute"

            real = path.resolve()
            if not real.is_dir():
                return 400, "repo directory does not exist"
            if not real.joinpath(".git").exists():
                return 400, "not a git repository"

            # 黑名单优先：这些目录及其子目录一律不生效
            excludes = cfg.get("exclude_roots") or []
            if excludes and under_any(real, excludes):
                return 403, "repo is in exclude_roots"

            # 白名单为空 = 作用于所有 git 仓库；非空则仅白名单内生效
            roots = cfg.get("repo_roots") or []
            if roots and not under_any(real, roots):
                return 403, "repo is outside configured repo_roots"
            return None

    return Handler


def cmd_dirs(args, field, title, empty_text):
    """通用目录列表管理（list/add/remove），写入 config.json。"""
    cfg = load_config()
    dirs = list(cfg.get(field) or [])

    if args.action == "list":
        print("配置文件: %s" % CONFIG_PATH)
        print(title)
        for d in dirs:
            print("  - %s" % d)
        if not dirs:
            print("  （空：%s）" % empty_text)
        return

    targets = [str(Path(d).expanduser()) for d in args.dir]
    changed = False
    for target in targets:
        if args.action == "add":
            if not Path(target).is_dir():
                print("跳过（目录不存在）: %s" % target)
                continue
            real = str(Path(target).resolve())
            if real in dirs:
                print("已存在: %s" % real)
            else:
                dirs.append(real)
                changed = True
                print("已添加: %s" % real)
        elif args.action == "remove":
            real = str(Path(target).resolve())
            if real in dirs:
                dirs.remove(real)
                changed = True
                print("已移除: %s" % real)
            else:
                print("不在配置中: %s" % real)

    if changed:
        cfg[field] = dirs
        if not cfg.get("token"):
            cfg["token"] = secrets.token_hex(16)
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        CONFIG_PATH.write_text(
            json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print("已更新: %s（服务实时读取，无需重启）" % CONFIG_PATH)


def cmd_roots(args):
    cmd_dirs(args, "repo_roots", "生效目录（白名单）:", "作用于所有 git 仓库")


def cmd_exclude(args):
    cmd_dirs(args, "exclude_roots", "黑名单（这些目录及子目录下的仓库不生效）:", "无排除目录")


def main():
    parser = argparse.ArgumentParser(
        prog="codegraph-helper",
        description="codegraph-helper：commit 后自动同步 codegraph 索引的本地服务",
    )
    sub = parser.add_subparsers(dest="command")
    p_roots = sub.add_parser("roots", help="白名单：空 = 作用于所有 git 仓库，非空则仅这些目录下的仓库被触发")
    p_roots.add_argument("action", nargs="?", default="list", choices=["list", "add", "remove"])
    p_roots.add_argument("dir", nargs="*", help="要添加或移除的目录（可多个）")
    p_exclude = sub.add_parser("exclude", help="黑名单：这些目录及子目录下的仓库不会被触发")
    p_exclude.add_argument("action", nargs="?", default="list", choices=["list", "add", "remove"])
    p_exclude.add_argument("dir", nargs="*", help="要添加或移除的目录（可多个）")
    args = parser.parse_args()

    if args.command == "roots":
        cmd_roots(args)
        return
    if args.command == "exclude":
        cmd_exclude(args)
        return

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        stream=sys.stdout,
    )
    cfg = load_config()

    if not cfg.get("token"):
        logging.warning("token 是空的，/hook 的请求会全部被拒")
    if not cfg.get("repo_roots"):
        logging.info("repo_roots 为空：作用于所有 git 仓库")
    if not shutil.which(cfg.get("codegraph_bin", "codegraph")):
        logging.warning("PATH 里找不到 '%s'，sync 会失败", cfg.get("codegraph_bin", "codegraph"))

    manager = RepoSyncManager(cfg)
    try:
        server = ThreadingHTTPServer(
            ("127.0.0.1", int(cfg.get("port", 9377))), make_handler(manager, cfg)
        )
    except OSError as exc:
        logging.error("起不来，端口大概被占了: %s", exc)
        raise SystemExit(1)

    server.daemon_threads = True
    logging.info("监听 http://127.0.0.1:%s", server.server_address[1])
    logging.info(
        "repo_roots=%s exclude_roots=%s require_codegraph_index=%s",
        cfg.get("repo_roots"), cfg.get("exclude_roots"), cfg.get("require_codegraph_index"),
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
