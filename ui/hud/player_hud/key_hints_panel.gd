# =============================================================================
# key_hints_panel.gd — KeyHintsPanel.
#
# Bottom-center strip of key hints, visible whenever InputSystems.
# key_hints_enabled is true (docs/scope_horizon.md H2). A collaborator
# cannot evaluate a build whose controls are undiscoverable — this is what
# makes them discoverable.
#
# Instanced inside player_hud.tscn rather than added as a separate
# WORLD_UI_SCENES entry — PlayerHUD already owns a world-UI lifecycle, a
# second one would duplicate it for no reason.
#
# THREE COLUMNS, NOT ONE RIBBON: a flat horizontal row list forces the eye
# to scan the whole thing, since left-to-right position only ever encoded
# sort_order, not meaning. One column per KeyHintEntry.Category
# (MOVEMENT/ACTION/SYSTEM), built by iterating Category.values() — so
# column ORDER comes from the enum's declaration order, not a case
# statement here. Within a column, rows still sort by sort_order.
#
# DATA-DRIVEN: rows come from a KeyHintsCatalog resource (catalog export,
# res://data/key_hints.tres by convention), not a hardcoded per-state
# switch — the valid-action combinations keep changing as modes/stances are
# added, and a code switch would need editing every time one does.
#
# REBUILDS ONLY ON SIGNAL: PlayerState.mode_changed / view_mode_changed /
# stance_changed / aiming_changed, never every frame. Each rebuild diffs the
# newly-active entry set against the rows already on screen, PER COLUMN
# (keyed within that column by KeyHintEntry.get_row_key()) instead of
# clearing and recreating anything wholesale, so a stance flip that only
# adds or drops one entry doesn't flash the rows that stayed valid — same
# idea as before columns existed, just scoped to one column's own row list
# instead of the panel's single flat one. A column with zero active rows
# hides itself (header included) rather than leaving an empty slot in the
# layout.
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

## Qualifier suffixes InputEventKey.as_text() appends, longest first so a
## match cannot leave a dangling separator. See _format_key_label().
const _KEY_LABEL_SUFFIXES: Array[String] = [" - Physical", " (Physical)"]

## Button index → short label, for the physical buttons every mouse has.
## Anything else (a fifth+ side button) falls back to "MB<index>" in
## _format_mouse_button_label(). Wheel directions are spelled out in ASCII
## rather than drawn with ↑/↓/←/→: this label is rendered through
## _mono_font (a plain SystemFont request, see _build_mono_font()), and
## nothing here guarantees the resolved system font actually carries those
## Unicode Arrows-block glyphs — an unsupported glyph renders as an empty
## box, which is worse than a slightly longer label. Hypothesis, not a
## verified fact: not something this change could confirm by running the
## game.
const _MOUSE_BUTTON_LABELS: Dictionary = {
	MOUSE_BUTTON_LEFT: "LMB",
	MOUSE_BUTTON_RIGHT: "RMB",
	MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel Up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel Dn",
	MOUSE_BUTTON_WHEEL_LEFT: "Wheel Left",
	MOUSE_BUTTON_WHEEL_RIGHT: "Wheel Right",
	MOUSE_BUTTON_XBUTTON1: "MB4",
	MOUSE_BUTTON_XBUTTON2: "MB5",
}

## One VBoxContainer column (header + its own row list) for one
## KeyHintEntry.Category. Plain data holder — see _build_columns().
class _Column:
	var container: VBoxContainer
	var rows_list: VBoxContainer
	## KeyHintEntry.get_row_key() → row Control currently on screen in THIS
	## column, for the diffed rebuild — scoped per column so a row never
	## needs to be told apart from a same-named row in another column.
	var rows: Dictionary = {}

@export var catalog: KeyHintsCatalog

@export_group("Style")
@export var background_color: Color = Color(0.05, 0.05, 0.05, 0.72)
@export var key_color: Color = Color(0.95, 0.82, 0.35, 1.0)
@export var description_color: Color = Color(0.88, 0.88, 0.88, 1.0)
## Deliberately dimmer/smaller than the descriptions: a column header is a
## landmark for the eye, not content to read.
@export var header_color: Color = Color(0.55, 0.55, 0.55, 0.85)
@export var font_size: int = 14
@export var header_font_size: int = 11
## Joins the individual key labels of a grouped entry (KeyHintEntry.
## action_names) into one cell, e.g. "W / A / S / D". The single place this
## separator is defined — nowhere else repeats it.
@export var group_key_separator: String = " / "
## Horizontal gap between a row's key label and its description.
@export var key_description_gap: float = 6.0
## Vertical gap between rows within one column.
@export var row_gap: float = 8.0
## Horizontal gap between columns — deliberately a separate export from
## row_gap, which now governs spacing WITHIN a column instead.
@export var column_gap: float = 28.0
## Panel padding around the column list.
@export var panel_padding: Vector2 = Vector2(16.0, 8.0)
## Distance from the bottom of the screen to the panel.
@export var bottom_margin: float = 16.0

