# Project State

Canonical handoff file. Append a dated entry when concluding a work session.

## Invariants

- `addons/godotion/core/` must never reference `EditorInterface`, `EditorPlugin`
  or anything else editor-only. It ships in exported games.
- `addons/godotion/editor/godotion_theme.gd` intentionally has **no**
  `class_name` — it touches `EditorInterface` and must stay out of the global
  class table. Editor scripts `preload()` it instead.
- The canvas (`timeline_canvas.gd`) never performs undoable mutations. It moves
  keys live during a drag for feedback, then emits `keys_dragged` so
  `timeline_panel.gd` can register a single symmetrical undo step
  (`commit_action(false)` — the do side is already applied).
- `MotionTrack.get_kind()` returns `int`, not the `Kind` enum: GDScript rejects
  casting a stored integer back into an enum type.
- `MotionTrack.keys` must stay sorted by time. Use `add_key` / `set_key` /
  `sort_keys` rather than mutating the array directly.

## Environment

- Godot **4.7-stable** (`5b4e0cb0f`) lives at `Godot_v4.7-stable_win64.exe` in
  this folder, and also at `C:\Users\Sand\Desktop\Coding\Godot\`. Use the
  `_console.exe` variant for headless runs — the plain exe detaches stdout.
- The binaries are gitignored (`Godot_v*.exe`).
- Verify with:
  `.\Godot_v4.7-stable_win64_console.exe --headless --path . --import`
  then `... --script res://tests/test_core.gd` (exits non-zero on failure).

## 2026-08-07 — v0.1.0 scaffold

Built the full plugin from empty: data model, runtime player, easing, bottom
panel, drawn timeline canvas, theme bridge, demo project, docs, MIT license.
Repo created on GitHub under `TheSandemon/godotion` (public).

**Verified on 4.7-stable**: clean `--import`, editor boots with the plugin
loaded and the panel constructed (`--editor --quit`), and `test_core.gd` passes
61/61.

A review pass before running caught: an invalid `as Kind` enum cast, an
`Array.filter` result assigned to a typed `Array[Dictionary]`, misuse of
`command_or_control_autoremap` instead of `is_command_or_control_pressed()`,
and `TYPE_RECT2` offered as keyable with no interpolation path. The 4.7 parser
then caught two more: `_canvas` was typed `Control`, so `:=` could not infer
types off dynamic member access. Fixed by typing it as the preloaded
`TimelineCanvas` script — worth remembering, since the same trap applies to any
`preload`ed script without a `class_name`.

### Next session should

1. Open `demo/demo.tscn` in the editor and drive the UI by hand: add a
   `MotionTimeline` to the MotionPlayer, then Add Track → Key → drag → undo →
   save. Headless coverage stops at the panel constructing; no gesture has been
   exercised against a real editor.
2. Then pick up the v0.2 candidates: bezier handle editing on the canvas,
   box-select, copy/paste keys, per-track time offset (stagger), and a
   `MotionTimeline` inspector plugin for editing key values numerically.
