# =============================================================================
# key_hints_panel.gd — KeyHintsPanel.
#
# Bottom-RIGHT corner column of key hints on an ink blot, visible whenever
# InputSystems.key_hints_enabled is true (docs/scope_horizon.md H2). A
# collaborator cannot evaluate a build whose controls are undiscoverable — this
# is what makes them discoverable.
#
# THE ORDER OF THE TRANSITION IS THE CONTRACT, not decoration: ink in, then
# text; text out, then ink. Hiding is a CHAIN rather than two parallel tweens
# with the text merely running shorter — an overlap does not read as a sequence.
# The ink itself is one ColorRect over vfx/shaders/key_hints_blot.gdshader.
# Its eight pieces share one progress scale, but a wide stagger makes their
# assembly visible before they fuse into the finished blot.
#
# Instanced inside player_hud.tscn rather than added as a separate
# WORLD_UI_SCENES entry — PlayerHUD already owns a world-UI lifecycle, a
# second one would duplicate it for no reason.
#
# TWO SECTIONS, NOT A RIBBON: movement and action hints stack in the narrow
# corner panel. System/debug controls are deliberately not advertised here.
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
extends Control

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
@export var key_color: Color = Color(0.973, 0.910, 0.753, 1.0)
## Fill behind a key glyph. From the study's `.key` rule.
@export var key_box_color: Color = Color(0.118, 0.094, 0.063, 0.85)
## Border of that box, same source.
@export var key_border_color: Color = Color(0.706, 0.549, 0.275, 0.6)
@export var description_color: Color = Color(0.88, 0.88, 0.88, 1.0)
## Deliberately dimmer/smaller than the descriptions: a column header is a
## landmark for the eye, not content to read.
@export var header_color: Color = Color(0.55, 0.55, 0.55, 0.85)
@export var font_size: int = 14
## The glyph inside a key box. Smaller than the description on purpose — the box
## already carries the emphasis, and a full-size glyph makes every row taller.
@export var key_font_size: int = 12
@export var header_font_size: int = 11
## Joins the individual key labels of a grouped entry (KeyHintEntry.
## action_names) into one cell, e.g. "W / A / S / D". The single place this
## separator is defined — nowhere else repeats it.
@export var group_key_separator: String = " / "
## Horizontal gap between a row's key label and its description.
@export var key_description_gap: float = 6.0
## Vertical gap between rows within one column.
@export var row_gap: float = 8.0
## Vertical gap between the movement and action blocks.
@export var category_gap: float = 14.0
## Space between the text and the edge of the panel's own rect.
@export var content_padding: Vector2 = Vector2(18.0, 14.0)

@export_group("Placement")
## Uniform visual scale for ink and text, keeping the whole panel compact.
@export var panel_scale: float = 0.82
## Distance from the right edge of the screen to the panel.
@export var right_margin: float = 24.0
## Distance from the bottom of the screen to the panel.
@export var bottom_margin: float = 20.0

@export_group("Blot")
## How much bigger the ink layer is than the text it backs, per axis. The blob
## mass is bottom-right heavy by construction (it is transcribed from a study
## anchored to that corner and covers UV 0.30..1.0 x, 0.15..1.0 y), so the
## layer has to extend UP and LEFT for the text to land inside the ink rather
## than on its thin edge. 1.9 x 1.55 puts the text's top-left corner at roughly
## UV (0.47, 0.35), comfortably inside.
@export var blot_scale: Vector2 = Vector2(1.9, 1.55)
## How far the ink runs PAST the panel toward the screen corner. The study lets
## its blots hang off the edge; without this they stop dead at the margin.
@export var blot_bleed: float = 28.0

@export_group("Animation")
## Ink in. The blobs' own stagger rides inside this, in the shader.
@export var appear_duration: float = 0.8
## The first panel entrance waits for the scene to settle. Later reopens stay
## immediate so toggling the hints does not repeat a startup-only pause.
@export var initial_appear_delay: float = 1.0
## Text arrives by tween only after every ink piece has appeared.
@export var content_fade_in_duration: float = 0.4
## Blobs grow from nothing to an undergrown assembled blot during the ink
## entrance, then spread to full size after the text arrives.
@export var initial_blot_radius_scale: float = 0.0
@export var assembled_blot_radius_scale: float = 0.8
@export var blot_settle_duration: float = 3.0
## Text out. Runs to completion BEFORE the ink starts to go, which is the same
## order reversed and is why this is a chain rather than two parallel tweens.
@export var text_fade_out_duration: float = 0.22
## Ink out, after the text has gone.
@export var dissolve_duration: float = 0.35

@onready var _blot_layer: ColorRect = $BlotLayer
@onready var _content: VBoxContainer = $Content
@onready var _title_label: Label = $Content/TitleLabel
@onready var _columns_box: VBoxContainer = $Content/Rows

## One shared monospace font for every key label — see _build_mono_font().
var _mono_font: Font = null

