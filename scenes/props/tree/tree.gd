@tool
class_name BillboardTree
extends Node3D
## "Crossed planes" tree: the same 2D texture on N vertical quads rotated around Y,
## so it reads as a 3D volume from any camera angle. Alpha-scissor keeps the cutout
## edges pixel-sharp and lets the tree cast/receive shadows without sorting issues.
##
## Editor: change any export and the tree rebuilds live.
## Runtime: applies random size/yaw variation on _ready (see Variation).

@export var texture: Texture2D = preload("res://assets/textures/tree.png"):
	set(value):
		texture = value
		_rebuild()
## Number of vertical planes, evenly spread over 180°. 2 = classic X, 4 = looks solid.
@export_range(1, 8) var planes := 4:
	set(value):
		planes = value
		_rebuild()
## Height in metres (the texture's alpha bounds should reach the bottom edge = ground).
@export_range(0.5, 30.0, 0.1) var height := 4.0:
	set(value):
		height = value
		_rebuild()
## Width / height. 1.0 for a square texture.
@export_range(0.1, 3.0, 0.05) var aspect := 1.0:
	set(value):
		aspect = value
		_rebuild()

@export_group("Variation (runtime)")
## ± fraction of random uniform scale applied on _ready. 0.25 = between 75% and 125%.
@export_range(0.0, 1.0, 0.01) var size_variation := 0.25
## Random rotation around Y on _ready, so identical trees don't line up.
@export var random_yaw := true
## 0 = derive the random seed from the tree's position (stable between runs).
@export var random_seed := 0

@export_group("Rendering")
## Unshaded keeps every plane the same brightness regardless of the sun angle
## (lit planes would flicker between light/dark as the camera orbits).
@export var unshaded := true:
	set(value):
		unshaded = value
		_rebuild()
@export var cast_shadows := true:
	set(value):
		cast_shadows = value
		_rebuild()
## Alpha cutoff. Raise it if the texture has soft edges you want to trim.
@export_range(0.0, 1.0, 0.01) var alpha_cutoff := 0.5:
	set(value):
		alpha_cutoff = value
		_rebuild()

@export_group("Wind")
## 0 = rigid, 1 = normal response to the global Wind node, 2 = very flexible.
@export_range(0.0, 3.0, 0.05) var wind_influence := 1.0:
	set(value):
		wind_influence = value
		_rebuild()
## Metres the top leans downwind at wind strength 1.0.
@export_range(0.0, 3.0, 0.01) var sway_amount := 0.35:
	set(value):
		sway_amount = value
		_rebuild()
## Metres of side-to-side flutter at the top (scaled by the Wind node's turbulence).
@export_range(0.0, 1.0, 0.01) var flutter_amount := 0.12:
	set(value):
		flutter_amount = value
		_rebuild()

@export_group("Interaction")
## React (rustle sound + shake) when a body walks into the foliage.
@export var interaction_enabled := true
## Foliage radius as a fraction of the prop's width (the trigger area).
@export_range(0.05, 1.0, 0.05) var interaction_radius_ratio := 0.35
@export var rustle_stream: AudioStream = preload("res://assets/audio/bush_colision.mp3")
@export_range(-40.0, 6.0, 0.5) var rustle_volume_db := -14.0
## Random pitch range per rustle (1.2 = ±20%) and random volume offset.
@export_range(1.0, 2.0, 0.01) var rustle_random_pitch := 1.2
@export_range(0.0, 12.0, 0.5) var rustle_random_volume_db := 3.0
## Seconds between repeated rustles while a body keeps moving inside the foliage.
@export_range(0.1, 3.0, 0.05) var rustle_interval := 0.55
## Metres the top is pushed on impact (decaying spring).
@export_range(0.0, 2.0, 0.01) var shake_amount := 0.35
@export_range(1.0, 20.0, 0.5) var shake_frequency := 8.0
@export_range(0.5, 10.0, 0.1) var shake_damping := 3.0
## Continuous lean (metres at the top) while a body pushes through, in its move direction.
@export_range(0.0, 2.0, 0.01) var push_lean := 0.25

