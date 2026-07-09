shader_type canvas_item;

uniform vec2 player_screen_pos_uv;
uniform vec2 viewport_size;
uniform float fade_radius = 200.0;
uniform float fade_distance = 200.0;
uniform float grain_intensity = 0.6;
uniform float grain_scale = 6.0;
uniform float time_speed = 1.0;
uniform bool effect_enabled = true;

// Цветной грейн для Sci-Fi
uniform vec3 grain_color : source_color = vec3(0.0, 0.8, 1.0); // Cyan
uniform float grain_color_mix = 0.3; // 0 = монохромный, 1 = цветной

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 frag_px = uv * viewport_size;
    vec2 player_px = player_screen_pos_uv * viewport_size;
    
    vec3 scene_col = texture(SCREEN_TEXTURE, uv).rgb;
    
    if (!effect_enabled) {
        COLOR = vec4(scene_col, 1.0);
    } else {
        float dist = distance(frag_px, player_px);
        float t = clamp((dist - fade_radius) / fade_distance, 0.0, 1.0);
        
        float grain_curve = pow(t, 0.6);
        float noise = rand(uv * grain_scale + vec2(TIME * time_speed));
        float grain_strength = grain_curve * grain_intensity;
        
        // Цветной грейн
        vec3 grain_mono = vec3(noise);
        vec3 grain_colored = grain_color * noise;
        vec3 grain_mixed = mix(grain_mono, grain_colored, grain_color_mix);
        
        vec3 with_grain = mix(scene_col, grain_mixed, grain_strength);
        
        float alpha = smoothstep(0.0, 1.0, t);
        COLOR = vec4(with_grain, alpha);
    }
}