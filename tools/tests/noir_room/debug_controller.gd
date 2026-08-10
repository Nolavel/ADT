extends Node

## Debug controller for the noir reference room evaluation scene.
##
## Diagnostic tooling, NOT production content. Lives with the test scene and is
## not referenced by anything in the game. Delete alongside the room once the
## renderer question is answered.
##
## Setup:
##   1. Open res://tools/tests/noir_room/noir_room_test.tscn
##   2. Add a plain Node as a child of the root, name it "DebugController"
##   3. Attach this script, save the scene
##   4. Run the scene (F6)
##
## Controls:
##   WASD / QE     move, RMB-drag or captured mouse to look
##   Shift         boost, Alt slow
##   Tab           capture / release the mouse
##   Escape        release the mouse; press again to quit
##   1-9           jump to evaluation step N from NOIR_REFERENCE_ROOM.md
##   F12           screenshot to user://noir_shots/
##   H             hide / show the panel (hide before screenshots)
##
## NOTE ON PROJECT CONVENTION: the codebase forbids Input.* reads outside
## InputSystems.gd, with a carve-out for level-design tooling under map_source/.
## This script reads Input directly and is a deliberate, documented extension of
## that carve-out to tools/tests/. It intentionally registers no actions in the
## InputMap so it cannot collide with gameplay bindings. Do not copy this pattern
## into anything under world/ or player/.

# ---------------------------------------------------------------------------
# Flycam tuning
# ---------------------------------------------------------------------------

const MOVE_SPEED: float = 4.0
const BOOST_MULTIPLIER: float = 4.0
const SLOW_MULTIPLIER: float = 0.25
const MOUSE_SENSITIVITY: float = 0.0025
const PITCH_LIMIT: float = 1.5

const SCREENSHOT_DIR: String = "user://noir_shots"

# ---------------------------------------------------------------------------
# Evaluation presets
# ---------------------------------------------------------------------------
# Cumulative build-up order from section 6 of the spec. The intermediate frames
# are the actual output of this exercise: they tell you which stage was
# responsible for the change, which "it looks better now" does not.
#
# Materials (step 5) and the LUT texture (step 8) cannot be toggled meaningfully
# from here — they are authored assets. Those steps are marked in the panel and
# left to manual comparison.

const PRESETS: Array[Dictionary] = [
	{"label": "1. Key light only (before)",
		"aces": false, "black_bg": false, "lightmap": false, "signs": false,
		"glow": false, "ssao": false, "ssil": false, "ssr": false, "fog": false,
		"grade": false, "dof": false},
	{"label": "2. ACES + black bg + no ambient",
		"aces": true, "black_bg": true, "lightmap": false, "signs": false,
		"glow": false, "ssao": false, "ssil": false, "ssr": false, "fog": false,
		"grade": false, "dof": false},
	{"label": "3. Baked lightmap",
		"aces": true, "black_bg": true, "lightmap": true, "signs": false,
		"glow": false, "ssao": false, "ssil": false, "ssr": false, "fog": false,
		"grade": false, "dof": false},
	{"label": "4. Sign lights + glow",
		"aces": true, "black_bg": true, "lightmap": true, "signs": true,
		"glow": true, "ssao": false, "ssil": false, "ssr": false, "fog": false,
		"grade": false, "dof": false},
	{"label": "5. Materials (manual - see spec)",
		"aces": true, "black_bg": true, "lightmap": true, "signs": true,
		"glow": true, "ssao": false, "ssil": false, "ssr": false, "fog": false,
		"grade": false, "dof": false},
	{"label": "6. SSAO / SSIL / SSR",
		"aces": true, "black_bg": true, "lightmap": true, "signs": true,
		"glow": true, "ssao": true, "ssil": true, "ssr": true, "fog": false,
		"grade": false, "dof": false},
	{"label": "7. Volumetric fog",
		"aces": true, "black_bg": true, "lightmap": true, "signs": true,
		"glow": true, "ssao": true, "ssil": true, "ssr": true, "fog": true,
		"grade": false, "dof": false},
	{"label": "8. Grading (LUT is manual)",
		"aces": true, "black_bg": true, "lightmap": true, "signs": true,
		"glow": true, "ssao": true, "ssil": true, "ssr": true, "fog": true,
		"grade": true, "dof": false},
	{"label": "9. Depth of field",
		"aces": true, "black_bg": true, "lightmap": true, "signs": true,
		"glow": true, "ssao": true, "ssil": true, "ssr": true, "fog": true,
		"grade": true, "dof": true},
]

# ---------------------------------------------------------------------------
# Scene references, resolved in _ready
# ---------------------------------------------------------------------------

