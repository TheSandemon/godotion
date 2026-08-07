@tool
extends EditorPlugin

## Godotion entry point.
##
## Registers the bottom panel and routes scene-tree selection of a
## [MotionPlayer] (or an inspected [MotionTimeline]) into it. The runtime
## classes register themselves through [code]class_name[/code], so no
## [method EditorPlugin.add_custom_type] calls are needed — adding them would
## collide with the global script classes.

const TimelinePanel := preload("res://addons/godotion/editor/timeline_panel.gd")

var _panel: VBoxContainer
var _panel_button: Button


func _enter_tree() -> void:
	_panel = TimelinePanel.new()
	_panel.name = "Godotion"
	_panel.undo_redo = get_undo_redo()
	_panel_button = add_control_to_bottom_panel(_panel, "Godotion")


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
	_panel_button = null


func _get_plugin_name() -> String:
	return "Godotion"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Animation", &"EditorIcons")


func _handles(object: Object) -> bool:
	return object is MotionPlayer or object is MotionTimeline


func _edit(object: Object) -> void:
	if _panel == null:
		return
	if object is MotionPlayer:
		_panel.edit_player(object)
	elif object is MotionTimeline:
		# Selecting the timeline sub-resource in the inspector must not unbind
		# the player it belongs to — Add Track and Key both need its root_node.
		_panel.edit_timeline(object)


func _make_visible(visible: bool) -> void:
	if _panel_button == null:
		return
	if visible:
		make_bottom_panel_item_visible(_panel)
	elif _panel.get_timeline() == null:
		hide_bottom_panel()
