// retro_post.gdshader — único pase de post-procesado del pipeline retro.
// Se aplica sobre un ColorRect a pantalla completa que muestrea la textura del
// SubViewport donde se renderiza el juego (resolución interna, p.ej. 640x360).
//
// Orden fijo de los pasos (cada uno con su bool de bypass y su intensidad):
//   1. Dither ordenado Bayer 8x8   (ANTES de cuantizar: desplaza el color justo
//                                   lo suficiente para que el redondeo cambie de
//                                   nivel según el patrón; después de cuantizar
//                                   sólo sería ruido superpuesto)
//   2. Cuantización de color        (a) N niveles por canal  (b) paleta 1D
//   3. Grano de película animado    (TIME)
//   4. Viñeta radial
shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Textura del SubViewport del juego. filter_nearest: nunca interpolamos píxeles internos.
uniform sampler2D screen_tex : filter_nearest, repeat_disable;
// Resolución interna del framebuffer (la asigna RetroRenderer).
uniform vec2 internal_resolution = vec2(640.0, 360.0);

// ------------------------------------------------------------ 0. Pixelación
// Tamaño del bloque de píxeles en píxeles internos. 1 = sin efecto (la pixelación
// la da sólo la resolución interna). 2-4 = bloques más gordos SIN bajar la resolución
// de render: la geometría, sombras y UI del juego se calculan igual, sólo la imagen
// final se agrupa en bloques. El dither y el grano se alinean al mismo bloque.
uniform int pixel_size : hint_range(1, 8) = 1;

// ---------------------------------------------------------------- 1. Dither
uniform bool  dither_enabled = true;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.35;
// Anclaje del patrón Bayer:
//   0 = SCREEN      -> celda = píxel del viewport donde corre el post (FRAGCOORD).
//   1 = FRAMEBUFFER -> celda = píxel de la resolución interna (floor(UV * internal_resolution)).
//
// TRADE-OFF: con stretch_mode=viewport ambos coinciden (el post corre a resolución
// interna). Difieren cuando el post corre a otra resolución (p.ej. stretch canvas_items
// o resolución interna cambiada sin tocar content_scale_size): en SCREEN el patrón usa
// píxeles de ventana, más fino que el píxel del juego, y "flota" como una rejilla
// superpuesta mientras la imagen se mueve a saltos de píxel interno. FRAMEBUFFER fija
// el patrón a la rejilla interna: el dither "pertenece" al píxel del juego y escala con él.
// Ninguno de los dos ancla el patrón al MUNDO: al mover la cámara el contenido se
// desplaza bajo un patrón fijo en pantalla. Para eso existe `dither_offset` (en píxeles
// internos): RetroRenderer.set_dither_offset() permite desplazar el patrón siguiendo la
// cámara (p.ej. paneo 2D / cámara ortográfica) y clavarlo al mundo.
uniform int   dither_space : hint_range(0, 1) = 1;
uniform vec2  dither_offset = vec2(0.0);
// Amplitud del dither en unidades de color. 0 = automático:
//   modo niveles -> 1/(niveles-1)  (exactamente un escalón de cuantización)
//   modo paleta  -> 1/8            (las paletas no son escaleras uniformes)
uniform float dither_spread : hint_range(0.0, 0.5, 0.005) = 0.0;

// ---------------------------------------------------------- 2. Cuantización
uniform bool  quantize_enabled = true;
// 0 = N niveles por canal, 1 = paleta (textura Nx1, color más cercano en RGB)
uniform int   quantize_mode : hint_range(0, 1) = 0;
uniform float quantize_strength : hint_range(0.0, 1.0) = 1.0;
uniform int   color_levels : hint_range(2, 64) = 32;
uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable, hint_default_black;
uniform int   palette_size : hint_range(1, 256) = 16;

