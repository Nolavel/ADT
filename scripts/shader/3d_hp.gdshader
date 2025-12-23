shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Основные параметры
uniform float health : hint_range(0.0, 1.0) = 1.0;
uniform vec3 direction = vec3(1.0, 0.0, 0.0); // Направление исчезновения

// Цвета для разных уровней здоровья
uniform vec3 color_high : source_color = vec3(0.0, 1.0, 0.0); // > 0.75 - зеленый
uniform vec3 color_medium : source_color = vec3(1.0, 1.0, 0.0); // 0.5-0.75 - желтый
uniform vec3 color_low : source_color = vec3(1.0, 0.5, 0.0); // 0.25-0.5 - оранжевый
uniform vec3 color_critical : source_color = vec3(1.0, 0.0, 0.0); // < 0.25 - красный

// Параметры эффектов на краях
uniform float edge_width : hint_range(0.0, 0.5) = 0.08;
uniform float edge_glow_intensity : hint_range(0.0, 5.0) = 2.5;
uniform vec3 edge_glow_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float pulse_speed : hint_range(0.0, 10.0) = 4.0;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.4;

// Параметры рамки/контура
uniform float border_thickness : hint_range(0.01, 0.3) = 0.05;
uniform vec3 border_color : source_color = vec3(0.2, 0.2, 0.2);
uniform float border_alpha : hint_range(0.0, 1.0) = 1.0;

// Параметры для эффекта исчезновения
uniform float dissolve_smoothness : hint_range(0.0, 0.2) = 0.05;

// 🌟 НОВЫЕ СAЙ-ФАЙ ПАРАМЕТРЫ
uniform bool enable_scanlines = true; // Горизонтальные линии
uniform float scanline_speed : hint_range(0.0, 5.0) = 1.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float scanline_count : hint_range(10.0, 200.0) = 50.0;

uniform bool enable_hologram = true; // Голографический эффект
uniform float hologram_flicker_speed : hint_range(0.0, 10.0) = 2.0;
uniform float hologram_flicker_intensity : hint_range(0.0, 0.5) = 0.1;

uniform bool enable_grid = false; // Сетка
uniform float grid_scale : hint_range(5.0, 100.0) = 20.0;
uniform float grid_width : hint_range(0.01, 0.1) = 0.02;
uniform vec3 grid_color : source_color = vec3(0.0, 0.8, 1.0);
uniform float grid_intensity : hint_range(0.0, 1.0) = 0.3;

uniform bool enable_glitch = false; // Глитч эффект при низком HP
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.5;

uniform bool enable_energy_flow = true; // Энергетические потоки
uniform float flow_speed : hint_range(0.0, 5.0) = 2.0;
uniform vec3 flow_color : source_color = vec3(0.0, 1.0, 1.0);
uniform float flow_intensity : hint_range(0.0, 1.0) = 0.3;

varying vec3 local_pos;
varying vec2 uv_coords;

void vertex() {
	local_pos = VERTEX;
	uv_coords = UV;
}

