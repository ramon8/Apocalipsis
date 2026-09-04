// room_corridor.gdshader — suelo del pasillo de salida: claro junto a la puerta y
// fundido a negro hacia fuera, para que se disuelva en el void del interior.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 color : source_color = vec3(0.95, 0.94, 0.9);
uniform float length = 1.8;
// >1 = se mantiene claro mas tiempo y cae al final; <1 = oscurece pronto.
uniform float fade_power : hint_range(0.5, 4.0, 0.1) = 1.6;

varying float v_t;

void vertex() {
	// PlaneMesh: z local de -length/2 (puerta) a +length/2 (fuera).
	v_t = clamp((VERTEX.z + length * 0.5) / max(length, 0.001), 0.0, 1.0);
}

void fragment() {
	// Fundido calculado en espacio perceptual (sRGB) y llevado a lineal: si se hiciera
	// en lineal, en pantalla se queda gris casi hasta el final.
	float fade_srgb = 1.0 - pow(v_t, fade_power);
	ALBEDO = color * pow(fade_srgb, 2.2);
}
