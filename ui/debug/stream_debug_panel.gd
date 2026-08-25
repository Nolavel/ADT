# =============================================================================
# StreamDebugPanel.gd
# Screen-space debug overlay, one Control living in WORLD_UI_SCENES. Started
# as a streaming-only panel; now hosts a second, independent section
# (lock-on) added deliberately here rather than as a fourth debug mechanism
# — see the note below on why.
#
# STREAMING SECTION RULE: pure observer. Subscribes to StreamingSystems /
# WorldSystems signals + one read-only snapshot at start. Never a call that
# changes streaming state. Do not grow control here.
#
# LOCK-ON SECTION: also a pure observer — reads OnFootCameraComponent's
# TpsCombatCameraState and calls its get_lock_on_diagnostic(), never
# anything that decides a lock. Added here instead of a new panel + a new
# WORLD_UI_SCENES entry because registering a new UI scene means editing
# world.gd, which CONTRIBUTING.md lists as "do not touch without asking";
# this file was already wired in and already is a toggleable screen-space
# debug overlay, so extending it avoids that edit entirely. If this file
# outgrows "a couple of independent read-only sections," it's worth
# revisiting as two separate panels then.
#
# UI строится кодом в _ready() — осознанно: дебаг-инструмент, стилизация
# в редакторе не предполагается, сцена остаётся двумя строками.
#
# Весь корень — mouse_filter = IGNORE: панель лежит поверх вьюпорта и не
# должна съедать клики click-to-move.
#
# Тоггл видимости: сигнал InputSystems.stream_debug_toggled
# (action "toggle_stream_debug" в Input Map) — same toggle drives both
# sections; no new input action was needed.
# =============================================================================

extends Control

const MAX_LOG_LINES   := 20
const REDRAW_INTERVAL := 0.25   # сек; списки перерисовываются не чаще

var _player: Node3D = null
## For the lock-on section only. Null until on_world_ready() runs, and
## still null if the current scene has no camera_follow (e.g. no TPS).
var _on_foot: OnFootCameraComponent = null

## Локальная копия состояния ячеек: id -> {type, state}.
## Обновляется ТОЛЬКО из сигналов и стартового снапшота.
var _cells: Dictionary = {}
var _log:   Array[String] = []

var _dirty:        bool  = false
var _redraw_timer: float = 0.0

var _header:       Label
var _cells_text:   RichTextLabel
var _log_text:     RichTextLabel
var _lock_on_text: RichTextLabel


func _ready() -> void:
	_build_ui()

	InputSystems.stream_debug_toggled.connect(_on_toggle)
	StreamingSystems.initialized.connect(_on_streaming_initialized)
	StreamingSystems.cell_state_changed.connect(_on_cell_state_changed)

	# Панель добавляется через call_deferred и почти наверняка просыпается
	# ПОСЛЕ синхронного StreamingSystems.initialize() — добираем уже
	# случившееся снапшотом, а не надеемся на сигнал initialized.
	_pull_snapshot()


## Вызывается world.gd (общий механизм WORLD_UI_SCENES).
func on_world_ready(context: WorldContext) -> void:
	_player = context.player
	if context.camera:
		# Same duck-typed call zoom_ruler_system.gd already makes on
		# context.camera — camera_follow.gd extends Camera3D and exposes
		# this itself, context.camera's static type just doesn't say so.
		_on_foot = context.camera.get_on_foot_component()


func _process(delta: float) -> void:
	if not visible:
		return

	_update_header()
	_update_lock_on_debug()

	_redraw_timer += delta
	if _dirty and _redraw_timer >= REDRAW_INTERVAL:
		_redraw_timer = 0.0
		_dirty = false
		_redraw_cells()
		_redraw_log()


# ── Обработчики сигналов ──────────────────────────────────────────────────────

func _on_toggle() -> void:
	visible = not visible


func _on_streaming_initialized(_cell_count: int) -> void:
	_pull_snapshot()


func _on_cell_state_changed(cell_id: String, cell_type: int,
		old_state: int, new_state: int) -> void:
	if not _cells.has(cell_id):
		_cells[cell_id] = { "type": cell_type, "state": new_state }
	else:
		_cells[cell_id]["state"] = new_state

	_push_log("%s: %s → %s" % [cell_id,
			_state_name(old_state), _state_name(new_state)])


# ── Данные ────────────────────────────────────────────────────────────────────

func _pull_snapshot() -> void:
	for entry in StreamingSystems.get_cells_snapshot():
		_cells[entry["id"]] = {
			"type":   entry["type"],
			"state":  entry["state"],
		}
	_dirty = true


func _push_log(line: String) -> void:
	_log.append("[%7.1f] %s" % [Time.get_ticks_msec() * 0.001, line])
	while _log.size() > MAX_LOG_LINES:
		_log.pop_front()
	_dirty = true


# ── Lock-on (read-only observer, see file header) ─────────────────────────────

