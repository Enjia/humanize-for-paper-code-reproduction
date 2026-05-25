#!/usr/bin/env python3
"""Run a command after restoring default signal dispositions.

Parallel bash test runners launch suites as background jobs; non-interactive
bash starts those jobs with SIGINT ignored. A child bash cannot reliably trap a
signal that was ignored on entry, so signal-handling tests must exec from a
process that resets SIGINT/SIGTERM first.
"""

import os
import signal
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: run-with-default-signals.py <command> [args...]", file=sys.stderr)
        return 2

    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    os.execvp(sys.argv[1], sys.argv[1:])
    return 127


if __name__ == "__main__":
    raise SystemExit(main())
