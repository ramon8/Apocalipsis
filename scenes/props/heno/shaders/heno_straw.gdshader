// heno_straw.gdshader — paja procedural para un fardo de heno (caja).
// Iluminado (reacciona al sol / dia-noche). Todo en fragment, sin texturas extra:
//  - caras laterales y superior: hebras alargadas a lo largo del fardo (ruido anisotropo)
//  - extremos (±X): puntas de paja cortadas (motas)
//  - cuerdas de atado alrededor del fardo
//  - snap a texels + cuantizacion en gamma para el look retro (como el suelo)
shader_type spatial;
render_mode cull_disabled;

group_uniforms Colors;
uniform vec3 straw_light : source_color = vec3(0.753, 0.757, 0.533);
uniform vec3 straw_dark : source_color = vec3(0.525, 0.388, 0.314);
// Tinte verdoso en manchas (heno mas fresco) mezclado por ruido grande.
uniform vec3 straw_green : source_color = vec3(0.627, 0.596, 0.471);
uniform float green_amount : hint_range(0.0, 1.0, 0.05) = 0.3;

group_uniforms Straw;
// Hebras por metro a lo ancho (perpendicular a la hebra).
uniform float strand_density : hint_range(2.0, 40.0, 1.0) = 5.0;
// Cuanto se alargan las hebras (1 = ruido isotropo).
uniform float strand_stretch : hint_range(1.0, 20.0, 0.5) = 7.0;
// Contraste claro/oscuro entre hebras.
uniform float strand_contrast : hint_range(0.0, 1.0, 0.05) = 0.75;
// Motas de las puntas cortadas en los extremos.
uniform float end_dot_density : hint_range(4.0, 60.0, 1.0) = 22.0;

group_uniforms Twine;
uniform bool twine_enabled = true;
uniform vec3 twine_color : source_color = vec3(0.11, 0.063, 0.035);
// Posiciones de las cuerdas a lo largo del fardo (fraccion de la mitad de la longitud).
uniform float twine_offset : hint_range(0.0, 1.0, 0.05) = 0.65;
uniform float twine_width : hint_range(0.005, 0.1, 0.005) = 0.065;
// Longitud del fardo en unidades de objeto (semi-longitud en X). Lo fija el script.
uniform float half_length = 3.0;

group_uniforms Retro;
// Texels por unidad de objeto (chunky pixels, como ground.gdshader).
uniform float texels_per_unit : hint_range(1.0, 32.0, 1.0) = 8.0;
// Niveles de cuantizacion en gamma (0 = off).
uniform int levels : hint_range(0, 16) = 6;
uniform float roughness : hint_range(0.0, 1.0, 0.05) = 0.95;
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
	vec3 an = abs(v_obj_normal);
	// Snap a la rejilla de texels (en espacio objeto) para pixeles gordos y estables.
	vec3 sp = floor(v_obj_pos * texels_per_unit + 0.5) / texels_per_unit;

	float strands;
	vec2 plane;
	if (an.x > max(an.y, an.z)) {
		// Extremos: puntas cortadas -> motas de celda.
		plane = sp.zy;
		float cell = hash2(floor(plane * end_dot_density));
		float cell2 = hash2(floor(plane * end_dot_density * 0.5 + 7.0));
		strands = mix(cell, cell2, 0.4);
	} else {
		// Lados y arriba/abajo: hebras a lo largo de X.
		plane = (an.y > an.z) ? sp.xz : sp.xy;
		vec2 q = vec2(plane.x * strand_density / strand_stretch, plane.y * strand_density);
		float n1 = vnoise(q);
		float n2 = vnoise(q * 2.3 + 11.0);
		strands = n1 * 0.65 + n2 * 0.35;
		// Rotura de las hebras: cortes ocasionales a lo largo.
		float breaks = vnoise(vec2(plane.x * strand_density * 0.6 + 3.0, plane.y * strand_density * 3.0));
		strands = mix(strands, strands * 0.6, step(0.82, breaks));
	}

	// Color: claro/oscuro por hebra + manchas verdosas grandes.
	float t = clamp((strands - 0.5) * (1.0 + strand_contrast * 2.0) + 0.5, 0.0, 1.0);
	vec3 col = mix(straw_dark, straw_light, t);
	float g = vnoise(sp.xz * 0.9 + sp.y * 0.7 + 21.0);
	col = mix(col, straw_green, smoothstep(0.55, 0.8, g) * green_amount);

	// Cuerdas: dos bandas alrededor del fardo (no en los extremos).
	if (twine_enabled && an.x <= max(an.y, an.z)) {
		float d = min(abs(sp.x - half_length * twine_offset), abs(sp.x + half_length * twine_offset));
		float band = 1.0 - smoothstep(twine_width * half_length, twine_width * half_length * 1.5, d);
		col = mix(col, twine_color, band);
	}

	// Cuantizacion retro en gamma (en lineal aplasta los oscuros a negro).
	if (levels > 0) {
		vec3 gcol = pow(max(col, vec3(0.0)), vec3(1.0 / 2.2));
		gcol = floor(gcol * float(levels) + 0.5) / float(levels);
		col = pow(gcol, vec3(2.2));
	}

	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.1;
}