var _camera: Camera3D
var _attributes: CameraAttributesPractical
var _environment: Environment
var _key_light: SpotLight3D
var _sign_lights: Array[Light3D] = []
var _sign_emitters: Array[MeshInstance3D] = []
var _lightmap: LightmapGI

## Captured at startup so sliders and toggles restore to the authored values
## rather than to engine defaults.
var _defaults: Dictionary = {}

var _yaw: float = 0.0
var _pitch: float = 0.0
var _mouse_captured: bool = false
var _looking_with_rmb: bool = false

var _panel: PanelContainer
var _status: Label
var _current_preset: int = -1


func _ready() -> void:
	if not _resolve_scene_references():
		push_error("Noir debug controller: scene layout not recognised. " +
				"Expected the scene produced by noir_room_builder.gd.")
		set_process(false)
		return

	_capture_defaults()
	_build_ui()

	var basis := _camera.global_transform.basis
	_yaw = basis.get_euler().y
	_pitch = basis.get_euler().x

	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)
	_set_status("Ready. Press 1 for the 'before' frame.")


# ---------------------------------------------------------------------------
# Scene wiring
# ---------------------------------------------------------------------------

## Resolved by type and node name rather than by hard-coded NodePath so the scene
## can be rearranged in the editor without breaking the tool.
func _resolve_scene_references() -> bool:
	var root := get_parent()
	if root == null:
		return false

	_camera = _find_first(root, Camera3D) as Camera3D
	var world_env := _find_first(root, WorldEnvironment) as WorldEnvironment
	_lightmap = _find_first(root, LightmapGI) as LightmapGI

	if _camera == null or world_env == null:
		return false

	_environment = world_env.environment
	_attributes = _camera.attributes as CameraAttributesPractical

	var lighting := root.get_node_or_null("Lighting")
	if lighting == null:
		return false

	_key_light = lighting.get_node_or_null("KeyLight") as SpotLight3D

	for child in lighting.get_children():
		if child is Light3D and child != _key_light:
			_sign_lights.append(child)
		elif child is MeshInstance3D and String(child.name).ends_with("Emitter"):
			_sign_emitters.append(child)

	return _environment != null and _key_light != null


func _find_first(node: Node, type) -> Node:
	if is_instance_of(node, type):
		return node
	for child in node.get_children():
		var found := _find_first(child, type)
		if found != null:
			return found
	return null


func _capture_defaults() -> void:
	_defaults = {
		"tonemap_exposure": _environment.tonemap_exposure,
		"glow_intensity": _environment.glow_intensity,
		"glow_hdr_threshold": _environment.glow_hdr_threshold,
		"fog_density": _environment.volumetric_fog_density,
		"ssao_intensity": _environment.ssao_intensity,
		"ssil_intensity": _environment.ssil_intensity,
		"saturation": _environment.adjustment_saturation,
		"contrast": _environment.adjustment_contrast,
		"key_energy": _key_light.light_energy,
		"background_color": _environment.background_color,
		"ambient_source": _environment.ambient_light_source,
		"tonemap_mode": _environment.tonemap_mode,
	}
	_defaults["sign_energy"] = _sign_lights[0].light_energy if not _sign_lights.is_empty() else 3.0


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (_mouse_captured or _looking_with_rmb):
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY,
				-PITCH_LIMIT, PITCH_LIMIT)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking_with_rmb = event.pressed
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match event.keycode:
		KEY_ESCAPE:
			# First press releases the mouse so the window can be closed or the
			# panel used; second press quits. Avoids trapping the pointer.
			if _mouse_captured:
				_set_mouse_captured(false)
				_set_status("Mouse released. Escape again to quit.")
			else:
				get_tree().quit()
		KEY_TAB:
			_set_mouse_captured(not _mouse_captured)
		KEY_K:
			_panel.visible = not _panel.visible
		KEY_F12:
			_take_screenshot()
		_:
			var index : int = event.keycode - KEY_1
			if index >= 0 and index < PRESETS.size():
				_apply_preset(index)


func _set_mouse_captured(captured: bool) -> void:
	_mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		direction.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		direction.z += 1.0
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_E):
		direction.y += 1.0
	if Input.is_key_pressed(KEY_Q):
		direction.y -= 1.0

	var speed := MOVE_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= BOOST_MULTIPLIER
	elif Input.is_key_pressed(KEY_ALT):
		speed *= SLOW_MULTIPLIER

	_camera.rotation = Vector3(_pitch, _yaw, 0.0)

	if direction != Vector3.ZERO:
		var motion := _camera.global_transform.basis * direction.normalized()
		_camera.global_position += motion * speed * delta


# ---------------------------------------------------------------------------
# Presets
# ---------------------------------------------------------------------------

