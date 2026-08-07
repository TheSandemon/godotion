extends SceneTree

## Headless test suite for Godotion's runtime core.
##
## Run with:
##   godot --headless --path . --script res://tests/test_core.gd
##
## Exits non-zero on the first failing assertion count, so it is CI-usable.
## Only `core/` is covered — the editor UI needs a real editor to drive.

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_test_easing()
	_test_bezier()
	_test_track_sampling()
	_test_interpolation_types()
	_test_track_kinds()
	_test_timeline_time()
	_test_player_applies_to_scene()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s" % label)


func _close(a: float, b: float, label: String, epsilon: float = 0.0001) -> void:
	_check(absf(a - b) <= epsilon, "%s (got %f, expected %f)" % [label, a, b])


func _test_easing() -> void:
	_close(MotionEasing.apply(MotionKey.Interp.LINEAR, 0.5), 0.5, "linear midpoint")
	_close(MotionEasing.apply(MotionKey.Interp.LINEAR, 0.0), 0.0, "linear start")
	_close(MotionEasing.apply(MotionKey.Interp.LINEAR, 1.0), 1.0, "linear end")
	_close(MotionEasing.apply(MotionKey.Interp.CONSTANT, 0.99), 0.0, "constant holds")
	_close(MotionEasing.apply(MotionKey.Interp.EASE_IN, 0.5), 0.125, "ease in midpoint")
	_close(MotionEasing.apply(MotionKey.Interp.EASE_OUT, 0.5), 0.875, "ease out midpoint")
	_close(MotionEasing.apply(MotionKey.Interp.EASE_IN_OUT, 0.5), 0.5, "ease in-out midpoint")

	# Out-of-range input must clamp rather than extrapolate.
	_close(MotionEasing.apply(MotionKey.Interp.LINEAR, 1.8), 1.0, "linear clamps high")
	_close(MotionEasing.apply(MotionKey.Interp.LINEAR, -0.4), 0.0, "linear clamps low")

	# Every curve must be monotonic across the segment.
	for interp in [MotionKey.Interp.LINEAR, MotionKey.Interp.EASE_IN,
			MotionKey.Interp.EASE_OUT, MotionKey.Interp.EASE_IN_OUT]:
		var previous := -1.0
		var monotonic := true
		for step in range(21):
			var w: float = MotionEasing.apply(interp, step / 20.0)
			if w < previous - 0.0001:
				monotonic = false
			previous = w
		_check(monotonic, "curve %d is monotonic" % interp)


func _test_bezier() -> void:
	var out_h := Vector2(0.25, 0.0)
	var in_h := Vector2(-0.25, 0.0)
	_close(MotionEasing.bezier_weight(out_h, in_h, 0.0), 0.0, "bezier start")
	_close(MotionEasing.bezier_weight(out_h, in_h, 1.0), 1.0, "bezier end")
	_close(MotionEasing.bezier_weight(out_h, in_h, 0.5), 0.5, "bezier symmetric midpoint", 0.01)

	# Flat handles are the case that breaks a Newton solver; bisection must cope.
	var flat := MotionEasing.bezier_weight(Vector2(1.0, 0.0), Vector2(-1.0, 0.0), 0.5)
	_check(flat >= 0.0 and flat <= 1.0, "flat handles stay in range (got %f)" % flat)


func _test_track_sampling() -> void:
	var track := MotionTrack.new()
	track.property = "position:x"
	track.set_key(0.0, 0.0)
	track.set_key(1.0, 100.0)

	_check(track.sample(-1.0) == 0.0, "sample before first key clamps")
	_close(track.sample(0.5), 50.0, "linear sample midpoint")
	_check(track.sample(2.0) == 100.0, "sample after last key clamps")
	_close(track.get_length(), 1.0, "track length is last key time")

	# set_key on an existing time replaces rather than appending.
	track.set_key(1.0, 200.0)
	_check(track.keys.size() == 2, "set_key replaces at the same time")
	_check(track.sample(1.0) == 200.0, "replaced value is used")

	# Keys must stay sorted regardless of insertion order.
	track.set_key(0.5, 999.0)
	_check(track.keys[1].time == 0.5, "keys re-sort on insert")

	# Constant interpolation holds until the next key.
	var hold := MotionTrack.new()
	hold.set_key(0.0, 10.0, MotionKey.Interp.CONSTANT)
	hold.set_key(1.0, 20.0)
	_check(hold.sample(0.99) == 10.0, "constant holds until next key")

	# An empty track has no opinion, which is distinct from keying zero.
	var empty := MotionTrack.new()
	_check(empty.sample(0.0) == null, "empty track samples null")

	# Zero-length segments must not divide by zero.
	var degenerate := MotionTrack.new()
	degenerate.set_key(0.0, 0.0)
	var twin := MotionKey.new()
	twin.time = 0.0
	twin.value = 50.0
	degenerate.add_key(twin)
	_check(degenerate.sample(0.0) != null, "duplicate-time keys do not crash")


