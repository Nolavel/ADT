extends Control

class_name StreamingControllerUI

### Оптимизированный стриминг контроллер УИ
### С AAA эффектами: Glitch, Screen Shake, Hologram, Chromatic Aberration

@onready var lbl_deck_a: Label = $Lbl_DECK_A
@onready var lbl_deck_b: Label = $Lbl_DECK_B
@onready var lbl_eva_zone: Label = $Lbl_EVA_Zone
@onready var lbl_chunk_sector: Label = $Lbl_ChunkSector
@onready var img_deck_current: TextureRect = $img_Pin_Deck

@onready var streaming_manager: StreamingManager = $"../../StreamingManager"

# Позиции для разных состояний
const POSITIONS = {
	"DECK_A": {
		"A": Vector2(95, -3),
		"B": Vector2(170, -3),
		"EVA": Vector2(245, -3)
	},
	"DECK_B": {
		"A": Vector2(20, -3),
		"B": Vector2(95, -3),
		"EVA": Vector2(170, -3)
	},
	"EVA_ZONE": {
		"A": Vector2(-55, -3),
		"B": Vector2(20, -3),
		"EVA": Vector2(95, -3)
	}
}

# Позиция пина
const PIN_POSITION_BASE = Vector2(-125, 2)
const PIN_POSITION_PULSE = Vector2(250, 2)
const PIN_PULSE_DURATION = 0.9

# Константы анимаций
const TRANSITION_DURATION = 1.0
const HIDE_DELAY = 5.0
const HIDE_DURATION = 2.0
const SHOW_DURATION = 0.5
const CHUNK_BLINK_DURATION = 0.1

# Константы эффектов
const GLITCH_CHANCE = 0.35
const GLITCH_DURATION = 1.1
const SHAKE_INTENSITY = 2.0
const SHAKE_DURATION = 0.2
const HOLOGRAM_FLICKER_INTERVAL = 2.0

# Drift параметры ТОЛЬКО для chunk label
const CHUNK_DRIFT_AMPLITUDE_X = Vector2(0.5, 1.5)
const CHUNK_DRIFT_AMPLITUDE_Y = Vector2(0.5, 1.5)
const CHUNK_DRIFT_DURATION = Vector2(18.0, 25.0)

# Цвета для анимации чанка
const CHUNK_COLOR_NORMAL = Color(0.6, 0.6, 0.6, 0.216)
const CHUNK_COLOR_ALERT = Color(0.6, 0.0, 0.0, 0.216)

# Альфа для неактивных деков в спящем режиме
const DECK_ALPHA_ACTIVE = 1.0
const DECK_ALPHA_INACTIVE = 0.7
const DECK_ALPHA_SLEEPING = 0.49  # 30% ниже от 0.7

# Состояние
var deck_labels_visible: bool = true
var is_shaking: bool = false

# Ссылки на твины (для правильной очистки)
var transition_tween: Tween = null
var chunk_blink_tween: Tween = null
var glitch_tween: Tween = null
var shake_tween: Tween = null
var pin_tween: Tween = null

# Таймеры
var hide_timer: Timer = null
var hologram_timer: Timer = null

# Для shake
var original_position: Vector2

# Glitch shader material
var glitch_material: ShaderMaterial = null

# Сай-фай пин (рисуем программно)
var scifi_pin: Control = null


func _ready() -> void:
	original_position = position
	
	_setup_timers()
	_setup_glitch_shader()
	_create_scifi_pin()
	_connect_signals()

func _setup_timers() -> void:
	# Таймер автоскрытия
	hide_timer = Timer.new()
	hide_timer.one_shot = true
	hide_timer.timeout.connect(_on_hide_timer_timeout)
	add_child(hide_timer)
	
	# Таймер hologram эффекта
	hologram_timer = Timer.new()
	hologram_timer.wait_time = HOLOGRAM_FLICKER_INTERVAL
	hologram_timer.timeout.connect(_trigger_hologram_flicker)
	hologram_timer.autostart = false
	add_child(hologram_timer)

