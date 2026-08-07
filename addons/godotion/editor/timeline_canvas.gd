@tool
extends Control

## The drawn timeline: gutter, ruler, track lanes, keys and playhead.
##
## This Control owns hit-testing and drag gestures but never mutates the
## timeline resource for anything undoable — it reports gestures upward via
## signals so [code]timeline_panel.gd[/code] can wrap them in undo steps.

signal playhead_moved(time: float)
## Emitted once per completed drag, with parallel arrays describing the move.
signal keys_dragged(tracks: Array, keys: Array, old_times: Array, new_times: Array)
signal selection_changed()
signal track_enable_toggled(track: MotionTrack, enabled: bool)
signal delete_requested()
signal key_double_clicked(track: MotionTrack, key: MotionKey)

const GodotionTheme := preload("res://addons/godotion/editor/godotion_theme.gd")

const GUTTER_W := 248.0
const RULER_H := 26.0
const ROW_H := 26.0
const ICON_SIZE := 16.0
const KEY_RADIUS := 5.5
const MIN_PPS := 8.0
const MAX_PPS := 2000.0

var timeline: MotionTimeline:
	set(v):
		timeline = v
		clear_selection()
		queue_redraw()

## Scene root used to resolve node paths for icon lookup.
var root_node: Node = null:
	set(v):
		root_node = v
		queue_redraw()

var playhead: float = 0.0:
	set(v):
		playhead = maxf(0.0, v)
		queue_redraw()

## Pixels per second. Drives horizontal zoom.
var pixels_per_second: float = 120.0
## Time at the left edge of the lane area.
var pan_time: float = 0.0
var v_offset: float = 0.0
var snap_enabled: bool = true

## Selected keys as an array of [code]{track, key}[/code] dictionaries.
var _selection: Array[Dictionary] = []
var _drag_mode := DragMode.NONE
var _drag_origin := Vector2.ZERO
var _drag_start_times: Array[float] = []
var _drag_start_pan := 0.0
var _drag_moved := false
var _last_click_key: MotionKey = null
var _last_click_msec := 0

enum DragMode { NONE, SCRUB, KEYS, PAN }


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(480, 160)


# -- coordinate helpers -------------------------------------------------------

func time_to_x(t: float) -> float:
	return GUTTER_W + (t - pan_time) * pixels_per_second


func x_to_time(x: float) -> float:
	return (x - GUTTER_W) / pixels_per_second + pan_time


func row_y(index: int) -> float:
	return RULER_H + index * ROW_H - v_offset


func _visible_track_count() -> int:
	return 0 if timeline == null else timeline.tracks.size()


func _content_height() -> float:
	return _visible_track_count() * ROW_H


func _max_v_offset() -> float:
	return maxf(0.0, _content_height() - (size.y - RULER_H))


# -- selection ----------------------------------------------------------------

func clear_selection() -> void:
	if _selection.is_empty():
		return
	_selection.clear()
	selection_changed.emit()
	queue_redraw()


func get_selection() -> Array[Dictionary]:
	return _selection.duplicate()


func _is_selected(key: MotionKey) -> bool:
	for entry in _selection:
		if entry["key"] == key:
			return true
	return false


func select_key(track: MotionTrack, key: MotionKey, additive: bool) -> void:
	if not additive:
		_selection.clear()
	elif _is_selected(key):
		for i in range(_selection.size()):
			if _selection[i]["key"] == key:
				_selection.remove_at(i)
				break
		selection_changed.emit()
		queue_redraw()
		return
	_selection.append({"track": track, "key": key})
	selection_changed.emit()
	queue_redraw()


# -- drawing ------------------------------------------------------------------

func _draw() -> void:
	var font := GodotionTheme.font()
	var fsize := GodotionTheme.font_size()
	var bg := GodotionTheme.color(&"dark_color_2", Color("21262d"))
	var gutter_bg := GodotionTheme.color(&"dark_color_3", Color("1a1e24"))
	var line_col := GodotionTheme.color(&"contrast_color_1", Color(1, 1, 1, 0.08))
	var text_col := GodotionTheme.color(&"font_color", Color("d4d7dd"))
	var accent := GodotionTheme.color(&"accent_color", Color("4b9fea"))

	draw_rect(Rect2(Vector2.ZERO, size), bg)

	if timeline == null:
		var msg := "Select a MotionPlayer, or create a timeline to begin."
		draw_string(font, Vector2(GUTTER_W * 0.5, size.y * 0.5), msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(text_col, 0.6))
		return

	_draw_lane_background(line_col)
	_draw_ruler(font, fsize, text_col, line_col)
	_draw_tracks(font, fsize, text_col, line_col)
	_draw_gutter(font, fsize, text_col, gutter_bg, line_col)
	_draw_playhead(font, fsize, accent)


