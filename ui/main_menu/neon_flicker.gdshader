shader_type canvas_item;

// Applied per-label. "active" pushes brightness up (fake glow) and makes
// flicker dropouts more frequent/violent, matching the CSS keyframes
// (flick-g / flick-r / flick-y) from the HTML prototype.

uniform float active : hint_range(0.0, 1.0) = 0.0;
uniform float seed : hint_range(0.0, 50.0) = 0.0;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.6;
uniform float flicker_speed : hint_range(0.5, 20.0) = 6.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	float t = TIME * flicker_speed + seed * 137.0;
	float slot = floor(t);
	float roll = hash(slot);

	// dropout chance: rarer and shallower when idle, more frequent when active
	float dropout_chance = 0.90 - active * 0.08;
	float flicker = 1.0;
	if (roll > dropout_chance) {
		flicker = 0.3 + hash(slot + 1.0) * 0.35;
	}

	float glow_boost = 1.0 + active * glow_strength;

	COLOR = vec4(tex.rgb * glow_boost, tex.a * flicker);
}
