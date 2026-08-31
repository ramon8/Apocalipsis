// psx_base.gdshader — material base reutilizable con el look PSX en la geometría.
//
//  - Vertex snapping: cuantiza la posición en clip space a la rejilla de la
//    resolución interna (los vértices "bailan" al moverse la cámara).
//  - Texture mapping afín: interpola las UV linealmente en pantalla en vez de
//    con corrección de perspectiva (el "wobble" de texturas de PSX).
//  - Texturas sin filtrado (nearest) y sin mipmaps.
//  - Niebla exponencial por distancia (FOG built-in de Godot).
//
// Los parámetros compartidos vienen de uniforms GLOBALES (los escribe
// RetroRenderer desde el RetroProfile activo). Cada material puede escalarlos
// con sus multiplicadores para excluir o exagerar objetos concretos.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_disabled;

// --- Globales (declarados en project.godot [shader_globals], escritos por RetroRenderer)
global uniform vec2  retro_internal_resolution;
global uniform float retro_snap_strength;
global uniform float retro_affine_strength;
global uniform bool  retro_fog_enabled;
global uniform vec4  retro_fog_color : source_color;
global uniform float retro_fog_density;

// --- Por material
uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform float snap_multiplier   : hint_range(0.0, 4.0) = 1.0;
uniform float affine_multiplier : hint_range(0.0, 4.0) = 1.0;
uniform float fog_multiplier    : hint_range(0.0, 4.0) = 1.0;

varying vec2  v_affine_uv;   // UV * w
varying float v_affine_w;    // w
varying float v_view_dist;   // distancia al ojo, para la niebla

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip = PROJECTION_MATRIX * view_pos;

	// Vertex snapping en clip space. La rejilla NDC [-1,1] tiene res/2 celdas por eje.
	float snap = retro_snap_strength * snap_multiplier;
	if (snap > 0.0 && clip.w > 0.0) {
		vec2 grid = retro_internal_resolution * 0.5;
		vec2 ndc = clip.xy / clip.w;
		vec2 snapped = floor(ndc * grid + 0.5) / grid;
		clip.xy = mix(ndc, snapped, snap) * clip.w;
	}
	POSITION = clip;

	// Truco afín: la GPU interpola varyings con corrección de perspectiva;
	// (UV*w)/(w) interpolados deshace esa corrección y deja interpolación lineal en pantalla.
	float w = max(clip.w, 1e-4);
	v_affine_uv = UV * uv_scale * w;
	v_affine_w = w;
	v_view_dist = length(view_pos.xyz);
}

void fragment() {
	float aff = clamp(retro_affine_strength * affine_multiplier, 0.0, 1.0);
	vec2 uv_perspective = UV * uv_scale;
	vec2 uv_affine = v_affine_uv / v_affine_w;
	vec2 uv = mix(uv_perspective, uv_affine, aff);

	vec4 tex = texture(albedo_tex, uv) * albedo_color;
	ALBEDO = tex.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;

	// Niebla exponencial por distancia: f = 1 - e^(-density * d)
	float fog_amount = 0.0;
	if (retro_fog_enabled) {
		fog_amount = 1.0 - exp(-retro_fog_density * fog_multiplier * v_view_dist);
	}
	FOG = vec4(retro_fog_color.rgb, clamp(fog_amount, 0.0, 1.0));
}
