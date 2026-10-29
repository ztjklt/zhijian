# Fauna delivery — 2026-10-25

Delivered three independently generated transparent black-ink 4×2 sprite sheets: `rabbit.png`, `deer.png`, `bat-v2.png`. The original bat variant is retained as `bat.png`. All four originals are byte-identical in `source/`; `generation_manifest.json` and `bat-v2-generation.json` preserve complete prompts, builtin tool identity, original generated-image paths and revision target. No API fallback or programmatic raster edits.

`manifest.json` registers rabbit (.85×.65m,28hp), deer (1.65×1.55m,60hp) and bat (1.25×.85m,40hp). `frames.json` provides measured common envelopes, foot rows and eight explicit bat atlas regions. The wider horizontal wing and lowered fourth wing are included completely; the downed final frame excludes the flight-row wingtip. Source rectangles may differ; all poses retain one common pixel/metre scale and cell-relative pivot. The renderer does not resize each pose independently.

`medieval_fauna.gd` implements cached source metadata, shared collider shapes/material, walking patrols and bounded bat flight, cropped native rendering and hurt/fall/dead frame selection. `medieval_entity.gd` hooks preserve existing TreeRoots code, horse/dragon behavior and actor64/mask9 interaction. Rabbit/deer expose the same .335-width /.05-foot contact contract as the horse. Nonfatal impacts preserve real knockback and avoid collider rebuilds; a fatal bat impact immediately restores gravity. World-owned slope spawning/patrol integration is delivered by the composition worker.

Validation:

- `python3 tests/run_isolated.py --script res://tests/medieval_fauna_test.gd`: **100 checks, 0 failures**. Initially failed on unsupported fauna before implementation. Final checks cover actor physics, eight real frames, common pixel scale, locomotion, hurt impulse, falling and downed poses.
- `python3 tests/run_isolated.py --visual --script res://tests/medieval_fauna_gallery.gd`: **24 frames rendered by Godot Metal at 90px/m**. Actual screenshot read and inspected: one complete creature per frame, no neighboring wing fragments.
- Actual runtime/gallery logs: `review/fauna-headless.log`, `review/fauna-metal.log`; screenshot: `review/godot-fauna-frames.png`.
- `validation.json` preserves SHA256 checks of each unchanged builtin output and its original duplicate.

Source and metadata frozen after final gallery inspection. No user save/window, Git, build or remote deployment changes.