func _connect_signals() -> void:
	if streaming_manager:
		streaming_manager.deck_changed.connect(_on_deck_changed)
		streaming_manager.chunk_changed.connect(_on_chunk_changed)
	else:
		push_error("StreamingManager не назначен в StreamingControllerUI!")

# ============ SCI-FI PIN CREATION ============

func _create_scifi_pin() -> void:
	# Создаем контейнер для пина
	scifi_pin = Control.new()
	scifi_pin.position = PIN_POSITION_BASE
	scifi_pin.size = Vector2(40, 40)
	scifi_pin.z_index = 100  # Максимальный z-index чтобы был сверху
	add_child(scifi_pin)
	
	# Внешнее свечение (glow)
	var outer_glow = ColorRect.new()
	outer_glow.size = Vector2(40, 40)
	outer_glow.position = Vector2(0, 0)
	outer_glow.color = Color(0.2, 0.8, 1.0, 0.2)
	outer_glow.material = _create_glow_shader()
	scifi_pin.add_child(outer_glow)
	
	# Внешнее кольцо
	var outer_ring = ColorRect.new()
	outer_ring.size = Vector2(32, 32)
	outer_ring.position = Vector2(4, 4)
	outer_ring.color = Color(0.3, 0.9, 1.0, 0.4)
	outer_ring.material = _create_ring_shader(0.0)
	scifi_pin.add_child(outer_ring)
	
	# Среднее кольцо
	var middle_ring = ColorRect.new()
	middle_ring.size = Vector2(24, 24)
	middle_ring.position = Vector2(8, 8)
	middle_ring.color = Color(0.4, 1.0, 1.0, 0.6)
	middle_ring.material = _create_ring_shader(2.0)
	scifi_pin.add_child(middle_ring)
	
	# Центральное ядро
	var core = ColorRect.new()
	core.size = Vector2(16, 16)
	core.position = Vector2(12, 12)
	core.color = Color(0.6, 1.0, 1.0, 0.9)
	core.material = _create_core_shader()
	scifi_pin.add_child(core)
	
	# Добавляем мерцание
	_start_pin_idle_animation()
	
	print("✨ Сай-фай пин создан на позиции: ", PIN_POSITION_BASE)

func _create_glow_shader() -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);
	
	// Мягкое свечение
	float glow = 1.0 - smoothstep(0.0, 0.5, dist);
	glow = pow(glow, 2.0);
	
	// Пульсация
	float pulse = sin(TIME * 2.0) * 0.3 + 0.7;
	
	COLOR.rgb = vec3(0.2, 0.8, 1.0);
	COLOR.a = glow * pulse * 0.3;
}
"""
	var material = ShaderMaterial.new()
	material.shader = shader
	return material

func _create_ring_shader(time_offset: float) -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float time_offset = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);
	
	// Кольцо с толщиной
	float ring = smoothstep(0.35, 0.38, dist) - smoothstep(0.48, 0.5, dist);
	
	// Вращающийся эффект
	float angle = atan(uv.y, uv.x);
	float rotation = sin(TIME * 2.0 + time_offset + angle * 3.0) * 0.5 + 0.5;
	
	ring *= rotation;
	
	COLOR.a *= ring;
}
"""
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("time_offset", time_offset)
	return material

