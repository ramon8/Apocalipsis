// ground.gdshader — suelo procedural estilo pixel-art.
// Base: textura tileada (o color plano) + ruido en espacio de mundo (manchas grandes,
// grano fino, motas). Encima, dos capas opcionales:
//   - hierba a parches (ruido umbralizado, dos tonos) que evita los caminos
//   - caminos de tierra desde una mascara (GroundPaths la pinta desde Path3D) con el
//     borde desgastado por ruido
// Todo se muestrea snapeado a una rejilla de texels y se cuantiza a pocos niveles, para
// que se lea como pixeles gordos y no como ruido suave.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// true = look pixel-art (texels snapeados, ruido cuantizado, bordes duros y punteados).
// false = continuo: coordenadas sin snap, ruido suave, bordes con degradado. Comparar y elegir.
uniform bool pixel_art = true;
uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable, hint_default_white;
// Suavidad de los bordes (hierba, camino) en modo continuo, en valor de ruido.
uniform float smooth_edge : hint_range(0.01, 0.5, 0.01) = 0.12;
uniform vec4 albedo_color : source_color = vec4(0.53, 0.40, 0.31, 1.0);
// Metres covered by one texture tile.
uniform float tile_size : hint_range(0.25, 20.0, 0.25) = 2.0;

// Texels per metre of the procedural pattern (higher = finer pixels).
uniform float texels_per_meter : hint_range(1.0, 64.0, 1.0) = 4.0;
// Number of brightness steps the noise is quantized to (2-3 = very pixel-art, 8 = soft).
uniform int levels : hint_range(2, 16) = 3;

// Large patches: size in metres; separate strength for the darker and the lighter areas.
uniform float patch_size : hint_range(0.5, 30.0, 0.5) = 8.0;
uniform float patch_dark_strength : hint_range(0.0, 0.8, 0.01) = 0.14;
uniform float patch_light_strength : hint_range(0.0, 0.8, 0.01) = 0.28;
// Fine grain: size in metres and strength.
uniform float grain_size : hint_range(0.05, 4.0, 0.05) = 1.0;
uniform float grain_strength : hint_range(0.0, 0.5, 0.01) = 0.08;
// Speckles (pebbles/dark spots): probability per texel; colour = base * multiplier,
// so they follow whatever texture/colour the ground has.
uniform float speckle_density : hint_range(0.0, 0.2, 0.001) = 0.015;
uniform float speckle_brightness : hint_range(0.2, 1.0, 0.05) = 0.65;
uniform float light_speckle_density : hint_range(0.0, 0.2, 0.001) = 0.006;
uniform float light_speckle_brightness : hint_range(1.0, 2.0, 0.05) = 1.3;
// Darker patches drift towards this tint (multiplied with the base colour).
uniform vec4 patch_tint : source_color = vec4(0.85, 0.8, 0.8, 1.0);
uniform float patch_tint_strength : hint_range(0.0, 1.0, 0.05) = 0.4;

group_uniforms grass;
uniform bool grass_enabled = true;
// Fraccion del suelo cubierta de hierba (0 = nada, 1 = todo).
uniform float grass_coverage : hint_range(0.0, 1.0, 0.01) = 0.5;
// Tamano de los parches (m) y del detalle que rompe su borde (m).
uniform float grass_scale : hint_range(1.0, 60.0, 0.5) = 9.0;
uniform float grass_detail_scale : hint_range(0.25, 10.0, 0.25) = 1.5;
uniform vec4 grass_color : source_color = vec4(0.32, 0.38, 0.26, 1.0);
// Segundo tono (hierba en sombra / mas densa) y cuanta superficie ocupa dentro del parche.
uniform vec4 grass_dark_color : source_color = vec4(0.15, 0.16, 0.06, 1.0);
uniform float grass_dark_amount : hint_range(0.0, 1.0, 0.05) = 0.35;
// Motas claras sobre la hierba (florecillas/puntas secas), probabilidad por texel.
uniform float grass_speckle_density : hint_range(0.0, 0.2, 0.001) = 0.01;
// Ancho (en valor de ruido) de la banda punteada en el borde de los parches.
uniform float grass_edge_dither : hint_range(0.0, 0.3, 0.01) = 0.1;
// Hasta que valor de la mascara de camino (anillos exteriores) la hierba se retira.
uniform float grass_path_margin : hint_range(0.0, 1.0, 0.05) = 0.3;

