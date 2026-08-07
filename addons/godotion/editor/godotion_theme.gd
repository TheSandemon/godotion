@tool
extends RefCounted

# Deliberately no class_name: this script touches EditorInterface, which does
# not exist in exported builds. Keeping it out of the global class table means
# it is only ever parsed by the editor scripts that preload it.

## Bridges Godot's editor theme with Godotion's own track accents.
##
## Structural colours (panel background, separators, text) are pulled live from
## [code]EditorInterface.get_editor_theme()[/code] so the panel matches whatever
## editor theme the user runs. Only the per-track accents are ours, so track
## kinds stay identifiable across light and dark editors.

const ACCENTS := {
	MotionTrack.Kind.TRANSFORM: Color("5fb2ff"),
	MotionTrack.Kind.ROTATION: Color("c58bff"),
	MotionTrack.Kind.SCALE: Color("55d6a0"),
	MotionTrack.Kind.COLOR: Color("ff8f5f"),
	MotionTrack.Kind.OPACITY: Color("ffd166"),
	MotionTrack.Kind.CUSTOM: Color("9aa4b2"),
}

const KIND_NAMES := {
	MotionTrack.Kind.TRANSFORM: "Transform",
	MotionTrack.Kind.ROTATION: "Rotation",
	MotionTrack.Kind.SCALE: "Scale",
	MotionTrack.Kind.COLOR: "Color",
	MotionTrack.Kind.OPACITY: "Opacity",
	MotionTrack.Kind.CUSTOM: "Custom",
}


static func accent_for(track: MotionTrack) -> Color:
	if track == null:
		return ACCENTS[MotionTrack.Kind.CUSTOM]
	return ACCENTS.get(track.get_kind(), ACCENTS[MotionTrack.Kind.CUSTOM])


static func editor_theme() -> Theme:
	if not Engine.is_editor_hint():
		return null
	return EditorInterface.get_editor_theme()


static func color(name: StringName, fallback: Color) -> Color:
	var theme := editor_theme()
	if theme != null and theme.has_color(name, &"Editor"):
		return theme.get_color(name, &"Editor")
	return fallback


static func font() -> Font:
	var theme := editor_theme()
	if theme != null and theme.has_font(&"main", &"EditorFonts"):
		return theme.get_font(&"main", &"EditorFonts")
	return ThemeDB.fallback_font


static func font_size() -> int:
	var theme := editor_theme()
	if theme != null and theme.has_font_size(&"main_size", &"EditorFonts"):
		return theme.get_font_size(&"main_size", &"EditorFonts")
	return ThemeDB.fallback_font_size


## Editor icon lookup with a graceful fallback chain, so unknown or custom
## classes still render something rather than crashing the draw pass.
static func icon(name: StringName) -> Texture2D:
	var theme := editor_theme()
	if theme == null:
		return null
	if theme.has_icon(name, &"EditorIcons"):
		return theme.get_icon(name, &"EditorIcons")
	return theme.get_icon(&"Node", &"EditorIcons")


## Resolves the editor icon for a live node, walking up its inheritance chain
## until an icon exists. This is what gives each track row its native branding.
static func icon_for_node(node: Node) -> Texture2D:
	if node == null:
		return icon(&"NodeWarning")
	var theme := editor_theme()
	if theme == null:
		return null
	var script := node.get_script() as Script
	if script != null:
		var global_name := script.get_global_name()
		if global_name != StringName() and theme.has_icon(global_name, &"EditorIcons"):
			return theme.get_icon(global_name, &"EditorIcons")
	var cls := node.get_class()
	while cls != "":
		if theme.has_icon(cls, &"EditorIcons"):
			return theme.get_icon(cls, &"EditorIcons")
		cls = ClassDB.get_parent_class(cls)
	return theme.get_icon(&"Node", &"EditorIcons")
