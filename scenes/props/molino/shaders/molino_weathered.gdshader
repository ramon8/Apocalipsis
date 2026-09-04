// molino_weathered.gdshader — envejecido procedural para el molino.
// Sobre la textura de paleta original añade, todo en fragment y sin texturas extra:
//  - mugre: manchas de value noise que oscurecen
//  - descolorido general por el sol
//  - suciedad de base: oscurecido hacia el suelo (lluvia/humedad)
shader_type spatial;
// cull_disabled: el glTF exporta estas mallas a doble cara (el tejado desaparece sin esto).
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest;

group_uniforms Grime;
// Manchas de mugre: intensidad del oscurecido.
uniform float grime_amount : hint_range(0.0, 1.0, 0.05) = 0.35;
// Escala de las manchas (metros).
uniform float grime_scale : hint_range(0.2, 10.0, 0.1) = 2.5;
// Desaturacion global (aspecto descolorido por el sol).
uniform float weathering : hint_range(0.0, 1.0, 0.05) = 0.25;

group_uniforms Base_dirt;
// Altura (m, espacio objeto) hasta la que sube la humedad desde la base.
uniform float dirt_height : hint_range(0.0, 20.0, 0.5) = 6.0;
uniform float dirt_amount : hint_range(0.0, 1.0, 0.05) = 0.4;
uniform vec3 dirt_tint : source_color = vec3(0.35, 0.3, 0.24);

group_uniforms Variation;
// Cambia el patron entre molinos (el script mete aqui un hash de la posicion).
uniform float seed_offset = 0.0;

varying vec3 v_obj_pos;
varying vec3 v_obj_normal;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed_offset) * 43758.5453);
}

// Value noise clasico, 1 octava.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x),
			mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	v_obj_pos = VERTEX;      // espacio objeto: el patron gira con las aspas
	v_obj_normal = NORMAL;
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb;

	// Proyeccion triplanar por eje dominante de la normal (sin costuras raras).
	vec3 an = abs(v_obj_normal);
	vec2 plane = an.y > max(an.x, an.z) ? v_obj_pos.xz
			: (an.x > an.z ? v_obj_pos.zy : v_obj_pos.xy);

	// --- mugre
	float g = vnoise(plane / grime_scale) * vnoise(plane / (grime_scale * 0.37) + 3.1);
	float grime = smoothstep(0.25, 0.75, g) * grime_amount;
	col = mix(col, col * 0.55, grime);

	// --- descolorido por el sol
	col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), weathering * 0.6);

	// --- humedad desde la base (solo cuerpo: por debajo de dirt_height)
	float dirt = (1.0 - smoothstep(0.0, dirt_height, v_obj_pos.y + 0.5))
			* (0.6 + 0.4 * vnoise(plane * 1.7)) * dirt_amount;
	col = mix(col, col * dirt_tint, dirt);

	ALBEDO = col;
}