func _create_core_shader() -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);
	
	// Пульсирующее ядро
	float pulse = sin(TIME * 3.0) * 0.3 + 0.7;
	float core = 1.0 - smoothstep(0.0, 0.5, dist);
	
	// Крестообразные лучи
	float cross_h = smoothstep(0.08, 0.0, abs(uv.y));
	float cross_v = smoothstep(0.08, 0.0, abs(uv.x));
	float cross = max(cross_h, cross_v);
	
	// Диагональные лучи
	float diag1 = smoothstep(0.08, 0.0, abs(uv.x - uv.y));
	float diag2 = smoothstep(0.08, 0.0, abs(uv.x + uv.y));
	float diagonals = max(diag1, diag2) * 0.5;
	
	float glow = core + cross + diagonals;
	
	COLOR.rgb = vec3(0.6, 1.0, 1.0) * glow * pulse;
	COLOR.a = glow;
}
"""
	var material = ShaderMaterial.new()
	material.shader = shader
	return material

func _start_pin_idle_animation() -> void:
	var idle_tween = create_tween()
	idle_tween.set_loops()
	idle_tween.set_trans(Tween.TRANS_SINE)
	idle_tween.set_ease(Tween.EASE_IN_OUT)
	
	# Легкое покачивание и вращение
	idle_tween.tween_property(scifi_pin, "rotation", deg_to_rad(8), 2.5)
	idle_tween.tween_property(scifi_pin, "rotation", deg_to_rad(-8), 2.5)

func _trigger_pin_pulse() -> void:
	_kill_tween(pin_tween)
	
	pin_tween = create_tween()
	pin_tween.set_trans(Tween.TRANS_BACK)
	pin_tween.set_ease(Tween.EASE_OUT)
	
	# Движение вверх и обратно
	pin_tween.tween_property(scifi_pin, "position", PIN_POSITION_PULSE, PIN_PULSE_DURATION * 0.5)
	pin_tween.tween_property(scifi_pin, "position", PIN_POSITION_BASE, PIN_PULSE_DURATION * 0.5)
	
	# Параллельно - увеличение и свечение
	var glow_tween = create_tween()
	glow_tween.set_parallel(true)
	glow_tween.set_trans(Tween.TRANS_ELASTIC)
	glow_tween.set_ease(Tween.EASE_OUT)
	
	glow_tween.tween_property(scifi_pin, "scale", Vector2(1.4, 1.4), PIN_PULSE_DURATION * 0.3)
	glow_tween.tween_property(scifi_pin, "modulate:a", 1.5, PIN_PULSE_DURATION * 0.3)
	glow_tween.tween_property(scifi_pin, "scale", Vector2(1.0, 1.0), PIN_PULSE_DURATION * 0.7)
	glow_tween.tween_property(scifi_pin, "modulate:a", 1.0, PIN_PULSE_DURATION * 0.7)
	
	print("📍 Pin pulse активирован!")

# ============ SHADER SETUP ============

func _setup_glitch_shader() -> void:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float glitch_strength : hint_range(0.0, 1.0) = 0.0;
uniform float scan_line_amount : hint_range(0.0, 1.0) = 0.1;
uniform float time_scale = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float time = TIME * time_scale;
	
	if (glitch_strength > 0.0) {
		float block_noise = noise(vec2(uv.y * 10.0, time * 3.0));
		if (block_noise > 0.85) {
			uv.x += (block_noise - 0.85) * glitch_strength * 0.15;
		}
		
		float tear = step(0.95, noise(vec2(time * 5.0, uv.y * 50.0)));
		uv.x += tear * glitch_strength * 0.05 * sin(time * 20.0);
		
		float jitter = noise(vec2(uv.x * 100.0, time * 10.0));
		if (jitter > 0.9) {
			uv.y += (jitter - 0.9) * glitch_strength * 0.03;
		}
		
		float distortion = noise(vec2(time * 2.0, uv.y * 5.0)) * glitch_strength;
		uv.x += sin(uv.y * 20.0 + time * 5.0) * distortion * 0.01;
	}
	
	float aberration = glitch_strength * 0.012;
	float r_offset = aberration * (1.0 + sin(time * 3.0) * 0.3);
	float b_offset = aberration * (1.0 + cos(time * 2.0) * 0.3);
	
	vec4 r = texture(TEXTURE, uv + vec2(r_offset, 0.0));
	vec4 g = texture(TEXTURE, uv);
	vec4 b = texture(TEXTURE, uv - vec2(b_offset, 0.0));
	
	vec4 color = vec4(r.r, g.g, b.b, g.a);
	
	float scan = sin(uv.y * 800.0 + time * 12.0) * 0.5 + 0.5;
	color.rgb -= scan * scan_line_amount * 0.08;
	
	float interlace = step(0.5, fract(uv.y * 400.0));
	color.rgb -= interlace * 0.03;
	
	if (glitch_strength > 0.5) {
		float corruption = noise(vec2(time * 15.0, uv.y * 20.0));
		if (corruption > 0.92) {
			color.rgb = vec3(corruption, 1.0 - corruption, 0.5) * 1.5;
		}
	}
	
	if (glitch_strength > 0.7) {
		float sort_line = step(0.98, noise(vec2(time * 20.0, uv.y * 15.0)));
		if (sort_line > 0.5) {
			float offset = hash(vec2(floor(uv.x * 20.0), time)) * 0.1;
			color = texture(TEXTURE, uv + vec2(offset, 0.0));
		}
	}
	
	float brightness_glitch = step(0.97, noise(vec2(time * 8.0, uv.y * 30.0)));
	color.rgb += brightness_glitch * glitch_strength * vec3(0.8, 0.9, 1.0) * 0.5;
	
	vec2 center = uv - 0.5;
	float vignette = 1.0 - dot(center, center) * 0.5;
	color.rgb *= vignette;
	
	color.rgb = mix(color.rgb, color.rgb * vec3(0.8, 0.9, 1.0), glitch_strength * 0.2);
	
	float final_alpha = COLOR.a * color.a;

	// Fade к прозрачности при низкой альфе (убирает тёмные артефакты)
	if (final_alpha < 0.99) {
		color.rgb = mix(vec3(0.0), color.rgb, final_alpha);
	}

	COLOR = vec4(color.rgb * final_alpha, final_alpha);
}
"""
	
	glitch_material = ShaderMaterial.new()
	glitch_material.shader = shader
	glitch_material.set_shader_parameter("glitch_strength", 0.0)
	glitch_material.set_shader_parameter("scan_line_amount", 0.15)
	glitch_material.set_shader_parameter("time_scale", 1.0)
	
	img_deck_current.material = glitch_material