// ------------------------------------------------------------------ 3. Grano
uniform bool  grain_enabled = true;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.03;
// Veces por segundo que cambia el patrón de grano (24 ~ cine).
uniform float grain_speed : hint_range(0.0, 60.0) = 8.0;

// ----------------------------------------------------------------- 4. Viñeta
uniform bool  vignette_enabled = true;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.25;
// Radio (0 = centro, 1 = borde corto de la pantalla) a partir del que oscurece.
uniform float vignette_radius : hint_range(0.0, 1.5) = 0.75;
// Anchura de la transición.
uniform float vignette_softness : hint_range(0.01, 1.0) = 0.6;


// Umbral Bayer 8x8 calculado por bits (equivale a la matriz clásica /64).
// Para cada bit k: par (2*(x^y)_k + y_k) en orden inverso de significancia.
float bayer8(ivec2 p) {
	int x = p.x & 7;
	int y = p.y & 7;
	int xy = x ^ y;
	int v = 0;
	v |= (((xy >> 0) & 1) << 5) | (((y >> 0) & 1) << 4);
	v |= (((xy >> 1) & 1) << 3) | (((y >> 1) & 1) << 2);
	v |= (((xy >> 2) & 1) << 1) | (((y >> 2) & 1) << 0);
	return (float(v) + 0.5) / 64.0;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 quantize_levels(vec3 c, int levels) {
	float n = float(levels - 1);
	return floor(c * n + 0.5) / n;
}

vec3 quantize_palette(vec3 c) {
	vec3 best = vec3(0.0);
	float best_d = 1e9;
	for (int i = 0; i < 256; i++) {
		if (i >= palette_size) {
			break;
		}
		vec3 p = texelFetch(palette_tex, ivec2(i, 0), 0).rgb;
		vec3 d = (c - p) * vec3(0.30, 0.59, 0.11); // distancia ponderada por luminancia
		float dist = dot(d, d);
		if (dist < best_d) {
			best_d = dist;
			best = p;
		}
	}
	return best;
}

void fragment() {
	// 0. Pixelación: muestrear el centro del bloque.
	vec2 sample_uv = UV;
	float block = float(max(pixel_size, 1));
	if (pixel_size > 1) {
		vec2 grid = internal_resolution / block;
		sample_uv = (floor(UV * grid) + 0.5) / grid;
	}
	vec3 color = texture(screen_tex, sample_uv).rgb;
	// Coordenada de píxel interno (o de bloque): grano y dither en modo FRAMEBUFFER.
	vec2 fb_px = floor(UV * internal_resolution / block);

	// 1. Dither (antes de cuantizar)
	if (dither_enabled) {
		vec2 px = (dither_space == 0) ? floor(FRAGCOORD.xy) : fb_px;
		float threshold = bayer8(ivec2(px + dither_offset)) - 0.5; // [-0.49, 0.49]
		float spread = dither_spread;
		if (spread <= 0.0) {
			spread = (quantize_mode == 0) ? 1.0 / float(max(color_levels - 1, 1)) : 1.0 / 8.0;
		}
		color += threshold * spread * dither_strength;
	}

	// 2. Cuantización
	if (quantize_enabled) {
		vec3 q = (quantize_mode == 0) ? quantize_levels(clamp(color, 0.0, 1.0), color_levels)
		                              : quantize_palette(clamp(color, 0.0, 1.0));
		color = mix(color, q, quantize_strength);
	}

	// 3. Grano animado
	if (grain_enabled) {
		float t = floor(TIME * grain_speed);
		float n = hash12(fb_px + vec2(t * 17.0, t * 31.0)) - 0.5;
		color += n * grain_strength;
	}

	// 4. Viñeta radial (elíptica, ajustada al aspecto de pantalla)
	if (vignette_enabled) {
		float d = length((UV - 0.5) * 2.0);
		float v = smoothstep(vignette_radius, vignette_radius + vignette_softness, d);
		color *= 1.0 - v * vignette_strength;
	}

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
