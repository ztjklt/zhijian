#!/bin/zsh
set -e
TASK_PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
TASK_RELEASE_DIR="$TASK_PROJECT_DIR/../dist/纸间联机验证版-20261024"
GAME_GODOT_BIN="${GODOT_BIN:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
"$GAME_GODOT_BIN" --headless --editor --path "$TASK_RELEASE_DIR" --import --quit
exec "$GAME_GODOT_BIN" --path "$TASK_RELEASE_DIR" res://scenes/network_lobby.tscn