// Функция для генерации шума
float random(vec2 st) {
	return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	vec3 dir = normalize(direction);
	vec2 uv = uv_coords;
	
	// === ОСНОВНАЯ ЛОГИКА (НЕ ТРОГАЕМ) ===
	vec2 dir_2d = vec2(dir.x, dir.y);
	if (length(dir_2d) < 0.1) {
		dir_2d = vec2(1.0, 1.0);
	}
	dir_2d = normalize(dir_2d);
	
	float progress = dot(uv, dir_2d);
	float proj_00 = dot(vec2(0.0, 0.0), dir_2d);
	float proj_10 = dot(vec2(1.0, 0.0), dir_2d);
	float proj_01 = dot(vec2(0.0, 1.0), dir_2d);
	float proj_11 = dot(vec2(1.0, 1.0), dir_2d);
	
	float min_proj = min(min(proj_00, proj_10), min(proj_01, proj_11));
	float max_proj = max(max(proj_00, proj_10), max(proj_01, proj_11));
	
	progress = (progress - min_proj) / (max_proj - min_proj);
	progress = clamp(progress, 0.0, 1.0);
	
	float distance_from_edge = progress - health;
	
	float border_dist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	bool is_border = border_dist < border_thickness;
	
	if (!is_border && distance_from_edge > dissolve_smoothness) {
		discard;
	}
	
	// === РЕНДЕРИНГ ===
	if (is_border) {
		// Бордер с глитчем при критическом HP
		vec3 final_border = border_color;
		
		if (enable_glitch && health < 0.25) {
			float glitch = random(vec2(uv.y, TIME * 10.0));
			if (glitch > 0.95) {
				final_border += vec3(0.5, 0.0, 0.5) * glitch_intensity;
			}
		}
		
		ALBEDO = final_border;
		ALPHA = border_alpha;
		EMISSION = vec3(0.0);
	} else {
		// === ЗАПОЛНЕНИЕ ===
		float edge_factor = 1.0 - smoothstep(-dissolve_smoothness, dissolve_smoothness, distance_from_edge);
		
		// Базовый цвет
		vec3 base_color;
		if (health > 0.75) {
			base_color = color_high;
		} else if (health > 0.5) {
			float t = (health - 0.5) / 0.25;
			base_color = mix(color_medium, color_high, t);
		} else if (health > 0.25) {
			float t = (health - 0.25) / 0.25;
			base_color = mix(color_low, color_medium, t);
		} else {
			float t = health / 0.25;
			base_color = mix(color_critical, color_low, t);
		}
		
		// === СAЙ-ФАЙ ЭФФЕКТЫ ===
		
		// 1. SCANLINES (горизонтальные линии)
		float scanline_effect = 0.0;
		if (enable_scanlines) {
			float scanline = sin((uv.y + TIME * scanline_speed * 0.1) * scanline_count * 6.28318);
			scanline_effect = scanline * scanline_intensity;
		}
		
		// 2. HOLOGRAM FLICKER (мерцание голограммы)
		float hologram_effect = 1.0;
		if (enable_hologram) {
			float flicker = sin(TIME * hologram_flicker_speed * 10.0 + uv.y * 5.0) * 0.5 + 0.5;
			hologram_effect = 1.0 - (flicker * hologram_flicker_intensity);
		}
		
		// 3. GRID (сетка)
		float grid_effect = 0.0;
		if (enable_grid) {
			vec2 grid_uv = fract(uv * grid_scale);
			float grid_x = step(1.0 - grid_width, grid_uv.x);
			float grid_y = step(1.0 - grid_width, grid_uv.y);
			grid_effect = max(grid_x, grid_y) * grid_intensity;
		}
		
		// 4. ENERGY FLOW (энергетические потоки вдоль направления)
		float flow_effect = 0.0;
		if (enable_energy_flow) {
			float flow_wave = sin(progress * 10.0 - TIME * flow_speed * 3.0);
			flow_wave = smoothstep(0.5, 0.9, flow_wave);
			flow_effect = flow_wave * flow_intensity;
		}
		
		// 5. GLITCH при критическом HP
		vec2 glitch_offset = vec2(0.0);
		if (enable_glitch && health < 0.25) {
			float glitch_amount = (0.25 - health) * 4.0; // От 0 до 1
			float glitch_rand = random(vec2(floor(TIME * 20.0), uv.y * 100.0));
			if (glitch_rand > 0.9) {
				glitch_offset.x = (random(vec2(TIME, uv.y)) - 0.5) * 0.05 * glitch_intensity * glitch_amount;
			}
		}
		
		// Применяем глитч сдвиг к UV
		vec2 final_uv = uv + glitch_offset;
		
		// === ОРИГИНАЛЬНЫЕ ЭФФЕКТЫ ===
		float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
		float edge_pulse = pulse * pulse_intensity;
		
		float edge_proximity = smoothstep(edge_width, 0.0, abs(distance_from_edge));
		float edge_glow = edge_proximity * edge_glow_intensity * (1.0 + edge_pulse);
		vec3 glow_color = edge_glow_color * edge_glow;
		
		if (edge_proximity > 0.1) {
			float wave = sin(progress * 30.0 - TIME * 8.0) * 0.5 + 0.5;
			glow_color += edge_glow_color * wave * edge_proximity * 0.5;
		}
		
		// === КОМБИНИРУЕМ ВСЕ ЭФФЕКТЫ ===
		vec3 final_color = base_color * hologram_effect; // Применяем голограмму
		final_color += glow_color; // Свечение края
		final_color += scanline_effect; // Сканлайны
		final_color += grid_color * grid_effect; // Сетка
		final_color += flow_color * flow_effect; // Энергетические потоки
		
		// Критическое состояние
		if (health < 0.35) {
			float critical_pulse = (sin(TIME * pulse_speed * 2.5) * 0.5 + 0.5);
			final_color += color_critical * critical_pulse * 0.5;
			
			if (health < 0.1) {
				float fast_blink = step(0.5, fract(TIME * 6.0));
				final_color += color_critical * fast_blink * 0.3;
			}
		}
		
		ALBEDO = final_color;
		ALPHA = edge_factor;
		EMISSION = glow_color * 0.7 + flow_color * flow_effect * 0.5;
	}
}