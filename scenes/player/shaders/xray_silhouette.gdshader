// X-ray silhouette: drawn as a material_overlay on the player's meshes.
// depth_test_inverted keeps ONLY the pixels that are behind something else, so the
// silhouette shows exactly where the character is occluded and nowhere else.
// Transparent (blend_mix) so it renders after all opaque geometry, with the depth
// buffer complete; depth_draw_never so it never occludes anything itself.
// Stencil: the character's own materials write reference 1 where they are visible, and
// this pass only draws where the stencil is NOT 1 -> self-occlusion (an arm behind the
// torso) never triggers the silhouette; only other objects do.
shader_type spatial;
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_back, blend_mix;
stencil_mode read, compare_not_equal, 1;

uniform vec4 color : source_color = vec4(0.4, 0.85, 1.0, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.75;
// 0 = solid, 1 = pixel checkerboard, 2 = horizontal scanlines
uniform int pattern : hint_range(0, 2) = 1;
// Pattern cell size in (internal) pixels.
uniform float pattern_scale : hint_range(1.0, 8.0, 1.0) = 1.0;

void fragment() {
	vec2 px = floor(FRAGCOORD.xy / pattern_scale);
	bool on = true;
	if (pattern == 1) {
		on = mod(px.x + px.y, 2.0) < 1.0;
	} else if (pattern == 2) {
		on = mod(px.y, 2.0) < 1.0;
	}
	if (!on) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = alpha;
}
