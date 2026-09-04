@tool
class_name FenceGate
extends Node3D
## Puerta en una valla. Se coloca como hijo de un Fence y se arrastra cerca de la curva: la
## valla lo pega al punto mas cercano, abre un hueco de `width` metros con un poste a cada
## lado y esta puerta construye su hoja (dos travesanos + montante) con bisagra en el poste
## de la izquierda (mirando desde fuera). E abre y cierra (InteractionZone); la colision va
## con la hoja. El eje X local de este nodo es la direccion de la valla; -Z es "fuera".

@export_range(0.6, 4.0, 0.1) var width := 1.6:
	set(v):
		width = v
		_notify_fence()
@export var open := false:
	set(v):
		open = v
		_animate()
## Angulo al que abre (grados). Siempre se abre hacia el lado contrario al jugador.
@export_range(30.0, 150.0, 1.0) var open_angle_deg := 100.0
@export_range(0.1, 3.0, 0.05) var swing_time := 0.6
## Bisagra en el poste de la derecha en vez del de la izquierda.
@export var hinge_right := false:
	set(v):
		hinge_right = v
		rebuild()
@export var prompt_open_text := "Abrir"
@export var prompt_close_text := "Cerrar"
@export_range(0.5, 4.0, 0.1) var interaction_radius := 1.4

var _leaf: Node3D
var _body: StaticBody3D
var _zone: InteractionZone
var _tween: Tween
var _post_height := 1.05
var _rail_radius := 0.045
var _rail_span := Vector2(0.4, 0.85)
var _snapped_xform := Transform3D()
var _editor_timer := 0.0
var _open_dir := 1.0  # +1 / -1: sentido de giro de la ultima apertura (lejos del jugador)


func _ready() -> void:
	rebuild()
	# Anadida a una valla que ya estaba construida (runtime o editor): que abra el hueco.
	# Al cargar la escena la valla aun no esta lista y se encarga ella en su _ready.
	var f := get_parent()
	if f and f.is_node_ready():
		_notify_fence()


func _exit_tree() -> void:
	var f := get_parent()
	if f and f.is_node_ready() and f.has_method("_rebuild"):
		f._rebuild.call_deferred()  # cerrar el hueco cuando se quita la puerta


# En el editor, si el usuario arrastra la puerta, la valla la vuelve a pegar a la curva.
# (Sondeo en vez de NOTIFICATION_TRANSFORM_CHANGED: esa notificacion, combinada con que
# la valla recoloca la puerta al cargar, dispara un error interno del motor.)
func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_editor_timer += delta
	if _editor_timer < 0.3:
		return
	_editor_timer = 0.0
	if not transform.is_equal_approx(_snapped_xform):
		_notify_fence()


func _notify_fence() -> void:
	var f := get_parent()
	if f and f.has_method("_rebuild"):
		f._rebuild()


## La valla llama a esto con la posicion/orientacion en la curva y sus medidas.
func snap_to(local_pos: Vector3, dir: Vector3, post_height: float, rail_radius: float, rail_span: Vector2) -> void:
	# X local = direccion de la valla; Y arriba; Z = X x Y (perpendicular, "dentro").
	var x := dir.normalized()
	var z := x.cross(Vector3.UP).normalized() * -1.0
	var target := Transform3D(Basis(x, Vector3.UP, z), local_pos)
	# Solo tocar la transform si cambia de verdad: la notificacion de transform es diferida
	# y volveria a pedir un rebuild a la valla en bucle.
	if not transform.is_equal_approx(target):
		transform = target
	_snapped_xform = target
	_post_height = post_height
	_rail_radius = rail_radius
	_rail_span = rail_span
	rebuild()