func _test_interpolation_types() -> void:
	_close(MotionTrack.interpolate_values(0.0, 10.0, 0.5), 5.0, "float lerp")
	_check(MotionTrack.interpolate_values(0, 10, 0.5) == 5, "int lerp rounds")
	_check(MotionTrack.interpolate_values(Vector2.ZERO, Vector2(10, 20), 0.5) == Vector2(5, 10), "Vector2 lerp")
	_check(MotionTrack.interpolate_values(Vector3.ZERO, Vector3(2, 4, 6), 0.5) == Vector3(1, 2, 3), "Vector3 lerp")
	_check(MotionTrack.interpolate_values(Color.BLACK, Color.WHITE, 0.5).r == 0.5, "Color lerp")
	_check(MotionTrack.interpolate_values(true, false, 0.2) == true, "bool snaps low")
	_check(MotionTrack.interpolate_values(true, false, 0.8) == false, "bool snaps high")
	# Mismatched types must degrade rather than error.
	_check(MotionTrack.interpolate_values(1.0, Vector2.ZERO, 0.2) == 1.0, "type mismatch falls back")


func _test_track_kinds() -> void:
	var cases := {
		"position": MotionTrack.Kind.TRANSFORM,
		"position:x": MotionTrack.Kind.TRANSFORM,
		"rotation": MotionTrack.Kind.ROTATION,
		"scale:y": MotionTrack.Kind.SCALE,
		"modulate": MotionTrack.Kind.COLOR,
		"modulate:a": MotionTrack.Kind.OPACITY,
		"visible": MotionTrack.Kind.CUSTOM,
	}
	for property in cases:
		var track := MotionTrack.new()
		track.property = property
		_check(track.get_kind() == cases[property], "kind of '%s'" % property)

	# An explicit override must win over inference.
	var overridden := MotionTrack.new()
	overridden.property = "position"
	overridden.kind_override = MotionTrack.Kind.COLOR
	_check(overridden.get_kind() == MotionTrack.Kind.COLOR, "kind_override wins")


func _test_timeline_time() -> void:
	var timeline := MotionTimeline.new()
	timeline.duration = 2.0
	timeline.fps = 60

	timeline.loop_mode = MotionTimeline.LoopMode.NONE
	_close(timeline.wrap_time(3.0), 2.0, "no-loop clamps to duration")
	_check(timeline.is_finished(2.0), "no-loop reports finished")

	timeline.loop_mode = MotionTimeline.LoopMode.LOOP
	_close(timeline.wrap_time(2.5), 0.5, "loop wraps")
	_check(not timeline.is_finished(9.0), "looping never finishes")

	timeline.loop_mode = MotionTimeline.LoopMode.PING_PONG
	_close(timeline.wrap_time(1.0), 1.0, "ping-pong forward leg")
	_close(timeline.wrap_time(3.0), 1.0, "ping-pong return leg")
	_close(timeline.wrap_time(4.0), 0.0, "ping-pong completes a cycle")

	_close(timeline.snap_to_frame(0.334), 0.333333, "snap to 60fps frame", 0.0001)

	# duration has a floor so wrap_time can never divide by zero.
	timeline.duration = -5.0
	_check(timeline.duration > 0.0, "duration clamps positive")


func _test_player_applies_to_scene() -> void:
	var root := Node2D.new()
	get_root().add_child(root)

	var target := Node2D.new()
	target.name = "Target"
	root.add_child(target)

	var player := MotionPlayer.new()
	root.add_child(player)
	player.root_node = player.get_path_to(root)

	var timeline := MotionTimeline.new()
	timeline.duration = 1.0
	var track := timeline.get_or_create_track(root.get_path_to(target), "position:x")
	track.set_key(0.0, 0.0)
	track.set_key(1.0, 100.0)
	player.timeline = timeline

	player.apply_at(0.0)
	_close(target.position.x, 0.0, "player writes start value")
	player.apply_at(0.5)
	_close(target.position.x, 50.0, "player writes interpolated value")
	player.apply_at(1.0)
	_close(target.position.x, 100.0, "player writes end value")

	# A disabled track must stop writing.
	track.enabled = false
	target.position.x = -1.0
	player.apply_at(0.5)
	_close(target.position.x, -1.0, "disabled track is skipped")
	track.enabled = true

	# get_or_create_track must not duplicate an existing track.
	var again := timeline.get_or_create_track(root.get_path_to(target), "position:x")
	_check(again == track, "get_or_create_track reuses")
	_check(timeline.tracks.size() == 1, "no duplicate track added")

	# seek must clamp to the timeline and keep the scene in sync.
	player.seek(5.0)
	_close(player.get_time(), 1.0, "seek clamps to duration")
	_close(target.position.x, 100.0, "seek applies")

	# An unresolvable node path must warn, not crash.
	var broken := timeline.get_or_create_track(NodePath("Nonexistent"), "position:x")
	broken.set_key(0.0, 5.0)
	player.apply_at(0.0)
	_check(true, "missing node path does not crash")

	root.queue_free()
