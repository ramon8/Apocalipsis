// heno_pile.gdshader — paja suelta para una PILA de heno (monticulo).
// Iluminado. A diferencia del fardo (hebras prensadas a lo largo), aqui la paja cae por
// la ladera: hebras verticales que se abren radialmente en la cima, mas oscuras y
// apelmazadas hacia la base, con briznas sueltas mas claras. Snap a texels + niveles retro.
shader_type spatial;
render_mode cull_disabled;

group_uniforms Colors;
uniform vec3 straw_light : source_color = vec3(0.753, 0.757, 0.533);
uniform vec3 straw_dark : source_color = vec3(0.525, 0.388, 0.314);
uniform vec3 straw_green : source_color = vec3(0.627, 0.596, 0.471);
uniform float green_amount : hint_range(0.0, 1.0, 0.05) = 0.25;
// Oscurecido hacia la base (paja apelmazada / sombra).
uniform float base_darkening : hint_range(0.0, 1.0, 0.05) = 0.45;

group_uniforms Straw;
uniform float strand_density : hint_range(2.0, 40.0, 1.0) = 12.0;
uniform float strand_stretch : hint_range(1.0, 20.0, 0.5) = 6.0;
uniform float strand_contrast : hint_range(0.0, 1.0, 0.05) = 0.7;
// Briznas sueltas mas claras por encima.
uniform float loose_amount : hint_range(0.0, 1.0, 0.05) = 0.35;

group_uniforms Retro;
uniform float texels_per_unit : hint_range(1.0, 32.0, 1.0) = 6.0;
uniform int levels : hint_range(0, 16) = 6;
uniform float roughness : hint_range(0.0, 1.0, 0.05) = 0.95;
// Altura del monticulo en unidades de objeto (para el oscurecido). Lo fija el script.
uniform float pile_height = 8.5;
uniform float seed_offset = 0.0;

varying vec3 v_obj_pos;
varying vec3 v_obj_normal;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed_offset) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x),
			mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	v_obj_pos = VERTEX;
	v_obj_normal = NORMAL;
}

void fragment() {
	vec3 sp = floor(v_obj_pos * texels_per_unit + 0.5) / texels_per_unit;
	float theta = atan(sp.z, sp.x);
	float radial = length(sp.xz);
	float ref_r = max(pile_height, 1.0);

	// Ladera: hebras verticales (caen). Coordenadas (angulo desenrollado, altura).
	vec2 side = vec2(theta * ref_r * strand_density, sp.y * strand_density / strand_stretch);
	float n_side = vnoise(side) * 0.65 + vnoise(side * 2.1 + 9.0) * 0.35;
	// Cima: hebras radiales desde el centro. Coordenadas (angulo * radio, radio).
	vec2 top = vec2(theta * max(radial, 0.3) * strand_density, radial * strand_density / strand_stretch);
	float n_top = vnoise(top) * 0.65 + vnoise(top * 2.1 + 4.0) * 0.35;
	float up = smoothstep(0.45, 0.85, abs(v_obj_normal.y));
	float strands = mix(n_side, n_top, up);

	// Briznas sueltas: trazos cortos y claros repartidos.
	float loose = step(0.93, vnoise(vec2(theta * ref_r * strand_density * 1.7, sp.y * strand_density * 0.4 + 17.0)));

	float t = clamp((strands - 0.5) * (1.0 + strand_contrast * 2.0) + 0.5, 0.0, 1.0);
	vec3 col = mix(straw_dark, straw_light, t);
	col = mix(col, straw_light * 1.08, loose * loose_amount);
	float g = vnoise(vec2(theta * ref_r * 0.5, sp.y * 0.6) + 31.0);
	col = mix(col, straw_green, smoothstep(0.55, 0.8, g) * green_amount);
	// Base mas oscura y apelmazada.
	float h = clamp(sp.y / max(pile_height, 0.001), 0.0, 1.0);
	col *= 1.0 - base_darkening * (1.0 - smoothstep(0.0, 0.6, h));

	if (levels > 0) {
		vec3 gcol = pow(max(col, vec3(0.0)), vec3(1.0 / 2.2));
		gcol = floor(gcol * float(levels) + 0.5) / float(levels);
		col = pow(gcol, vec3(2.2));
	}

	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.1;
}