func _draw_lane_background(line_col: Color) -> void:
	var lane_rect := Rect2(GUTTER_W, RULER_H, size.x - GUTTER_W, size.y - RULER_H)
	# Shade the region beyond the authored duration so overruns are obvious.
	var end_x := time_to_x(timeline.duration)
	if end_x < size.x:
		draw_rect(Rect2(maxf(end_x, GUTTER_W), RULER_H, size.x - maxf(end_x, GUTTER_W), lane_rect.size.y),
			Color(0, 0, 0, 0.18))

	for i in range(_visible_track_count()):
		var y := row_y(i)
		if y + ROW_H < RULER_H or y > size.y:
			continue
		if i % 2 == 1:
			draw_rect(Rect2(GUTTER_W, y, size.x - GUTTER_W, ROW_H), Color(1, 1, 1, 0.02))
		draw_line(Vector2(GUTTER_W, y + ROW_H), Vector2(size.x, y + ROW_H), line_col, 1.0)


## Draws time labels at a step chosen so ticks never crowd below ~64px apart.
func _draw_ruler(font: Font, fsize: int, text_col: Color, line_col: Color) -> void:
	draw_rect(Rect2(0, 0, size.x, RULER_H), GodotionTheme.color(&"dark_color_1", Color("15191e")))

	var step := _pick_ruler_step()
	var first := floorf(pan_time / step) * step
	var t := first
	while true:
		var x := time_to_x(t)
		if x > size.x:
			break
		if x >= GUTTER_W:
			draw_line(Vector2(x, 0), Vector2(x, size.y), line_col, 1.0)
			draw_string(font, Vector2(x + 4, RULER_H - 8), _format_time(t),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize - 2, Color(text_col, 0.75))
		t += step
	draw_line(Vector2(0, RULER_H), Vector2(size.x, RULER_H), line_col, 1.0)


func _pick_ruler_step() -> float:
	const CANDIDATES := [1.0 / 60.0, 1.0 / 24.0, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0, 300.0]
	for candidate in CANDIDATES:
		if candidate * pixels_per_second >= 64.0:
			return candidate
	return CANDIDATES[CANDIDATES.size() - 1]


func _format_time(t: float) -> String:
	if pixels_per_second > 400.0:
		return "%.2fs" % t
	if t >= 60.0:
		return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]
	return "%.2fs" % t


func _draw_tracks(font: Font, fsize: int, text_col: Color, line_col: Color) -> void:
	for i in range(timeline.tracks.size()):
		var track: MotionTrack = timeline.tracks[i]
		var y := row_y(i)
		if y + ROW_H < RULER_H or y > size.y:
			continue
		var accent := GodotionTheme.accent_for(track)
		if not track.enabled:
			accent = Color(accent, 0.35)
		var mid := y + ROW_H * 0.5

		# Span bar between the first and last key.
		if track.keys.size() > 1:
			var x0 := time_to_x(track.keys[0].time)
			var x1 := time_to_x(track.keys[track.keys.size() - 1].time)
			var from_x := maxf(x0, GUTTER_W)
			var to_x := minf(x1, size.x)
			if to_x > from_x:
				draw_line(Vector2(from_x, mid), Vector2(to_x, mid), Color(accent, 0.45), 2.0)

		for key in track.keys:
			var x := time_to_x(key.time)
			if x < GUTTER_W - KEY_RADIUS or x > size.x + KEY_RADIUS:
				continue
			_draw_key(Vector2(x, mid), accent, _is_selected(key), key.interp)


func _draw_key(center: Vector2, accent: Color, selected: bool, interp: int) -> void:
	var r := KEY_RADIUS
	var points := PackedVector2Array([
		center + Vector2(0, -r),
		center + Vector2(r, 0),
		center + Vector2(0, r),
		center + Vector2(-r, 0),
	])
	# Constant keys read as squares so hold segments are visible at a glance.
	if interp == MotionKey.Interp.CONSTANT:
		points = PackedVector2Array([
			center + Vector2(-r, -r), center + Vector2(r, -r),
			center + Vector2(r, r), center + Vector2(-r, r),
		])
	draw_colored_polygon(points, accent)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(1, 1, 1, 0.9) if selected else Color(0, 0, 0, 0.6), 1.5)


