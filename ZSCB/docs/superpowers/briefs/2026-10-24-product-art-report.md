# Product artwork delivery — 2026-10-24

Completed all 22 individually generated black-ink transparent PNGs under `assets/medieval/expansion/`. Every final PNG is an unchanged builtin `image_gen` output, duplicated identically in `source/`; `generation_manifest.json` preserves the full individual prompts, original generated-image paths, output hints, tool and purpose. `validation.json` records actual pixel sizes, alpha ranges and SHA256 values. No API fallback, program-drawn stand-ins, outside runtime edits, commits or remote actions.

`manifest.json` contains all requested stable IDs, metre sizes, health/category, resource paths and final calibrated walk edges. After paper compositing and actual Godot captures, 14 standable assets were traced from actual image pixel coordinates to the exact runtime source rectangle (alpha > .05, stride 3, padding 3). `walk_edge_calibration.json` retains those source rectangles and pixel picks. In particular, the tavern's roof peak is on the right, the forge has an asymmetric roof, and the windmill's cap, balcony and windows are standable; its rotor sails are not. The original tentative geometry marker was removed.

Validation command, run twice with the final metadata on the second run:

```sh
python3 tests/run_isolated.py --visual --script res://tests/product_asset_gallery.gd
```

PASS: 22 independent PNGs, 22 preserved originals, provenance, normalized edges, and 8 actual-renderer gameplay-scale gallery screenshots. All 22 assets inspected composited on warm paper. The four `review/godot-gallery-*.png` images use the real Godot 4.6.3 Metal renderer at 60 pixels/metre and actual `MedievalEntity.source_rect`; four matching `-walk-edges.png` images show the calibrated ledges. `source/` and `review/` have `.gdignore` to prevent duplicate runtime imports.

Quality notes: rich large-source botanical/architectural detail naturally becomes fine texture at 60 px/metre; silhouettes remain distinct. Some generated material interiors retain pale fill despite the prompt requesting open interiors; the surrounding alpha is transparent, with no rectangular paper background. These are original retained outputs, not destructively processed. One benign botanical output was falsely rejected by the generation service and successfully retried with simpler botanical language. No deliverables remain missing.