## KeyHintEntry.Category → _Column, one per category, built once in
## _build_columns() and never recreated — only their contents change.
var _columns: Dictionary = {}

## The ONE tween this panel ever owns. Every transition kills it first.
##
## Not a courtesy: TargetIndicator built a fresh tween per frame on a per-frame
## assertion and produced "27 resources still in use at exit", which is a gated
## ERROR line in CI. A rebuild arriving mid-transition here is the same shape.
## → docs/postmortems/verification_ladder.md
var _transition: Tween = null
## Row keys currently ON SCREEN, not the ones last requested. The difference
## matters: caching the request means a change arriving mid-transition updates
## the cache, and the re-read after the transition then sees "nothing changed"
## and drops it.
var _shown_row_keys: Array[StringName] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columns_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columns_box.add_theme_constant_override("separation", int(category_gap))
	_mono_font = _build_mono_font()
	_style_title()
	_build_columns()

	resized.connect(_reposition)
	get_viewport().size_changed.connect(_reposition)

	PlayerState.mode_changed.connect(_on_mode_changed)
	PlayerState.view_mode_changed.connect(_on_view_mode_changed)
	PlayerState.stance_changed.connect(_on_stance_changed)
	PlayerState.aiming_changed.connect(_on_aiming_changed)
	InputSystems.key_hints_enabled_changed.connect(_on_enabled_changed)

	visible = InputSystems.key_hints_enabled
	_set_blot_progress(0.0)
	_content.modulate.a = 0.0
	_rebuild()
	_reposition()
	if visible:
		_begin_appear(initial_appear_delay)


## The title is a landmark, not content: small, spaced out, and the same dim
## gold as the category headers.
func _style_title() -> void:
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_font_size_override("font_size", header_font_size)
	_title_label.add_theme_color_override("font_color", header_color)
	## Letter-spacing without a RichTextLabel: one theme constant on a plain
	## Label does it, and a BBCode parser for a single word would be worse.
	_title_label.add_theme_constant_override("spacing", 3)


func _blot_progress() -> float:
	var mat := _blot_layer.material as ShaderMaterial
	if mat == null:
		return 0.0
	return float(mat.get_shader_parameter("progress"))


func _set_blot_progress(value: float) -> void:
	var mat := _blot_layer.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("progress", clampf(value, 0.0, 1.0))


func _blot_radius_scale() -> float:
	var mat := _blot_layer.material as ShaderMaterial
	if mat == null:
		return initial_blot_radius_scale
	return float(mat.get_shader_parameter("radius_scale"))


func _set_blot_radius_scale(value: float) -> void:
	var mat := _blot_layer.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("radius_scale", clampf(value, 0.0, 2.0))


func _set_blot_entrance_seed(value: float) -> void:
	var mat := _blot_layer.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("entrance_seed", value)


## One block per KeyHintEntry.Category, in Category.values() order — the enum's
## declaration order is the only thing that decides their order, not anything
## written here.
##
## They STACK now rather than sitting side by side: the panel is a narrow corner
## column, and three columns in a corner would be a wide strip that the ink
## cannot back. Category itself is untouched in the data, so going back to three
## columns is a change of parent container and nothing else.
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
	if enabled:
		visible = true
		_rebuild()
		_begin_appear()
	else:
		_begin_hide()


## Decides WHETHER the rows on screen have to change, and if so runs the
## transition around the change. The diffing itself is _apply_rebuild() below
## and is unchanged.
##
## The comparison is against what is SHOWN, never against the last request —
## see _shown_row_keys.
func _rebuild() -> void:
	if catalog == null:
		push_warning("[KeyHintsPanel] no catalog assigned — panel stays empty")
		return

	var active := catalog.get_active_entries(
			PlayerState.mode, PlayerState.view_mode, PlayerState.stance, PlayerState.is_aiming)
	var wanted := _collect_row_keys(active)
	if wanted == _shown_row_keys:
		return

	if not visible or _blot_progress() <= 0.01:
		_apply_rebuild(active)
		_shown_row_keys = wanted
		return

	## On screen already: text out, then ink out, then swap, then ink in, then
	## text in. The swap happens while nothing is drawn.
	_kill_transition()
	_transition = create_tween()
	_transition.tween_property(_content, "modulate:a", 0.0, text_fade_out_duration)
	_transition.tween_method(_set_blot_progress, _blot_progress(), 0.0, dissolve_duration)
	_transition.tween_callback(func() -> void:
		_apply_rebuild(active)
		_shown_row_keys = wanted
		_begin_appear()
	)


func _collect_row_keys(active: Array[KeyHintEntry]) -> Array[StringName]:
	var keys: Array[StringName] = []
	for entry in active:
		keys.append(entry.get_row_key())
	return keys