# ============ SIGNAL HANDLERS ============

func _on_deck_changed(deck_name: String) -> void:
	_animate_to_deck(deck_name)
	_trigger_chromatic_flash()
	_trigger_pin_pulse()

func _on_chunk_changed(chunk_name: String) -> void:
	hide_timer.stop()
	
	if chunk_name.is_empty():
		lbl_chunk_sector.text = "Сектор: ---"
		_start_hide_timer()
	else:
		lbl_chunk_sector.text = chunk_name
		
		# AAA эффекты
		_animate_chunk_background()
		_trigger_screen_shake()
		_trigger_pin_pulse()
		
		if randf() < GLITCH_CHANCE:
			_trigger_glitch_effect()
		
		_show_deck_labels()
		_start_hide_timer()

# ============ VISIBILITY MANAGEMENT ============

func _start_hide_timer() -> void:
	#hide_timer.start(HIDE_DELAY)
	if hide_timer and hide_timer.is_inside_tree():
		hide_timer.start(HIDE_DELAY)
	else:
		call_deferred("_deferred_start_hide_timer", HIDE_DELAY)


func _on_hide_timer_timeout() -> void:
	_hide_deck_labels()
	hologram_timer.stop()

func _hide_deck_labels() -> void:
	if not deck_labels_visible:
		return
	
	deck_labels_visible = false
	_kill_tween(transition_tween)
	img_deck_current.material = null
	
	transition_tween = create_tween()
	transition_tween.set_parallel(true)
	transition_tween.set_trans(Tween.TRANS_CUBIC)
	transition_tween.set_ease(Tween.EASE_IN_OUT)
	
	# ВСЕ лейблы деков полностью исчезают (как раньше)
	transition_tween.tween_property(lbl_deck_a, "modulate:a", 0.0, HIDE_DURATION)
	transition_tween.tween_property(lbl_deck_b, "modulate:a", 0.0, HIDE_DURATION)
	transition_tween.tween_property(lbl_eva_zone, "modulate:a", 0.0, HIDE_DURATION)
	transition_tween.tween_property(img_deck_current, "modulate:a", 0.0, HIDE_DURATION)
	
	# Проваливание вниз
	transition_tween.tween_property(lbl_deck_a, "position:y", lbl_deck_a.position.y + 5, HIDE_DURATION)
	transition_tween.tween_property(lbl_deck_b, "position:y", lbl_deck_b.position.y + 5, HIDE_DURATION)
	transition_tween.tween_property(lbl_eva_zone, "position:y", lbl_eva_zone.position.y + 5, HIDE_DURATION)
	transition_tween.tween_property(img_deck_current, "position:y", img_deck_current.position.y + 5, HIDE_DURATION)
	
	# Chunk и пин только приглушаются
	transition_tween.tween_property(lbl_chunk_sector, "modulate:a", 0.55, HIDE_DURATION)
	transition_tween.tween_property(scifi_pin, "modulate:a", 0.3, HIDE_DURATION)

