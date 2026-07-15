# =============================================================================
# StreamDebugPanel.gd
# Screen-space дебаг-панель конвейера стриминга. Живёт в WORLD_UI_SCENES.
#
# ПРАВИЛО: панель — ЧИСТЫЙ НАБЛЮДАТЕЛЬ. Подписки на сигналы StreamingSystems /
# WorldSystems + один read-only снапшот при старте. Ни одного вызова,
# меняющего состояние стриминга. Не наращивать здесь управление.
#
# UI строится кодом в _ready() — осознанно: дебаг-инструмент, стилизация
# в редакторе не предполагается, сцена остаётся двумя строками.
#
# Весь корень — mouse_filter = IGNORE: панель лежит поверх вьюпорта и не
# должна съедать клики click-to-move.
#
# Тоггл видимости: сигнал InputSystems.stream_debug_toggled
# (action "toggle_stream_debug" в Input Map).
# =============================================================================

extends Control

const MAX_LOG_LINES   := 20
const REDRAW_INTERVAL := 0.25   # сек; списки перерисовываются не чаще

var _player: Node3D = null

## Локальная копия состояния ячеек: id -> {type, state, strata}.
## Обновляется ТОЛЬКО из сигналов и стартового снапшота.
var _cells: Dictionary = {}
var _log:   Array[String] = []

var _dirty:        bool  = false
var _redraw_timer: float = 0.0

var _header:     Label
var _cells_text: RichTextLabel
var _log_text:   RichTextLabel


func _ready() -> void:
	_build_ui()

	InputSystems.stream_debug_toggled.connect(_on_toggle)
	StreamingSystems.initialized.connect(_on_streaming_initialized)
	StreamingSystems.cell_state_changed.connect(_on_cell_state_changed)
	StreamingSystems.layer_changed.connect(_on_layer_changed)

	# Панель добавляется через call_deferred и почти наверняка просыпается
	# ПОСЛЕ синхронного StreamingSystems.initialize() — добираем уже
	# случившееся снапшотом, а не надеемся на сигнал initialized.
	_pull_snapshot()


## Вызывается world.gd (общий механизм WORLD_UI_SCENES).
func on_world_ready(context: WorldContext) -> void:
	_player = context.player


func _process(delta: float) -> void:
	if not visible:
		return

	_update_header()

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
		_cells[cell_id] = { "type": cell_type, "state": new_state, "strata": "" }
	else:
		_cells[cell_id]["state"] = new_state

	_push_log("%s: %s → %s" % [cell_id,
			_state_name(old_state), _state_name(new_state)])


func _on_layer_changed(block_id: String, strata: String, loaded: bool) -> void:
	if _cells.has(block_id):
		_cells[block_id]["strata"] = strata if loaded else ""
	_push_log("%s: layer %s %s" % [block_id, strata,
			"loaded" if loaded else "freed"])


# ── Данные ────────────────────────────────────────────────────────────────────

func _pull_snapshot() -> void:
	for entry in StreamingSystems.get_cells_snapshot():
		_cells[entry["id"]] = {
			"type":   entry["type"],
			"state":  entry["state"],
			"strata": entry["strata"],
		}
	_dirty = true


func _push_log(line: String) -> void:
	_log.append("[%7.1f] %s" % [Time.get_ticks_msec() * 0.001, line])
	while _log.size() > MAX_LOG_LINES:
		_log.pop_front()
	_dirty = true


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

	_header.text = "pos %s | %s | %s\nACTIVE %d  READY %d  LOADING %d  QUEUED %d  UNLOADED %d" % [
		pos_str, WorldSystems.current_strata, tile_str,
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
		if cell["type"] == StreamingSystems.CellType.BLOCK \
				and not str(cell["strata"]).is_empty():
			line += "  [%s]" % cell["strata"]
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