## Ink first, then text. The content tween is chained after the full ink tween,
## so the text cannot fade in over a partially assembled blot.
func _begin_appear(delay: float = 0.0) -> void:
	_kill_transition()
	_content.modulate.a = 0.0
	_set_blot_entrance_seed(randf())
	_set_blot_radius_scale(initial_blot_radius_scale)
	_transition = create_tween()
	if delay > 0.0:
		_transition.tween_interval(delay)
	_transition.tween_method(_set_blot_progress, _blot_progress(), 1.0, appear_duration)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.parallel().tween_method(
		_set_blot_radius_scale,
		_blot_radius_scale(),
		assembled_blot_radius_scale,
		appear_duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.tween_property(_content, "modulate:a", 1.0, content_fade_in_duration)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.tween_method(
		_set_blot_radius_scale, assembled_blot_radius_scale, 1.0, blot_settle_duration
	)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


## Text out to completion, THEN the ink. A chain, not two parallel tweens with
## the text merely running shorter — "text first, then blots" is the request,
## and an overlap does not read as a sequence.
func _begin_hide() -> void:
	_kill_transition()
	_transition = create_tween()
	_transition.tween_property(_content, "modulate:a", 0.0, text_fade_out_duration)
	_transition.tween_method(_set_blot_progress, _blot_progress(), 0.0, dissolve_duration)
	_transition.tween_callback(func() -> void: visible = false)


func _kill_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null


## Splits the newly-active KeyHintEntry set by category, then diffs each
## column's share against its own rows already shown — adds/removes/
## reorders only what changed, per column, never clears any list wholesale.
func _apply_rebuild(active: Array[KeyHintEntry]) -> void:
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


## A row is [key][key]… description, where each key is its OWN boxed glyph.
##
## A grouped entry (W/S/A/D) gets FOUR boxes joined by group_key_separator, not
## one wide box holding all four: the study draws a key as a physical thing you
## press, and four of them in one frame reads as a single strange key. It is also
## the difference between legible and not once the row sits on dark ink.
func _make_row(entry: KeyHintEntry) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % entry.get_row_key()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(key_description_gap))

	var labels := _resolve_entry_key_labels(entry)
	for i in labels.size():
		if i > 0:
			var joiner := Label.new()
			joiner.text = group_key_separator.strip_edges()
			joiner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			joiner.add_theme_font_size_override("font_size", font_size)
			joiner.add_theme_color_override("font_color", description_color)
			row.add_child(joiner)
		row.add_child(_make_key_box(labels[i]))

	var desc_label := Label.new()
	desc_label.text = entry.description
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_label.add_theme_font_size_override("font_size", font_size)
	desc_label.add_theme_color_override("font_color", description_color)
	row.add_child(desc_label)

	return row


## One key glyph in its box. A PanelContainer with a StyleBoxFlat rather than a
## drawn rectangle: it sizes itself to the glyph, so "Space" and "W" both come
## out right without any width arithmetic here.
func _make_key_box(label_text: String) -> Control:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var style := StyleBoxFlat.new()
	style.bg_color = key_box_color
	style.border_color = key_border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	box.add_theme_stylebox_override("panel", style)

	var key_label := Label.new()
	key_label.text = label_text
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_font_override("font", _mono_font)
	key_label.add_theme_font_size_override("font_size", key_font_size)
	key_label.add_theme_color_override("font_color", key_color)
	box.add_child(key_label)

	return box


## Every key label this entry needs, one per action — the caller boxes them
## individually. Returns a list rather than a joined string because a grouped
## entry is several keys, and the join used to hide that.
func _resolve_entry_key_labels(entry: KeyHintEntry) -> Array[String]:
	var labels: Array[String] = []
	for action_name in entry.get_action_names():
		labels.append(_resolve_key_label(action_name))
	return labels


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


## Bottom-RIGHT, and the panel sizes itself to its text rather than being sized
## by a container: the root is a plain Control precisely so the ink layer can be
## bigger than the content and hang off the corner, which no container would
## allow.
func _reposition() -> void:
	var content_min := _content.get_combined_minimum_size()
	_content.position = content_padding
	_content.size = content_min
	size = content_min + content_padding * 2.0
	scale = Vector2.ONE * panel_scale

	var viewport_size := get_viewport_rect().size
	global_position = Vector2(
			viewport_size.x - size.x * panel_scale - right_margin,
			viewport_size.y - size.y * panel_scale - bottom_margin
	)

	## The ink is anchored to the panel's bottom-right and grows up and left,
	## matching where the blob mass actually sits — see blot_scale.
	var blot_size := Vector2(size.x * blot_scale.x, size.y * blot_scale.y)
	_blot_layer.size = blot_size
	_blot_layer.position = size - blot_size + Vector2.ONE * blot_bleed
	var mat := _blot_layer.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("rect_size", blot_size)


## SystemFont, not a bundled asset: this panel is a working tool for showing
## the build to a reviewer, not final UI (see this file's own header) — not
## worth shipping a font file for. Falls back to the platform default if
## none of these are installed, same as any other SystemFont use.
func _build_mono_font() -> Font:
	var system_font := SystemFont.new()
	system_font.font_names = ["Consolas", "Courier New", "DejaVu Sans Mono", "monospace"]
	return system_font
