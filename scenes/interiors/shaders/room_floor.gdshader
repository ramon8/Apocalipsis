// room_floor.gdshader — suelo sucio procedural para el interior de una habitacion.
// Sin luz (unshaded): el interior es un void negro y el suelo se pinta solo.
// Tierra pisada con manchas de mugre, motas y oscurecido hacia las paredes.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 base_color : source_color = vec3(0.32, 0.26, 0.19);
uniform vec3 dirt_color : source_color = vec3(0.16, 0.12, 0.08);
// Cantidad de manchas de suciedad.
uniform float dirt_amount : hint_range(0.0, 1.0, 0.05) = 0.55;
// Escala de las manchas (metros).
uniform float dirt_scale : hint_range(0.2, 5.0, 0.1) = 1.2;
// Motas pequenas (piedrecitas / restos).
uniform float speckle_amount : hint_range(0.0, 1.0, 0.05) = 0.35;
// Oscurecido radial hacia el borde (paredes).
uniform float edge_darkening : hint_range(0.0, 1.0, 0.05) = 0.45;
// Radio del suelo en unidades locales (para el oscurecido del borde).
uniform float floor_radius = 2.0;
// Planta rectangular: semiejes (m). (0,0) = circular (usa floor_radius).
uniform vec2 floor_half = vec2(0.0);
// Cuantiza el resultado a N niveles (0 = desactivado, recomendado: el post retro
// ya cuantiza la pantalla entera; niveles bajos aplastan el tono a gris).
uniform int levels : hint_range(0, 16) = 0;
uniform float seed_offset = 0.0;

varying vec3 v_local;

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
	v_local = VERTEX;
}

void fragment() {
	vec2 p = v_local.xz;
	// Manchas grandes + medianas de tierra sucia.
	float d = vnoise(p / dirt_scale) * 0.6 + vnoise(p / (dirt_scale * 0.31) + 5.7) * 0.4;
	float dirt = smoothstep(0.35, 0.75, d) * dirt_amount;
	vec3 col = mix(base_color, dirt_color, dirt);
	// Motas: puntos sueltos mas claros y mas oscuros.
	float sp = hash2(floor(p * 9.0));
	col = mix(col, col * 1.35, step(0.985, sp) * speckle_amount);
	col = mix(col, col * 0.6, step(sp, 0.012) * speckle_amount);
	// Mas sucio y oscuro pegado a las paredes.
	float edge;
	if (floor_half.x > 0.0) {
		// Distancia normalizada al borde mas cercano del rectangulo.
		vec2 q = abs(p) / floor_half;
		edge = smoothstep(0.55, 1.0, max(q.x, q.y));
	} else {
		edge = smoothstep(floor_radius * 0.55, floor_radius, length(p));
	}
	col = mix(col, col * (1.0 - edge_darkening), edge * (0.6 + 0.4 * vnoise(p * 2.3)));
	// Cuantizacion retro. OJO: los source_color llegan en espacio LINEAL (muy oscuros:
	// 0.32 sRGB ~ 0.08 lineal); cuantizar ahi aplasta todo a negro. Se cuantiza en gamma.
	if (levels > 0) {
		vec3 g = pow(max(col, vec3(0.0)), vec3(1.0 / 2.2));
		g = floor(g * float(levels) + 0.5) / float(levels);
		col = pow(g, vec3(2.2));
	}
	ALBEDO = col;
}
