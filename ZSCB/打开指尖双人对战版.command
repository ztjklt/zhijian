#!/bin/zsh
set -e
PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
DUEL_DIR="$PROJECT_DIR/../dist/指尖双人对战版-20261025-r3-black-red"
exec "$DUEL_DIR/打开双人联机.command"
