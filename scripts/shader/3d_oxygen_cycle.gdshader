shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_back, unshaded;

// Основные параметры кислорода
uniform float oxygen : hint_range(0.0, 1.0) = 1.0;
uniform bool clockwise = true; // Направление заполнения

// Цвета кислорода
uniform vec3 color_full : source_color = vec3(0.0, 0.8, 1.0); // Полный - голубой
uniform vec3 color_medium : source_color = vec3(0.0, 1.0, 0.5); // Средний - зеленовато-голубой
uniform vec3 color_low : source_color = vec3(1.0, 0.8, 0.0); // Низкий - желтый
uniform vec3 color_critical : source_color = vec3(1.0, 0.2, 0.0); // Критический - красный

// Параметры свечения
uniform float glow_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 3.0;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.3;

// Граница/контур
uniform float border_thickness : hint_range(0.01, 0.2) = 0.03;
uniform vec3 border_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float border_alpha : hint_range(0.0, 1.0) = 0.8;

// Эффекты
uniform float dissolve_smoothness : hint_range(0.0, 0.3) = 0.1;

// Сай-фай эффекты
uniform bool enable_bubbles = true; // Пузырьки кислорода
uniform float bubble_speed : hint_range(0.0, 5.0) = 1.5;
uniform float bubble_count : hint_range(5.0, 50.0) = 20.0;
uniform float bubble_size : hint_range(0.01, 0.1) = 0.03;

uniform bool enable_flow_lines = true; // Линии потока
uniform float flow_speed : hint_range(0.0, 5.0) = 2.0;
uniform float flow_intensity : hint_range(0.0, 1.0) = 0.4;

uniform bool enable_scanlines = true; // Сканлайны
uniform float scanline_speed : hint_range(0.0, 3.0) = 0.5;
uniform float scanline_density : hint_range(20.0, 200.0) = 80.0;
uniform float scanline_intensity : hint_range(0.0, 0.5) = 0.15;

uniform bool enable_warning_flash = true; // Мигание при низком кислороде
uniform float warning_threshold : hint_range(0.0, 0.5) = 0.25;

varying vec2 uv_coords;
varying vec3 world_normal;

