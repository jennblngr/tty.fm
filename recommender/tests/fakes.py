"""Module-level analysis stand-ins: the worker pickles them into its child."""

import os
import signal
import time


def ok(path):
    return {"bpm": 120.0, "key": "A", "scale": "minor", "path_seen": path}


def fails(path):
    raise ValueError("cannot decode")


def crashes(path):
    os.kill(os.getpid(), signal.SIGKILL)


def hangs(path):
    time.sleep(60)
