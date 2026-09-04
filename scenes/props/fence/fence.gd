@tool
class_name Fence
extends Path3D
## Valla de madera generada a lo largo de la curva: postes cada `post_spacing` metros y
## travesanos (cilindros) entre poste y poste. Dibuja la curva en el editor (cierra el
## bucle con `curve.closed` para un corral) y se reconstruye sola. Postes y travesanos son
## MultiMesh con el shader de madera del banco (semilla por instancia); colision por tramo.
## La altura de los puntos se ignora: todo va a la altura de este nodo.

const WOOD_SHADER := preload("res://scenes/props/bench/shaders/wood.gdshader")

@export_group("Postes")
@export_range(0.5, 10.0, 0.1) var post_spacing := 2.0:
	set(v):
		post_spacing = v
		_rebuild()
@export_range(0.3, 3.0, 0.05) var post_height := 1.05:
	set(v):
		post_height = v
		_rebuild()
@export_range(0.03, 0.3, 0.005) var post_radius := 0.07:
	set(v):
		post_radius = v
		_rebuild()
## Inclinacion aleatoria maxima de cada poste (grados): vallas viejas, no rectas del todo.
@export_range(0.0, 15.0, 0.5) var post_lean_deg := 3.0:
	set(v):
		post_lean_deg = v
		_rebuild()
## Variacion aleatoria de altura (fraccion).
@export_range(0.0, 0.5, 0.01) var post_height_variation := 0.08:
	set(v):
		post_height_variation = v
		_rebuild()

@export_group("Travesanos")
@export_range(0, 4) var rails := 2:
	set(v):
		rails = v
		_rebuild()
@export_range(0.02, 0.2, 0.005) var rail_radius := 0.045:
	set(v):
		rail_radius = v
		_rebuild()
## Altura del travesano mas bajo y del mas alto, como fraccion de post_height.
@export var rail_span := Vector2(0.4, 0.85):
	set(v):
		rail_span = v
		_rebuild()
## Los travesanos sobresalen un poco del poste (m).
@export_range(0.0, 0.3, 0.01) var rail_overhang := 0.06:
	set(v):
		rail_overhang = v
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
## Corteza en postes y travesanos (1 = troncos sin pelar).
@export_range(0.0, 1.0, 0.05) var bark_amount := 1.0:
	set(v):
		bark_amount = v
		_set_param("bark_amount", v)
@export var palette_snap := true:
	set(v):
		palette_snap = v
		_set_param("palette_snap", v)

@export_group("Colision")
@export var collision_enabled := true:
	set(v):
		collision_enabled = v
		_rebuild()
## Grosor de la caja de colision de cada tramo (m).
@export_range(0.05, 1.0, 0.05) var collision_thickness := 0.25

@export_group("Varios")
## 0 = semilla por posicion (estable); otro valor = fija ese aspecto.
@export var seed := 0:
	set(v):
		seed = v
		_rebuild()
@export_range(3, 12) var radial_segments := 6:
	set(v):
		radial_segments = v
		_rebuild()

var _posts: MultiMeshInstance3D
var _rails: MultiMeshInstance3D
var _body: StaticBody3D
var _post_mat: ShaderMaterial
var _rail_mat: ShaderMaterial
var _building := false


func _ready() -> void:
	curve_changed.connect(_rebuild)
	_rebuild()


func _set_param(pname: String, value: Variant) -> void:
	for m in [_post_mat, _rail_mat]:
		if m:
			m.set_shader_parameter(pname, value)


func _make_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WOOD_SHADER
	for p in ["wood_light", "wood_dark", "bark_color", "bark_dark", "bark_amount", "palette_snap"]:
		m.set_shader_parameter(p, get(p))
	m.set_shader_parameter("grain_density", 7.0)
	m.set_shader_parameter("texels_per_unit", 48.0)
	return m


func _clear() -> void:
	for n in [_posts, _rails, _body]:
		if n:
			n.free()
	_posts = null
	_rails = null
	_body = null


## Puntos de poste a lo largo de la curva (locales a este nodo, y = 0) y direccion.
func _post_points() -> Array:
	var out := []
	if curve == null or curve.point_count < 2:
		return out
	var length := curve.get_baked_length()
	if length < 0.1:
		return out
	var n := maxi(1, int(round(length / post_spacing)))
	var closed := curve.closed
	var count := n if closed else n + 1
	for i in count:
		var d := length * float(i) / float(n)
		var p := curve.sample_baked(minf(d, length))
		var q := curve.sample_baked(minf(d + 0.05, length)) if d + 0.05 <= length else curve.sample_baked(maxf(d - 0.05, 0.0))
		var dir := q - p if d + 0.05 <= length else p - q
		dir.y = 0.0
		out.append({"pos": Vector3(p.x, 0.0, p.z), "dir": dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD})
	return out


