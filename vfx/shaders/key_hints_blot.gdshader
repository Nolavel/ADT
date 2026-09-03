shader_type canvas_item;

// =============================================================================
// key_hints_blot.gdshader — the ink-blot backing of the key-hints panel.
//
// Eight soft blobs whose union is the panel's background, brought in on ONE
// uniform. Eight nodes would be eight draw calls, eight tween targets and eight
// delays to keep in step; a single ColorRect with this shader is one of each,
// and the stagger becomes data rather than orchestration.
//
// THE RAGGED EDGE IS THE POINT. The HTML study this comes from gets its
// character from feTurbulence + feDisplacementMap (scale 18) — a torn ink
// contour, not a soft circle. The shader equivalent is DOMAIN WARPING: distort
// the coordinate BEFORE measuring distance to a centre, so the circle itself
// arrives torn. Warping the centres instead (which is the tempting shortcut)
// only slides eight smooth ellipses around and looks nothing like ink.
// =============================================================================

uniform float progress : hint_range(0.0, 1.0) = 0.0;
// Spread of the eight entrances. The ORDER values below come from the study's
// own transition-delays, so the ripple is the authored one rather than a
// linear ramp.
uniform float stagger : hint_range(0.0, 0.3) = 0.08;
uniform vec4 blob_color : source_color = vec4(0.02, 0.015, 0.01, 0.94);
// A plain multiplier on every radius. Named "softness" in the version this
// came from, but it never softened anything — it only scaled the blobs, and
// calling it softness is what sent me looking for the wrong fix first.
uniform float radius_scale : hint_range(0.1, 2.0) = 1.0;
// How far the contour is torn, in UV. 0 gives eight clean circles — that is
// the "before" of this file's whole reason to exist.
// The study displaces by 18 px on a 340 px box — about 5% — so that is the
// scale here too. 0.13 was my first guess and it tore the shape into pieces.
uniform float edge_ragged : hint_range(0.0, 0.4) = 0.05;
// Frequency of the tear. Low is a lazy wobble, high is a frayed rag.
uniform float warp_scale : hint_range(1.0, 12.0) = 4.5;
// Panel size in pixels, written by key_hints_panel.gd. Without it the blobs
// are round only when the panel happens to be square.
uniform vec2 rect_size = vec2(300.0, 240.0);
// Living ink: the tear crawls. OFF by default — a HUD element that never
// settles redraws every frame forever, and the FPS target is tight.
uniform float idle_drift : hint_range(0.0, 0.2) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// THE FALLOFF IS TRANSCRIBED FROM THE STUDY'S OWN radial-gradient, not chosen:
//
//   rgba(0,0,0,0.97) 0%, rgba(0,0,0,0.8) 35%, rgba(0,0,0,0.45) 65%, transparent 100%
//
// The first version used 1.0 - smoothstep(0, R, d), which is HALF this at the
// same distance — 0.30 where the study holds 0.45 — so each blob faded out
// before it reached its neighbours and the eight never fused into one mass.
// The blot rendered at roughly 56% of its intended size and I went looking at
// the radii, which were fine. Match the stops and the union appears.
float gradient_profile(float t) {
	if (t >= 1.0) {
		return 0.0;
	}
	if (t < 0.35) {
		return mix(0.97, 0.80, t / 0.35);
	}
	if (t < 0.65) {
		return mix(0.80, 0.45, (t - 0.35) / 0.30);
	}
	return mix(0.45, 0.0, (t - 0.65) / 0.35);
}

// `p` arrives warped; the aspect correction is applied to the DIFFERENCE, not
// to the coordinates, so `radius` stays in units of panel HEIGHT whatever the
// panel's proportions. Correcting the coordinates instead scales the centres
// away from where they were authored.
float blob(vec2 p, vec2 center, float radius, float aspect, float blob_progress) {
	vec2 diff = (p - center) * vec2(aspect, 1.0);
	float t = length(diff) / max(radius * radius_scale, 0.001);
	return gradient_profile(t) * blob_progress;
}

// smoothstep window for one blob, given its place in the authored order.
float entrance(float order, float p) {
	float start = order * stagger;
	return smoothstep(start, start + 0.2, p);
}

void fragment() {
	// Round blobs on a non-square panel: measure in a space where x carries the
	// panel's aspect, and put the centres in the same space.
	float aspect = max(rect_size.x, 1.0) / max(rect_size.y, 1.0);
	vec2 drift = vec2(TIME * idle_drift, TIME * idle_drift * 0.7);
	vec2 warp = vec2(
		fbm(UV * warp_scale + drift),
		fbm(UV * warp_scale + vec2(17.3, 5.1) + drift)
	) - 0.5;
	vec2 p = UV + warp * edge_ragged;

	// Centres and radii converted from the HTML study's own right/bottom
	// offsets on its 340x280 stack, so the mass hangs off the bottom-right
	// corner exactly as it does there. Radii are HALF-HEIGHT fractions (w/280/2
	// etc.) to match blob()'s height-based units — reading them as width
	// fractions is what shrank the whole thing to a smudge on the first try.
	// Order = that element's transition-delay divided by 0.07s, the smallest
	// non-zero one.
	float field = 0.0;
	field += blob(p, vec2(0.735, 0.768), 0.429, aspect, entrance(0.00, progress));
	field += blob(p, vec2(0.559, 0.750), 0.357, aspect, entrance(1.00, progress));
	field += blob(p, vec2(0.838, 0.554), 0.375, aspect, entrance(0.57, progress));
	field += blob(p, vec2(0.515, 0.625), 0.304, aspect, entrance(1.57, progress));
	field += blob(p, vec2(0.706, 0.464), 0.321, aspect, entrance(2.00, progress));
	field += blob(p, vec2(0.485, 0.518), 0.268, aspect, entrance(1.29, progress));
	field += blob(p, vec2(0.676, 0.357), 0.250, aspect, entrance(2.29, progress));
	field += blob(p, vec2(0.868, 0.411), 0.232, aspect, entrance(0.86, progress));

	field = clamp(field, 0.0, 1.0);
	field = pow(field, 0.75);
	COLOR = vec4(blob_color.rgb, blob_color.a * field);
}
