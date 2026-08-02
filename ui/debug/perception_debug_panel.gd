# =============================================================================
# PerceptionDebugPanel.gd
# Screen-space debug overlay, one Control living in WORLD_UI_SCENES — split
# out of stream_debug_panel.gd's lock-on section rather than added to it,
# per that file's own note that a third unrelated section should become its
# own panel. This one is about NPCs, not the camera.
#
# Pure observer: for every NPCBase in the scene, calls its
# PerceptionComponent.observe_player() (a plain fact, see
# player_observation.gd) and, ONLY for display, works out which check would
# have rejected the player — range, cone or line-of-sight — from that fact
# plus the component's own public vision_range/vision_angle_deg. This is
# still not perception deciding anything: the component itself never
# reports "why", the panel derives it purely for a human to read.
#
# UI built in _ready() by code, same convention as stream_debug_panel.gd —
# a debug tool, not something styled in the editor.
#
# Root mouse_filter = IGNORE: sits over the viewport, must not eat
# click-to-move clicks.
#
# Toggle: InputSystems.perception_debug_toggled (action
# "toggle_perception_debug" in Input Map).
# =============================================================================
extends Control

const REDRAW_INTERVAL := 0.25

var _redraw_timer: float = 0.0
var _text: RichTextLabel


func _ready() -> void:
	_build_ui()
	InputSystems.perception_debug_toggled.connect(_on_toggle)


func _on_toggle() -> void:
	visible = not visible


func _process(delta: float) -> void:
	if not visible:
		return

	_redraw_timer += delta
	if _redraw_timer < REDRAW_INTERVAL:
		return
	_redraw_timer = 0.0

	_redraw()


func _redraw() -> void:
	var npcs: Array[NPCBase] = []
	for candidate in get_tree().get_nodes_in_group("lockable"):
		if candidate is NPCBase:
			npcs.append(candidate)

	if npcs.is_empty():
		_text.text = "[color=#777777]— no NPCs in scene —[/color]"
		return

	var lines: Array[String] = []
	for npc in npcs:
		lines.append(_describe_npc(npc))

	_text.text = "\n\n".join(lines)


func _describe_npc(npc: NPCBase) -> String:
	var perception: PerceptionComponent = null
	for child in npc.get_children():
		if child is PerceptionComponent:
			perception = child
			break

	if not perception:
		return "%s: [color=#ff6666]no PerceptionComponent[/color]" % npc.name

	var observation := perception.observe_player()
	if observation.distance == INF:
		return "%s: [color=#777777]no player in scene[/color]" % npc.name

	var seen_color := "#35ff66" if observation.is_seen else "#ff6666"
	var seen_text := "YES" if observation.is_seen else "no"

	var line := "%s   dist %.1fm / %.1fm   angle %.0f° / %.0f°   is_seen: [color=%s]%s[/color]" % [
		npc.name,
		observation.distance, perception.vision_range,
		observation.angle_deg, perception.vision_angle_deg * 0.5,
		seen_color, seen_text,
	]

	if not observation.is_seen:
		line += "\n  rejected by: %s" % _rejection_reason(observation, perception)

	line += "\n  %s" % _describe_body_turn(npc, observation)

	return line


## Body-turn debug: how long the player has been continuously visible,
## whether the body has actually committed to a facing target, and the
## current body-to-player angle. Without this, "the body didn't turn" reads
## identically to "it's broken" — the same story lock-on debugging had
## before it got its own overlay.
func _describe_body_turn(npc: NPCBase, observation: PlayerObservation) -> String:
	var facing_color := "#35ff66" if npc.has_facing_target() else "#777777"
	var facing_text := "YES" if npc.has_facing_target() else "no"

	## visible_time is IdleNPCController's own bookkeeping, not NPCBase's —
	## a future controller type may track it differently or not at all, so
	## this degrades to "n/a" instead of assuming every NPC has one.
	var idle_controller: IdleNPCController = null
	for child in npc.get_children():
		if child is IdleNPCController:
			idle_controller = child
			break

	var visible_text: String
	if idle_controller:
		visible_text = "%.1fs" % idle_controller.get_visible_time()
	else:
		visible_text = "n/a"

	return "visible %s   facing_target: [color=%s]%s[/color]   body angle %.0f°" % [
		visible_text, facing_color, facing_text, observation.angle_deg,
	]


## Derives which check would have rejected the player, purely for display —
## observation itself never says "why", only is_seen/distance/angle_deg.
func _rejection_reason(observation: PlayerObservation, perception: PerceptionComponent) -> String:
	if observation.distance > perception.vision_range:
		return "range"
	if observation.angle_deg > perception.vision_angle_deg * 0.5:
		return "cone"
	return "line of sight (wall/floor between eye and chest)"


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored to the top-right corner instead of a guessed pixel offset
	# below stream_debug_panel.gd's panel — avoids overlapping it without
	# knowing that panel's exact rendered height, and stays correct at any
	# viewport size.
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -380.0
	panel.offset_top = 8.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.content_margin_left   = 10
	style.content_margin_right  = 10
	style.content_margin_top    = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var header := Label.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.text = "NPC PERCEPTION"
	header.add_theme_font_size_override("font_size", 13)
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.custom_minimum_size = Vector2(360, 0)
	_text.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(_text)
