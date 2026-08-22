# =============================================================================
# PerceptionDebugPanel.gd
# Screen-space debug overlay, one Control living in WORLD_UI_SCENES — split
# out of stream_debug_panel.gd's lock-on section rather than added to it,
# per that file's own note that a third unrelated section should become its
# own panel. This one is about perceived actors, not the camera.
#
# Pure observer: for every ActorBase in the scene (NPCs and police drones
# alike, one shared list tagged by type — they share the same perception,
# a second panel would just be the same rows twice) calls its
# PerceptionComponent.observe_player() (a plain fact, see
# player_observation.gd) and, ONLY for display, works out which check would
# have rejected the player — range, cone or line-of-sight — from that fact
# plus the component's own public vision_range/vision_angle_deg. This is
# still not perception deciding anything: the component itself never
# reports "why", the panel derives it purely for a human to read.
#
# Enumerates ActorBase.GROUP_PERCEIVED_ACTOR, not the "lockable" group
# NPCBase also joins — "lockable" is the combat camera's lock-on pool and
# does not include drones by design; see actor_base.gd's own comment.
#
# UI built in _ready() by code, same convention as stream_debug_panel.gd —
# a debug tool, not something styled in the editor.
#
# Root mouse_filter = IGNORE: sits over the viewport, must not eat
# click-to-move clicks.
#
# Toggle: InputSystems.perception_debug_toggled (action
# "toggle_perception_debug" in Input Map).
#
# Also reports what perception alone can't: the last IncidentRegistry entry
# (global, resolved via on_world_ready() — a WORLD_UI_SCENES entry gets one,
# unlike PatrolDroneController), each NPCBase's knocked-down state, and per
# drone, why it's in ALERT (incident memory, never a raised stance anymore)
# and whether its spotlight is lit.
#
# WHILE an IdleNPCController is in ReactionState.CALLING (docs/attribution.md
# §7), also shows why its active WitnessReport got the observation_level it
# got — distance, whether it was in FOV at all, and the resulting ceiling —
# plus the report's own PENDING/COMMITTED/CANCELLED status and time
# remaining. This is the only place any of that is visible; the player never
# sees it, and WitnessReport itself is never logged.
# =============================================================================
extends Control

const REDRAW_INTERVAL := 0.25

var _redraw_timer: float = 0.0
var _text: RichTextLabel
## Resolved via WorldContext (WORLD_UI_SCENES entries get on_world_ready(),
## unlike PatrolDroneController — see that file's own comment on why it has
## to fall back to a group lookup instead). Null (and the last-incident line
## silently skipped) only in an isolated test scene without one.
var _incident_registry: IncidentRegistry = null
## Resolved the same way — needed to turn Incident.timestamp (game hours,
## since H1) into an age a human can read. See _describe_last_incident()'s
## own comment for why this can't just reuse Time.get_ticks_msec() anymore.
var _game_clock: GameClockSystem = null


func _ready() -> void:
	_build_ui()
	InputSystems.perception_debug_toggled.connect(_on_toggle)
	visible = false


func on_world_ready(context: WorldContext) -> void:
	_incident_registry = context.get_system(IncidentRegistry) as IncidentRegistry
	_game_clock = context.get_system(GameClockSystem) as GameClockSystem


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
	var actors: Array[ActorBase] = []
	for candidate in get_tree().get_nodes_in_group(ActorBase.GROUP_PERCEIVED_ACTOR):
		if candidate is ActorBase:
			actors.append(candidate)

	## Global, not per-row — same value for every actor's observation.stance
	## — but worth its own line: stance is still what idle_npc_controller.gd's
	## own glance/turn gate reacts to, even though it no longer triggers a
	## drone's ALERT on its own (see patrol_drone_controller.gd's header).
	var header := "player stance: %s" % PlayerState.Stance.keys()[PlayerState.stance]
	header += "\n" + _describe_last_incident()

	if actors.is_empty():
		_text.text = header + "\n\n[color=#777777]— no NPCs or drones in scene —[/color]"
		return

	var lines: Array[String] = []
	for actor in actors:
		lines.append(_describe_actor(actor))

	_text.text = header + "\n\n" + "\n\n".join(lines)


## "last incident: ASSAULT 0.05h ago" or "no incidents recorded" — global,
## same reasoning as the stance line above. Incident.timestamp is game hours
## (GameClockSystem.total_game_hours) as of H1 (docs/scope_horizon.md), not
## Time.get_ticks_msec() — see incident_registry.gd's own header for why a
## durable record can't be timestamped in a clock that resets on launch. Age
## is therefore read against GameClockSystem here too, not computed from
## engine uptime.
func _describe_last_incident() -> String:
	if not _incident_registry:
		return "last incident: [color=#777777]no IncidentRegistry in scene[/color]"

	var incident := _incident_registry.get_latest_incident()
	if incident == null:
		return "last incident: [color=#777777]none recorded[/color]"

	if not _game_clock:
		return "last incident: %s   [color=#777777]no GameClockSystem in scene[/color]" \
				% Incident.Kind.keys()[incident.kind]

	var age_hours := _game_clock.total_game_hours - incident.timestamp
	return "last incident: %s   %.2fh ago" % [Incident.Kind.keys()[incident.kind], age_hours]


