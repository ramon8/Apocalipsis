@tool
class_name ScatterWorld
extends Node3D
## Vegetacion por chunks con LOD para mapas enormes (p.ej. 1000x1000 m) con millones de
## instancias VIRTUALES: cada celda se genera de forma determinista (semilla + coords),
## y solo residen en memoria las celdas cercanas al jugador.
##
##   anillo CERCANO  (near_radius):  arboles/arbustos reales (colision, interaccion,
##                                   oclusores, variacion propia) + hierba completa.
##   anillo LEJANO   (far_radius):   un MultiMesh de quads cruzados por celda y tipo
##                                   (miles de copas en 1 draw call, sin nodos ni fisica).
##   mas alla:                       nada (se genera al acercarse).
##
## En el EDITOR muestra una previsualizacion alrededor del origen (props en MultiMesh +
## hierba en el radio cercano) que se regenera sola al cambiar cualquier export.

@export_group("World")
## Tamano total del mundo en metros, centrado en este nodo.
@export var world_size := Vector2(1000.0, 1000.0)
## Lado de cada celda. 32 m equilibra draw calls y coste de generacion.
@export_range(8.0, 128.0, 1.0) var cell_size := 32.0
@export var seed := 1

@export_group("LOD")
## Radio con props reales + hierba (el jugador siempre esta dentro).
@export_range(16.0, 256.0, 1.0) var near_radius := 64.0
## Radio visible con MultiMesh lejano. Mas alla no se renderiza nada.
@export_range(32.0, 1024.0, 1.0) var far_radius := 220.0
## Cada cuanto se comprueba el movimiento del jugador (s).
@export_range(0.1, 2.0, 0.1) var update_interval := 0.3

@export_group("Trees & bushes")
## Variantes de arbol: cada prop de tipo arbol elige una al azar (determinista por celda).
## Debe ir en paralelo con tree_textures (misma posicion = misma variante).
@export var tree_scenes: Array[PackedScene] = [
	preload("res://scenes/props/tree/tree.tscn"),
	preload("res://scenes/props/tree/tree_2.tscn"),
	preload("res://scenes/props/tree/tree_3.tscn"),
]
@export var bush_scene: PackedScene = preload("res://scenes/props/tree/bush.tscn")
## Props por 100 m2 dentro de las zonas densas (como TreeArea).
@export_range(0.0, 50.0, 0.1) var prop_density := 4.0
## Probabilidad relativa arbol vs arbusto.
@export var tree_weight := 1.0
@export var bush_weight := 1.5
@export_range(0.5, 10.0, 0.1) var prop_min_distance := 2.5
## Texturas/altura usadas por el LOD lejano (en paralelo con tree_scenes).
@export var tree_textures: Array[Texture2D] = [
	preload("res://assets/textures/tree.png"),
	preload("res://assets/textures/tree_2.png"),
	preload("res://assets/textures/tree_3.png"),
]
@export var bush_texture: Texture2D = preload("res://assets/textures/bush.png")
@export var tree_height := 6.0
@export var bush_height := 1.8
@export var size_variation := 0.25

@export_group("Paths")
## Caminos (GroundPaths) que la dispersion respeta: nada se planta encima ni a menos de
## `path_clearance` metros de su borde.
@export var paths: GroundPaths
@export_range(0.0, 10.0, 0.25) var path_clearance := 1.0

@export_group("Forest shape")
## 0 = bosque uniforme; 1 = manchas de bosque y claros segun el ruido.
@export_range(0.0, 1.0, 0.05) var patchiness := 0.7
@export_range(10.0, 500.0, 5.0) var patch_scale := 90.0
@export_range(0.0, 1.0, 0.01) var patch_threshold := 0.45

@export_group("Grass")
@export var grass_enabled := true
## Radio con hierba (independiente de near_radius: en celdas lejanas es solo visual).
## Debe cubrir lo que ve la camara en el zoom maximo.
@export_range(16.0, 512.0, 1.0) var grass_radius := 90.0
## Briznas por m2 en zonas densas (la GrassArea de cada celda aplica su propio parcheado).
@export_range(0.0, 100.0, 0.5) var grass_density := 20.0
@export var grass_height_range := Vector2(0.18, 0.4)
@export_range(1, 4) var grass_segments := 3
## Colores de las briznas: base (raiz), punta y tinte de variacion por brizna.
@export var grass_base_color := Color(0.18, 0.32, 0.14)
@export var grass_tip_color := Color(0.45, 0.62, 0.25)
@export var grass_variation_color := Color(0.35, 0.45, 0.18)
@export_range(0.0, 1.0, 0.05) var grass_variation_amount := 0.5
@export_range(0.005, 0.3, 0.005) var grass_blade_width := 0.05
## 0 = briznas verticales; 1 = billboard completo (tambien se inclinan hacia la camara).
@export_range(0.0, 1.0, 0.05) var grass_billboard_tilt := 0.0

