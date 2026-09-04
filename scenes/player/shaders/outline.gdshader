// outline.gdshader — contorno de 1 pixel por "inverted hull" en espacio de pantalla.
// Se usa como next_pass del material del personaje: dibuja las caras traseras del modelo
// extruidas N pixeles a lo largo de la normal EN PANTALLA, asi el grosor es constante
// (siempre width_px pixeles internos) sea cual sea el zoom de la camara ortografica.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
// Marca el stencil con la referencia del personaje (1): asi el x-ray, que solo pinta
// donde el stencil NO es 1, no confunde el casco del contorno con un objeto que tapa.
stencil_mode write, 1;

uniform vec4 color : source_color = vec4(0.03, 0.02, 0.02, 1.0);
uniform float width_px : hint_range(0.5, 4.0, 0.5) = 1.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n_view = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 n_clip = (PROJECTION_MATRIX * vec4(n_view, 0.0)).xy;
	float len = length(n_clip);
	n_clip = len > 0.0001 ? n_clip / len : vec2(0.0);
	// NDC va de -1 a 1: un pixel son 2/tam. Multiplicar por w compensa la perspectiva
	// (en ortografica w = 1).
	clip.xy += n_clip * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = color.rgb;
}