func _update_lock_on_debug() -> void:
	if not _lock_on_text:
		return

	if not _on_foot:
		_lock_on_text.text = "[color=#777777]— no camera_follow found —[/color]"
		return

	var combat := _on_foot.get_combat_state()
	var state_name: String = str(TpsCombatCameraState.TpsState.keys()[combat.state])
	var target_name: String = str(combat.locked_target.name) if is_instance_valid(combat.locked_target) else "null"

	var lines: Array[String] = []
	lines.append("state: %s   locked_target: %s" % [state_name, target_name])

	if not is_instance_valid(_player):
		lines.append("no player reference")
		_lock_on_text.text = "\n".join(lines)
		return

	var diag := combat.get_lock_on_diagnostic(_player)
	lines.append("stance: %s   lockable in scene: %d" % [diag.stance, diag.lockable_count])

	if diag.lockable_count == 0:
		lines.append("[color=#ff6666]no lockable candidates[/color]")
	else:
		var passed: bool = diag.rejected_by == ""
		var verdict_color := "#35ff66" if passed else "#ff6666"
		var verdict_text := "PASS" if passed else "REJECTED (%s)" % diag.rejected_by
		lines.append("nearest: %s  dist %.1fm  angle %.0f°  [color=%s]%s[/color]" % [
			diag.nearest_name, diag.distance, diag.angle_deg, verdict_color, verdict_text])
		lines.append("facing %s" % _v3_str(diag.forward))
		lines.append("to target %s" % _v3_str(diag.to_nearest))

	_lock_on_text.text = "\n".join(lines)


func _v3_str(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


# ── Отрисовка ─────────────────────────────────────────────────────────────────

func _update_header() -> void:
	var pos_str := "—"
	if is_instance_valid(_player):
		var p := _player.global_position
		pos_str = "(%.0f, %.0f, %.0f)" % [p.x, p.y, p.z]

	var tile := WorldSystems.current_tile
	var tile_str := WorldSystems.get_tile_id(tile) \
			if WorldSystems.is_tile_inside_grid(tile) else "вне сетки"

	var counts := { }
	for cell in _cells.values():
		counts[cell["state"]] = counts.get(cell["state"], 0) + 1

	_header.text = "pos %s | %s\nACTIVE %d  READY %d  LOADING %d  QUEUED %d  UNLOADED %d" % [
		pos_str, tile_str,
		counts.get(StreamingSystems.CellState.ACTIVE, 0),
		counts.get(StreamingSystems.CellState.READY, 0),
		counts.get(StreamingSystems.CellState.LOADING, 0),
		counts.get(StreamingSystems.CellState.QUEUED, 0),
		counts.get(StreamingSystems.CellState.UNLOADED, 0),
	]


func _redraw_cells() -> void:
	var ids := _cells.keys()
	ids.sort()

	var lines: Array[String] = []
	for id: String in ids:
		var cell: Dictionary = _cells[id]
		if cell["state"] == StreamingSystems.CellState.UNLOADED:
			continue   # список показывает только "живые" ячейки
		var color := _state_color(cell["state"]).to_html(false)
		var line := "[color=#%s]●[/color] %s  %s" % [color, id,
				_state_name(cell["state"])]
		lines.append(line)

	_cells_text.text = "\n".join(lines) if not lines.is_empty() \
			else "[color=#777777]— нет активных ячеек —[/color]"


func _redraw_log() -> void:
	_log_text.text = "\n".join(_log)


func _state_name(state: int) -> String:
	return StreamingSystems.CellState.keys()[state]


func _state_color(state: int) -> Color:
	match state:
		StreamingSystems.CellState.QUEUED:  return Color(0.6, 0.6, 0.6)
		StreamingSystems.CellState.LOADING: return Color(1.0, 0.85, 0.2)
		StreamingSystems.CellState.READY:   return Color(0.3, 0.85, 1.0)
		StreamingSystems.CellState.ACTIVE:  return Color(0.35, 1.0, 0.4)
		_:                                  return Color(0.5, 0.5, 0.5)


# ── Построение UI ─────────────────────────────────────────────────────────────

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(8, 8)
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

	_header = Label.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_header)

	vbox.add_child(HSeparator.new())

	_cells_text = RichTextLabel.new()
	_cells_text.bbcode_enabled = true
	_cells_text.fit_content = true
	_cells_text.scroll_active = false
	_cells_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cells_text.custom_minimum_size = Vector2(340, 0)
	_cells_text.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(_cells_text)

	vbox.add_child(HSeparator.new())

	_log_text = RichTextLabel.new()
	_log_text.scroll_following = true
	_log_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_text.custom_minimum_size = Vector2(340, 170)
	_log_text.add_theme_font_size_override("normal_font_size", 11)
	vbox.add_child(_log_text)

	vbox.add_child(HSeparator.new())

	var lock_on_header := Label.new()
	lock_on_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_on_header.text = "LOCK-ON"
	lock_on_header.add_theme_font_size_override("font_size", 13)
	vbox.add_child(lock_on_header)

	_lock_on_text = RichTextLabel.new()
	_lock_on_text.bbcode_enabled = true
	_lock_on_text.fit_content = true
	_lock_on_text.scroll_active = false
	_lock_on_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_on_text.custom_minimum_size = Vector2(340, 0)
	_lock_on_text.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(_lock_on_text)