@export_group("Editor preview")
## Mostrar el bosque en el editor (alrededor del origen del nodo).
@export var editor_preview := true
## Radio de la previsualizacion en el editor.
@export_range(32.0, 512.0, 1.0) var preview_radius := 140.0

const WIND_SHADER := preload("res://scenes/props/tree/shaders/wind_cutout_unshaded.gdshader")

var _cells := {}          # Vector2i -> {"lod": int(0 near / 1 far), "node": Node3D}
var _pending: Array[Vector2i] = []
var _pending_lod := {}
var _noise := FastNoiseLite.new()
var _cross_mesh: ArrayMesh
var _tree_mats: Array[ShaderMaterial] = []
var _bush_mat: ShaderMaterial
var _timer := 0.0
var _player: Node3D
var _preview_hash := 0
var _preview_timer := 0.0
## Estadisticas (solo lectura): nodos de props reales y instancias lejanas residentes.
var stats := {"near_cells": 0, "far_cells": 0, "near_props": 0, "far_instances": 0, "grass_blades": 0}


func _ready() -> void:
	_cross_mesh = _build_cross_mesh()
	_refresh_materials()
	_refresh_noise()
	if Engine.is_editor_hint():
		_preview_hash = 0  # fuerza la primera construccion
	else:
		prewarm.call_deferred()


func _refresh_noise() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = seed
	_noise.frequency = 1.0 / patch_scale
	_noise.fractal_octaves = 2


func _refresh_materials() -> void:
	_tree_mats.clear()
	for tex in tree_textures:
		_tree_mats.append(_make_wind_material(tex))
	_bush_mat = _make_wind_material(bush_texture)


## Numero de variantes de arbol utilizables (escena Y textura presentes).
func _tree_variant_count() -> int:
	return maxi(mini(tree_scenes.size(), tree_textures.size()), 1)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# Regenerar la previsualizacion cuando cambia cualquier parametro (sondeo barato).
		_preview_timer -= delta
		if _preview_timer <= 0.0:
			_preview_timer = 0.5
			var h := _config_hash()
			if h != _preview_hash:
				_preview_hash = h
				_refresh_noise()
				_refresh_materials()
				_build_editor_preview()
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = update_interval
		_update_cells()
	# Materializar como mucho una celda por frame.
	if not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		var lod: int = _pending_lod.get(c, -1)
		_pending_lod.erase(c)
		if lod >= 0:
			_build_cell_state(c, lod)


func _config_hash() -> int:
	return hash([world_size, cell_size, seed, near_radius, grass_radius, prop_density, tree_weight,
			bush_weight, prop_min_distance, tree_textures, tree_scenes, bush_texture, tree_height,
			bush_height, size_variation, patchiness, patch_scale, patch_threshold,
			grass_enabled, grass_density, grass_height_range, grass_segments,
			grass_base_color, grass_tip_color, grass_variation_color,
			grass_variation_amount, grass_blade_width, grass_billboard_tilt,
			editor_preview, preview_radius,
			path_clearance, paths._content_hash() if paths else 0])


func _build_editor_preview() -> void:
	for c in _cells.keys():
		_cells[c].node.free()
	_cells.clear()
	if not editor_preview:
		return
	var max_cells := Vector2i(ceili(world_size.x / cell_size), ceili(world_size.y / cell_size))
	var r := preview_radius
	var half := world_size * 0.5
	for cx in range(maxi(floori((-r + half.x) / cell_size), 0), mini(floori((r + half.x) / cell_size), max_cells.x - 1) + 1):
		for cz in range(maxi(floori((-r + half.y) / cell_size), 0), mini(floori((r + half.y) / cell_size), max_cells.y - 1) + 1):
			var c := Vector2i(cx, cz)
			var centre := _cell_centre(c)
			var d := Vector2(centre.x, centre.z).length()
			if d > r + cell_size * 0.7:
				continue
			var props := _cell_props(c)
			var cell := Node3D.new()
			cell.name = "PreviewCell_%d_%d" % [c.x, c.y]
			cell.position = centre
			add_child(cell)
			for v in _tree_mats.size():
				_add_far_multimesh(cell, props, 0, _tree_mats[v], tree_height, v)
			_add_far_multimesh(cell, props, 1, _bush_mat, bush_height)
			if grass_enabled and grass_density > 0.0 and d < minf(grass_radius, r):
				cell.add_child(_make_grass_area(c))
			_cells[c] = {"lod": 1, "node": cell}


