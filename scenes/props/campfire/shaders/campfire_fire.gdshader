// Procedural pixel-art flame for crossed quads (UV: x 0..1 across, y 0 top .. 1 bottom).
// The flame is computed on a coarse cell grid and coloured with a hard 3-step ramp,
// so it reads as animated pixel art rather than smooth fire.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Cells across the quad (x) and up (y): the "pixel" resolution of the flame.
uniform vec2 cells = vec2(11.0, 16.0);
uniform float speed : hint_range(0.2, 6.0, 0.1) = 2.2;
uniform float turbulence : hint_range(0.0, 1.0, 0.05) = 0.45;
uniform vec4 color_core : source_color = vec4(1.0, 0.93, 0.55, 1.0);
uniform vec4 color_mid : source_color = vec4(0.98, 0.55, 0.15, 1.0);
uniform vec4 color_outer : source_color = vec4(0.75, 0.2, 0.08, 1.0);
// Overall flame amount: 1 = full blaze, lower = smaller shy flame (embers ~0.4).
uniform float intensity : hint_range(0.0, 1.5, 0.05) = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	// Per-instance phase so several campfires don't flicker in sync.
	float phase = fract(dot(NODE_POSITION_WORLD.xz, vec2(0.717, 0.331))) * 37.0;
	// Snap to the cell grid (chunky pixels), keep a stable id per cell.
	vec2 cell = floor(UV * cells);
	vec2 cuv = (cell + 0.5) / cells;
	float up = 1.0 - cuv.y;               // 0 base .. 1 tip
	float x = (cuv.x - 0.5) * 2.0;        // -1 .. 1

	// Rising noise: scrolls downward in UV so the flame licks upward.
	float n = vnoise(vec2(cell.x * 0.9 + phase, cuv.y * cells.y * 0.55 + TIME * speed * cells.y * 0.22 + phase));
	n = 0.65 * n + 0.35 * vnoise(vec2(cell.x * 1.7 - phase, cuv.y * cells.y * 1.1 + TIME * speed * cells.y * 0.4));

	// Teardrop shape: wide at the base, narrowing to the tip, eaten by noise.
	float body = 1.0 - up;
	float edge = 1.0 - abs(x) * (0.55 + up * 1.3);
	float f = min(body, edge) * intensity - n * turbulence * (0.35 + up);

	if (f < 0.06) {
		discard;
	}
	vec3 col = color_outer.rgb;
	if (f > 0.38) {
		col = color_core.rgb;
	} else if (f > 0.2) {
		col = color_mid.rgb;
	}
	ALBEDO = col;
	// A hint of emission-like brightness for the core against dark scenes.
	EMISSION = col * 0.6;
}
