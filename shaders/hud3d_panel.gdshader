shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform sampler2D albedo_texture;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint_color : source_color = vec4(1.0);

// Насколько быстро исчезать к краям
uniform float edge_softness : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    vec4 base_tex = texture(albedo_texture, UV);
    vec4 color = base_tex * tint_color;

    // Центр UV.x = 0.5
    float dist_from_center = abs(UV.x - 0.5) * 2.0; 
    // Преобразуем расстояние в плавный градиент
    float edge = 1.0 - smoothstep(0.0, edge_softness, dist_from_center);

    // Общая прозрачность
    color.a *= fade * edge;

    ALBEDO = color.rgb;
    ALPHA = color.a;
    EMISSION = color.rgb * color.a;
}
