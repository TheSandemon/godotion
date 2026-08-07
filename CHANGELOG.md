# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Headless test suite (`tests/test_core.gd`) — 61 assertions over easing, the
  bezier solver, track sampling, per-type interpolation, kind inference, loop
  and ping-pong time wrapping, and scene application. CI-usable exit code.

### Fixed

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
