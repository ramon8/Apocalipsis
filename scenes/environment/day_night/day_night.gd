@tool
class_name DayNightCycle
extends Node3D
## Ciclo dia/noche autonomo. Se instancia en cualquier escena y se le pasan el Sol
## (DirectionalLight3D) y el WorldEnvironment; el nodo mueve el sol por el cielo,
## regula su energia/color, funde los colores del cielo (ProceduralSkyMaterial) y
## la luz ambiente, y saca una luna tenue por la noche.
##
## `time_of_day` (0-24) se puede arrastrar en el inspector para previsualizar
## cualquier hora en el editor. En juego avanza sola: un dia completo dura
## `day_length_minutes` minutos reales.
##
## OJO editor: la previsualizacion escribe sobre el material de cielo de la escena;
## si guardas, esos colores quedan guardados. Da igual en runtime (el ciclo los
## pisa cada frame), pero no te extranes si el .tscn cambia.

signal hour_changed(hour: int)
signal night_started
signal day_started

@export_group("Time")
## Hora del dia (0-24). Arrastralo en el editor para previsualizar.
@export_range(0.0, 24.0, 0.01) var time_of_day := 12.0:
	set(value):
		time_of_day = fposmod(value, 24.0)
		_apply()
## Minutos reales que dura un dia completo de juego.
@export_range(0.5, 120.0, 0.5) var day_length_minutes := 10.0
## Si avanza el tiempo automaticamente en juego.
@export var advance_time := true
## Avanzar tambien dentro del editor (para ver el ciclo en movimiento).
@export var advance_in_editor := false

@export_group("References")
@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment

@export_group("Sun")
@export_range(0.0, 12.0, 0.1) var sunrise_hour := 6.5
@export_range(12.0, 24.0, 0.1) var sunset_hour := 20.5
@export_range(0.0, 4.0, 0.05) var sun_max_energy := 1.2
## Elevacion maxima del sol a mediodia, en grados.
@export_range(15.0, 89.0, 0.5) var max_elevation_deg := 55.0
## Orientacion (yaw) del recorrido del sol; el arco va de este a oeste alrededor de ella.
@export var azimuth_deg := -30.0
## Color del sol a lo largo del dia (0 = amanecer, 0.5 = mediodia, 1 = atardecer).
@export var sun_gradient: Gradient

@export_group("Moon")
@export var moon_enabled := true
@export_range(0.0, 1.0, 0.01) var moon_energy := 0.18
@export var moon_color := Color(0.55, 0.65, 0.9)
@export var moon_shadows := true

@export_group("Sky")
## Colores del cenit segun el momento (0 = noche cerrada, 0.5 = horizonte, 1 = pleno dia).
@export var sky_top_gradient: Gradient
## Colores del horizonte segun el momento (mismo eje que el de arriba).
@export var sky_horizon_gradient: Gradient
## Energia de la luz ambiente en plena noche / pleno dia.
@export_range(0.0, 2.0, 0.05) var ambient_night := 0.35
@export_range(0.0, 2.0, 0.05) var ambient_day := 1.0

var _moon: DirectionalLight3D
var _last_hour := -1
var _was_day := true


func _ready() -> void:
	if sun_gradient == null:
		sun_gradient = _make_gradient([0.0, 0.12, 0.5, 0.88, 1.0], [
			Color(1.0, 0.45, 0.2), Color(1.0, 0.85, 0.65), Color(1.0, 0.98, 0.92),
			Color(1.0, 0.8, 0.55), Color(1.0, 0.4, 0.18)])
	if sky_top_gradient == null:
		sky_top_gradient = _make_gradient([0.0, 0.35, 0.55, 1.0], [
			Color(0.015, 0.02, 0.06), Color(0.06, 0.06, 0.14), Color(0.2, 0.22, 0.42),
			Color(0.25, 0.35, 0.55)])
	if sky_horizon_gradient == null:
		sky_horizon_gradient = _make_gradient([0.0, 0.35, 0.55, 1.0], [
			Color(0.05, 0.06, 0.12), Color(0.55, 0.3, 0.22), Color(0.85, 0.55, 0.38),
			Color(0.65, 0.7, 0.8)])
	if moon_enabled and _moon == null:
		_moon = DirectionalLight3D.new()
		_moon.name = "Moon"
		_moon.shadow_enabled = moon_shadows
		_moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		_moon.directional_shadow_max_distance = 250.0
		add_child(_moon)
	_apply()


