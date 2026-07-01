shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always;

uniform sampler2D albedo_texture : source_color;
uniform float curvature = 0.1;          // степень выпуклости (0–0.6)
uniform float vignette_strength = 0.7;   // сила затемнения по краям
uniform float scanline_strength = 0.35;  // яркость скан‑линий
uniform float scanline_density = 200.0;  // плотность линий по вертикали
uniform float flicker_strength = 0.04;   // сила мигания
uniform float noise_strength = 0.2;     // сила «шума»
uniform vec4 tint_color : source_color = vec4(0.6, 0.9, 0.5, 1.0); // кислотный

// Простенький псевдослучайный шум
float hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)),
			 dot(p, vec2(269.5, 183.3)));
	return fract(sin(p.x * 43758.5453 + p.y * 12345.123) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv * 2.0 - 1.0;
	float r2 = dot(centered, centered);
	float k = curvature;
	vec2 warped = centered * (1.0 + k * r2);
	vec2 uv_warped = warped * 0.5 + 0.5;

	bool outside = uv_warped.x < 0.0 || uv_warped.x > 1.0 || uv_warped.y < 0.0 || uv_warped.y > 1.0;
	
	vec4 base_tex = outside ? vec4(0.0, 0.0, 0.0, 1.0) : texture(albedo_texture, uv_warped);
	
	float lum = dot(base_tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 mono = tint_color.rgb * lum;

	float scan = sin(uv_warped.y * scanline_density * 3.14159);
	float scan_mask = 0.5 + 0.5 * scan;
	scan_mask = mix(1.0, scan_mask, scanline_strength);

	float flicker = 1.0 + sin(TIME * 120.0) * flicker_strength;

	float n = hash(vec2(uv_warped * 800.0 + TIME * 60.0));
	float noise = 1.0 + (n - 0.5) * 2.0 * noise_strength;

	float vignette = 1.0 - pow(r2, 0.75);
	vignette = mix(1.0 - vignette_strength, 1.0, vignette);

	vec3 col = mono * scan_mask * flicker * noise * vignette;

	ALBEDO = col;
	ALPHA = base_tex.a;
}
