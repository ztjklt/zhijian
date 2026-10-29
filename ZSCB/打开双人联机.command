#!/bin/zsh
set -e
PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
GAME_GODOT_BIN="${GODOT_BIN:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
exec "$GAME_GODOT_BIN" --path "$PROJECT_DIR" res://scenes/network_lobby.tscn
