// water.gdshader — agua de lago plana, estilo del suelo (misma paleta, mismo interruptor
// pixel_art). El lago es un plano que cubre el bbox de la orilla; la forma la da una
// mascara (Lake la pinta desde su Path3D): R = distancia a la orilla (0 en el borde,
// 1 a `mask_range` metros hacia dentro), G = 1 dentro / 0 fuera. Fuera se descarta.
// Ondas: ruido animado en bandas. Espuma: lineas que se alejan de la orilla.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D mask : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// Metros que cubre R = 1 en la mascara.
uniform float mask_range = 4.0;

uniform bool pixel_art = false;
uniform float texels_per_meter : hint_range(1.0, 64.0, 1.0) = 4.0;
uniform int levels : hint_range(2, 16) = 3;

group_uniforms color;
uniform vec4 deep_color : source_color = vec4(0.10, 0.13, 0.13, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.20, 0.24, 0.20, 1.0);
// Metros desde la orilla en los que el agua pasa de somera a profunda.
uniform float shallow_width : hint_range(0.1, 10.0, 0.1) = 2.5;
// Transparencia global y fundido con el suelo en el borde (m).
uniform float water_alpha : hint_range(0.0, 1.0, 0.05) = 0.92;
uniform float edge_fade : hint_range(0.0, 2.0, 0.05) = 0.35;

group_uniforms ripples;
uniform float ripple_scale : hint_range(0.5, 20.0, 0.5) = 3.0;
uniform float ripple_strength : hint_range(0.0, 0.6, 0.01) = 0.18;
uniform float ripple_speed : hint_range(0.0, 2.0, 0.05) = 0.25;
uniform vec2 ripple_direction = vec2(1.0, 0.4);

group_uniforms contact_foam;
// Espuma alrededor de lo que corta la superficie (piernas, postes, cacharros). Se buscan
// en pantalla, en un disco de `contact_radius_px`, puntos opacos cercanos a la linea de
// flotacion (hasta `contact_width` m por debajo y `contact_above` por encima) y la espuma
// se pinta si el agua esta a menos de `contact_halo` metros (horizontales) de ese punto.
// El fondo queda a 0.115 m bajo la superficie: contact_width debe ser menor.
uniform bool contact_foam_enabled = true;
uniform float contact_width : hint_range(0.01, 0.5, 0.005) = 0.09;
uniform float contact_above : hint_range(0.0, 2.0, 0.05) = 0.6;
uniform float contact_halo : hint_range(0.05, 2.0, 0.05) = 0.45;
uniform float contact_radius_px : hint_range(0.0, 24.0, 0.5) = 10.0;
uniform float contact_speed : hint_range(0.0, 4.0, 0.05) = 1.2;
// Detalle del borde (m) y cuanto lo rompe el ruido.
uniform float contact_noise_scale : hint_range(0.05, 2.0, 0.05) = 0.35;
uniform float contact_break : hint_range(0.0, 1.0, 0.05) = 0.5;

group_uniforms foam;
uniform vec4 foam_color : source_color = vec4(0.75, 0.76, 0.53, 1.0);
// Ancho de la franja de espuma junto a la orilla (m) y separacion entre lineas (m).
uniform float foam_width : hint_range(0.0, 5.0, 0.1) = 1.6;
uniform float foam_spacing : hint_range(0.2, 3.0, 0.05) = 0.7;
uniform float foam_speed : hint_range(0.0, 2.0, 0.05) = 0.35;
// Fraccion de cada franja que es linea (grosor) y cuanto la rompe el ruido.
uniform float foam_thickness : hint_range(0.05, 0.6, 0.01) = 0.18;
uniform float foam_break : hint_range(0.0, 1.0, 0.05) = 0.55;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

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