func _process(delta: float) -> void:
	var advancing := advance_in_editor if Engine.is_editor_hint() else advance_time
	if advancing and day_length_minutes > 0.0:
		time_of_day = fposmod(time_of_day + delta * 24.0 / (day_length_minutes * 60.0), 24.0)
	if not Engine.is_editor_hint():
		_emit_transitions()


func is_day() -> bool:
	return time_of_day >= sunrise_hour and time_of_day < sunset_hour


## 0 = noche cerrada, 0.5 = sol en el horizonte, 1 = pleno dia. Eje comun de los gradientes.
func daylight_factor() -> float:
	var elev := _sun_elevation_deg()
	return clampf(inverse_lerp(-14.0, 12.0, elev), 0.0, 1.0)


func _sun_elevation_deg() -> float:
	if is_day():
		var f: float = inverse_lerp(sunrise_hour, sunset_hour, time_of_day)
		return sin(f * PI) * max_elevation_deg
	var g := _night_fraction()
	return -sin(g * PI) * 24.0  # cuanto se hunde bajo el horizonte (crepusculo -> noche)


## 0 = acaba de anochecer .. 1 = a punto de amanecer.
func _night_fraction() -> float:
	var night_len := 24.0 - (sunset_hour - sunrise_hour)
	var since_sunset := fposmod(time_of_day - sunset_hour, 24.0)
	return clampf(since_sunset / maxf(night_len, 0.01), 0.0, 1.0)


func _apply() -> void:
	if not is_inside_tree():
		return
	var t := daylight_factor()

	if sun:
		if is_day():
			var f: float = inverse_lerp(sunrise_hour, sunset_hour, time_of_day)
			sun.rotation_degrees = Vector3(-_sun_elevation_deg(),
					azimuth_deg + lerpf(70.0, -70.0, f), 0.0)
			if sun_gradient:
				sun.light_color = sun_gradient.sample(f)
		# La energia muere suavemente al acercarse al horizonte (y es 0 de noche).
		var strength := clampf(inverse_lerp(-2.0, 8.0, _sun_elevation_deg()), 0.0, 1.0)
		sun.light_energy = sun_max_energy * strength
		sun.visible = strength > 0.005  # sin luz no pagamos sus sombras

	if _moon:
		var g := _night_fraction()
		var moon_elev: float = sin(g * PI) * max_elevation_deg * 0.7
		_moon.rotation_degrees = Vector3(-moon_elev, azimuth_deg + lerpf(70.0, -70.0, g) + 180.0, 0.0)
		_moon.light_color = moon_color
		# Presente solo cuando el sol no aporta: entra en el crepusculo y sale al alba.
		var moon_strength := clampf(inverse_lerp(0.55, 0.15, t), 0.0, 1.0) * clampf(sin(g * PI) * 3.0, 0.0, 1.0)
		_moon.light_energy = moon_energy * moon_strength
		_moon.visible = moon_strength > 0.01

	if world_environment and world_environment.environment:
		var env := world_environment.environment
		env.ambient_light_energy = lerpf(ambient_night, ambient_day, t)
		if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
			var mat: ProceduralSkyMaterial = env.sky.sky_material
			var top := sky_top_gradient.sample(t)
			var horizon := sky_horizon_gradient.sample(t)
			mat.sky_top_color = top
			mat.sky_horizon_color = horizon
			mat.ground_horizon_color = horizon
			mat.ground_bottom_color = top.darkened(0.4)


func _emit_transitions() -> void:
	var hour := int(time_of_day)
	if hour != _last_hour:
		_last_hour = hour
		hour_changed.emit(hour)
	var day := is_day()
	if day != _was_day:
		_was_day = day
		if day:
			day_started.emit()
		else:
			night_started.emit()


func _make_gradient(offsets: Array, colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g