func _show_deck_labels() -> void:
	if deck_labels_visible:
		return
	
	deck_labels_visible = true
	hologram_timer.start()
	
	_kill_tween(transition_tween)
	
	img_deck_current.material = glitch_material
	
	transition_tween = create_tween()
	transition_tween.set_parallel(true)
	transition_tween.set_trans(Tween.TRANS_BACK)
	transition_tween.set_ease(Tween.EASE_OUT)
	
	var current_deck = streaming_manager.current_deck if streaming_manager else "DECK_A"
	var positions = POSITIONS[current_deck]
	
	# Восстанавливаем позиции
	transition_tween.tween_property(lbl_deck_a, "position:y", positions["A"].y, SHOW_DURATION)
	transition_tween.tween_property(lbl_deck_b, "position:y", positions["B"].y, SHOW_DURATION)
	transition_tween.tween_property(lbl_eva_zone, "position:y", positions["EVA"].y, SHOW_DURATION)
	transition_tween.tween_property(img_deck_current, "position:y", img_deck_current.position.y - 5, SHOW_DURATION)
	
	# Устанавливаем альфу: активный = 1.0, неактивные = 0.7 (спящий режим 0.49)
	var alpha_values = _get_deck_alpha_values(current_deck, false)
	transition_tween.tween_property(lbl_deck_a, "modulate:a", alpha_values[0], SHOW_DURATION)
	transition_tween.tween_property(lbl_deck_b, "modulate:a", alpha_values[1], SHOW_DURATION)
	transition_tween.tween_property(lbl_eva_zone, "modulate:a", alpha_values[2], SHOW_DURATION)
	
	transition_tween.tween_property(lbl_chunk_sector, "modulate:a", 1.0, SHOW_DURATION)
	transition_tween.tween_property(img_deck_current, "modulate:a", 1.0, SHOW_DURATION)
	transition_tween.tween_property(scifi_pin, "modulate:a", 1.0, SHOW_DURATION)

func _get_deck_alpha_values(deck_name: String, sleeping: bool = false) -> Array[float]:
	# sleeping больше не используется для скрытия, только для различия неактивных
	var inactive_alpha = DECK_ALPHA_INACTIVE  # Всегда 0.7 когда видимы
	var active_alpha = DECK_ALPHA_ACTIVE      # Всегда 1.0 для активного
	
	match deck_name:
		"DECK_A": return [active_alpha, inactive_alpha, inactive_alpha]
		"DECK_B": return [inactive_alpha, active_alpha, inactive_alpha]
		"EVA_ZONE": return [inactive_alpha, inactive_alpha, active_alpha]
		_: return [inactive_alpha, inactive_alpha, inactive_alpha]

# ============ DECK ANIMATION ============

func _animate_to_deck(deck_name: String) -> void:
	if not deck_labels_visible:
		_show_deck_labels()
		_start_hide_timer()
	
	_kill_tween(transition_tween)
	
	var target_positions = POSITIONS.get(deck_name)
	if not target_positions:
		push_error("Неизвестный дек: " + deck_name)
		return
	
	transition_tween = create_tween()
	transition_tween.set_parallel(true)
	transition_tween.set_trans(Tween.TRANS_CUBIC)
	transition_tween.set_ease(Tween.EASE_IN_OUT)
	
	transition_tween.tween_property(lbl_deck_a, "position", target_positions["A"], TRANSITION_DURATION)
	transition_tween.tween_property(lbl_deck_b, "position", target_positions["B"], TRANSITION_DURATION)
	transition_tween.tween_property(lbl_eva_zone, "position", target_positions["EVA"], TRANSITION_DURATION)
	
	_highlight_current_deck(deck_name)

