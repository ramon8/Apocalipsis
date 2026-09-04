// wood.gdshader — madera de tronco procedural, con la paleta del juego.
// Pensado para cilindros con el eje en Y local (CylinderMesh): en los laterales veta
// longitudinal (a lo largo del eje) y corteza mas oscura; en las tapas anillos
// concentricos. Todo en fragment sin texturas; el color final se ajusta al color mas
// cercano de la paleta de 8 (assets/textures/palette.png) para que case con el resto.
shader_type spatial;

group_uniforms Wood;
uniform vec3 wood_light : source_color = vec3(0.627, 0.596, 0.471);  // #a09878
uniform vec3 wood_dark : source_color = vec3(0.525, 0.388, 0.314);   // #866350
uniform vec3 bark_color : source_color = vec3(0.263, 0.125, 0.082);  // #432015
uniform vec3 bark_dark : source_color = vec3(0.11, 0.063, 0.035);    // #1c1009
// Vetas por unidad a lo largo del perimetro y anillos por unidad de radio.
uniform float grain_density : hint_range(1.0, 40.0, 0.5) = 9.0;
uniform float ring_density : hint_range(2.0, 40.0, 0.5) = 14.0;
// 0 = tronco pelado (madera en los laterales); 1 = con corteza en los laterales.
uniform float bark_amount : hint_range(0.0, 1.0, 0.05) = 1.0;
// Ondulacion de la veta / anillos.
uniform float wobble : hint_range(0.0, 1.0, 0.05) = 0.35;
// Madera serrada (tablones, cajas): veta plana a lo largo del eje X local en todas las
// caras, sin corteza ni anillos. Para cilindros/troncos dejarlo en false.
uniform bool flat_grain = false;

group_uniforms Retro;
uniform bool palette_snap = true;
uniform float texels_per_unit : hint_range(1.0, 64.0, 1.0) = 24.0;
uniform float roughness : hint_range(0.0, 1.0, 0.05) = 0.95;
uniform float seed_offset = 0.0;

const int PALETTE_SIZE = 8;
const vec3 PALETTE[8] = {
	vec3(0.753, 0.757, 0.533), vec3(0.627, 0.596, 0.471), vec3(0.322, 0.380, 0.263),
	vec3(0.153, 0.161, 0.063), vec3(0.525, 0.388, 0.314), vec3(0.510, 0.247, 0.227),
	vec3(0.263, 0.125, 0.082), vec3(0.110, 0.063, 0.035)
};

varying vec3 v_pos;
varying vec3 v_normal;
// Semilla por instancia (MultiMesh: custom_data.x); 0 en mallas normales.
varying float v_seed;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed_offset + v_seed) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x),
			mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

// Color de la paleta mas cercano (en espacio lineal, como llegan los source_color).
vec3 snap_palette(vec3 c) {
	vec3 best = PALETTE[0];
	float bd = 1e9;
	for (int i = 0; i < PALETTE_SIZE; i++) {
		vec3 p = pow(PALETTE[i], vec3(2.2));
		float d = dot(c - p, c - p);
		if (d < bd) { bd = d; best = p; }
	}
	return best;
}

void vertex() {
	v_pos = VERTEX;
	v_normal = NORMAL;
	v_seed = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec3 p = floor(v_pos * texels_per_unit + 0.5) / texels_per_unit;
	float r = length(p.xz);
	float ang = atan(p.z, p.x);
	vec3 col;
	if (flat_grain) {
		// Veta a lo largo de X; la coordenada transversal depende de la cara.
		float across = abs(v_normal.y) > 0.7 ? p.z : (abs(v_normal.x) > 0.7 ? p.z : p.y);
		float along = abs(v_normal.x) > 0.7 ? p.y : p.x;
		vec2 g = vec2(across * grain_density, along * grain_density * 0.2);
		float grain = vnoise(g + wobble * 2.0 * vnoise(g * 0.3 + 9.0));
		col = mix(wood_light, wood_dark, smoothstep(0.4, 0.75, grain));
		// Nudos ocasionales.
		float knot = vnoise(vec2(along * 1.5, across * 6.0) + 21.0);
		col = mix(col, wood_dark * 0.8, smoothstep(0.86, 0.95, knot));
	} else if (abs(v_normal.y) > 0.7) {
		// Tapa: anillos concentricos con ondulacion.
		float rr = r + wobble * 0.04 * vnoise(vec2(ang * 3.0, r * 6.0) + 5.0);
		float ring = fract(rr * ring_density);
		float band = smoothstep(0.35, 0.5, ring) - smoothstep(0.75, 0.9, ring);
		col = mix(wood_light, wood_dark, band);
		// Corteza en el borde exterior de la tapa.
		float edge = smoothstep(0.86, 0.96, r / max(length(vec2(0.5)), 0.001));
		col = mix(col, bark_color, edge * bark_amount);
	} else {
		// Lateral: veta a lo largo del eje Y, corteza rugosa por encima.
		vec2 g = vec2(ang * grain_density, p.y * grain_density * 0.25);
		float grain = vnoise(g + wobble * 2.0 * vnoise(g * 0.3 + 9.0));
		col = mix(wood_light, wood_dark, smoothstep(0.35, 0.7, grain));
		vec2 b = vec2(ang * grain_density * 0.8, p.y * grain_density * 0.9);
		float bark = vnoise(b) * 0.6 + vnoise(b * 2.7 + 3.0) * 0.4;
		vec3 barkc = mix(bark_dark, bark_color, smoothstep(0.3, 0.7, bark));
		col = mix(col, barkc, bark_amount);
	}
	if (palette_snap) {
		col = snap_palette(col);
	}
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.1;
}