func _apply_preset(index: int) -> void:
	var preset := PRESETS[index]
	_current_preset = index

	_environment.tonemap_mode = (Environment.TONE_MAPPER_ACES if preset["aces"]
			else Environment.TONE_MAPPER_LINEAR)

	# Step 1 restores a naive setup — grey ambient and a lit background — because
	# that is what the "before" frame actually looks like in an unconfigured scene.
	if preset["black_bg"]:
		_environment.background_color = _defaults["background_color"]
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	else:
		_environment.background_color = Color(0.3, 0.32, 0.35)
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_environment.ambient_light_color = Color(0.35, 0.36, 0.4)
		_environment.ambient_light_energy = 1.0

	if _lightmap != null:
		_lightmap.visible = preset["lightmap"]

	for light in _sign_lights:
		light.visible = preset["signs"]
	for emitter in _sign_emitters:
		emitter.visible = preset["signs"]

	_environment.glow_enabled = preset["glow"]
	_environment.ssao_enabled = preset["ssao"]
	_environment.ssil_enabled = preset["ssil"]
	_environment.ssr_enabled = preset["ssr"]
	_environment.volumetric_fog_enabled = preset["fog"]
	_environment.adjustment_enabled = preset["grade"]

	if _attributes != null:
		_attributes.dof_blur_far_enabled = preset["dof"]

	_set_status(preset["label"])


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(12, 12)
	_panel.custom_minimum_size = Vector2(300, 0)
	layer.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(280, 0)
	column.add_child(_status)

	column.add_child(HSeparator.new())

	# Live tuning. Ranges are deliberately wider than the authored values so the
	# effect of over- and under-driving each parameter is visible.
	_add_slider(column, "Exposure", 0.2, 3.0, _defaults["tonemap_exposure"],
			func(v: float) -> void: _environment.tonemap_exposure = v)
	_add_slider(column, "Glow intensity", 0.0, 2.0, _defaults["glow_intensity"],
			func(v: float) -> void: _environment.glow_intensity = v)
	_add_slider(column, "Glow threshold", 0.0, 3.0, _defaults["glow_hdr_threshold"],
			func(v: float) -> void: _environment.glow_hdr_threshold = v)
	_add_slider(column, "Fog density", 0.0, 0.15, _defaults["fog_density"],
			func(v: float) -> void: _environment.volumetric_fog_density = v)
	_add_slider(column, "SSAO intensity", 0.0, 6.0, _defaults["ssao_intensity"],
			func(v: float) -> void: _environment.ssao_intensity = v)
	_add_slider(column, "SSIL intensity", 0.0, 4.0, _defaults["ssil_intensity"],
			func(v: float) -> void: _environment.ssil_intensity = v)
	_add_slider(column, "Saturation", 0.0, 2.0, _defaults["saturation"],
			func(v: float) -> void: _environment.adjustment_saturation = v)
	_add_slider(column, "Contrast", 0.5, 2.0, _defaults["contrast"],
			func(v: float) -> void: _environment.adjustment_contrast = v)
	_add_slider(column, "Key energy", 0.0, 12.0, _defaults["key_energy"],
			func(v: float) -> void: _key_light.light_energy = v)
	_add_slider(column, "Sign energy", 0.0, 10.0, _defaults["sign_energy"],
			func(v: float) -> void:
				for light in _sign_lights:
					light.light_energy = v)

	column.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "1-9 preset  |  Tab mouse  |  K hide\nF12 shot  |  Esc release / quit"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.6)
	column.add_child(hint)


func _add_slider(parent: VBoxContainer, label_text: String, minimum: float,
		maximum: float, value: float, on_change: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	parent.add_child(row)

	var label := Label.new()
	label.text = "%s: %.3f" % [label_text, value]
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = (maximum - minimum) / 200.0
	slider.value = value
	slider.custom_minimum_size = Vector2(280, 16)
	row.add_child(slider)

	slider.value_changed.connect(func(new_value: float) -> void:
		label.text = "%s: %.3f" % [label_text, new_value]
		on_change.call(new_value))


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


# ---------------------------------------------------------------------------
# Screenshots
# ---------------------------------------------------------------------------

## Filenames carry the preset index so the nine comparison frames stay ordered
## and identifiable after the fact. Hide the panel with H first.
func _take_screenshot() -> void:
	var image := get_viewport().get_texture().get_image()
	var step := "step%d" % (_current_preset + 1) if _current_preset >= 0 else "free"
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/noir_%s_%s.png" % [SCREENSHOT_DIR, step, stamp]

	if image.save_png(path) == OK:
		_set_status("Saved %s" % path)
	else:
		_set_status("Screenshot failed.")
