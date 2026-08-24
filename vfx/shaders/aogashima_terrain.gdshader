shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D heightmap : hint_default_black, filter_linear, repeat_disable;
uniform float height_range = 500.0;
uniform float sea_level = 0.0;

// Цветовые палитры рельефа
uniform vec4 land_color : source_color = vec4(0.18, 0.38, 0.12, 1.0);
uniform vec4 cliff_color : source_color = vec4(0.28, 0.25, 0.22, 1.0);
uniform vec4 coast_rock_color : source_color = vec4(0.15, 0.14, 0.13, 1.0);

varying float v_height;
varying vec3 v_world_pos;

void vertex() {
	// Выборка нормализованной высоты [0.0, 1.0] из красного канала
	float h_norm = texture(heightmap, UV).r;
	v_height = h_norm * height_range;
	
	// Смещение вершины по вертикали Y
	VERTEX.y = v_height;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Определение крутизны склонов для отображения скал/клиффов
	float slope = 1.0 - NORMAL.y;
	
	vec3 col = land_color.rgb;
	
	// Переход в крутые скалы на ободе кальдеры и морских обрывах
	float cliff_mask = smoothstep(0.25, 0.55, slope);
	col = mix(col, cliff_color.rgb, cliff_mask);
	
	// Окрашивание темных прибрежных скал у уреза воды
	if (v_height <= sea_level + 8.0) {
		float coast_mask = smoothstep(sea_level + 8.0, sea_level, v_height);
		col = mix(col, coast_rock_color.rgb, coast_mask);
	}

	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
}