@onready var _columns_box: HBoxContainer = $Rows

## One shared monospace font for every key label — see _build_mono_font().
var _mono_font: Font = null

## KeyHintEntry.Category → _Column, one per category, built once in
## _build_columns() and never recreated — only their contents change.
var _columns: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columns_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columns_box.add_theme_constant_override("separation", int(column_gap))
	_mono_font = _build_mono_font()
	_apply_background_style()
	_build_columns()

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


## One column per KeyHintEntry.Category, in Category.values() order — the
## enum's declaration order is the only thing that decides column order,
## not anything written here.
func _build_columns() -> void:
	for category in KeyHintEntry.Category.values():
		var column := _Column.new()

		column.container = VBoxContainer.new()
		column.container.name = "Column_%s" % KeyHintEntry.Category.keys()[category]
		column.container.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var header := Label.new()
		header.text = KeyHintEntry.Category.keys()[category].capitalize()
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_theme_font_size_override("font_size", header_font_size)
		header.add_theme_color_override("font_color", header_color)
		column.container.add_child(header)

		column.rows_list = VBoxContainer.new()
		column.rows_list.name = "Rows"
		column.rows_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.rows_list.add_theme_constant_override("separation", int(row_gap))
		column.container.add_child(column.rows_list)

		_columns_box.add_child(column.container)
		_columns[category] = column


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


## Splits the newly-active KeyHintEntry set by category, then diffs each
## column's share against its own rows already shown — adds/removes/
## reorders only what changed, per column, never clears any list wholesale.
func _rebuild() -> void:
	if catalog == null:
		push_warning("[KeyHintsPanel] no catalog assigned — panel stays empty")
		return

	var active := catalog.get_active_entries(
			PlayerState.mode, PlayerState.view_mode, PlayerState.stance, PlayerState.is_aiming)

	# get_active_entries() already returns entries sorted by sort_order, and
	# filtering by category below preserves that relative order — no
	# separate per-column sort needed.
	var active_by_category: Dictionary = {}
	for entry in active:
		if not active_by_category.has(entry.category):
			active_by_category[entry.category] = []
		(active_by_category[entry.category] as Array).append(entry)

	for category in _columns.keys():
		var column: _Column = _columns[category]
		_rebuild_column(column, active_by_category.get(category, []))

	_reposition()


## Same diffing shape _rebuild() always used, applied to one column's own
## row list instead of one shared one — adds/removes/reorders only what
## changed within THIS column, never clears the whole thing.
func _rebuild_column(column: _Column, active_entries: Array) -> void:
	var wanted: Array[StringName] = []
	for entry in active_entries:
		wanted.append(entry.get_row_key())

	# Dictionary.keys() materializes a fresh Array each call, so this is safe
	# to iterate while erasing from column.rows below — it is not a live view.
	for row_key in column.rows.keys():
		if not wanted.has(row_key):
			var stale_row: Control = column.rows[row_key]
			stale_row.queue_free()
			column.rows.erase(row_key)

	for i in active_entries.size():
		var entry: KeyHintEntry = active_entries[i]
		var row_key := entry.get_row_key()
		var row: Control = column.rows.get(row_key) as Control
		if row == null:
			row = _make_row(entry)
			column.rows_list.add_child(row)
			column.rows[row_key] = row
		column.rows_list.move_child(row, i)

	# An empty column would otherwise leave a bare header floating over
	# nothing, or — worse — a dead gap in the row where its content used to
	# be. Hiding the whole container removes both at once.
	column.container.visible = not active_entries.is_empty()


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


## Strips as_text()'s qualifier suffix. A player needs to know which key to
## press, not that the binding was stored as a physical keycode, and the panel
## is a fixed-width column — "W - Physical" is four times the width of "W" and
## pushes the whole Movement column out.
##
## BOTH SEPARATORS, because this file already got it wrong once: it cut at the
## first " (" only, which is the form the Godot docs suggest. Measured on 4.7.2
## with a temporary print over InputMap, 2026-09-03 — what actually comes back
## is a DASH:
##
##   move_forward  -> "W - Physical"
##   jump          -> "Space - Physical"
##   interact      -> "F - Physical"
##
## so the parenthetical cut never fired and every row carried the suffix. Both
## forms are handled now, and the dash cut is bounded to the known suffix
## rather than "everything after the first dash": a future Godot wording change
## should show up on screen as a wrong label, not be silently swallowed here.
func _format_key_label(event: InputEventKey) -> String:
	var text := event.as_text()
	for suffix in _KEY_LABEL_SUFFIXES:
		var index := text.rfind(suffix)
		if index != -1:
			text = text.substr(0, index)
			break
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
