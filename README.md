# Godotion

A motion-graphics timeline editor for Godot 4, built as an `EditorPlugin`.

Scene nodes become tracks. Each track drives one property of one node, keyed on
a drawn timeline that sits in the editor's bottom panel and borrows the editor's
own icons and theme so it reads as part of Godot rather than bolted onto it.

> **Status: v0.1.0, early.** The data model, runtime player and timeline canvas
> are implemented and the plugin loads as-is. It has not yet been run against a
> Godot 4.7 build — see [Version support](#version-support).

## Why not AnimationPlayer?

Godot's `AnimationPlayer` is built for gameplay animation. Motion-graphics work
wants a different shape: per-clip time remapping, staggered offsets across many
nodes, and easing authored per segment. Godotion uses its own `MotionTimeline`
resource so those features have somewhere to live, and its own `MotionPlayer`
node to evaluate them — identically in the editor preview and at runtime.

## Install

1. Copy `addons/godotion/` into your project's `addons/` folder.
2. **Project → Project Settings → Plugins**, enable **Godotion**.
3. A **Godotion** tab appears in the bottom panel.

Or clone this repository and open it directly — it *is* a Godot project, with a
small demo scene under `demo/`.

## Usage

1. Add a **MotionPlayer** node to your scene.
2. In the inspector, create a new **MotionTimeline** resource on its `Timeline`
   property. Set `Root Node` to the node your animated nodes live under
   (defaults to the MotionPlayer's parent).
3. Select the MotionPlayer — the Godotion panel binds to it.
4. Select one or more nodes in the scene tree, press **Add Track**, and pick a
   property. Vector and color components are offered individually, so you can
   key `position:x` or `modulate:a` on their own.
5. Scrub the ruler, pose your nodes in the viewport, and press **Key** to insert
   keyframes at the playhead from the nodes' current values.

### Timeline controls

| Gesture | Action |
| --- | --- |
| Drag the ruler | Scrub the playhead |
| Drag a key | Move it in time (snaps to frames) |
| Hold <kbd>Ctrl</kbd> while dragging | Bypass frame snapping |
| <kbd>Shift</kbd> + click a key | Add to / remove from the selection |
| Click a track name | Select all of that track's keys |
| Double-click a key | Cycle its interpolation mode |
| <kbd>Delete</kbd> | Delete selected keys |
| Mouse wheel | Scroll tracks vertically |
| <kbd>Ctrl</kbd> + wheel | Zoom time |
| <kbd>Shift</kbd> + wheel | Pan time |
| Middle-drag | Pan both axes |

Every edit goes through `EditorUndoRedoManager`, so <kbd>Ctrl</kbd>+<kbd>Z</kbd>
works as expected.

### Track colours

Track kind is inferred from the property name and drives the accent colour of
the row marker, key diamonds and span bar. The node's own class icon — pulled
live from the editor theme — sits next to it.

| Kind | Colour | Matches |
| --- | --- | --- |
| Transform | blue | `position`, `offset`, `transform`, `skew` |
| Rotation | purple | `rotation`, `quaternion` |
| Scale | green | `scale` |
| Color | orange | `modulate`, `*color*` |
| Opacity | yellow | `modulate:a`, `*alpha`, `*opacity` |
| Custom | grey | everything else |

Override the inference per track by setting `kind_override` on the `MotionTrack`.

## Runtime API

```gdscript
var player: MotionPlayer = $MotionPlayer

player.play()             # from the current position
player.play(0.0)          # from a specific time
player.pause()
player.stop()             # stop and rewind
player.seek(1.5)          # move the playhead, keep the play state
player.apply_at(1.5)      # sample and write without touching playback state

player.started.connect(...)
player.finished.connect(...)
player.looped.connect(...)
player.time_changed.connect(func(t: float) -> void: print(t))
```

Interpolation modes per key: `CONSTANT`, `LINEAR`, `EASE_IN`, `EASE_OUT`,
`EASE_IN_OUT`, `BEZIER`. Bezier segments use the outgoing handle of the left key
and the incoming handle of the right one, solved for X by bisection so flat
handles behave.

Values interpolate by type — floats, ints, `Vector2/3/4`, `Color`, `Quaternion`
(slerp), `Transform2D/3D`. Anything else snaps at the segment midpoint.

## Layout

```
addons/godotion/
  plugin.cfg
  plugin.gd              EditorPlugin: bottom panel, selection routing
  core/                  runtime — no editor dependencies
    motion_key.gd        one keyframe
    motion_track.gd      one property of one node; sampling + interpolation
    motion_timeline.gd   tracks + duration/fps/loop; the saved resource
    motion_player.gd     Node that evaluates a timeline into the scene
    motion_easing.gd     easing curves and the bezier solver
  editor/                editor-only — never loaded at runtime
    timeline_panel.gd    toolbar, dialogs, all undoable mutations
    timeline_canvas.gd   the drawn timeline and its input handling
    godotion_theme.gd    editor theme bridge + track accent palette
  icons/
demo/                    scratch scene for exercising the plugin
```

`core/` never references `EditorInterface`, so exported builds carry only the
runtime. `editor/godotion_theme.gd` deliberately has no `class_name` to keep it
out of the global class table at runtime.

## Version support

Written against the Godot 4 plugin API, which has been stable across 4.x. It is
intended for **Godot 4.7**; the local dev machine has no working 4.7 build yet,
so it has been verified by review rather than by running the editor. If you hit
a 4.7-specific issue, please open one.

## Contributing

Issues and PRs welcome. Keep `core/` free of editor dependencies, and route
every user-facing edit through `EditorUndoRedoManager`.

## License

MIT — see [LICENSE](LICENSE).
