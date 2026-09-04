@tool
class_name Dock
extends Path3D
## Embarcadero de madera generado a lo largo de la curva: tablones transversales, dos
## vigas longitudinales debajo, pilotes cada `pile_spacing` metros hundidos en el agua y
## una rampa en el arranque (primer punto de la curva) para subir desde tierra. Colision
## transitable. Dibuja la curva desde la orilla hacia el agua y se reconstruye sola.
## Grupos: "water_passage" (el lago no pone colision de orilla bajo el embarcadero) y
## "scatter_exclusion" (sin arboles encima). La altura de los puntos se ignora.

const WOOD_SHADER := preload("res://scenes/props/bench/shaders/wood.gdshader")

@export_group("Tablero")
@export_range(0.8, 5.0, 0.1) var deck_width := 1.8:
	set(v):
		deck_width = v
		_rebuild()
## Altura del tablero sobre este nodo (m).
@export_range(0.1, 2.0, 0.05) var deck_height := 0.45:
	set(v):
		deck_height = v
		_rebuild()
@export_range(0.1, 0.6, 0.01) var plank_width := 0.28:
	set(v):
		plank_width = v
		_rebuild()
@export_range(0.0, 0.2, 0.005) var plank_gap := 0.035:
	set(v):
		plank_gap = v
		_rebuild()
@export_range(0.02, 0.15, 0.005) var plank_thickness := 0.06:
	set(v):
		plank_thickness = v
		_rebuild()
## Variacion aleatoria de largo/giro de cada tablon (madera vieja).
@export_range(0.0, 0.2, 0.01) var plank_variation := 0.06:
	set(v):
		plank_variation = v
		_rebuild()
## Largo de la rampa de subida desde tierra (0 = sin rampa).
@export_range(0.0, 6.0, 0.1) var ramp_length := 1.6:
	set(v):
		ramp_length = v
		_rebuild()

@export_group("Estructura")
@export_range(0.5, 6.0, 0.1) var pile_spacing := 2.0:
	set(v):
		pile_spacing = v
		_rebuild()
@export_range(0.04, 0.3, 0.005) var pile_radius := 0.09:
	set(v):
		pile_radius = v
		_rebuild()
## Cuanto sobresalen los pilotes por encima del tablero (m).
@export_range(0.0, 1.0, 0.05) var pile_top := 0.25:
	set(v):
		pile_top = v
		_rebuild()
## Hasta que profundidad bajan los pilotes (m, bajo este nodo).
@export_range(0.0, 3.0, 0.1) var pile_depth := 0.6:
	set(v):
		pile_depth = v
		_rebuild()
@export_range(0.03, 0.2, 0.005) var beam_radius := 0.07:
	set(v):
		beam_radius = v
		_rebuild()

@export_group("Madera")
@export var wood_light := Color("a09878"):
	set(v):
		wood_light = v
		_set_param("wood_light", v)
@export var wood_dark := Color("866350"):
	set(v):
		wood_dark = v
		_set_param("wood_dark", v)
@export var bark_color := Color("432015"):
	set(v):
		bark_color = v
		_set_param("bark_color", v)
@export var bark_dark := Color("1c1009"):
	set(v):
		bark_dark = v
		_set_param("bark_dark", v)
## Corteza en pilotes y vigas (los tablones siempre van serrados).
@export_range(0.0, 1.0, 0.05) var bark_amount := 0.8:
	set(v):
		bark_amount = v
		_set_param("bark_amount", v)
@export var palette_snap := true:
	set(v):
		palette_snap = v
		_set_param("palette_snap", v)

@export_group("Varios")
@export var collision_enabled := true:
	set(v):
		collision_enabled = v
		_rebuild()
@export var seed := 0:
	set(v):
		seed = v
		_rebuild()

var _planks: MultiMeshInstance3D
var _piles: MultiMeshInstance3D
var _beams: MultiMeshInstance3D
var _body: StaticBody3D
var _plank_mat: ShaderMaterial
var _log_mat: ShaderMaterial
var _clearance: CurveClearance
var _building := false


func _ready() -> void:
	curve_changed.connect(_rebuild)
	_rebuild()


func _enter_tree() -> void:
	add_to_group("water_passage")
	add_to_group("scatter_exclusion")


## Holgura (m) al eje del embarcadero: negativa bajo el tablero (y un poco alrededor).
func clearance_at(world_xz: Vector2) -> float:
	if curve == null:
		return INF
	if _clearance == null:
		_clearance = CurveClearance.from_curve(curve, global_transform, false, deck_width * 0.5 + 0.4, false)
	return _clearance.clearance_at(world_xz)


