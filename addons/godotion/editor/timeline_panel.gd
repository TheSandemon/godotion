@tool
extends VBoxContainer

## Bottom-panel UI: toolbar + [code]timeline_canvas.gd[/code].
##
## Owns every mutation of the edited [MotionTimeline] so each one can be pushed
## through [EditorUndoRedoManager]. The canvas only reports gestures.

const TimelineCanvas := preload("res://addons/godotion/editor/timeline_canvas.gd")
const GodotionTheme := preload("res://addons/godotion/editor/godotion_theme.gd")

## Property types worth keyframing. Anything else is filtered out of the
## Add Track picker because [MotionTrack] cannot interpolate it meaningfully.
const ANIMATABLE_TYPES := [
	TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4,
	TYPE_COLOR, TYPE_QUATERNION, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D,
]

var undo_redo: EditorUndoRedoManager

var _player: MotionPlayer
var _timeline: MotionTimeline
var _canvas: TimelineCanvas

var _play_button: Button
var _stop_button: Button
var _key_button: Button
var _add_track_button: Button
var _delete_button: Button
var _snap_button: Button
var _save_button: Button
var _duration_spin: SpinBox
var _fps_spin: SpinBox
var _title_label: Label

var _add_dialog: ConfirmationDialog
var _property_picker: OptionButton
var _target_label: Label
var _pending_nodes: Array[Node] = []

var _previewing := false


func _ready() -> void:
	custom_minimum_size = Vector2(0, 260)
	_build_toolbar()
	_build_canvas()
	_build_add_dialog()
	set_process(false)
	_refresh_controls()


# -- construction -------------------------------------------------------------

func _build_toolbar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)

	_play_button = _make_button(bar, "Play", &"Play", "Preview the timeline in the editor viewport.")
	_play_button.pressed.connect(_on_play_pressed)
	_stop_button = _make_button(bar, "Stop", &"Stop", "Stop preview and rewind to 0.")
	_stop_button.pressed.connect(_on_stop_pressed)

	bar.add_child(VSeparator.new())

	_key_button = _make_button(bar, "Key", &"Key", "Insert keys at the playhead using each track's current scene value.")
	_key_button.pressed.connect(_on_key_pressed)
	_add_track_button = _make_button(bar, "Add Track", &"Add", "Add a track for the selected scene node.")
	_add_track_button.pressed.connect(_on_add_track_pressed)
	_delete_button = _make_button(bar, "Delete", &"Remove", "Delete the selected keys.")
	_delete_button.pressed.connect(_on_delete_pressed)

	bar.add_child(VSeparator.new())

	_snap_button = _make_button(bar, "Snap", &"SnapGrid", "Snap keys and the playhead to frames. Hold Ctrl to bypass.")
	_snap_button.toggle_mode = true
	_snap_button.button_pressed = true
	_snap_button.toggled.connect(func(on: bool) -> void: _canvas.snap_enabled = on)

	var fit := _make_button(bar, "Fit", &"Zoom", "Zoom so the whole duration is visible.")
	fit.pressed.connect(func() -> void: _canvas.zoom_to_fit())

	bar.add_child(VSeparator.new())

	bar.add_child(_make_label("Duration"))
	_duration_spin = SpinBox.new()
	_duration_spin.min_value = 0.1
	_duration_spin.max_value = 3600.0
	_duration_spin.step = 0.1
	_duration_spin.suffix = "s"
	_duration_spin.custom_minimum_size.x = 88
	_duration_spin.value_changed.connect(_on_duration_changed)
	bar.add_child(_duration_spin)

	bar.add_child(_make_label("FPS"))
	_fps_spin = SpinBox.new()
	_fps_spin.min_value = 1
	_fps_spin.max_value = 240
	_fps_spin.step = 1
	_fps_spin.custom_minimum_size.x = 64
	_fps_spin.value_changed.connect(_on_fps_changed)
	bar.add_child(_fps_spin)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_title_label = Label.new()
	_title_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	bar.add_child(_title_label)

	_save_button = _make_button(bar, "Save", &"Save", "Write the timeline resource to disk.")
	_save_button.pressed.connect(_on_save_pressed)


func _make_button(parent: Node, text: String, icon_name: StringName, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	var icon := GodotionTheme.icon(icon_name)
	if icon != null:
		button.icon = icon
	parent.add_child(button)
	return button


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	return label


func _build_canvas() -> void:
	_canvas = TimelineCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_canvas)

	_canvas.playhead_moved.connect(_on_playhead_moved)
	_canvas.keys_dragged.connect(_on_keys_dragged)
	_canvas.selection_changed.connect(_refresh_controls)
	_canvas.track_enable_toggled.connect(_on_track_enable_toggled)
	_canvas.delete_requested.connect(_on_delete_pressed)
	_canvas.key_double_clicked.connect(_on_key_double_clicked)


