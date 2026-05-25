#!/usr/bin/env bash
# start-paper-repro-loop.sh
# Public entrypoint for checkpoint-aware paper reproduction loop setup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
exec "$SCRIPT_DIR/setup-paper-repro-loop.sh" "$@"