func _rebuild() -> void:
	if not is_inside_tree() or _building:
		return
	_building = true
	_clear()
	var points := _post_points()
	if points.size() >= 2 or (points.size() == 1 and curve.closed):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed if seed != 0 else hash(global_position.snapped(Vector3.ONE * 0.01))
		_post_mat = _make_material()
		_rail_mat = _make_material()
		_build_posts(points, rng)
		_build_rails(points, rng)
		if collision_enabled:
			_build_collision(points)
	_building = false


func _build_posts(points: Array, rng: RandomNumberGenerator) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = post_radius
	mesh.bottom_radius = post_radius
	mesh.height = 1.0
	mesh.radial_segments = radial_segments
	mesh.rings = 1
	mesh.material = _post_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in points.size():
		var h := post_height * (1.0 + rng.randf_range(-post_height_variation, post_height_variation))
		var lean := deg_to_rad(rng.randf_range(-post_lean_deg, post_lean_deg))
		var lean_dir := rng.randf_range(0.0, TAU)
		var basis := Basis.from_euler(Vector3(lean * cos(lean_dir), rng.randf_range(0.0, TAU), lean * sin(lean_dir)))
		basis = basis * Basis.from_scale(Vector3(1.0, h, 1.0))  # escala local (a lo largo del poste)
		var xf := Transform3D(basis, points[i].pos + Vector3(0.0, h * 0.5 - 0.02, 0.0))
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, Color(rng.randf() * 100.0, 0.0, 0.0, 0.0))
	_posts = MultiMeshInstance3D.new()
	_posts.name = "Posts"
	_posts.multimesh = mm
	add_child(_posts)


func _build_rails(points: Array, rng: RandomNumberGenerator) -> void:
	if rails <= 0:
		return
	var segs := points.size() if curve.closed else points.size() - 1
	if segs <= 0:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = rail_radius
	mesh.bottom_radius = rail_radius
	mesh.height = 1.0
	mesh.radial_segments = radial_segments
	mesh.rings = 1
	mesh.material = _rail_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = segs * rails
	var idx := 0
	for s in segs:
		var a: Vector3 = points[s].pos
		var b: Vector3 = points[(s + 1) % points.size()].pos
		var along := b - a
		var len := along.length()
		if len < 0.01:
			for r in rails:
				mm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3.ZERO), a))
				idx += 1
			continue
		var dir := along / len
		# Eje Y del cilindro -> direccion del tramo.
		var up := Vector3.UP
		var x := dir.cross(up).normalized()
		var basis := Basis(x, dir, x.cross(dir))
		for r in rails:
			var t := 0.5 if rails == 1 else float(r) / float(rails - 1)
			var h := post_height * lerpf(rail_span.x, rail_span.y, t)
			# Ligero hundimiento del travesano en el centro y variacion de altura por tramo.
			var wobble := rng.randf_range(-0.03, 0.03)
			# Escala local: el eje Y del cilindro (columna y del basis) mide lo que el tramo.
			var xf := Transform3D(basis * Basis.from_scale(Vector3(1.0, len + rail_overhang * 2.0, 1.0)),
					(a + b) * 0.5 + Vector3(0.0, h + wobble, 0.0))
			mm.set_instance_transform(idx, xf)
			mm.set_instance_custom_data(idx, Color(rng.randf() * 100.0, 0.0, 0.0, 0.0))
			idx += 1
	_rails = MultiMeshInstance3D.new()
	_rails.name = "Rails"
	_rails.multimesh = mm
	add_child(_rails)


func _build_collision(points: Array) -> void:
	var segs := points.size() if curve.closed else points.size() - 1
	if segs <= 0:
		return
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	for s in segs:
		var a: Vector3 = points[s].pos
		var b: Vector3 = points[(s + 1) % points.size()].pos
		var along := b - a
		var len := along.length()
		if len < 0.01:
			continue
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(collision_thickness, post_height, len)
		shape.shape = box
		shape.position = (a + b) * 0.5 + Vector3(0.0, post_height * 0.5, 0.0)
		shape.rotation.y = atan2(along.x, along.z)
		_body.add_child(shape)
	add_child(_body)
