shader_type canvas_item;

// A VIGNETTE, anchored on the screen and not on the character (2026-09-03).
// It used to track the player's unprojected position, so the clear hole drove
// around the frame with them. Stan asked for a vignette instead: clear in the
// middle, grain in the corners and a little along the edges.
uniform vec2 vignette_center_uv = vec2(0.5, 0.5);
uniform vec2 viewport_size;
// BOTH ARE FRACTIONS OF THE HALF-DIAGONAL, not pixels. As pixels they could
// not describe a vignette: 400/400 on a 1280x720 screen put full grain at
// 800 px while the corner is only 734 px out, so the corners never reached it
// and the effect had no visible edge at all. In these units 1.0 IS the corner,
// whatever the resolution.
uniform float fade_radius = 0.5;    // clear out to here
uniform float fade_distance = 0.5;  // ...then grain ramps in over this much
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
    vec2 center_px = vignette_center_uv * viewport_size;
    // Half the diagonal: the distance from the centre to a corner. Dividing by
    // it turns the pixel distance below into "how far toward the corner am I",
    // which is what makes the two radii resolution-independent.
    float half_diagonal = max(length(viewport_size) * 0.5, 1.0);
    
    vec3 scene_col = texture(SCREEN_TEXTURE, uv).rgb;
    
    if (!effect_enabled) {
        COLOR = vec4(scene_col, 1.0);
    } else {
        float dist = distance(frag_px, center_px) / half_diagonal;
        float t = clamp((dist - fade_radius) / max(fade_distance, 0.001), 0.0, 1.0);
        
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