func _player_pos() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		var rig := get_tree().get_first_node_in_group("camera_rig")
		_player = rig.target if rig else null
	return _player.global_position if _player else global_position


func _update_cells() -> void:
	var p := to_local(_player_pos())
	var half := world_size * 0.5
	var min_c := Vector2i(floori((p.x - far_radius + half.x) / cell_size), floori((p.z - far_radius + half.y) / cell_size))
	var max_c := Vector2i(floori((p.x + far_radius + half.x) / cell_size), floori((p.z + far_radius + half.y) / cell_size))
	var max_cells := Vector2i(ceili(world_size.x / cell_size), ceili(world_size.y / cell_size))
	var wanted := {}
	for cx in range(maxi(min_c.x, 0), mini(max_c.x, max_cells.x - 1) + 1):
		for cz in range(maxi(min_c.y, 0), mini(max_c.y, max_cells.y - 1) + 1):
			var c := Vector2i(cx, cz)
			var centre := _cell_centre(c)
			var d := Vector2(p.x, p.z).distance_to(Vector2(centre.x, centre.z))
			if d > far_radius + cell_size * 0.7:
				continue
			var lod := 0 if d < near_radius else 1
			var with_grass := d < grass_radius + cell_size * 0.7
			wanted[c] = lod * 2 + (1 if with_grass else 0)
	for c in _cells.keys():
		if not wanted.has(c):
			_cells[c].node.queue_free()
			_cells.erase(c)
	for c in wanted:
		var state: int = wanted[c]
		if _cells.has(c) and _cells[c].state == state:
			continue
		if _pending_lod.get(c, -1) != state:
			_pending_lod[c] = state
			if not _pending.has(c):
				_pending.append(c)
	_refresh_stats()


## Construye TODO lo pendiente de golpe (arranque / teletransporte): carga un poco mas
## larga a cambio de que no se vea aparecer el mundo.
func prewarm() -> void:
	_update_cells()
	while not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		var state: int = _pending_lod.get(c, -1)
		_pending_lod.erase(c)
		if state >= 0:
			_build_cell_state(c, state)


func _cell_centre(c: Vector2i) -> Vector3:
	var half := world_size * 0.5
	return Vector3(c.x * cell_size + cell_size * 0.5 - half.x, 0.0, c.y * cell_size + cell_size * 0.5 - half.y)


func _make_grass_area(c: Vector2i) -> GrassArea:
	var grass := GrassArea.new()
	grass.size = Vector2(cell_size, cell_size)
	grass.density = grass_density
	grass.height_range = grass_height_range
	grass.segments = grass_segments
	grass.seed = _cell_seed(c)
	grass.base_color = grass_base_color
	grass.tip_color = grass_tip_color
	grass.variation_color = grass_variation_color
	grass.variation_amount = grass_variation_amount
	grass.blade_width = grass_blade_width
	grass.billboard_tilt = grass_billboard_tilt
	return grass


func _build_cell_state(c: Vector2i, state: int) -> void:
	var lod := state / 2
	var with_grass := (state % 2) == 1
	if _cells.has(c):
		_cells[c].node.queue_free()
		_cells.erase(c)
	var props := _cell_props(c)
	var cell := Node3D.new()
	cell.name = "Cell_%d_%d" % [c.x, c.y]
	cell.position = _cell_centre(c)
	add_child(cell)
	if lod == 0:
		for p in props:
			var variant := mini(int(p.get("v", 0)), tree_scenes.size() - 1)
			var inst: Node3D = (tree_scenes[variant] if p.kind == 0 else bush_scene).instantiate()
			# Igualar EXACTAMENTE el quad del LOD lejano (altura, escala y yaw deterministas)
			# para que la transicion cercano<->lejano no haga pop.
			inst.set("size_variation", 0.0)
			inst.set("random_yaw", false)
			inst.set("height", tree_height if p.kind == 0 else bush_height)
			cell.add_child(inst)
			inst.position = p.pos
			inst.scale = Vector3.ONE * p.s
			inst.rotation.y = p.yaw
	else:
		for v in _tree_mats.size():
			_add_far_multimesh(cell, props, 0, _tree_mats[v], tree_height, v)
		_add_far_multimesh(cell, props, 1, _bush_mat, bush_height)
	if with_grass and grass_enabled and grass_density > 0.0:
		cell.add_child(_make_grass_area(c))
	_cells[c] = {"lod": lod, "state": state, "node": cell}
	_refresh_stats()