void vertex() {
	uv_coords = UV;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Функция шума
float random(vec2 st) {
	return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Функция для создания пузырьков
float bubble_pattern(vec2 uv, float time) {
	float bubbles = 0.0;
	for (float i = 0.0; i < bubble_count; i += 1.0) {
		vec2 bubble_pos = vec2(
			fract(i * 0.1234 + time * bubble_speed * 0.1),
			fract(i * 0.5678)
		);
		float dist = distance(uv, bubble_pos);
		float bubble = smoothstep(bubble_size, bubble_size * 0.5, dist);
		bubbles += bubble;
	}
	return clamp(bubbles, 0.0, 1.0);
}

void fragment() {
	vec2 uv = uv_coords;

	// Вычисляем угловой прогресс для тороидального заполнения
	// UV.x идёт по окружности тора (0 to 1 = 360°)
	float angle_progress = uv.x;
	if (!clockwise) {
		angle_progress = 1.0 - angle_progress;
	}

	// Расстояние от границы заполнения
	float distance_from_fill = angle_progress - oxygen;

	// Определяем расстояние до края тора (для бордера)
	// UV.y идёт по сечению тора
	float radial_dist = abs(uv.y - 0.5) * 2.0; // 0 в центре, 1 на краях
	bool is_border = radial_dist > (1.0 - border_thickness * 2.0);

	// Отбрасываем невидимые части
	if (!is_border && distance_from_fill > dissolve_smoothness) {
		discard;
	}

	// === РЕНДЕРИНГ ===
	if (is_border) {
		// Бордер с лёгким свечением
		vec3 border_glow = border_color;
		if (oxygen < warning_threshold && enable_warning_flash) {
			float warning_pulse = step(0.5, fract(TIME * 4.0));
			border_glow += color_critical * warning_pulse * 0.3;
		}

		ALBEDO = border_glow;
		ALPHA = border_alpha;
		EMISSION = border_glow * 0.2;
	} else {
		// === ЗАПОЛНЕНИЕ КИСЛОРОДОМ ===

		// Плавность края исчезновения
		float edge_factor = 1.0 - smoothstep(-dissolve_smoothness, dissolve_smoothness, distance_from_fill);

		// Базовый цвет в зависимости от уровня кислорода
		vec3 base_color;
		if (oxygen > 0.75) {
			base_color = color_full;
		} else if (oxygen > 0.5) {
			float t = (oxygen - 0.5) / 0.25;
			base_color = mix(color_medium, color_full, t);
		} else if (oxygen > 0.25) {
			float t = (oxygen - 0.25) / 0.25;
			base_color = mix(color_low, color_medium, t);
		} else {
			float t = oxygen / 0.25;
			base_color = mix(color_critical, color_low, t);
		}

		// === САЙ-ФАЙ ЭФФЕКТЫ ===

		// 1. ПУЗЫРЬКИ КИСЛОРОДА
		float bubbles = 0.0;
		if (enable_bubbles) {
			bubbles = bubble_pattern(uv, TIME);
		}

		// 2. ЛИНИИ ПОТОКА вдоль тора
		float flow_lines = 0.0;
		if (enable_flow_lines) {
			float flow_wave = sin(uv.x * 20.0 - TIME * flow_speed);
			flow_wave += sin(uv.x * 35.0 + TIME * flow_speed * 0.7);
			flow_lines = smoothstep(0.7, 1.0, flow_wave) * flow_intensity;
		}

		// 3. СКАНЛАЙНЫ по окружности
		float scanlines = 0.0;
		if (enable_scanlines) {
			float scan = sin((uv.x + TIME * scanline_speed * 0.1) * scanline_density);
			scanlines = scan * scanline_intensity;
		}

		// 4. ЭФФЕКТ КРАЯ заполнения с пульсацией
		float edge_proximity = smoothstep(0.1, 0.0, abs(distance_from_fill));
		float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
		float edge_glow = edge_proximity * glow_intensity * (1.0 + pulse * pulse_intensity);

		// 5. ВОЛНОВОЙ ЭФФЕКТ на краю
		float wave_effect = 0.0;
		if (edge_proximity > 0.1) {
			float wave = sin(angle_progress * 30.0 - TIME * 5.0) * 0.5 + 0.5;
			wave_effect = wave * edge_proximity * 0.5;
		}

		// 6. МИГАНИЕ при критическом уровне
		float warning_blink = 0.0;
		if (enable_warning_flash && oxygen < warning_threshold) {
			float blink_speed = 3.0 + (warning_threshold - oxygen) * 10.0;
			warning_blink = (sin(TIME * blink_speed) * 0.5 + 0.5) * 0.5;
		}

		// 7. FRESNEL эффект для объёмности
		vec3 view_dir = normalize(VIEW);
		float fresnel = pow(1.0 - abs(dot(view_dir, world_normal)), 2.0);

		// 8. РАДИАЛЬНЫЙ ГРАДИЕНТ для глубины
		float radial_fade = 1.0 - radial_dist * 0.3;

		// === КОМБИНИРУЕМ ВСЁ ===
		vec3 final_color = base_color * radial_fade;
		final_color += base_color * bubbles * 0.8; // Пузырьки
		final_color += base_color * flow_lines; // Потоки
		final_color += scanlines; // Сканлайны
		final_color += base_color * edge_glow; // Свечение края
		final_color += base_color * wave_effect; // Волны
		final_color += color_critical * warning_blink; // Мигание
		final_color += base_color * fresnel * 0.4; // Fresnel

		// Дополнительная пульсация всей поверхности при низком кислороде
		if (oxygen < 0.15) {
			float critical_pulse = sin(TIME * 8.0) * 0.5 + 0.5;
			final_color += color_critical * critical_pulse * 0.3;
		}

		ALBEDO = final_color;
		ALPHA = edge_factor;
		EMISSION = final_color * 0.8; // Сильное свечение для кислорода
	}
}