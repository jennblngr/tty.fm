"""The analysis loop: pull the queue from the server, analyse each file in a
child process (a crash or a hang on one file must not stop the worker) and
report the result."""

from __future__ import annotations

import logging
import multiprocessing as mp
import os
import time
from concurrent.futures import ThreadPoolExecutor

from .client import Client

log = logging.getLogger("recommender")

# Each file is analysed in a fresh child of a fork server: forking the worker
# itself is unsafe once its threads run, and the fork server can import
# Essentia once (see preload) instead of on every file.
_ctx = mp.get_context("forkserver")


def preload() -> None:
    _ctx.set_forkserver_preload(["ttyfm_recommender.analyze", "essentia.standard"])


def resolve(music_dir: str, rel: str) -> str:
    """Path of a track inside the music folder; refuses to leave it."""
    root = os.path.realpath(music_dir)
    path = os.path.realpath(os.path.join(root, rel))
    if os.path.commonpath([root, path]) != root:
        raise ValueError(f"path outside the music folder: {rel!r}")
    return path


def _default_analyze(path: str) -> dict:
    from .analyze import analyze

    return analyze(path)


def _run(fn, path: str, conn) -> None:
    try:
        conn.send(("ok", fn(path)))
    except Exception as e:  # reported to the server as the track's error
        conn.send(("error", f"{type(e).__name__}: {e}"))
    finally:
        conn.close()


def analyze_isolated(path: str, timeout: float, analyze_fn=None) -> dict:
    """Runs the analysis in a child process. Returns the report fields, or
    {"error": ...} if the file could not be analysed. analyze_fn must be a
    module-level function (it is pickled)."""
    parent, child = _ctx.Pipe(duplex=False)
    proc = _ctx.Process(target=_run, args=(analyze_fn or _default_analyze, path, child), daemon=True)
    proc.start()
    child.close()
    try:
        if parent.poll(timeout):
            status, value = parent.recv()
            return value if status == "ok" else {"error": value}
        return {"error": f"timeout after {timeout:.0f} s"}
    except EOFError:  # the child died without answering (segfault, OOM kill)
        return {"error": "analyser crashed"}
    finally:
        parent.close()
        proc.join(1)
        if proc.is_alive():
            proc.kill()
            proc.join()


class Worker:
    def __init__(
        self,
        client: Client,
        music_dir: str,
        analyzer: str,
        workers: int = 1,
        timeout: float = 300,
        poll: float = 60,
        analyze_fn=None,
    ):
        self.client = client
        self.music_dir = music_dir
        self.analyzer = analyzer
        self.workers = max(1, workers)
        self.timeout = timeout
        self.poll = poll
        self.analyze_fn = analyze_fn

    def process(self, job: dict) -> dict:
        start = time.monotonic()
        try:
            path = resolve(self.music_dir, job["path"])
            result = analyze_isolated(path, self.timeout, self.analyze_fn)
        except ValueError as e:
            result = {"error": str(e)}
        report = {"file_mtime": job["file_mtime"], "analyzer": self.analyzer, **result}
        self.client.report(job["id"], report)
        if "error" in result:
            log.warning("analysis failed: %s: %s", job["path"], result["error"])
        else:
            log.info(
                "analysed %s in %.1f s: %s bpm, %s %s",
                job["path"],
                time.monotonic() - start,
                result.get("bpm", "?"),
                result.get("key", "?"),
                result.get("scale", ""),
            )
        return report

    def run_once(self) -> int:
        """Analyses one batch of the queue; returns how many tracks it handled."""
        jobs = self.client.queue(limit=max(20, self.workers * 4))
        if not jobs:
            return 0
        with ThreadPoolExecutor(self.workers) as pool:
            list(pool.map(self.process, jobs))
        return len(jobs)

    def run_forever(self) -> None:
        backoff = 5.0
        idle = False
        while True:
            try:
                n = self.run_once()
                backoff = 5.0
            except Exception as e:  # server down, network...
                log.warning("server unreachable (%s); retrying in %.0f s", e, backoff)
                time.sleep(backoff)
                backoff = min(backoff * 2, 300)
                continue
            if n == 0:
                if not idle:
                    log.info("queue empty; checking again every %.0f s", self.poll)
                idle = True
                time.sleep(self.poll)
            else:
                idle = False
