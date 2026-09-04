class_name Wading
extends Node
## Vadeo: cada frame de fisica pregunta a los lagos (grupo "lake", `depth_at(xz)`) cuanta
## agua hay bajo el personaje. Con agua: el modelo se hunde esa profundidad (la fisica sigue
## sobre el suelo plano), el jugador anda mas despacio, los pasos suenan a chapoteo y cada
## pisada deja una onda sobre el agua. El dueno llama a setup() y tick(delta).

@export var enabled := true
## Ondas concentricas en cada pisada. Apagadas por defecto: el agua ya pinta espuma de
## contacto alrededor de lo que la corta (contact_foam en water.gdshader).
@export var ripples_enabled := false
## Suavizado del hundimiento (mas = mas lento).
@export_range(1.0, 30.0, 0.5) var sink_smoothing := 10.0
## Tamano de la onda de cada pisada (m) y su duracion (s).
@export_range(0.3, 3.0, 0.1) var ripple_size := 1.1
@export_range(0.2, 3.0, 0.1) var ripple_life := 0.9
## Aros por onda (1 o 2).
@export_range(1, 3) var ripple_rings := 1
## Onda extra continua mientras esta parado con agua (cada tantos segundos; 0 = no).
@export_range(0.0, 5.0, 0.1) var idle_ripple_interval := 1.6
## Estela al moverse por el agua (bufer del lago). Radio (m) y velocidad minima (m/s).
@export var wake_enabled := true
@export_range(0.1, 1.5, 0.05) var wake_radius := 0.32
@export_range(0.0, 3.0, 0.1) var wake_min_speed := 0.4

var depth := 0.0  # metros de agua bajo los pies (0 = seco)
var _speed_factor := 1.0
var _sink := 0.0
var _body: Node3D
var _model: Node3D
var _model_base_y := 0.0
var _idle_timer := 0.0
var _lakes: Array[Node] = []
var _lakes_refresh := 0.0
var _current_lake: Node
var _last_xz := Vector2.INF
var _last_stamp_xz := Vector2.INF


func setup(body: Node3D, model: Node3D, model_base_y: float) -> void:
	_body = body
	_model = model
	_model_base_y = model_base_y


func in_water() -> bool:
	return depth > 0.001


## Multiplicador de velocidad del dueno (1 en seco).
func speed_factor() -> float:
	return _speed_factor


func tick(delta: float) -> void:
	if not enabled or _body == null:
		return
	_lakes_refresh -= delta
	if _lakes_refresh <= 0.0:
		_lakes_refresh = 1.0
		_lakes.clear()
		for l in _body.get_tree().get_nodes_in_group("lake"):
			if l.has_method("depth_at"):
				_lakes.append(l)
	var xz := Vector2(_body.global_position.x, _body.global_position.z)
	depth = 0.0
	_speed_factor = 1.0
	_current_lake = null
	for lake in _lakes:
		# Sobre un embarcadero (o cualquier cosa por encima de la superficie): seco.
		if _body.global_position.y > lake.global_position.y + lake.water_level + 0.15:
			continue
		var d: float = lake.depth_at(xz)
		if d > depth:
			depth = d
			_current_lake = lake
			_speed_factor = lerpf(1.0, lake.wade_speed_factor, clampf(d / maxf(lake.wade_depth, 0.001), 0.0, 1.0))
	# Estela: estampar la posicion en el bufer del lago mientras se mueve.
	if wake_enabled and _current_lake and _current_lake.has_method("add_wake") and _last_xz != Vector2.INF:
		var speed := _last_xz.distance_to(xz) / maxf(delta, 0.0001)
		# Por distancia, no por frame: si no, las estampas se solapan y saturan el bufer.
		if speed >= wake_min_speed and (_last_stamp_xz == Vector2.INF or _last_stamp_xz.distance_to(xz) >= wake_radius * 0.5):
			var strength := clampf(speed / 3.0, 0.5, 1.0) * clampf(depth / 0.1, 0.4, 1.0)
			_current_lake.add_wake(xz, wake_radius, strength)
			_last_stamp_xz = xz
	if not in_water():
		_last_stamp_xz = Vector2.INF
	_last_xz = xz
	_sink = lerpf(_sink, depth, 1.0 - exp(-sink_smoothing * delta))
	if _model:
		_model.position.y = _model_base_y - _sink
	# Ondas suaves al estar quieto en el agua.
	if in_water() and idle_ripple_interval > 0.0:
		_idle_timer += delta
		if _idle_timer >= idle_ripple_interval:
			_idle_timer = 0.0
			ripple(0.7)
	else:
		_idle_timer = 0.0


## Onda en la posicion del dueno (la llama el dueno en cada pisada dentro del agua).
func ripple(scale := 1.0) -> void:
	if not ripples_enabled or not in_water() or _body == null:
		return
	var pos := _body.global_position
	pos.y = _current_lake.global_position.y + _current_lake.water_level + 0.02
	SplashRipple.spawn(_body.get_parent(), pos, ripple_size * scale, ripple_life, ripple_rings, _current_lake)