group_uniforms paths;
// Mascara pintada por GroundPaths: 0 = sin camino, 1 = nucleo del camino.
uniform sampler2D path_mask : hint_default_black, filter_nearest, repeat_disable;
// Region del mundo que cubre la mascara: (min_x, min_z, ancho, alto) en metros.
uniform vec4 path_region = vec4(-128.0, -128.0, 256.0, 256.0);
// Tinte del camino (multiplica la base): un poco mas claro y calido que el suelo.
uniform vec4 path_tint : source_color = vec4(1.08, 1.02, 0.92, 1.0);
// Irregularidad del borde (0 = borde limpio al ancho del camino, 1 = muy desgastado).
uniform float path_edge_noise : hint_range(0.0, 1.0, 0.05) = 0.6;
uniform float path_edge_scale : hint_range(0.25, 10.0, 0.25) = 1.25;
// Las motas del suelo se reducen dentro del camino (tierra pisada, mas lisa).
uniform float path_speckle_factor : hint_range(0.0, 1.0, 0.05) = 0.3;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Smooth value noise in [0,1].
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Ruido de gradiente (Perlin 2D con gradientes por hash), en [0,1]. Sin la rejilla
// axial del ruido de valor: al umbralizarlo no salen bordes rectos.
vec2 grad2(vec2 i) {
	float a = hash21(i) * 6.2831853;
	return vec2(cos(a), sin(a));
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(grad2(i), f);
	float b = dot(grad2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(grad2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(grad2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.7 + 0.5;
}

// Dos octavas rotadas + deformacion del dominio: parches organicos sin direccion dominante.
float organic(vec2 p, float scale) {
	const mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 q = p / scale;
	vec2 warp = vec2(gnoise(q * 0.7 + 13.0), gnoise(q * 0.7 + 71.0)) - 0.5;
	q += warp * 0.9;
	float v = gnoise(q) * 0.65 + gnoise(rot * q * 2.1 + 5.0) * 0.35;
	return clamp((v - 0.5) * 1.8 + 0.5, 0.0, 1.0);  // recuperar contraste
}

float quantize(float v) {
	if (!pixel_art) {
		return v;
	}
	float n = float(max(levels - 1, 1));
	return floor(v * n + 0.5) / n;
}

// Valor de la mascara de caminos en este texel (0 fuera de la region).
float path_mask_at(vec2 texel) {
	vec2 uv = (texel - path_region.xy) / path_region.zw;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 0.0;
	}
	return texture(path_mask, uv).r;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Snap the sample position to the texel grid: crisp pixels instead of smooth gradients.
	vec2 texel = pixel_art ? floor(world_pos.xz * texels_per_meter) / texels_per_meter : world_pos.xz;

	vec3 base = texture(albedo_tex, texel / tile_size).rgb * albedo_color.rgb;

	// Large patches (two octaves), centred on 0.
	float patch = vnoise(texel / patch_size) * 0.65 + vnoise(texel / patch_size * 2.3 + 17.0) * 0.35;
	patch = quantize(patch) - 0.5;
	// Fine grain.
	float grain = quantize(vnoise(texel / grain_size)) - 0.5;

	float patch_gain = (patch >= 0.0) ? patch_light_strength : patch_dark_strength;
	vec3 col = base * (1.0 + patch * 2.0 * patch_gain + grain * 2.0 * grain_strength);
	// Tint the darker patches.
	float dampness = clamp(-patch * 2.0, 0.0, 1.0) * patch_tint_strength;
	col = mix(col, col * patch_tint.rgb, dampness);

	// --- caminos: mascara + ruido en el umbral = borde desgastado.
	float mask = path_mask_at(texel);
	float edge_n = organic(texel + 101.0, path_edge_scale);
	float threshold = 0.5 + (edge_n - 0.5) * path_edge_noise;
	float path = pixel_art ? ((mask > 0.0 && mask >= threshold) ? 1.0 : 0.0)
			: smoothstep(threshold - smooth_edge * 0.5, threshold + smooth_edge * 0.5, mask) * step(0.001, mask);

	// --- hierba a parches, lejos de los caminos.
	float grass = 0.0;
	vec3 grass_col = grass_color.rgb;
	if (grass_enabled) {
		float g = organic(texel + 3.0, grass_scale) * 0.6 + organic(texel + 31.0, grass_detail_scale) * 0.4;
		float thr = 1.0 - grass_coverage;
		// Borde punteado: en una banda alrededor del umbral cada texel decide al azar, asi el
		// parche se deshilacha en matas sueltas en vez de cortarse en bloque.
		float band = grass_edge_dither;
		float dither_r = hash21(texel * 3.3 + 11.0);
		float dark = organic(texel + 7.0, grass_detail_scale * 1.7);
		if (pixel_art) {
			if (g > thr + band) {
				grass = 1.0;
			} else if (g > thr - band) {
				grass = (dither_r < (g - (thr - band)) / (2.0 * band)) ? 1.0 : 0.0;
			}
			// Se retira del camino y de sus anillos exteriores (tambien con borde punteado).
			if (mask > grass_path_margin) {
				grass = 0.0;
			} else if (mask > 0.0) {
				grass *= (dither_r < 1.0 - mask / grass_path_margin) ? 1.0 : 0.0;
			}
			float in_core = (g > thr + band + 0.08) ? 1.0 : 0.0;  // el tono oscuro solo en el interior
			grass_col = mix(grass_color.rgb, grass_dark_color.rgb, in_core * ((dark > 1.0 - grass_dark_amount) ? 1.0 : 0.0));
		} else {
			grass = smoothstep(thr - smooth_edge, thr + smooth_edge, g);
			grass *= 1.0 - smoothstep(0.0, grass_path_margin, mask);
			float in_core = smoothstep(thr, thr + smooth_edge * 2.0, g);
			float dark_w = smoothstep(1.0 - grass_dark_amount - 0.1, 1.0 - grass_dark_amount + 0.1, dark);
			grass_col = mix(grass_color.rgb, grass_dark_color.rgb, in_core * dark_w);
		}
		grass *= 1.0 - path;
		grass_col *= 1.0 + grain * 2.0 * grain_strength;
	}

	// Speckles, one texel each (solo tienen sentido con texels: en continuo serian ruido por pixel).
	float s = hash21(texel * 7.1 + 3.7);
	float speckle_scale = pixel_art ? mix(1.0, path_speckle_factor, path) : 0.0;
	if (s < speckle_density * speckle_scale) {
		col = base * speckle_brightness;
	} else if (s > 1.0 - light_speckle_density * speckle_scale) {
		col = base * light_speckle_brightness;
	}

	col = mix(col, col * path_tint.rgb, path);
	if (pixel_art) {
		if (grass > 0.5) {
			col = grass_col;
			if (s > 1.0 - grass_speckle_density) {
				col = grass_color.rgb * 1.35;
			}
		}
	} else {
		col = mix(col, grass_col, grass);
	}

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
