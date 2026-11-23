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
  print "未找到 Godot。请安装 Godot 4.6.3 后重试。"
  exit 1
fi
if [[ "${1:-}" == "--play" ]]; then
  shift
  "$godot_bin" --headless --editor --path "$project_dir" --import --quit --quiet
  exec "$godot_bin" --path "$project_dir" "$@"
fi
exec "$godot_bin" --editor --path "$project_dir" --scene "res://scenes/title_menu.tscn"
