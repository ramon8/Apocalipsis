// npc_tint.gdshader — recolorea la textura de paleta del NPC por partes (ropa, piel...)
// con un giro de tono, saturacion y valor. Iluminado, filtro nearest.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_nearest;
// Giro de tono en vueltas (0..1 = 0..360 grados).
uniform float hue_shift : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float sat_mul : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float val_mul : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float roughness : hint_range(0.0, 1.0, 0.05) = 0.9;
// Piel: los texels cuyo tono original cae en este rango (naranjas de la paleta) usan
// la variacion de piel en vez de la de ropa (manos dentro de la malla de brazos, etc.).
uniform bool skin_detect = true;
uniform float skin_hue_min : hint_range(0.0, 1.0, 0.005) = 0.02;
uniform float skin_hue_max : hint_range(0.0, 1.0, 0.005) = 0.11;
uniform float skin_hue_shift : hint_range(-0.2, 0.2, 0.005) = 0.0;
uniform float skin_val_mul : hint_range(0.0, 2.0, 0.01) = 1.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb2hsv(col);
	bool is_skin = skin_detect && hsv.x >= skin_hue_min && hsv.x <= skin_hue_max && hsv.y > 0.15;
	if (is_skin) {
		hsv.x = fract(hsv.x + skin_hue_shift);
		hsv.z = clamp(hsv.z * skin_val_mul, 0.0, 1.0);
	} else {
		hsv.x = fract(hsv.x + hue_shift);
		hsv.y = clamp(hsv.y * sat_mul, 0.0, 1.0);
		hsv.z = clamp(hsv.z * val_mul, 0.0, 1.0);
	}
	ALBEDO = hsv2rgb(hsv);
	ROUGHNESS = roughness;
	SPECULAR = 0.15;
}
