// ripple.gdshader — anillo de agua que se expande y se desvanece (chapoteo). Quad plano
// sobre el agua; `progress` 0..1 lo anima desde el codigo (SplashRipple).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.75, 0.76, 0.53, 1.0);
uniform float ring_width : hint_range(0.02, 0.5) = 0.12;
uniform float rings = 2.0;

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;  // 0 centro, 1 borde del quad
	float a = 0.0;
	for (int i = 0; i < 3; i++) {
		if (float(i) >= rings) {
			break;
		}
		float p = clamp(progress - float(i) * 0.18, 0.0, 1.0);
		float radius = p * 0.95;
		float band = 1.0 - smoothstep(0.0, ring_width, abs(r - radius));
		a = max(a, band * (1.0 - p) * (p > 0.0 ? 1.0 : 0.0));
	}
	ALBEDO = color.rgb;
	ALPHA = a * color.a * 0.8;
}