func _highlight_current_deck(deck_name: String) -> void:
	var labels = [lbl_deck_a, lbl_deck_b, lbl_eva_zone]
	var deck_index = {"DECK_A": 0, "DECK_B": 1, "EVA_ZONE": 2}.get(deck_name, 0)
	
	for i in labels.size():
		var current_alpha = labels[i].modulate.a
		var brightness = 1.0 if i == deck_index else 0.7
		labels[i].modulate = Color(brightness, brightness, brightness, current_alpha)

# ============ CHUNK BACKGROUND ANIMATION ============

func _animate_chunk_background() -> void:
	var style_box = lbl_chunk_sector.get("theme_override_styles/normal")
	
	if not style_box is StyleBoxFlat:
		return
	
	_kill_tween(chunk_blink_tween)
	
	chunk_blink_tween = create_tween()
	chunk_blink_tween.set_trans(Tween.TRANS_LINEAR)
	chunk_blink_tween.set_ease(Tween.EASE_IN_OUT)
	
	# Двойное мигание
	for i in 2:
		chunk_blink_tween.tween_property(style_box, "bg_color", CHUNK_COLOR_ALERT, CHUNK_BLINK_DURATION)
		chunk_blink_tween.tween_property(style_box, "bg_color", CHUNK_COLOR_NORMAL, CHUNK_BLINK_DURATION)

# ============ AAA ЭФФЕКТЫ ============

func _trigger_glitch_effect() -> void:
	if not glitch_material:
		return
	
	_kill_tween(glitch_tween)
	
	glitch_tween = create_tween()
	glitch_tween.set_trans(Tween.TRANS_CUBIC)
	glitch_tween.set_ease(Tween.EASE_IN_OUT)
	
	glitch_tween.tween_property(glitch_material, "shader_parameter/glitch_strength", 0.8, 0.05)
	glitch_tween.tween_property(glitch_material, "shader_parameter/glitch_strength", 0.0, GLITCH_DURATION)

func _trigger_screen_shake() -> void:
	if is_shaking:
		return
	
	is_shaking = true
	_kill_tween(shake_tween)
	
	shake_tween = create_tween()
	
	# 10 быстрых смещений относительно original_position
	for i in 10:
		var offset = Vector2(
			randf_range(-SHAKE_INTENSITY, SHAKE_INTENSITY),
			randf_range(-SHAKE_INTENSITY, SHAKE_INTENSITY)
		)
		shake_tween.tween_property(self, "position", original_position + offset, SHAKE_DURATION / 10.0)
	
	# Возврат в исходную позицию
	shake_tween.tween_property(self, "position", original_position, SHAKE_DURATION / 10.0)
	shake_tween.finished.connect(func(): is_shaking = false)

func _trigger_chromatic_flash() -> void:
	var flash_tween = create_tween()
	flash_tween.set_parallel(true)
	flash_tween.set_trans(Tween.TRANS_ELASTIC)
	flash_tween.set_ease(Tween.EASE_OUT)
	
	var labels = [lbl_deck_a, lbl_deck_b, lbl_eva_zone]
	for label in labels:
		var original_scale = label.scale
		flash_tween.tween_property(label, "scale", original_scale * 1.05, 0.1)
		flash_tween.tween_property(label, "scale", original_scale, 0.3)

func _trigger_hologram_flicker() -> void:
	if not deck_labels_visible or randf() > 0.3:
		return
	
	var flicker_tween = create_tween()
	flicker_tween.set_parallel(true)
	
	var labels = [lbl_deck_a, lbl_deck_b, lbl_eva_zone]
	for label in labels:
		var current_alpha = label.modulate.a
		flicker_tween.tween_property(label, "modulate:a", current_alpha * 0.3, 0.05)
		flicker_tween.tween_property(label, "modulate:a", current_alpha, 0.05)
	
	if randf() < 0.85:
		_trigger_glitch_effect()

# ============ UTILITY ============

func _kill_tween(tween: Tween) -> void:
	if tween and tween.is_valid():
		tween.kill()

# Cleanup при выходе
func _exit_tree() -> void:
	_kill_tween(transition_tween)
	_kill_tween(chunk_blink_tween)
	_kill_tween(glitch_tween)
	_kill_tween(shake_tween)
	_kill_tween(pin_tween)
