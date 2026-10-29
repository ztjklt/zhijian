#!/bin/zsh
set -e
PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
exec python3 "$PROJECT_DIR/server/start_local.py"
