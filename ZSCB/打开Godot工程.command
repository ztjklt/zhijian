#!/bin/zsh
set -eu
project_dir="${0:A:h}"
godot_bin=""
for candidate in "$HOME/Applications/Godot.app/Contents/MacOS/Godot" "/Applications/Godot.app/Contents/MacOS/Godot"; do
  if [[ -x "$candidate" ]]; then
    godot_bin="$candidate"
    break
  fi
done
if [[ -z "$godot_bin" ]]; then
  godot_bin="$(command -v godot || command -v Godot || true)"
fi
if [[ -z "$godot_bin" ]]; then
  print "未找到 Godot。请用 Godot 4.6 打开此目录的 project.godot。"
  exit 1
fi
if [[ "${1:-}" == "--play" ]]; then
  exec "$godot_bin" --path "$project_dir" -- --experience
fi
exec "$godot_bin" --editor --path "$project_dir" --scene "res://scenes/title_menu.tscn"
