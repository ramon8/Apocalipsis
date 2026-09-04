@tool
class_name TreeArea
extends Node3D
## Scatters props (trees, bushes...) over a rectangular area.
## Instance it, set `size`, pick the scenes and the density; it regenerates live in the
## editor when any export changes, and again on _ready at runtime with the same seed,
## so the generated instances are never saved into your scene file.
## Each prop keeps its own variation (BillboardTree derives it from its position).

@export_group("Area")
## Width (X) and depth (Z) in metres, centred on this node.
@export var size := Vector2(20.0, 20.0):
	set(value):
		size = value.max(Vector2(1.0, 1.0))
		_update_bounds()
		_regenerate()
## Keep this margin free along the edges.
@export_range(0.0, 20.0, 0.1) var edge_padding := 0.5:
	set(value):
		edge_padding = value
		_regenerate()
## Radius of a clearing kept empty in the centre (0 = none).
@export_range(0.0, 50.0, 0.1) var clearing_radius := 0.0:
	set(value):
		clearing_radius = value
		_regenerate()
## Draw the area bounds in the editor.
@export var show_bounds := true:
	set(value):
		show_bounds = value
		_update_bounds()

@export_group("Props")
## Scenes to scatter (e.g. tree.tscn, bush.tscn).
@export var scenes: Array[PackedScene] = []:
	set(value):
		scenes = value
		_regenerate()
## Relative probability per scene (same order). Empty = all equal.
@export var weights: PackedFloat32Array = []:
	set(value):
		weights = value
		_regenerate()

@export_group("Distribution")
## Props per 100 m² (a 20x20 area at density 5 -> 20 props).
@export_range(0.0, 100.0, 0.1) var density := 5.0:
	set(value):
		density = value
		_regenerate()
## Minimum distance between two props. Higher = more even spacing, fewer placed.
@export_range(0.0, 20.0, 0.1) var min_distance := 2.0:
	set(value):
		min_distance = value
		_regenerate()
## Safety cap on the number of instances.
@export_range(1, 5000) var max_count := 500:
	set(value):
		max_count = value
		_regenerate()
## Extra uniform scale range applied on top of each prop's own variation.
@export var scale_range := Vector2(1.0, 1.0):
	set(value):
		scale_range = value
		_regenerate()
@export var random_yaw := true:
	set(value):
		random_yaw = value
		_regenerate()
## Cast a ray down to place props on uneven ground (needs collision under the area).
@export var snap_to_ground := false:
	set(value):
		snap_to_ground = value
		_regenerate()
## Height above the node the ground ray starts from.
@export_range(1.0, 200.0, 1.0) var ground_ray_height := 50.0

@export_group("Seed")
@export var seed := 1:
	set(value):
		seed = value
		_regenerate()
## Tick to pick a new random seed (the checkbox resets itself).
@export var randomize_seed := false:
	set(value):
		if value:
			seed = randi_range(1, 999999)

var _container: Node3D
var _bounds: MeshInstance3D
## Number of props placed by the last generation (read-only).
var placed_count := 0


func _ready() -> void:
	_update_bounds()
	_regenerate()


func _regenerate() -> void:
	if not is_inside_tree():
		return
	if _container:
		_container.queue_free()
	_container = Node3D.new()
	_container.name = "Generated"
	add_child(_container)
	placed_count = 0
	if scenes.is_empty() or density <= 0.0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var half := size * 0.5 - Vector2.ONE * edge_padding
	if half.x <= 0.0 or half.y <= 0.0:
		return
	var target := mini(int(round(size.x * size.y / 100.0 * density)), max_count)
	var placed: Array[Vector2] = []
	var attempts := 0
	var max_attempts := target * 20

	while placed.size() < target and attempts < max_attempts:
		attempts += 1
		var p := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
		if clearing_radius > 0.0 and p.length() < clearing_radius:
			continue
		if min_distance > 0.0 and _too_close(p, placed):
			continue
		var scene := _pick_scene(rng)
		if scene == null:
			return
		var inst := scene.instantiate() as Node3D
		if inst == null:
			continue
		var y := 0.0
		if snap_to_ground:
			var hit_y := _ground_height(p)
			if is_nan(hit_y):
				continue
			y = hit_y
		inst.name = "%s_%d" % [inst.name, placed.size()]
		inst.position = Vector3(p.x, y, p.y)
		if random_yaw:
			inst.rotation.y = rng.randf_range(0.0, TAU)
		var s := rng.randf_range(scale_range.x, scale_range.y)
		if not is_equal_approx(s, 1.0):
			inst.scale = Vector3.ONE * s
		_container.add_child(inst)
		placed.append(p)
	placed_count = placed.size()


func _too_close(p: Vector2, placed: Array[Vector2]) -> bool:
	var d2 := min_distance * min_distance
	for q in placed:
		if p.distance_squared_to(q) < d2:
			return true
	return false


func _pick_scene(rng: RandomNumberGenerator) -> PackedScene:
	if weights.size() != scenes.size() or weights.is_empty():
		return scenes[rng.randi_range(0, scenes.size() - 1)]
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return scenes[0]
	var r := rng.randf() * total
	for i in scenes.size():
		r -= maxf(weights[i], 0.0)
		if r <= 0.0:
			return scenes[i]
	return scenes[scenes.size() - 1]


## Returns the local Y of the ground under a local XZ point, or NAN if nothing was hit.
func _ground_height(p: Vector2) -> float:
	var space := get_world_3d().direct_space_state
	var from := to_global(Vector3(p.x, ground_ray_height, p.y))
	var to := to_global(Vector3(p.x, -ground_ray_height, p.y))
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return to_local(hit.position).y


func _update_bounds() -> void:
	if not is_inside_tree():
		return
	if _bounds:
		_bounds.free()
		_bounds = null
	if not (show_bounds and Engine.is_editor_hint()):
		return
	_bounds = MeshInstance3D.new()
	_bounds.name = "Bounds"
	var mesh := PlaneMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 0.9, 0.4, 0.15)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	_bounds.mesh = mesh
	_bounds.position.y = 0.02
	add_child(_bounds)