func _build_add_dialog() -> void:
	_add_dialog = ConfirmationDialog.new()
	_add_dialog.title = "Add Motion Track"
	_add_dialog.ok_button_text = "Add Track"
	var box := VBoxContainer.new()
	_target_label = Label.new()
	box.add_child(_target_label)
	var row := HBoxContainer.new()
	row.add_child(_make_label("Property"))
	_property_picker = OptionButton.new()
	_property_picker.custom_minimum_size.x = 260
	row.add_child(_property_picker)
	box.add_child(row)
	_add_dialog.add_child(box)
	_add_dialog.confirmed.connect(_on_add_dialog_confirmed)
	add_child(_add_dialog)


# -- external API -------------------------------------------------------------

func edit_player(player: MotionPlayer) -> void:
	_player = player
	set_timeline(player.timeline if player != null else null)
	_canvas.root_node = _resolve_root()
	_refresh_controls()


func set_timeline(timeline: MotionTimeline) -> void:
	if _timeline == timeline:
		return
	_timeline = timeline
	_canvas.timeline = timeline
	_canvas.root_node = _resolve_root()
	if timeline != null:
		_duration_spin.set_value_no_signal(timeline.duration)
		_fps_spin.set_value_no_signal(timeline.fps)
		_canvas.zoom_to_fit()
	_refresh_controls()


func get_timeline() -> MotionTimeline:
	return _timeline


func _resolve_root() -> Node:
	if _player == null:
		return null
	return _player.get_node_or_null(_player.root_node)


func _refresh_controls() -> void:
	var has_timeline := _timeline != null
	var has_selection := has_timeline and not _canvas.get_selection().is_empty()
	_play_button.disabled = not has_timeline or _player == null
	_stop_button.disabled = _play_button.disabled
	_key_button.disabled = not has_timeline or _timeline.tracks.is_empty()
	_add_track_button.disabled = not has_timeline
	_delete_button.disabled = not has_selection
	_duration_spin.editable = has_timeline
	_fps_spin.editable = has_timeline
	_save_button.disabled = not has_timeline
	_play_button.text = "Pause" if _previewing else "Play"
	if has_timeline:
		var path := _timeline.resource_path
		_title_label.text = "%s  ·  %s" % [_timeline.timeline_name, path if path != "" else "(built-in)"]
	else:
		_title_label.text = ""


# -- editor preview -----------------------------------------------------------

func _process(delta: float) -> void:
	if not _previewing or _timeline == null:
		return
	var t := _canvas.playhead + delta
	if _timeline.is_finished(t):
		_canvas.playhead = _timeline.duration
		_apply_preview()
		_set_previewing(false)
		return
	_canvas.playhead = _timeline.wrap_time(t)
	_apply_preview()


func _set_previewing(on: bool) -> void:
	_previewing = on
	set_process(on)
	_refresh_controls()


func _apply_preview() -> void:
	if _player != null and is_instance_valid(_player):
		_player.apply_at(_canvas.playhead)


func _on_play_pressed() -> void:
	_set_previewing(not _previewing)


func _on_stop_pressed() -> void:
	_set_previewing(false)
	_canvas.playhead = 0.0
	_apply_preview()


func _on_playhead_moved(_time: float) -> void:
	_apply_preview()


# -- mutations (all undoable) -------------------------------------------------

func _on_duration_changed(value: float) -> void:
	if _timeline == null or is_equal_approx(_timeline.duration, value):
		return
	var old := _timeline.duration
	undo_redo.create_action("Godotion: Set Duration")
	undo_redo.add_do_property(_timeline, "duration", value)
	undo_redo.add_undo_property(_timeline, "duration", old)
	undo_redo.commit_action()
	_canvas.queue_redraw()


func _on_fps_changed(value: float) -> void:
	if _timeline == null or _timeline.fps == int(value):
		return
	var old := _timeline.fps
	undo_redo.create_action("Godotion: Set FPS")
	undo_redo.add_do_property(_timeline, "fps", int(value))
	undo_redo.add_undo_property(_timeline, "fps", old)
	undo_redo.commit_action()
	_canvas.queue_redraw()


func _on_track_enable_toggled(track: MotionTrack, enabled: bool) -> void:
	undo_redo.create_action("Godotion: Toggle Track")
	undo_redo.add_do_property(track, "enabled", enabled)
	undo_redo.add_undo_property(track, "enabled", not enabled)
	undo_redo.commit_action()
	_canvas.queue_redraw()


func _on_keys_dragged(tracks: Array, keys: Array, old_times: Array, new_times: Array) -> void:
	# The canvas already moved the keys live; register the inverse first so the
	# action is symmetrical, then re-apply on redo.
	undo_redo.create_action("Godotion: Move Keys")
	for i in range(keys.size()):
		undo_redo.add_do_property(keys[i], "time", new_times[i])
		undo_redo.add_undo_property(keys[i], "time", old_times[i])
	for track in tracks:
		undo_redo.add_do_method(track, "sort_keys")
		undo_redo.add_undo_method(track, "sort_keys")
	undo_redo.commit_action(false)
	_canvas.queue_redraw()


