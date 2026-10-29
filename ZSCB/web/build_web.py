"""Export a separate, protocol-matched browser client from a fixed source."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests"))
from runtime_tools import resolve_godot
from prepare_client import prepare

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEFAULT_SOURCE = HERE.parent
DEFAULT_OUTPUT = ROOT / "dist/纸间网页候选-r22"
PROTECTED_OUTPUTS = {ROOT / ("dist/纸间网页版-20261025-" + release)
                     for release in ("flow", "perf", "latency", "ack", "r7")}
FONT_SHA256 = "2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b"


def prepare_project(args):
    source = args.source.resolve()
    output = args.output.resolve()
    if output in PROTECTED_OUTPUTS:
        raise ValueError("Refusing to replace a published rollback package; use a new output directory")
    if not (source / "project.godot").is_file():
        raise ValueError("The fixed source project is missing")
    if output == source or source in output.parents or output in source.parents:
        raise ValueError("Build output must be separate from the source")
    marker = output / ".zhijian-web-build"
    if output.exists() and any(output.iterdir()) and not marker.exists():
        raise ValueError("Refusing to replace a directory this builder did not create")
    output.mkdir(parents=True, exist_ok=True)
    marker.touch()
    project = output / "project"
    site = output / "site"
    for folder in (project, site):
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir()
    for name in ("scripts", "scenes", "animations", "assets"):
        shutil.copytree(source / name, project / name, ignore=shutil.ignore_patterns(".DS_Store", "__pycache__"))
    prepare(project)
    config = (source / "project.godot").read_text()
    config = re.sub(r'^config/name=.*$', 'config/name="指尖"', config, flags=re.M)
    config = re.sub(r'^config/features=.*$', 'config/features=PackedStringArray("4.6", "GL Compatibility")', config, flags=re.M)
    config = re.sub(r'^anti_aliasing/quality/msaa_2d=.*$', 'anti_aliasing/quality/msaa_2d=0', config, flags=re.M)
    config = config.replace("[rendering]", '[rendering]\n\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\ntextures/vram_compression/import_etc2_astc=true', 1)
    config += '\n[audio]\n\ngeneral/default_playback_type=1\n'
    bootstrap = 'WebBootstrap="*res://web_bootstrap.gd"\nWebMetrics="*res://web_metrics.gd"'
    if "[autoload]" in config:
        config = config.replace("[autoload]", "[autoload]\n\n" + bootstrap, 1)
    else:
        config += "\n[autoload]\n\n" + bootstrap + "\n"
    (project / "project.godot").write_text(config)
    font = HERE / "fonts/NotoSansCJKsc-Regular.otf"
    if hashlib.sha256(font.read_bytes()).hexdigest() != FONT_SHA256:
        raise ValueError("CJK font checksum mismatch")
    fonts = project / "assets/fonts"
    fonts.mkdir(exist_ok=True)
    shutil.copy2(font, fonts / font.name)
    shutil.copy2(HERE / "fonts/LICENSE.txt", fonts / "LICENSE.txt")
    # Browser builds cannot resolve installed OS fonts. Retain SystemFont's API
    # while giving every existing usage the same explicit bundled CJK fallback.
    for script in (project / "scripts").rglob("*.gd"):
        text = script.read_text()
        if "SystemFont.new()" in text:
            script.write_text(text.replace("SystemFont.new()", 'preload("res://web_font.gd").create()'))
    # Godot's WebGL2 renderer has no 2D MSAA. Avoid invoking the unsupported
    # option, and make the desktop-only setting explicit in this browser build.
    preferences = project / "scripts/preferences.gd"
    text = preferences.read_text()
    text = text.replace('bool(config.get_value("video", "antialias", true))', 'false')
    text = text.replace('Viewport.MSAA_4X if values.antialias else Viewport.MSAA_DISABLED', 'Viewport.MSAA_DISABLED')
    preferences.write_text(text)
    settings = project / "scripts/settings_panel.gd"
    text = settings.read_text().replace('antialias.text = "4× 抗锯齿"', 'antialias.text = "4× 抗锯齿（桌面客户端功能）"\n\tantialias.disabled = true')
    settings.write_text(text)
    session = project / "scripts/net/session.gd"
    text = session.read_text().replace(
        'hud=Label.new(); hud.mouse_filter=Control.MOUSE_FILTER_IGNORE',
        'hud=Label.new(); hud.mouse_filter=Control.MOUSE_FILTER_IGNORE\n\t\thud.add_theme_font_override("font", load("res://assets/fonts/NotoSansCJKsc-Regular.otf"))')
    session.write_text(text)
    (project / "web_font.gd").write_text('''extends RefCounted
static func create() -> SystemFont:
\tvar font := SystemFont.new()
\tfont.fallbacks = [preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")]
\treturn font
''')
    (project / "web_bootstrap.gd").write_text('''extends Node
func _enter_tree() -> void:
\tvar font := load("res://assets/fonts/NotoSansCJKsc-Regular.otf") as Font
\tThemeDB.fallback_font = font
\tThemeDB.get_default_theme().default_font = font
\tThemeDB.get_default_theme().set_font("font", "Label", font)
''')
    shutil.copy2(HERE / "shell.html", project / "web_shell.html")
    (project / "export_presets.cfg").write_text('''[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="*.json,*.txt"
exclude_filter=""
export_path="../site/index.html"

[preset.0.options]
custom_template/debug=""
custom_template/release=""
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=true
html/export_icon=false
html/custom_html_shell="res://web_shell.html"
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false
''')
    return project, site


def run(args):
    project, site = prepare_project(args)
    source, output = args.source.resolve(), args.output.resolve()
    godot = resolve_godot(getattr(args, "godot", None))
    log = output / "export.log"
    with log.open("w") as stream:
        for command in ([godot, "--headless", "--path", str(project), "--editor", "--import", "--quit"],
                        [godot, "--headless", "--path", str(project), "--export-release", "Web", str(site / "index.html")]):
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=240)
            stream.flush()
            if result.returncode:
                raise RuntimeError(f"Godot export failed; see {log}")
    errors = [line for line in log.read_text().splitlines() if "SCRIPT ERROR" in line or "ERROR:" in line]
    if errors:
        raise RuntimeError("\n".join(errors[:20]))
    for suffix in ("html", "js", "wasm", "pck"):
        if not (site / f"index.{suffix}").is_file():
            raise RuntimeError(f"Missing exported index.{suffix}")
    # Godot 4.6.3's tracked stream omitted reader rejection propagation;
    # an interrupted HTTP/2 body otherwise hangs arrayBuffer and skips retries.
    loader = site / "index.js"
    text = loader.read_text()
    old = "\t\t\t\tonloadprogress(reader, controller).then(function () {\n\t\t\t\t\tcontroller.close();\n\t\t\t\t});"
    new = "\t\t\t\tonloadprogress(reader, controller).then(function () {\n\t\t\t\t\tcontroller.close();\n\t\t\t\t}).catch(function (error) {\n\t\t\t\t\tcontroller.error(error);\n\t\t\t\t});"
    if text.count(old) != 1:
        raise RuntimeError("Exported preloader anchor changed; revalidate download recovery")
    loader.write_text(text.replace(old,new,1))
    shutil.copy2(HERE / "Dockerfile", site / "Dockerfile")
    shutil.copy2(HERE / "Caddyfile", site / "Caddyfile")
    shutil.copy2(HERE / "fonts/LICENSE.txt", site / "fonts-license.txt")
    files = {p.name: {"bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
             for p in sorted(site.iterdir()) if p.is_file()}
    protocol = int(re.search(r"const PROTOCOL := (\d+)", (source / "scripts/net/codec.gd").read_text()).group(1))
    (output / "WEB_RELEASE.json").write_text(json.dumps({"source": str(source.relative_to(ROOT)) if source.is_relative_to(ROOT) else str(source), "protocol": protocol,
        "renderer": "gl_compatibility", "threads": False, "files": files}, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"site": str(site), "files": len(files), "bytes": sum(v["bytes"] for v in files.values())}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--godot", default=None)
    run(parser.parse_args())
