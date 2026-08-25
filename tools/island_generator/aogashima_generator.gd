@tool
extends EditorScript

## EditorScript утилита процедурной генерации 16-битной карты высот (Heightmap)
## острова Аогасима по спецификации Blackrock Terrain.
##
## Запуск из редактора: File -> Run (Ctrl+Shift+X)
##
## Output Spec:
## - Dimensions: 2048 x 2048 px
## - Format: 16-bit Grayscale PNG (FORMAT_RH)
## - Height Range: 0m (Sea level) to 500m (65535)
## - Spatial Extent: 3500m x 3500m (World Size)

const MAP_SIZE_PX := 2048
const MAP_SIZE_M := 3500.0        # Физический размер карты по стороне (метры)
const HEIGHT_RANGE_M := 500.0     # Максимальная высота кодирования (65535 = 500m)

# Геометрические параметры острова
const CALDERA_RIM_RADIUS_X := 850.0
const CALDERA_RIM_RADIUS_Z := 750.0
const OTONBU_HEIGHT_M := 423.0    # Северо-западная высшая точка (423 м)
const OTONBU_CENTER_OFFSET := Vector2(0.0, -550.0)

const OUTPUT_PATH := "res://world/aogashima/aogashima_heightmap_16bit.png"


func _run() -> void:
	print("[Aogashima Generator] Старт генерации 16-битного heightmap...")
	_generate_heightmap()


func _generate_heightmap() -> void:
	var img := Image.create(MAP_SIZE_PX, MAP_SIZE_PX, false, Image.FORMAT_RH)
	var center := Vector2(MAP_SIZE_PX * 0.5, MAP_SIZE_PX * 0.5)
	var meters_per_pixel := MAP_SIZE_M / float(MAP_SIZE_PX)

	# Шум эрозии хребтов (Ridged multifractal)
	var noise_ridge := FastNoiseLite.new()
	noise_ridge.seed = 1337
	noise_ridge.frequency = 0.003
	noise_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_ridge.fractal_octaves = 4

	# Микро-рельеф и шершавость склонов
	var noise_detail := FastNoiseLite.new()
	noise_detail.seed = 777
	noise_detail.frequency = 0.008
	noise_detail.fractal_octaves = 3

	for y in range(MAP_SIZE_PX):
		for x in range(MAP_SIZE_PX):
			var pos_px := Vector2(float(x), float(y))
			var pos_m := (pos_px - center) * meters_per_pixel
			
			var height_m := _sample_aogashima_complex(pos_m, noise_ridge, noise_detail)
			
			# Строгое соблюдение ТЗ: 0m = sea level; все что ниже — отсекается в 0
			height_m = clampf(height_m, 0.0, HEIGHT_RANGE_M)
			
			# Нормализация в диапазон [0.0, 1.0] для 16-битного буфера RH
			var normalized_height := height_m / HEIGHT_RANGE_M
			img.set_pixel(x, y, Color(normalized_height, 0.0, 0.0, 1.0))

	var err := img.save_png(OUTPUT_PATH)
	if err == OK:
		print("[Aogashima Generator] Успешно сохранен 16-битный PNG: ", OUTPUT_PATH)
	else:
		push_error("[Aogashima Generator] Ошибка сохранения PNG файла: " + str(err))


func _sample_aogashima_complex(pos: Vector2, n_ridge: FastNoiseLite, n_detail: FastNoiseLite) -> float:
	var angle := atan2(pos.y, pos.x)
	var dist := pos.length()

	# 1. Асимметричная береговая линия (Срез на севере, удлинение на юге)
	var max_coast_r := 1600.0 + sin(angle * 2.0) * 150.0 - (pos.y * 0.15)
	
	if dist > max_coast_r:
		return 0.0 # Океан

	# 2. Внешний обод кальдеры
	var rim_target_r := 850.0 + sin(angle * 3.0) * 80.0
	var dist_to_rim := absf(dist - rim_target_r)
	var rim_factor := smoothstep(700.0, 0.0, dist_to_rim)
	
	# Пик Отонбу на севере (423м) со спадом высоты к южному хребту (~200м)
	var north_bias := remap(clampf(pos.y, -1200.0, 1200.0), -1200.0, 1200.0, 1.0, 0.45)
	var rim_height := OTONBU_HEIGHT_M * north_bias * rim_factor

	# 3. Дно кальдеры (~100–110 м)
	var caldera_floor_factor := smoothstep(rim_target_r, 450.0, dist)
	var base_terrain := lerpf(rim_height, 110.0, caldera_floor_factor)

	# 4. Морские обрывы (Sea Cliffs) — крутой сброс в воду без пляжей
	if dist > rim_target_r:
		var coast_cliff_factor := smoothstep(max_coast_r, rim_target_r, dist)
		base_terrain = lerpf(0.0, rim_height, coast_cliff_factor)
		if dist > max_coast_r - 80.0:
			base_terrain *= smoothstep(max_coast_r, max_coast_r - 80.0, dist)

	# 5. Внутренний вулкан Маруヤマ с главным и малым кратерами
	var maruyama_center := Vector2(40.0, 80.0)
	var m_dist := pos.distance_to(maruyama_center)
	var maruyama_r := 380.0

	if m_dist < maruyama_r:
		var m_factor := smoothstep(maruyama_r, 0.0, m_dist)
		var m_cone := m_factor * 120.0
		
		# Главный кратер
		var main_crater := smoothstep(80.0, 0.0, m_dist) * 45.0
		
		# Побочный кратер-паразит на склоне
		var sub_crater_pos := maruyama_center + Vector2(-90.0, -70.0)
		var sub_crater_dist := pos.distance_to(sub_crater_pos)
		var sub_crater := smoothstep(55.0, 0.0, sub_crater_dist) * 25.0
		
		var maruyama_final_h := 110.0 + m_cone - main_crater - sub_crater
		base_terrain = maxf(base_terrain, maruyama_final_h)

	# 6. Вертикальные скальные складки и овраги эрозии
	var radial_mask := smoothstep(300.0, rim_target_r, dist)
	var ridge_noise := n_ridge.get_noise_2d(pos.x, pos.y) * 40.0 * radial_mask
	var detail_noise := n_detail.get_noise_2d(pos.x, pos.y) * 12.0

	return base_terrain + ridge_noise + detail_noise