func _on_key_pressed() -> void:
	if _timeline == null:
		return
	var root := _resolve_root()
	if root == null:
		push_warning("Godotion: cannot key — the MotionPlayer's root_node does not resolve.")
		return
	var time: float = _timeline.snap_to_frame(_canvas.playhead)
	var created: Array[MotionKey] = []
	var owners: Array[MotionTrack] = []
	for track in _timeline.tracks:
		if not track.enabled or track.property.is_empty():
			continue
		var node: Node = root if track.node_path.is_empty() else root.get_node_or_null(track.node_path)
		if node == null:
			continue
		var value: Variant = node.get_indexed(NodePath(track.property))
		if value == null:
			continue
		if track.find_key_at(time) != null:
			continue
		var key := MotionKey.new()
		key.time = time
		key.value = value
		created.append(key)
		owners.append(track)

	if created.is_empty():
		return
	undo_redo.create_action("Godotion: Insert Keys")
	for i in range(created.size()):
		undo_redo.add_do_method(owners[i], "add_key", created[i])
		undo_redo.add_undo_method(owners[i], "remove_key", created[i])
	undo_redo.commit_action()
	_canvas.queue_redraw()


func _on_delete_pressed() -> void:
	var selection: Array[Dictionary] = _canvas.get_selection()
	if selection.is_empty():
		return
	undo_redo.create_action("Godotion: Delete Keys")
	for entry in selection:
		undo_redo.add_do_method(entry["track"], "remove_key", entry["key"])
		undo_redo.add_undo_method(entry["track"], "add_key", entry["key"])
	undo_redo.commit_action()
	_canvas.clear_selection()
	_canvas.queue_redraw()


func _on_key_double_clicked(_track: MotionTrack, key: MotionKey) -> void:
	# Cycle interpolation modes; the inspector remains available for handles.
	var next: int = (key.interp + 1) % MotionKey.Interp.size()
	undo_redo.create_action("Godotion: Change Interpolation")
	undo_redo.add_do_property(key, "interp", next)
	undo_redo.add_undo_property(key, "interp", key.interp)
	undo_redo.commit_action()
	_canvas.queue_redraw()


func _on_save_pressed() -> void:
	if _timeline == null:
		return
	if _timeline.resource_path.is_empty():
		# Built-in resource: it lives inside the scene, so mark the scene dirty.
		EditorInterface.mark_scene_as_unsaved()
		return
	var err := ResourceSaver.save(_timeline, _timeline.resource_path)
	if err != OK:
		push_error("Godotion: failed to save '%s' (error %d)." % [_timeline.resource_path, err])


# -- add track flow -----------------------------------------------------------

func _on_add_track_pressed() -> void:
	if _timeline == null:
		return
	var root := _resolve_root()
	if root == null:
		push_warning("Godotion: assign a valid root_node on the MotionPlayer first.")
		return
	_pending_nodes = []
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node == _player:
			continue
		if node == root or root.is_ancestor_of(node):
			_pending_nodes.append(node)
	if _pending_nodes.is_empty():
		push_warning("Godotion: select one or more nodes under '%s' in the scene tree." % root.name)
		return

	_property_picker.clear()
	for prop in _collect_animatable_properties(_pending_nodes[0]):
		_property_picker.add_item(prop)
	if _property_picker.item_count == 0:
		push_warning("Godotion: '%s' exposes no animatable properties." % _pending_nodes[0].name)
		return

	var names := PackedStringArray()
	for node in _pending_nodes:
		names.append(node.name)
	_target_label.text = "Target: %s" % ", ".join(names)
	_add_dialog.popup_centered(Vector2i(420, 140))


## Flattens a node's exported properties into keyable paths, expanding vector
## and color components so users can key a single axis or the alpha channel.
func _collect_animatable_properties(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in node.get_property_list():
		var usage: int = entry["usage"]
		if usage & PROPERTY_USAGE_EDITOR == 0 or usage & PROPERTY_USAGE_CATEGORY != 0:
			continue
		var type: int = entry["type"]
		if not ANIMATABLE_TYPES.has(type):
			continue
		var name: String = entry["name"]
		if name.begins_with("_") or name.contains("/"):
			continue
		out.append(name)
		match type:
			TYPE_VECTOR2:
				out.append(name + ":x")
				out.append(name + ":y")
			TYPE_VECTOR3:
				out.append(name + ":x")
				out.append(name + ":y")
				out.append(name + ":z")
			TYPE_COLOR:
				out.append(name + ":r")
				out.append(name + ":g")
				out.append(name + ":b")
				out.append(name + ":a")
	return out


func _on_add_dialog_confirmed() -> void:
	if _timeline == null or _property_picker.selected < 0:
		return
	var property := _property_picker.get_item_text(_property_picker.selected)
	var root := _resolve_root()
	if root == null:
		return

	var new_tracks: Array[MotionTrack] = []
	for node in _pending_nodes:
		var path := root.get_path_to(node)
		if _timeline.find_track(path, property) != null:
			continue
		var track := MotionTrack.new()
		track.node_path = path
		track.property = property
		new_tracks.append(track)

	if new_tracks.is_empty():
		return
	undo_redo.create_action("Godotion: Add Track")
	for track in new_tracks:
		undo_redo.add_do_method(_timeline, "add_track", track)
		undo_redo.add_undo_method(_timeline, "remove_track", track)
	undo_redo.commit_action()
	_refresh_controls()
	_canvas.queue_redraw()
