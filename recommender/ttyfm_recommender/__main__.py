"""Entry point: python -m ttyfm_recommender. Configured from TTYFM_*
environment variables, like the server."""

from __future__ import annotations

import functools
import logging
import os
import sys

from . import models
from .client import Client
from .worker import Worker, analyze_file, preload


def env(key: str, default: str | None = None) -> str | None:
    v = os.environ.get("TTYFM_" + key)
    return v if v else default


def main() -> int:
    logging.basicConfig(
        level=(env("LOG_LEVEL", "info") or "info").upper(),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    password = env("ADMIN_PASSWORD")
    if not password:
        print("TTYFM_ADMIN_PASSWORD is required", file=sys.stderr)
        return 2
    from .analyze import analyzer_name

    models_dir = env("MODELS_DIR", "/models")
    if models.available(models_dir):
        logging.info("ML models found in %s: genre, mood and acousticness enabled", models_dir)
    else:
        logging.warning(
            "ML models missing from %s: genre, mood and acousticness are skipped "
            "(python -m ttyfm_recommender.models %s downloads them)",
            models_dir,
            models_dir,
        )
    preload()

    # Analysis is background work: leave the CPU to the server and the NAS.
    try:
        os.nice(int(env("ANALYSIS_NICE", "10") or 10))
    except OSError:
        pass
    client = Client(
        env("SERVER_URL", "http://server:4533"),
        env("ADMIN_USER", "admin"),
        password,
        os.path.join(env("STATE_DIR", "/state"), "token"),
    )
    Worker(
        client,
        env("MUSIC_DIR", "/music"),
        analyzer_name(models_dir),
        workers=int(env("ANALYSIS_WORKERS", "1")),
        timeout=float(env("ANALYSIS_TIMEOUT", "300")),
        poll=float(env("ANALYSIS_POLL", "60")),
        analyze_fn=functools.partial(analyze_file, models_dir=models_dir),
    ).run_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