## Lista determinista de props de una celda: [{pos: Vector3 (local celda), kind, s, yaw}].
func _cell_props(c: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _cell_seed(c)
	var out := []
	var target := int(round(cell_size * cell_size / 100.0 * prop_density))
	var centre := _cell_centre(c)
	var placed: Array[Vector2] = []
	var total_w := tree_weight + bush_weight
	for i in target:
		var p := Vector2(rng.randf_range(-cell_size * 0.5, cell_size * 0.5), rng.randf_range(-cell_size * 0.5, cell_size * 0.5))
		var n := (_noise.get_noise_2d(centre.x + p.x, centre.z + p.y) + 1.0) * 0.5
		var keep := lerpf(1.0, smoothstep(patch_threshold - 0.15, patch_threshold + 0.15, n), patchiness)
		if rng.randf() > keep:
			continue
		if paths and paths.clearance_at(Vector2(global_position.x + centre.x + p.x,
				global_position.z + centre.z + p.y)) < path_clearance:
			continue
		var ok := true
		for q in placed:
			if p.distance_squared_to(q) < prop_min_distance * prop_min_distance:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var kind := 0 if rng.randf() * total_w < tree_weight else 1
		out.append({"pos": Vector3(p.x, 0.0, p.y), "kind": kind,
				"s": 1.0 + rng.randf_range(-size_variation, size_variation), "yaw": rng.randf_range(0.0, TAU),
				"v": rng.randi_range(0, _tree_variant_count() - 1)})
	return out


func _cell_seed(c: Vector2i) -> int:
	return hash([seed, c.x, c.y])


func _add_far_multimesh(cell: Node3D, props: Array, kind: int, mat: ShaderMaterial, height: float, variant := -1) -> void:
	var list := props.filter(func(p) -> bool:
		return p.kind == kind and (variant < 0 or int(p.get("v", 0)) == variant))
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _cross_mesh
	mm.instance_count = list.size()
	for i in list.size():
		var p: Dictionary = list[i]
		var s: float = height * p.s
		var basis := Basis.from_euler(Vector3(0.0, p.yaw, 0.0)).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(basis, p.pos))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.custom_aabb = AABB(Vector3(-cell_size, -1.0, -cell_size), Vector3(cell_size * 2.0, height * 2.0 + 2.0, cell_size * 2.0))
	cell.add_child(mi)


## Malla unitaria de dos quads cruzados (1 m de ancho y alto, base en y=0).
func _build_cross_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in 2:
		var right := Vector3(0.5, 0.0, 0.0) if i == 0 else Vector3(0.0, 0.0, 0.5)
		var base := verts.size()
		verts.append_array([-right, right, right + Vector3.UP, -right + Vector3.UP])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_wind_material(tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WIND_SHADER
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("alpha_cutoff", 0.5)
	m.set_shader_parameter("wind_influence", 1.0)
	m.set_shader_parameter("sway_amount", 0.35)
	m.set_shader_parameter("flutter_amount", 0.12)
	return m


func _refresh_stats() -> void:
	var near_cells := 0
	var far_cells := 0
	var near_props := 0
	var far_inst := 0
	var blades := 0
	for c in _cells:
		var entry: Dictionary = _cells[c]
		if entry.lod == 0:
			near_cells += 1
			for child in entry.node.get_children():
				if child is GrassArea:
					blades += child.blade_count
				else:
					near_props += 1
		else:
			far_cells += 1
			for child in entry.node.get_children():
				if child is MultiMeshInstance3D:
					far_inst += child.multimesh.instance_count
	stats = {"near_cells": near_cells, "far_cells": far_cells, "near_props": near_props,
			"far_instances": far_inst, "grass_blades": blades}