func _describe_actor(actor: ActorBase) -> String:
	var perception: PerceptionComponent = null
	for child in actor.get_children():
		if child is PerceptionComponent:
			perception = child
			break

	var type_label := actor.get_debug_type_label()

	if not perception:
		return "[%s] %s: [color=#ff6666]no PerceptionComponent[/color]" % [type_label, actor.name]

	var observation := perception.observe_player()
	if observation.distance == INF:
		return "[%s] %s: [color=#777777]no player in scene[/color]" % [type_label, actor.name]

	var seen_color := "#35ff66" if observation.is_seen else "#ff6666"
	var seen_text := "YES" if observation.is_seen else "no"

	var line := "[%s] %s   dist %.1fm / %.1fm   angle %.0f° / %.0f°   is_seen: [color=%s]%s[/color]" % [
		type_label, actor.name,
		observation.distance, perception.vision_range,
		observation.angle_deg, perception.vision_angle_deg * 0.5,
		seen_color, seen_text,
	]

	if not observation.is_seen:
		line += "\n  rejected by: %s" % _rejection_reason(observation, perception)

	line += "\n  %s" % _describe_controller_state(actor, observation)

	## NPCBase-only — take_hit()/is_knocked_down() isn't on ActorBase, see
	## that file's own header on why (no drone equivalent exists).
	if actor is NPCBase:
		var npc: NPCBase = actor
		var down := npc.is_knocked_down()
		var down_color := "#ff6666" if down else "#777777"
		line += "\n  knocked down: [color=%s]%s[/color]" % [down_color, "YES" if down else "no"]

	return line


## Dispatches on whichever controller type the actor actually has —
## IdleNPCController and PatrolDroneController expose incompatible extra
## state (facing_target vs. ALERT memory), so there is no single shared
## description, only a shared slot for one.
func _describe_controller_state(actor: ActorBase, observation: PlayerObservation) -> String:
	var idle_controller: IdleNPCController = null
	var drone_controller: PatrolDroneController = null
	for child in actor.get_children():
		if child is IdleNPCController:
			idle_controller = child
		elif child is PatrolDroneController:
			drone_controller = child

	if idle_controller:
		return _describe_idle_controller(actor, idle_controller, observation)
	if drone_controller:
		return _describe_drone_controller(drone_controller)
	return "controller: n/a"


## Body-turn debug: how long the player has been continuously visible,
## whether the body has actually committed to a facing target, and the
## current body-to-player angle. Without this, "the body didn't turn" reads
## identically to "it's broken" — the same story lock-on debugging had
## before it got its own overlay. has_facing_target() is NPCBase-only (not
## on ActorBase — DroneBase orients its mesh via look target alone, there
## is no separate facing-target concept), hence the cast.
func _describe_idle_controller(
	actor: ActorBase, controller: IdleNPCController, observation: PlayerObservation
) -> String:
	var npc := actor as NPCBase
	var has_facing := npc != null and npc.has_facing_target()
	var facing_color := "#35ff66" if has_facing else "#777777"
	var facing_text := "YES" if has_facing else "no"

	var line := "state: %s   visible %.1fs   facing_target: [color=%s]%s[/color]   body angle %.0f°" % [
		controller.get_state_name(), controller.get_visible_time(),
		facing_color, facing_text, observation.angle_deg,
	]

	if controller.has_active_witness_report():
		line += "\n" + _describe_witness_report(controller)

	return line


## docs/attribution.md §7's debug panel format, adapted to this panel's own
## layout — WITNESS (the inputs _resolve_observation_level() used) and
## REPORT (the resolved WitnessReport's own state). "actor UNRESOLVED" is a
## fixed label, not read off anything: WitnessReport has no field a suspect
## could go in (see witness_report.gd's own header), so this line exists
## purely to make that boundary visible to whoever is reading the panel.
##
## "in FOV" replaces what used to be an "attention" line — a witness only
## ever gets this far (has an active report to describe at all) once
## _is_incident_in_vision_cone() already gated them in, so this always reads
## true today; it is shown anyway, as a plain fact, rather than assumed. See
## idle_npc_controller.gd's own header on why "facing away" no longer
## quietly downgrades a report instead of blocking it.
func _describe_witness_report(controller: IdleNPCController) -> String:
	var remaining := controller.get_witness_report_remaining()
	var remaining_text := "  (%.1fs remaining)" % remaining if remaining >= 0.0 else ""
	return (
		"  WITNESS\n"
		+ "    distance   %.1f m\n" % controller.get_witness_distance()
		+ "    in FOV     %s\n" % controller.get_witness_in_cone_text()
		+ "    ceiling    %s\n" % controller.get_witness_ceiling_name()
		+ "    result     %s\n" % controller.get_witness_observation_level_name()
		+ "  REPORT\n"
		+ "    actor      UNRESOLVED\n"
		+ "    status     %s%s" % [controller.get_witness_report_status_name(), remaining_text]
	)


## ALERT is always held by incident memory now, never a raised stance — see
## patrol_drone_controller.gd's own header — so "what holds ALERT" is
## answered plainly rather than as a fake incident-vs-memory binary: it was
## triggered by an incident, and alert memory is how much longer before it
## lapses. Spotlight state is read through a getter, not the private
## _spotlight field, same encapsulation as get_alert_memory_remaining().
func _describe_drone_controller(controller: PatrolDroneController) -> String:
	var remaining := controller.get_alert_memory_remaining()
	var remaining_text := "%.1fs" % remaining if remaining >= 0.0 else "n/a"
	var spot_color := "#35ff66" if controller.is_spotlight_active() else "#777777"
	var spot_text := "YES" if controller.is_spotlight_active() else "no"
	return "state: %s   held by incident memory: %s   spotlight: [color=%s]%s[/color]" % [
		controller.get_state_name(), remaining_text, spot_color, spot_text,
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