func _draw_gutter(font: Font, fsize: int, text_col: Color, gutter_bg: Color, line_col: Color) -> void:
	draw_rect(Rect2(0, 0, GUTTER_W, size.y), gutter_bg)
	draw_line(Vector2(GUTTER_W, 0), Vector2(GUTTER_W, size.y), line_col, 1.0)
	draw_string(font, Vector2(10, RULER_H - 8), "Tracks", HORIZONTAL_ALIGNMENT_LEFT, -1,
		fsize - 2, Color(text_col, 0.55))

	if timeline == null:
		return

	for i in range(timeline.tracks.size()):
		var track: MotionTrack = timeline.tracks[i]
		var y := row_y(i)
		if y + ROW_H < RULER_H or y > size.y:
			continue
		var accent := GodotionTheme.accent_for(track)
		var alpha := 1.0 if track.enabled else 0.4

		draw_rect(Rect2(0, y + 3, 3, ROW_H - 6), Color(accent, alpha))

		# Enable toggle.
		var toggle_rect := Rect2(8, y + (ROW_H - 12) * 0.5, 12, 12)
		draw_rect(toggle_rect, Color(accent, 0.85 if track.enabled else 0.0))
		draw_rect(toggle_rect, Color(accent, 0.85), false, 1.0)

		# Native class icon for the animated node.
		var node := _resolve_track_node(track)
		var icon := GodotionTheme.icon_for_node(node)
		if icon != null:
			draw_texture_rect(icon, Rect2(26, y + (ROW_H - ICON_SIZE) * 0.5, ICON_SIZE, ICON_SIZE),
				false, Color(1, 1, 1, alpha))

		var label := track.get_display_name()
		draw_string(font, Vector2(48, y + ROW_H * 0.5 + 4), label,
			HORIZONTAL_ALIGNMENT_LEFT, 108, fsize, Color(text_col, alpha))
		draw_string(font, Vector2(160, y + ROW_H * 0.5 + 4), track.property,
			HORIZONTAL_ALIGNMENT_LEFT, GUTTER_W - 166, fsize - 2, Color(accent, alpha))

		draw_line(Vector2(0, y + ROW_H), Vector2(GUTTER_W, y + ROW_H), line_col, 1.0)


func _draw_playhead(font: Font, fsize: int, accent: Color) -> void:
	var x := time_to_x(playhead)
	if x < GUTTER_W or x > size.x:
		return
	draw_line(Vector2(x, 0), Vector2(x, size.y), accent, 1.0)
	var head := PackedVector2Array([
		Vector2(x - 6, 0), Vector2(x + 6, 0), Vector2(x + 6, 10), Vector2(x, 16), Vector2(x - 6, 10),
	])
	draw_colored_polygon(head, accent)


func _resolve_track_node(track: MotionTrack) -> Node:
	if root_node == null:
		return null
	if track.node_path.is_empty():
		return root_node
	return root_node.get_node_or_null(track.node_path)


# -- hit testing --------------------------------------------------------------

func _row_at(pos: Vector2) -> int:
	if pos.y < RULER_H or timeline == null:
		return -1
	var index := int((pos.y + v_offset - RULER_H) / ROW_H)
	if index < 0 or index >= timeline.tracks.size():
		return -1
	return index


func _key_at(pos: Vector2) -> Dictionary:
	var row := _row_at(pos)
	if row < 0 or pos.x < GUTTER_W:
		return {}
	var track: MotionTrack = timeline.tracks[row]
	var mid := row_y(row) + ROW_H * 0.5
	if absf(pos.y - mid) > KEY_RADIUS + 3.0:
		return {}
	var best: MotionKey = null
	var best_dist := KEY_RADIUS + 4.0
	for key in track.keys:
		var dist := absf(time_to_x(key.time) - pos.x)
		if dist < best_dist:
			best_dist = dist
			best = key
	if best == null:
		return {}
	return {"track": track, "key": best}


func get_track_at(pos: Vector2) -> MotionTrack:
	var row := _row_at(pos)
	return null if row < 0 else timeline.tracks[row]


# -- input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if timeline == null:
		return

	if event is InputEventMouseButton:
		_handle_button(event)
	elif event is InputEventMouseMotion:
		_handle_motion(event)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE:
			delete_requested.emit()
			accept_event()