@export_group("Occlusion")
## Register the crown as a visual occluder (Area3D on `occluder_layer`) so the player's
## x-ray silhouette knows when it is hidden behind this prop.
@export var occluder_enabled := true:
	set(value):
		occluder_enabled = value
		_rebuild()
## Crown radius (at its widest) as a fraction of the width.
@export_range(0.05, 1.0, 0.05) var occluder_radius_ratio := 0.3:
	set(value):
		occluder_radius_ratio = value
		_rebuild()
## CONE tapers to the tip (pines); CYLINDER keeps the full radius up to the top (round crowns).
enum OccluderShape { CONE, CYLINDER }
@export var occluder_shape: OccluderShape = OccluderShape.CONE:
	set(value):
		occluder_shape = value
		_rebuild()
## Height (fraction of the prop) where the crown is widest; below it the shape narrows to the trunk.
@export_range(0.0, 0.9, 0.05) var occluder_base_fraction := 0.2:
	set(value):
		occluder_base_fraction = value
		_rebuild()
@export_flags_3d_physics var occluder_layer := 8

@export_group("Collision")
@export var collision_enabled := true:
	set(value):
		collision_enabled = value
		_rebuild()
@export_range(0.05, 3.0, 0.05) var trunk_radius := 0.25:
	set(value):
		trunk_radius = value
		_rebuild()

var _planes_root: Node3D
var _body: StaticBody3D
var _material: ShaderMaterial
var _area: Area3D
var _rustle_player: AudioStreamPlayer
var _bodies_inside: Array[Node3D] = []
var _shake_dir := Vector3.ZERO
var _shake_t := INF
var _rustle_cooldown := 0.0
var _lean := Vector3.ZERO


func _ready() -> void:
	if not Engine.is_editor_hint():
		_apply_variation()
	_rebuild()
	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	if _material == null:
		return
	_rustle_cooldown -= delta
	# Continuous lean while something moves through the foliage.
	var target_lean := Vector3.ZERO
	for body in _bodies_inside:
		if not is_instance_valid(body):
			continue
		var v: Vector3 = _body_velocity(body)
		if v.length() > 0.3:
			target_lean = v.normalized() * push_lean
			if _rustle_cooldown <= 0.0:
				_rustle_cooldown = rustle_interval
				_play_rustle(-4.0)
				_shake(v.normalized(), 0.5)
	_lean = _lean.lerp(target_lean, 1.0 - exp(-6.0 * delta))

	# Damped spring after an impact.
	var shake := Vector3.ZERO
	if _shake_t < 4.0:
		_shake_t += delta
		var a := shake_amount * exp(-shake_damping * _shake_t) * cos(TAU * shake_frequency * _shake_t)
		shake = _shake_dir * a
	_material.set_shader_parameter("hit_offset", (_lean + shake) / maxf(scale.y, 0.001))


func _apply_variation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed if random_seed != 0 else hash(global_position.snapped(Vector3(0.01, 0.01, 0.01)))
	if size_variation > 0.0:
		scale = Vector3.ONE * (1.0 + rng.randf_range(-size_variation, size_variation))
	if random_yaw:
		rotation.y = rng.randf_range(0.0, TAU)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _planes_root:
		_planes_root.queue_free()
	if _body:
		_body.queue_free()

	var width := height * aspect
	var material := _make_material()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(width, height)
	mesh.material = material

	_planes_root = Node3D.new()
	_planes_root.name = "Planes"
	add_child(_planes_root)
	for i in planes:
		var mi := MeshInstance3D.new()
		mi.name = "Plane%d" % i
		mi.mesh = mesh
		mi.position.y = height * 0.5
		mi.rotation.y = PI * float(i) / float(planes)
		mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_planes_root.add_child(mi)

	_material = material
	if interaction_enabled and not Engine.is_editor_hint():
		_setup_interaction(width, height)
	if occluder_enabled and not Engine.is_editor_hint():
		_setup_occluder(width, height)

	if collision_enabled and not Engine.is_editor_hint():
		_body = StaticBody3D.new()
		_body.name = "Trunk"
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = trunk_radius
		cyl.height = height
		shape.shape = cyl
		shape.position.y = height * 0.5
		_body.add_child(shape)
		add_child(_body)


var _occluder: Area3D