func rebuild() -> void:
	if not is_inside_tree():
		return
	for n in [_leaf, _zone]:
		if n:
			remove_child(n)
			n.queue_free()  # free() en el mismo frame en que se registra la colision da errores en el servidor de fisica
	_leaf = null
	_zone = null
	var fence := get_parent()
	var mat: ShaderMaterial = fence._make_material() if fence and fence.has_method("_make_material") else null
	var sign := -1.0 if hinge_right else 1.0
	var hinge_x := -width * 0.5 * sign
	_leaf = Node3D.new()
	_leaf.name = "Leaf"
	_leaf.position = Vector3(hinge_x, 0.0, 0.0)
	add_child(_leaf)
	var leaf_len := width - 0.12
	# Travesanos a lo largo de la hoja (eje X local).
	for i in 2:
		var t := float(i)
		var h := _post_height * lerpf(_rail_span.x, _rail_span.y, t)
		_leaf.add_child(_cylinder(_rail_radius, leaf_len, mat, Vector3(sign * leaf_len * 0.5, h, 0.0), Vector3(0.0, 0.0, PI * 0.5)))
	# Montante en el extremo libre y diagonal.
	var post_h := _post_height * _rail_span.y + 0.06
	_leaf.add_child(_cylinder(_rail_radius * 1.1, post_h, mat, Vector3(sign * leaf_len, post_h * 0.5, 0.0), Vector3.ZERO))
	var brace_len := sqrt(leaf_len * leaf_len + pow(_post_height * (_rail_span.y - _rail_span.x), 2.0))
	var brace := _cylinder(_rail_radius * 0.8, brace_len, mat,
			Vector3(sign * leaf_len * 0.5, _post_height * (_rail_span.x + _rail_span.y) * 0.5, 0.0), Vector3.ZERO)
	brace.rotation.z = sign * (PI * 0.5 - atan2(_post_height * (_rail_span.y - _rail_span.x), leaf_len))
	_leaf.add_child(brace)
	# Colision de la hoja.
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(leaf_len, _post_height, 0.2)
	shape.shape = box
	shape.position = Vector3(sign * leaf_len * 0.5, _post_height * 0.5, 0.0)
	_body.add_child(shape)
	_leaf.add_child(_body)
	_leaf.rotation.y = deg_to_rad(open_angle_deg) * _open_dir if open else 0.0
	_body.collision_layer = 0 if open else 1
	if not Engine.is_editor_hint():
		_zone = InteractionZone.new()
		_zone.name = "InteractionZone"
		_zone.radius = interaction_radius
		_zone.height = 0.5
		_zone.interact_priority = 2
		add_child(_zone)


func _cylinder(radius: float, length: float, mat: Material, pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.material = mat
	mi.mesh = cyl
	mi.position = pos
	mi.rotation = rot
	return mi


func _animate() -> void:
	if _leaf == null:
		return
	var target := deg_to_rad(open_angle_deg) * _open_dir if open else 0.0
	if Engine.is_editor_hint() or not is_inside_tree():
		_leaf.rotation.y = target
		_body.collision_layer = 0 if open else 1
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	# Abierta no bloquea: la colision se quita al empezar a abrir y vuelve al terminar de
	# cerrar (asi no atrapa a quien este en el hueco mientras se cierra).
	if open:
		_body.collision_layer = 0
	_tween = create_tween()
	_tween.tween_property(_leaf, "rotation:y", target, swing_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if not open:
		_tween.tween_callback(func() -> void:
			if is_instance_valid(_body) and not open:
				_body.collision_layer = 1)


# ------------------------------------------------------------------ InteractionZone

func interaction_prompt(_player: Player) -> String:
	return prompt_close_text if open else prompt_open_text


func interact_with(player: Player) -> void:
	if not open:
		# Girar hacia el lado contrario al jugador. La punta de la hoja (extremo +X con
		# bisagra izquierda) se va a -Z con angulo positivo; con bisagra derecha, al reves.
		var player_z := to_local(player.global_position).z
		var away := 1.0 if player_z > 0.0 else -1.0
		_open_dir = away * (-1.0 if hinge_right else 1.0)
	open = not open
	if _zone:
		_zone.refresh_prompt()
