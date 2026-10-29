#!/bin/zsh
set -e
PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
CANDIDATE_DIR="$PROJECT_DIR/../dist/指尖生命墨水版-20261025-r4"
exec "$CANDIDATE_DIR/打开双人联机.command"
