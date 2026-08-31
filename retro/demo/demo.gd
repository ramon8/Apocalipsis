extends Node3D
## Escena de tuneo del pipeline retro. Cámara orbitando, primitivas con psx_base.

@export var orbit_speed_deg := 12.0
@export var orbit_radius := 7.0
@export var orbit_height := 3.0
@export var auto_orbit := true

@onready var _camera: Camera3D = $Camera3D
@onready var _cube: MeshInstance3D = $Cube
@onready var _hint: Label = $UI/Hint
@onready var _env: Environment = $WorldEnvironment.environment

var _angle := 0.0


func _ready() -> void:
	_hint.text = "TAB: panel   ESPACIO: orbitar   R: retro on/off   1/2: presets"
	RetroRenderer.profile_applied.connect(_on_profile_applied)
	_on_profile_applied(RetroRenderer.profile)


## El fondo debe casar con la niebla para que el horizonte "desaparezca" como en PSX.
func _on_profile_applied(p: RetroProfile) -> void:
	if p.fog_enabled and RetroRenderer.retro_enabled:
		_env.background_color = p.fog_color


func _process(delta: float) -> void:
	if auto_orbit:
		_angle += deg_to_rad(orbit_speed_deg) * delta
	_camera.position = Vector3(sin(_angle) * orbit_radius, orbit_height, cos(_angle) * orbit_radius)
	_camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	_cube.rotate_y(delta * 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_SPACE:
				auto_orbit = not auto_orbit
			KEY_R:
				RetroRenderer.retro_enabled = not RetroRenderer.retro_enabled
			KEY_1:
				$UI/Panel.load_preset("res://retro/profiles/psx_crudo.tres")
			KEY_2:
				$UI/Panel.load_preset("res://retro/profiles/suave.tres")