float quantize(float v) {
	if (!pixel_art) {
		return v;
	}
	float n = float(max(levels - 1, 1));
	return floor(v * n + 0.5) / n;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 m = texture(mask, UV);
	if (m.g < 0.5) {
		discard;
	}
	float d = m.r * mask_range;  // metros desde la orilla
	vec2 p = pixel_art ? floor(world_pos.xz * texels_per_meter) / texels_per_meter : world_pos.xz;

	// Ondas: dos capas de ruido que se desplazan en direcciones distintas.
	vec2 dir = normalize(ripple_direction);
	float r1 = gnoise((p + dir * TIME * ripple_speed) / ripple_scale);
	float r2 = gnoise((p - dir.yx * TIME * ripple_speed * 0.7) / (ripple_scale * 0.6) + 40.0);
	float ripple = quantize(r1 * 0.6 + r2 * 0.4) - 0.5;

	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, shallow_width, d));
	col *= 1.0 + ripple * 2.0 * ripple_strength;

	// Espuma: bandas paralelas a la orilla que se alejan, rotas por ruido.
	if (foam_width > 0.0 && d < foam_width) {
		float n = gnoise(p / 1.2 + 7.0);
		float band = fract(d / foam_spacing - TIME * foam_speed + (n - 0.5) * 0.6);
		float line = step(1.0 - foam_thickness, band);
		float keep = step(foam_break, gnoise(p / 0.8 + TIME * 0.1 + 3.0) * 0.5 + 0.5 * (1.0 - d / foam_width));
		float fade = 1.0 - smoothstep(foam_width * 0.5, foam_width, d);
		col = mix(col, foam_color.rgb, line * keep * fade);
	}

	// Espuma de contacto: distancia vertical (mundo) entre la superficie y lo opaco de debajo.
	float contact = 0.0;
	if (contact_foam_enabled) {
		vec2 px = 1.0 / VIEWPORT_SIZE;
		float best = 1.0;  // 0 = pegado al objeto, 1 = fuera del halo
		for (int ring_i = 0; ring_i <= 3; ring_i++) {
			float rr = contact_radius_px * float(ring_i) / 3.0;
			int dirs = ring_i == 0 ? 1 : 8;
			for (int k = 0; k < 8; k++) {
				if (k >= dirs) {
					break;
				}
				float ang = float(k) * 0.7853982 + float(ring_i) * 0.3927;
				vec2 uv = SCREEN_UV + vec2(cos(ang), sin(ang)) * rr * px;
				float depth_raw = texture(depth_tex, uv).r;
				vec3 ndc = vec3(uv * 2.0 - 1.0, depth_raw);
				vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
				view.xyz /= view.w;
				vec3 scene_world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
				float gap = world_pos.y - scene_world.y;  // >0: el punto opaco esta bajo el agua
				if (gap > -contact_above && gap < contact_width) {
					float hd = length(world_pos.xz - scene_world.xz) / contact_halo;
					best = min(best, hd);
				}
			}
		}
		if (best < 1.0) {
			float f = best;  // 0 en el contorno, ->1 al borde del halo
			float n = gnoise(p / contact_noise_scale + vec2(TIME * contact_speed, -TIME * contact_speed * 0.6));
			float n2 = gnoise(p / (contact_noise_scale * 2.5) + 19.0 - TIME * contact_speed * 0.3);
			// Franja pegada al contorno, deshilachada por ruido, y un anillo exterior que late.
			float core = step(f, 0.45 * (1.0 - contact_break) + contact_break * n);
			float ring_pos = 0.7 + 0.18 * sin(TIME * 2.5 + n2 * 6.0);
			float ring = step(abs(f - ring_pos), 0.07) * step(0.35, n);
			contact = max(core, ring);
		}
	}
	col = mix(col, foam_color.rgb, contact);

	ALBEDO = col;
	ALPHA = water_alpha * (edge_fade > 0.0 ? smoothstep(0.0, edge_fade, d) : 1.0);
	ROUGHNESS = 0.6;
	METALLIC = 0.0;
}
