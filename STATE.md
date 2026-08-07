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

## 2026-08-07 — v0.1.0 scaffold

Built the full plugin from empty: data model, runtime player, easing, bottom
panel, drawn timeline canvas, theme bridge, demo project, docs, MIT license.
Repo created on GitHub under `TheSandemon/godotion` (public).

**Not yet verified in a running editor.** The Godot binary on this machine
(`C:\Users\Sand\Desktop\Godot_v4.6.1-stable_win64.exe`) is a 1-byte stub, so
`--headless --import` could not run. The code passed a manual review pass that
caught and fixed: an invalid `as Kind` enum cast, an `Array.filter` result
assigned to a typed `Array[Dictionary]`, misuse of
`command_or_control_autoremap` instead of `is_command_or_control_pressed()`,
and `TYPE_RECT2` being offered as keyable without an interpolation path.

### Next session should

1. Install a real Godot 4.7 build, then run
   `godot --headless --path . --import` and fix whatever the parser reports.
2. Open `demo/demo.tscn`, add a `MotionTimeline` to the MotionPlayer, and
   exercise: Add Track → Key → drag → undo → save.
3. Then pick up the v0.2 candidates: bezier handle editing on the canvas,
   box-select, copy/paste keys, per-track time offset (stagger), and a
   `MotionTimeline` inspector plugin for editing key values numerically.
