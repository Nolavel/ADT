# =============================================================================
# key_hints_panel.gd — KeyHintsPanel.
#
# Bottom-center strip of "key — what it does" rows, visible whenever
# InputSystems.key_hints_enabled is true (docs/scope_horizon.md H2). A
# collaborator cannot evaluate a build whose controls are undiscoverable —
# this is what makes them discoverable.
#
# Instanced inside player_hud.tscn rather than added as a separate
# WORLD_UI_SCENES entry — PlayerHUD already owns a world-UI lifecycle, a
# second one would duplicate it for no reason.
#
# DATA-DRIVEN: rows come from a KeyHintsCatalog resource (catalog export,
# res://data/key_hints.tres by convention), not a hardcoded per-state
# switch — the valid-action combinations keep changing as modes/stances are
# added, and a code switch would need editing every time one does.
#
# REBUILDS ONLY ON SIGNAL: PlayerState.mode_changed / view_mode_changed /
# stance_changed / aiming_changed, never every frame. Each rebuild diffs the
# newly-active entry set against the rows already on screen (keyed by
# KeyHintEntry.get_row_key()) instead of clearing and recreating the whole
# row list, so a stance flip that only adds or drops one entry doesn't flash
# the rows that stayed valid.
#
# GROUPING: an entry can describe several actions that share one meaning
# (KeyHintEntry.action_names, e.g. WASD → "Move") — their key labels are
# joined into one cell instead of costing one row each. See
# _resolve_entry_key_label().
#
# SELF-CONTAINED: unlike the rest of player_hud.gd, this reads PlayerState
# and InputSystems directly in _ready() rather than waiting for
# on_world_ready(context) — both are autoloads, always present, and nothing
# here needs the player/camera a WorldContext would hand over.
#
# Dependencies: PlayerState, InputSystems (both autoloads).
# =============================================================================
class_name KeyHintsPanel
extends PanelContainer

## Button index → short label, for the physical buttons every mouse has.
## Anything else (a fifth+ side button) falls back to "MB<index>" in
## _format_mouse_button_label().
const _MOUSE_BUTTON_LABELS: Dictionary = {
	MOUSE_BUTTON_LEFT: "LMB",
	MOUSE_BUTTON_RIGHT: "RMB",
	MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel ↑",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel ↓",
	MOUSE_BUTTON_WHEEL_LEFT: "Wheel ←",
	MOUSE_BUTTON_WHEEL_RIGHT: "Wheel →",
	MOUSE_BUTTON_XBUTTON1: "MB4",
	MOUSE_BUTTON_XBUTTON2: "MB5",
}

@export var catalog: KeyHintsCatalog

@export_group("Style")
@export var background_color: Color = Color(0.05, 0.05, 0.05, 0.72)
@export var key_color: Color = Color(0.95, 0.82, 0.35, 1.0)
@export var description_color: Color = Color(0.88, 0.88, 0.88, 1.0)
@export var font_size: int = 14
## Joins the individual key labels of a grouped entry (KeyHintEntry.
## action_names) into one cell, e.g. "W / A / S / D". The single place this
## separator is defined — nowhere else repeats it.
@export var group_key_separator: String = " / "
## Horizontal gap between a row's key label and its description.
@export var key_description_gap: float = 6.0
## Horizontal gap between rows.
@export var row_gap: float = 20.0
## Panel padding around the row list.
@export var panel_padding: Vector2 = Vector2(16.0, 8.0)
## Distance from the bottom of the screen to the panel.
@export var bottom_margin: float = 16.0

@onready var _rows_box: HBoxContainer = $Rows

## One shared monospace font for every key label — see _build_mono_font().
var _mono_font: Font = null

## KeyHintEntry.get_row_key() → row Control currently on screen, for the
## diffed rebuild.
var _rows: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_box.add_theme_constant_override("separation", int(row_gap))
	_mono_font = _build_mono_font()
	_apply_background_style()

	resized.connect(_reposition)
	get_viewport().size_changed.connect(_reposition)

	PlayerState.mode_changed.connect(_on_mode_changed)
	PlayerState.view_mode_changed.connect(_on_view_mode_changed)
	PlayerState.stance_changed.connect(_on_stance_changed)
	PlayerState.aiming_changed.connect(_on_aiming_changed)
	InputSystems.key_hints_enabled_changed.connect(_on_enabled_changed)

	visible = InputSystems.key_hints_enabled
	_rebuild()
	_reposition()


func _on_mode_changed(_old_mode: PlayerState.Mode, _new_mode: PlayerState.Mode) -> void:
	_rebuild()


func _on_view_mode_changed(_old_view: PlayerState.ViewMode, _new_view: PlayerState.ViewMode) -> void:
	_rebuild()


func _on_stance_changed(_old_stance: PlayerState.Stance, _new_stance: PlayerState.Stance) -> void:
	_rebuild()


func _on_aiming_changed(_is_aiming: bool) -> void:
	_rebuild()