func _setup_occluder(width: float, height: float) -> void:
	if _occluder:
		_occluder.queue_free()
	_occluder = Area3D.new()
	_occluder.name = "Occluder"
	_occluder.monitoring = false      # never scans; only exists to be hit by rays
	_occluder.monitorable = true
	_occluder.collision_layer = occluder_layer
	_occluder.collision_mask = 0
	var shape := CollisionShape3D.new()
	var r := maxf(width * occluder_radius_ratio, 0.1)
	if occluder_shape == OccluderShape.CYLINDER:
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = height
		shape.shape = cyl
		shape.position.y = height * 0.5
	else:
		# Convex "spindle": trunk point at the ground, widest ring at base_fraction, tip at the top.
		var pts := PackedVector3Array()
		pts.append(Vector3(0.0, 0.0, 0.0))
		pts.append(Vector3(0.0, height, 0.0))
		var ring_y := height * occluder_base_fraction
		for i in 8:
			var a := TAU * float(i) / 8.0
			pts.append(Vector3(cos(a) * r, ring_y, sin(a) * r))
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		shape.shape = hull
	_occluder.add_child(shape)
	add_child(_occluder)


func _setup_interaction(width: float, height: float) -> void:
	if _area:
		_area.queue_free()
	_area = Area3D.new()
	_area.name = "Foliage"
	_area.monitorable = false
	# Only listen to layer 2 (the player / characters), not floors, trunks or props.
	_area.collision_layer = 0
	_area.collision_mask = 2
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(width * interaction_radius_ratio, 0.1)
	cyl.height = height
	shape.shape = cyl
	shape.position.y = height * 0.5
	_area.add_child(shape)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	add_child(_area)

	if rustle_stream == null:
		rustle_stream = DEFAULT_RUSTLE  # guard against a null override saved in a scene
	if _rustle_player == null and rustle_stream:
		var randomizer := AudioStreamRandomizer.new()
		randomizer.add_stream(0, rustle_stream)
		randomizer.random_pitch = rustle_random_pitch
		randomizer.random_volume_offset_db = rustle_random_volume_db
		_rustle_player = AudioStreamPlayer.new()
		_rustle_player.bus = &"World"
		_rustle_player.name = "Rustle"
		_rustle_player.stream = randomizer
		_rustle_player.max_polyphony = 2
		add_child(_rustle_player)


func _body_velocity(body: Node3D) -> Vector3:
	var v = body.get("velocity")
	if v is Vector3:
		return Vector3(v.x, 0.0, v.z)
	return Vector3.ZERO


func _on_body_entered(body: Node3D) -> void:
	if body is StaticBody3D or body == _body:
		return
	_bodies_inside.append(body)
	var v := _body_velocity(body)
	var dir := v.normalized() if v.length() > 0.1 else (body.global_position - global_position)
	dir.y = 0.0
	_shake(dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD, 1.0)
	_play_rustle(0.0)
	_rustle_cooldown = rustle_interval


func _on_body_exited(body: Node3D) -> void:
	_bodies_inside.erase(body)


func _shake(dir: Vector3, strength: float) -> void:
	_shake_dir = dir * strength
	_shake_t = 0.0


func _play_rustle(extra_db: float) -> void:
	if _rustle_player == null:
		return
	_rustle_player.volume_db = rustle_volume_db + extra_db
	_rustle_player.play()


const DEFAULT_RUSTLE := preload("res://assets/audio/bush_colision.mp3")
const SHADER_UNSHADED := preload("res://scenes/props/tree/shaders/wind_cutout_unshaded.gdshader")
const SHADER_LIT := preload("res://scenes/props/tree/shaders/wind_cutout_lit.gdshader")


## Wind-animated alpha-scissor material (see wind_cutout.gdshaderinc).
func _make_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER_UNSHADED if unshaded else SHADER_LIT
	m.set_shader_parameter("albedo_tex", texture)
	m.set_shader_parameter("alpha_cutoff", alpha_cutoff)
	m.set_shader_parameter("wind_influence", wind_influence)
	m.set_shader_parameter("sway_amount", sway_amount)
	m.set_shader_parameter("flutter_amount", flutter_amount)
	return m