func _set_param(pname: String, value: Variant) -> void:
	for m in [_plank_mat, _log_mat]:
		if m:
			m.set_shader_parameter(pname, value)


func _make_material(bark: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WOOD_SHADER
	for p in ["wood_light", "wood_dark", "bark_color", "bark_dark", "palette_snap"]:
		m.set_shader_parameter(p, get(p))
	m.set_shader_parameter("bark_amount", bark)
	m.set_shader_parameter("grain_density", 6.0)
	m.set_shader_parameter("texels_per_unit", 40.0)
	return m


func _clear() -> void:
	for n in [_planks, _piles, _beams, _body]:
		if n:
			remove_child(n)
			n.queue_free()
	_planks = null
	_piles = null
	_beams = null
	_body = null
	_clearance = null


## Altura del tablero a `d` metros del arranque (la rampa sube desde 0).
func _height_at(d: float) -> float:
	if ramp_length <= 0.0 or d >= ramp_length:
		return deck_height
	return deck_height * clampf(d / ramp_length, 0.0, 1.0)


## Punto y marco local a `d` metros: {pos (con altura), fwd, side, slope (rad)}.
func _frame_at(d: float, length: float) -> Dictionary:
	d = clampf(d, 0.0, length)
	var p := curve.sample_baked(d)
	var q := curve.sample_baked(minf(d + 0.05, length)) if d + 0.05 <= length else curve.sample_baked(maxf(d - 0.05, 0.0))
	var fwd := (q - p) if d + 0.05 <= length else (p - q)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.FORWARD
	# side = up x fwd para que Basis(side, up, fwd) sea dextrogira (det +1). Con fwd x up el
	# basis queda especular y las normales de los tablones se invierten (tapa sin luz).
	var side := Vector3.UP.cross(fwd).normalized()
	var h := _height_at(d)
	var slope := 0.0
	if ramp_length > 0.0 and d < ramp_length:
		slope = atan2(deck_height, ramp_length)
	return {"pos": Vector3(p.x, h, p.z), "fwd": fwd, "side": side, "slope": slope}


func _rebuild() -> void:
	if not is_inside_tree() or _building or curve == null or curve.point_count < 2:
		return
	_building = true
	_clear()
	var length := curve.get_baked_length()
	if length > 0.3:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed if seed != 0 else hash(global_position.snapped(Vector3.ONE * 0.01))
		_plank_mat = _make_material(0.0)
		_plank_mat.set_shader_parameter("flat_grain", true)
		_plank_mat.set_shader_parameter("grain_density", 5.0)
		_log_mat = _make_material(bark_amount)
		_build_planks(length, rng)
		_build_structure(length, rng)
		if collision_enabled:
			_build_collision(length)
	_building = false
	_notify_lakes()


## Los lagos quitan su colision de orilla bajo el embarcadero: que se reconstruyan.
func _notify_lakes() -> void:
	if Engine.is_editor_hint():
		return
	for lake in get_tree().get_nodes_in_group("lake"):
		if lake.has_method("_rebuild") and lake.is_node_ready():
			lake.call_deferred("_rebuild")


func _build_planks(length: float, rng: RandomNumberGenerator) -> void:
	var pitch := plank_width + plank_gap
	var count := maxi(1, int(floor(length / pitch)))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(deck_width, plank_thickness, plank_width)
	mesh.material = _plank_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var d := pitch * (float(i) + 0.5)
		var f := _frame_at(d, length)
		var basis := Basis(f.side, Vector3.UP, f.fwd)  # X = ancho, Z = avance
		if f.slope != 0.0:
			basis = basis * Basis(Vector3.RIGHT, -f.slope)  # inclinar con la rampa
		var yaw_var := rng.randf_range(-plank_variation, plank_variation) * 0.5
		basis = basis * Basis(Vector3.UP, yaw_var)
		var len_var := 1.0 + rng.randf_range(-plank_variation, plank_variation)
		basis = basis * Basis.from_scale(Vector3(len_var, 1.0, 1.0))
		var off: Vector3 = f.side * rng.randf_range(-plank_variation, plank_variation) * 0.5
		mm.set_instance_transform(i, Transform3D(basis, f.pos + off - Vector3(0.0, plank_thickness * 0.5, 0.0)))
		mm.set_instance_custom_data(i, Color(rng.randf() * 100.0, 0.0, 0.0, 0.0))
	_planks = MultiMeshInstance3D.new()
	_planks.name = "Planks"
	_planks.multimesh = mm
	add_child(_planks)


func _build_structure(length: float, rng: RandomNumberGenerator) -> void:
	# Pilotes: pares a ambos lados cada pile_spacing (siempre uno al final del embarcadero).
	var n := maxi(1, int(round(length / pile_spacing)))
	var pile_ds := []
	for i in n + 1:
		pile_ds.append(length * float(i) / float(n))
	var half := deck_width * 0.5 - pile_radius
	var pile_mesh := CylinderMesh.new()
	pile_mesh.top_radius = pile_radius
	pile_mesh.bottom_radius = pile_radius
	pile_mesh.height = 1.0
	pile_mesh.radial_segments = 6
	pile_mesh.rings = 1
	pile_mesh.material = _log_mat
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.use_custom_data = true
	pm.mesh = pile_mesh
	pm.instance_count = pile_ds.size() * 2
	var idx := 0
	var frames := []
	for d in pile_ds:
		var f := _frame_at(d, length)
		frames.append(f)
		for s in [-1.0, 1.0]:
			var top: float = f.pos.y + pile_top
			var bottom := -pile_depth
			var h := top - bottom
			var lean := Basis.from_euler(Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(0.0, TAU), rng.randf_range(-0.03, 0.03)))
			var xf := Transform3D(lean * Basis.from_scale(Vector3(1.0, h, 1.0)),
					Vector3(f.pos.x, (top + bottom) * 0.5, f.pos.z) + f.side * half * s)
			pm.set_instance_transform(idx, xf)
			pm.set_instance_custom_data(idx, Color(rng.randf() * 100.0, 0.0, 0.0, 0.0))
			idx += 1
	_piles = MultiMeshInstance3D.new()
	_piles.name = "Piles"
	_piles.multimesh = pm
	add_child(_piles)

	# Vigas: entre pilotes consecutivos, a cada lado, justo bajo los tablones.
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = beam_radius
	beam_mesh.bottom_radius = beam_radius
	beam_mesh.height = 1.0
	beam_mesh.radial_segments = 6
	beam_mesh.rings = 1
	beam_mesh.material = _log_mat
	var bm := MultiMesh.new()
	bm.transform_format = MultiMesh.TRANSFORM_3D
	bm.use_custom_data = true
	bm.mesh = beam_mesh
	bm.instance_count = maxi(0, (frames.size() - 1) * 2)
	idx = 0
	for i in frames.size() - 1:
		for s in [-1.0, 1.0]:
			var a: Vector3 = frames[i].pos + frames[i].side * (half - pile_radius * 0.2) * s - Vector3(0.0, plank_thickness + beam_radius, 0.0)
			var b: Vector3 = frames[i + 1].pos + frames[i + 1].side * (half - pile_radius * 0.2) * s - Vector3(0.0, plank_thickness + beam_radius, 0.0)
			var along := b - a
			var len := along.length()
			if len < 0.01:
				bm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3.ZERO), a))
				idx += 1
				continue
			var dir := along / len
			var x := dir.cross(Vector3.UP)
			if x.length() < 0.001:
				x = Vector3.RIGHT
			x = x.normalized()
			var basis := Basis(x, dir, x.cross(dir)) * Basis.from_scale(Vector3(1.0, len, 1.0))
			bm.set_instance_transform(idx, Transform3D(basis, (a + b) * 0.5))
			bm.set_instance_custom_data(idx, Color(rng.randf() * 100.0, 0.0, 0.0, 0.0))
			idx += 1
	_beams = MultiMeshInstance3D.new()
	_beams.name = "Beams"
	_beams.multimesh = bm
	add_child(_beams)


## Tablero transitable: cajas cada ~1 m siguiendo la curva (inclinadas en la rampa).
func _build_collision(length: float) -> void:
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	var n := maxi(1, int(ceil(length / 1.0)))
	for i in n:
		var d0 := length * float(i) / float(n)
		var d1 := length * float(i + 1) / float(n)
		var f0 := _frame_at(d0, length)
		var f1 := _frame_at(d1, length)
		var a: Vector3 = f0.pos
		var b: Vector3 = f1.pos
		var along := b - a
		var len := along.length()
		if len < 0.01:
			continue
		var dir := along / len
		var side := Vector3(dir.z, 0.0, -dir.x).normalized() if absf(dir.y) < 0.999 else Vector3.RIGHT
		var up := side.cross(dir).normalized()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(deck_width, 0.12, len + 0.05)
		shape.shape = box
		shape.transform = Transform3D(Basis(side, up, dir), (a + b) * 0.5 - up * 0.06)
		_body.add_child(shape)
	add_child(_body)