func _on_enabled_changed(enabled: bool) -> void:
	visible = enabled


## Diffs the newly-active KeyHintEntry set against the rows already shown —
## adds/removes/reorders only what changed, never clears the whole list.
func _rebuild() -> void:
	if catalog == null:
		push_warning("[KeyHintsPanel] no catalog assigned — panel stays empty")
		return

	var active := catalog.get_active_entries(
			PlayerState.mode, PlayerState.view_mode, PlayerState.stance, PlayerState.is_aiming)

	var wanted: Array[StringName] = []
	for entry in active:
		wanted.append(entry.get_row_key())

	# Dictionary.keys() materializes a fresh Array each call, so this is safe
	# to iterate while erasing from _rows below — it is not a live view.
	for row_key in _rows.keys():
		if not wanted.has(row_key):
			var stale_row: Control = _rows[row_key]
			stale_row.queue_free()
			_rows.erase(row_key)

	for i in active.size():
		var entry := active[i]
		var row_key := entry.get_row_key()
		var row: Control = _rows.get(row_key) as Control
		if row == null:
			row = _make_row(entry)
			_rows_box.add_child(row)
			_rows[row_key] = row
		_rows_box.move_child(row, i)

	_reposition()


func _make_row(entry: KeyHintEntry) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % entry.get_row_key()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(key_description_gap))

	var key_label := Label.new()
	key_label.text = "[%s]" % _resolve_entry_key_label(entry)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_label.add_theme_font_override("font", _mono_font)
	key_label.add_theme_font_size_override("font_size", font_size)
	key_label.add_theme_color_override("font_color", key_color)
	row.add_child(key_label)

	var desc_label := Label.new()
	desc_label.text = entry.description
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_label.add_theme_font_size_override("font_size", font_size)
	desc_label.add_theme_color_override("font_color", description_color)
	row.add_child(desc_label)

	return row


## The key cell for one entry: one resolved label for a single-action entry,
## or every action's label joined by group_key_separator for a grouped one
## (KeyHintEntry.action_names), e.g. "W / A / S / D".
func _resolve_entry_key_label(entry: KeyHintEntry) -> String:
	var labels: Array[String] = []
	for action_name in entry.get_action_names():
		labels.append(_resolve_key_label(action_name))
	return _join_labels(labels, group_key_separator)


func _join_labels(labels: Array[String], separator: String) -> String:
	var joined := ""
	for i in labels.size():
		if i > 0:
			joined += separator
		joined += labels[i]
	return joined


## Resolves the on-screen label for one action straight from InputMap, so a
## rebind is reflected without touching this panel or its catalog.
##
## An action can carry several bound events (keyboard, mouse, wheel, and in
## principle a gamepad). Keyboard wins when there's a choice — it is always
## the most universally-recognizable label — with the first event of any
## other kind as fallback; no action in today's catalog is actually bound
## to more than one device, so this only matters going forward.
func _resolve_key_label(action_name: StringName) -> String:
	if action_name == &"" or not InputMap.has_action(action_name):
		return "?"
	var events := InputMap.action_get_events(action_name)
	if events.is_empty():
		return "?"
	return _format_event_label(_pick_display_event(events))


func _pick_display_event(events: Array) -> InputEvent:
	for event in events:
		if event is InputEventKey:
			return event
	return events[0]


func _format_event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		return _format_key_label(event as InputEventKey)
	if event is InputEventMouseButton:
		return _format_mouse_button_label(event as InputEventMouseButton)
	return event.as_text().strip_edges()


## Strips as_text()'s occasional "(Physical)"-style parenthetical — a
## reviewer doesn't need to know a binding came from a physical keycode,
## only which key to press.
func _format_key_label(event: InputEventKey) -> String:
	var text := event.as_text()
	var paren_index := text.find(" (")
	if paren_index != -1:
		text = text.substr(0, paren_index)
	return text.strip_edges()


func _format_mouse_button_label(event: InputEventMouseButton) -> String:
	if _MOUSE_BUTTON_LABELS.has(event.button_index):
		return _MOUSE_BUTTON_LABELS[event.button_index]
	return "MB%d" % event.button_index


func _reposition() -> void:
	var viewport_size := get_viewport_rect().size
	global_position = Vector2(
			(viewport_size.x - size.x) / 2.0,
			viewport_size.y - size.y - bottom_margin
	)


func _apply_background_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.content_margin_left = panel_padding.x
	style.content_margin_right = panel_padding.x
	style.content_margin_top = panel_padding.y
	style.content_margin_bottom = panel_padding.y
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)


## SystemFont, not a bundled asset: this panel is a working tool for showing
## the build to a reviewer, not final UI (see this file's own header) — not
## worth shipping a font file for. Falls back to the platform default if
## none of these are installed, same as any other SystemFont use.
func _build_mono_font() -> Font:
	var system_font := SystemFont.new()
	system_font.font_names = ["Consolas", "Courier New", "DejaVu Sans Mono", "monospace"]
	return system_font
