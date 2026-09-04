@tool
class_name GrassArea
extends MultiMeshInstance3D
## Field of flat-coloured grass blades (one MultiMesh, thousands of instances).
## Each blade is a thin billboarded strip drawn by grass.gdshader; it sways with the
## global Wind node. Regenerates live in the editor and on _ready at runtime (seeded),
## so nothing heavy is saved into the scene file.

const GRASS_SHADER := preload("res://scenes/environment/grass/shaders/grass.gdshader")

@export_group("Area")
## Width (X) and depth (Z) in metres, centred on this node.
@export var size := Vector2(20.0, 20.0):
	set(value):
		size = value.max(Vector2(0.5, 0.5))
		_regenerate()
## Keep an empty circle in the centre (0 = none).
@export_range(0.0, 50.0, 0.1) var clearing_radius := 0.0:
	set(value):
		clearing_radius = value
		_regenerate()

@export_group("Blades")
## Blades per square metre inside the dense patches (bare areas get fewer).
@export_range(0.5, 200.0, 0.5) var density := 25.0:
	set(value):
		density = value
		_regenerate()
@export var height_range := Vector2(0.18, 0.4):
	set(value):
		height_range = value
		_regenerate()
## Bend segments per blade (more = smoother curve, more vertices).
@export_range(1, 6) var segments := 3:
	set(value):
		segments = value
		_regenerate()
## Safety cap on instances.
@export_range(100, 200000) var max_blades := 60000:
	set(value):
		max_blades = value
		_regenerate()
## Cast shadows (off by default: thin lines just add noise to the shadow map).
@export var blades_cast_shadow := false:
	set(value):
		blades_cast_shadow = value
		cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if value
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

@export_group("Patchiness")
## 0 = uniform field, 1 = coverage fully driven by the noise (dense clumps and bare spots).
@export_range(0.0, 1.0, 0.05) var patchiness := 0.7:
	set(value):
		patchiness = value
		_regenerate()
## Size of the patches in metres.
@export_range(0.5, 50.0, 0.5) var patch_scale := 6.0:
	set(value):
		patch_scale = value
		_regenerate()
## Noise level below which grass thins out. Higher = more bare ground overall.
@export_range(0.0, 1.0, 0.01) var patch_threshold := 0.45:
	set(value):
		patch_threshold = value
		_regenerate()
## Width of the transition between bare and dense (0 = hard edge).
@export_range(0.0, 0.5, 0.01) var patch_softness := 0.2:
	set(value):
		patch_softness = value
		_regenerate()
## Blades inside dense areas grow up to this factor taller than in sparse ones.
@export_range(1.0, 2.0, 0.05) var height_by_density := 1.3:
	set(value):
		height_by_density = value
		_regenerate()

@export_group("Look")
@export var base_color := Color(0.18, 0.32, 0.14):
	set(value):
		base_color = value
		_update_material()
@export var tip_color := Color(0.45, 0.62, 0.25):
	set(value):
		tip_color = value
		_update_material()
@export var variation_color := Color(0.35, 0.45, 0.18):
	set(value):
		variation_color = value
		_update_material()
@export_range(0.0, 1.0, 0.05) var variation_amount := 0.5:
	set(value):
		variation_amount = value
		_update_material()
## Blade width in metres (~1-2 internal pixels reads best).
@export_range(0.005, 0.3, 0.005) var blade_width := 0.05:
	set(value):
		blade_width = value
		_update_material()
@export_range(0.0, 1.0, 0.01) var sway_amount := 0.12:
	set(value):
		sway_amount = value
		_update_material()
@export_range(0.0, 0.5, 0.01) var flutter_amount := 0.04:
	set(value):
		flutter_amount = value
		_update_material()
@export_range(0.0, 0.5, 0.01) var lean := 0.04:
	set(value):
		lean = value
		_update_material()
## 0 = blades stay vertical (classic); 1 = full billboard: they also tilt to face the
## camera head-on when it pitches. Values in between blend.
@export_range(0.0, 1.0, 0.05) var billboard_tilt := 0.0:
	set(value):
		billboard_tilt = value
		_update_material()

@export_group("Seed")
@export var seed := 1:
	set(value):
		seed = value
		_regenerate()
@export var randomize_seed := false:
	set(value):
		if value:
			seed = randi_range(1, 999999)

## Number of blades in the last generation (read-only).
var blade_count := 0


func _ready() -> void:
	_regenerate()


func _regenerate() -> void:
	if not is_inside_tree():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _build_blade_mesh()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / maxf(patch_scale, 0.01)
	noise.fractal_octaves = 2
	var target := mini(int(round(size.x * size.y * density)), max_blades)
	var half := size * 0.5
	var transforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	# One candidate per "slot": rejected candidates are NOT retried, so `density` is the
	# density inside the dense patches and bare areas genuinely lower the total.
	for attempt in target:
		var p := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
		if clearing_radius > 0.0 and p.length() < clearing_radius:
			continue
		# Noise-driven coverage: probability of keeping this blade (world-space so
		# neighbouring areas with the same seed line up).
		var n := (noise.get_noise_2d(global_position.x + p.x, global_position.z + p.y) + 1.0) * 0.5
		var cover := smoothstep(patch_threshold - patch_softness, patch_threshold + patch_softness, n)
		var keep := lerpf(1.0, cover, patchiness)
		if rng.randf() > keep:
			continue
		var h := rng.randf_range(height_range.x, height_range.y) * lerpf(1.0, height_by_density, cover * patchiness)
		var xf := Transform3D(Basis.from_scale(Vector3(1.0, h, 1.0)), Vector3(p.x, 0.0, p.y))
		transforms.append(xf)
		customs.append(Color(rng.randf(), rng.randf(), 0.0, 0.0))

	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_custom_data(i, customs[i])
	multimesh = mm
	blade_count = transforms.size()

	# Generous AABB so blades bent by the wind never get culled at the edges.
	custom_aabb = AABB(Vector3(-half.x - 1.0, -0.5, -half.y - 1.0), Vector3(size.x + 2.0, height_range.y + 2.0, size.y + 2.0))
	cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if blades_cast_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_update_material()


## Thin vertical strip: x in [-0.5, 0.5], y in [0, 1], `segments` quads stacked.
func _build_blade_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in segments + 1:
		var y := float(row) / float(segments)
		verts.append(Vector3(-0.5, y, 0.0))
		verts.append(Vector3(0.5, y, 0.0))
		uvs.append(Vector2(0.0, y))
		uvs.append(Vector2(1.0, y))
	for row in segments:
		var a := row * 2
		indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _update_material() -> void:
	if not is_inside_tree():
		return
	var mat := material_override as ShaderMaterial
	if mat == null or mat.shader != GRASS_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = GRASS_SHADER
		material_override = mat
	mat.set_shader_parameter("base_color", base_color)
	mat.set_shader_parameter("tip_color", tip_color)
	mat.set_shader_parameter("variation_color", variation_color)
	mat.set_shader_parameter("variation_amount", variation_amount)
	mat.set_shader_parameter("blade_width", blade_width)
	mat.set_shader_parameter("sway_amount", sway_amount)
	mat.set_shader_parameter("flutter_amount", flutter_amount)
	mat.set_shader_parameter("lean", lean)
	mat.set_shader_parameter("billboard_tilt", billboard_tilt)