func _handle_button(event: InputEventMouseButton) -> void:
	var pos := event.position

	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not event.pressed:
			return
		var dir := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		if event.is_command_or_control_pressed():
			_zoom_at(pos.x, 1.0 + dir * 0.15)
		elif event.shift_pressed:
			pan_time = maxf(0.0, pan_time - dir * (80.0 / pixels_per_second))
		else:
			v_offset = clampf(v_offset - dir * ROW_H * 2.0, 0.0, _max_v_offset())
		queue_redraw()
		accept_event()
		return

	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_drag_mode = DragMode.PAN if event.pressed else DragMode.NONE
		_drag_origin = pos
		_drag_start_pan = pan_time
		accept_event()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not event.pressed:
		_finish_drag()
		accept_event()
		return

	grab_focus()

	# Gutter: toggle enable, or select the whole track's keys.
	if pos.x < GUTTER_W:
		var row := _row_at(pos)
		if row >= 0:
			var track: MotionTrack = timeline.tracks[row]
			if pos.x >= 6.0 and pos.x <= 22.0:
				track_enable_toggled.emit(track, not track.enabled)
			else:
				_selection.clear()
				for key in track.keys:
					_selection.append({"track": track, "key": key})
				selection_changed.emit()
			queue_redraw()
		accept_event()
		return

	# Ruler: scrub.
	if pos.y < RULER_H:
		_drag_mode = DragMode.SCRUB
		_set_playhead_from_x(pos.x)
		accept_event()
		return

	var hit := _key_at(pos)
	if hit.is_empty():
		clear_selection()
		accept_event()
		return

	var now := Time.get_ticks_msec()
	if hit["key"] == _last_click_key and now - _last_click_msec < 400:
		key_double_clicked.emit(hit["track"], hit["key"])
		_last_click_key = null
		accept_event()
		return
	_last_click_key = hit["key"]
	_last_click_msec = now

	if not _is_selected(hit["key"]):
		select_key(hit["track"], hit["key"], event.shift_pressed)
	_begin_key_drag(pos)
	accept_event()


func _handle_motion(event: InputEventMouseMotion) -> void:
	match _drag_mode:
		DragMode.SCRUB:
			_set_playhead_from_x(event.position.x)
			accept_event()
		DragMode.PAN:
			pan_time = maxf(0.0, _drag_start_pan - (event.position.x - _drag_origin.x) / pixels_per_second)
			v_offset = clampf(v_offset - event.relative.y, 0.0, _max_v_offset())
			queue_redraw()
			accept_event()
		DragMode.KEYS:
			var delta := (event.position.x - _drag_origin.x) / pixels_per_second
			if absf(event.position.x - _drag_origin.x) > 2.0:
				_drag_moved = true
			for i in range(_selection.size()):
				var key: MotionKey = _selection[i]["key"]
				var target := _drag_start_times[i] + delta
				if snap_enabled and not event.ctrl_pressed:
					target = timeline.snap_to_frame(target)
				key.time = maxf(0.0, target)
			for entry in _selection:
				(entry["track"] as MotionTrack).sort_keys()
			queue_redraw()
			accept_event()


func _begin_key_drag(pos: Vector2) -> void:
	_drag_mode = DragMode.KEYS
	_drag_origin = pos
	_drag_moved = false
	_drag_start_times.clear()
	for entry in _selection:
		_drag_start_times.append((entry["key"] as MotionKey).time)


## Ends the gesture. Key drags are reported as a single batch so the panel can
## register one undo step for the whole move.
func _finish_drag() -> void:
	if _drag_mode == DragMode.KEYS and _drag_moved:
		var tracks: Array = []
		var keys: Array = []
		var old_times: Array = []
		var new_times: Array = []
		for i in range(_selection.size()):
			var key: MotionKey = _selection[i]["key"]
			if is_equal_approx(key.time, _drag_start_times[i]):
				continue
			tracks.append(_selection[i]["track"])
			keys.append(key)
			old_times.append(_drag_start_times[i])
			new_times.append(key.time)
		if not keys.is_empty():
			keys_dragged.emit(tracks, keys, old_times, new_times)
	_drag_mode = DragMode.NONE
	_drag_moved = false


func _set_playhead_from_x(x: float) -> void:
	var t := maxf(0.0, x_to_time(x))
	if snap_enabled:
		t = timeline.snap_to_frame(t)
	playhead = clampf(t, 0.0, timeline.duration)
	playhead_moved.emit(playhead)


func _zoom_at(anchor_x: float, factor: float) -> void:
	var anchor_time := x_to_time(anchor_x)
	pixels_per_second = clampf(pixels_per_second * factor, MIN_PPS, MAX_PPS)
	pan_time = maxf(0.0, anchor_time - (anchor_x - GUTTER_W) / pixels_per_second)


## Fits the authored duration to the visible lane width.
func zoom_to_fit() -> void:
	if timeline == null:
		return
	var lane_w := maxf(64.0, size.x - GUTTER_W - 16.0)
	pixels_per_second = clampf(lane_w / maxf(0.1, timeline.duration), MIN_PPS, MAX_PPS)
	pan_time = 0.0
	queue_redraw()
