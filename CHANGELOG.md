# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Add Track now picks the node itself.** The dialog shows the scene hierarchy
  with each node's editor icon; multi-select with Ctrl. Previously it silently
  required a prior Scene dock selection and warned if you had none, with nothing
  on screen explaining why. A Scene dock selection still seeds the dialog when
  present, but is no longer required.

### Added

- Headless test suite (`tests/test_core.gd`) — 61 assertions over easing, the
  bezier solver, track sampling, per-type interpolation, kind inference, loop
  and ping-pong time wrapping, and scene application. CI-usable exit code.

### Fixed

- Null entries created by inspector array editing crashed the panel's draw loop
  every frame. `MotionTimeline` and `MotionTrack` now expose null-free views
  (`get_valid_tracks()` / `get_valid_keys()`) while the raw exported arrays keep
  their holes for the inspector.
- Selecting a timeline sub-resource in the inspector unbound the MotionPlayer,
  producing a spurious "assign a valid root_node" warning.
- Track edits now propagate to the timeline's `changed` signal, so inspector
  edits repaint the panel.
- `timeline_panel.gd` failed to parse on Godot 4.7: `_canvas` was typed as
  `Control`, so `:=` could not infer types from dynamic member access. It is now
  typed as the preloaded `TimelineCanvas` script.

## [0.1.0] — 2026-08-07

Initial scaffold. Verified against Godot 4.7-stable.

### Added

- `MotionTimeline`, `MotionTrack`, `MotionKey` resources — the saved data model.
- `MotionPlayer` node with play/pause/stop/seek, loop and ping-pong modes,
  cached node resolution and configuration warnings.
- `MotionEasing` with constant/linear/ease/bezier curves; bezier X solved by
  bisection so flat handles do not diverge.
- Type-aware value interpolation for float, int, `Vector2/3/4`, `Color`,
  `Quaternion` (slerp) and `Transform2D/3D`.
- Bottom-panel editor with a drawn timeline: gutter with live editor class
  icons, frame ruler, track lanes, draggable keys, playhead and editor preview
  playback.
- Track accent palette keyed to inferred track kind, layered over the editor
  theme.
- Add Track dialog that expands vector and color components into keyable paths.
- Undo/redo coverage for every mutation via `EditorUndoRedoManager`.

[Unreleased]: https://github.com/TheSandemon/godotion/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/TheSandemon/godotion/releases/tag/v0.1.0
