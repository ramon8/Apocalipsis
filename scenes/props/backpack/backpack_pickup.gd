@tool
class_name BackpackPickup
extends Node3D
## World pickup for the backpack: a RigidBody3D that drops to the ground and rests there
## (random tilt/yaw so it looks thrown). Uses the "Backpack" mesh from the character GLB.
## When the player is in range a prompt shows; pressing E (InteractionZone) grabs it.

signal picked_up(player: Player)

## Model that contains the backpack mesh.
@export var model_scene: PackedScene = preload("res://assets/models/character/character.glb")
## Name of the MeshInstance3D inside the model.
@export var mesh_name := "Backpack"
## Same scale the player applies to the model, so the pickup is life-size.
@export var model_scale := 0.3

@export_group("Physics")
## Height above this node the body is spawned at (it falls from there).
@export_range(0.0, 5.0, 0.05) var drop_height := 0.6
## Random yaw + tilt applied at spawn so it doesn't land perfectly upright.
@export var random_rotation := true
@export_range(0.0, 90.0, 1.0) var max_tilt_deg := 40.0
@export var mass := 2.0
## Physics layer the body lives on (default 4 = "props": the player walks through it).
@export_flags_3d_physics var body_collision_layer := 4
## What the body collides with (default 1 = world).
@export_flags_3d_physics var body_collision_mask := 1

@export_group("Pickup")
## Range at which the prompt appears and E works.
@export var pickup_radius := 1.4
@export var prompt_key_text := "E"
## Action label shown next to the key in the corner prompt.
@export var prompt_action_text := "Pick up"
## Accion del jugador al cogerla (la bolsa desaparece del suelo en el apex).
@export var pickup_action: PlayerAction = preload("res://scenes/player/actions/pickup_backpack.tres")
@export var pickup_sound: AudioStream = preload("res://assets/audio/pickupbackpack.wav")
@export_range(-40.0, 6.0, 0.5) var pickup_volume_db := -8.0
## Random pitch range per play (1.1 = ±10%).
@export_range(1.0, 2.0, 0.01) var pickup_random_pitch := 1.08
## Remove the node after pickup (false = just hide it, e.g. to respawn later).
@export var free_on_pickup := true

var _body: RigidBody3D
var _taken := false
var _zone: InteractionZone


func _ready() -> void:
	_build_body()
	if Engine.is_editor_hint():
		set_process(false)
		return
	_build_zone()


## RigidBody3D -> Mesh (centred, scaled) + BoxShape from the mesh AABB.
func _build_body() -> void:
	var model := model_scene.instantiate()
	var source := model.find_child(mesh_name, true, false) as MeshInstance3D
	if source == null:
		push_warning("BackpackPickup: mesh '%s' not found in the model." % mesh_name)
		model.free()
		return
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = source.mesh
	var setup := ModelMaterials.new()  # solo nearest: la bolsa en el suelo no lleva contorno
	for i in source.get_surface_override_material_count():
		var mat := source.get_active_material(i)
		if mat is BaseMaterial3D:
			mesh_node.set_surface_override_material(i, setup.prepare(mat))
	model.free()

	var aabb := mesh_node.mesh.get_aabb()
	mesh_node.position = -aabb.get_center() * model_scale
	mesh_node.scale = Vector3.ONE * model_scale

	_body = RigidBody3D.new()
	_body.name = "Body"
	_body.mass = mass
	_body.collision_layer = body_collision_layer
	_body.collision_mask = body_collision_mask
	_body.linear_damp = 0.5
	_body.angular_damp = 1.0
	_body.can_sleep = true
	_body.freeze = Engine.is_editor_hint()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size * model_scale
	shape.shape = box
	_body.add_child(shape)
	_body.add_child(mesh_node)

	var half_height := box.size.y * 0.5
	_body.position = Vector3(0.0, half_height + drop_height, 0.0)
	if random_rotation and not Engine.is_editor_hint():
		_body.rotation = Vector3(
			deg_to_rad(randf_range(-max_tilt_deg, max_tilt_deg)),
			randf_range(0.0, TAU),
			deg_to_rad(randf_range(-max_tilt_deg, max_tilt_deg)))
	add_child(_body)


## Zona de interaccion colgada del cuerpo rigido: sigue a la mochila donde caiga.
func _build_zone() -> void:
	_zone = InteractionZone.new()
	_zone.name = "InteractionZone"
	_zone.target = self
	_zone.radius = pickup_radius
	_zone.height = 0.0
	_zone.interact_priority = 0
	_zone.key_text = prompt_key_text
	_zone.action_text = prompt_action_text
	_body.add_child(_zone)


func can_interact(_player: Player) -> bool:
	return not _taken


func interact_with(player: Player) -> void:
	_grab(player)


func _grab(player: Player) -> void:
	if _taken:
		return
	_taken = true
	_zone.enabled = false
	# Play the character's pickup animation; the bag vanishes when the hand reaches it.
	if player.start_action(pickup_action):
		player.action_apex.connect(_on_reached.bind(player), CONNECT_ONE_SHOT)
	else:
		player.show_backpack = true
		_on_reached(pickup_action.kind, player)


func _on_reached(_kind: StringName, player: Player) -> void:
	picked_up.emit(player)
	if pickup_sound:
		var sfx := AudioStreamPlayer.new()
		sfx.stream = pickup_sound
		sfx.volume_db = pickup_volume_db
		sfx.pitch_scale = randf_range(1.0 / pickup_random_pitch, pickup_random_pitch)
		sfx.finished.connect(sfx.queue_free)
		get_parent().add_child(sfx)
		sfx.play()
	if free_on_pickup:
		queue_free()
	else:
		visible = false
		_body.freeze = true
		set_process(false)
