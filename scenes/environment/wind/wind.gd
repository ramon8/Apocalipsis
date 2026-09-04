@tool
class_name WindController
extends Node
## Global wind. Writes the `wind_*` shader globals every frame so any material that
## declares them (see scenes/props/wind_cutout.gdshaderinc) sways in sync.
## Gusts come from smooth 1D noise, so the strength breathes instead of pulsing.
## Add one to the level; only one should be active at a time.

@export_group("Wind")
@export var enabled := true
## Compass direction the wind blows TOWARDS, in degrees (0 = +X, 90 = +Z).
@export_range(0.0, 360.0, 1.0) var direction_deg := 35.0
## Steady strength. 0 = calm, 1 = strong; props scale it with their own sway_amount.
@export_range(0.0, 2.0, 0.01) var strength := 0.4
## Animation speed of the sway/flutter.
@export_range(0.0, 5.0, 0.05) var speed := 1.0
## Side-to-side flutter amount fed to the shaders.
@export_range(0.0, 1.0, 0.01) var turbulence := 0.5

@export_group("Spatial variation")
## 0 = every prop feels the same wind; 1 = strength fully driven by the noise map
## (some areas calm, others gusting).
@export_range(0.0, 1.0, 0.01) var spatial_variation := 0.7
## Size of the gust pattern: metres covered by one noise tile. Bigger = broader gusts.
@export_range(5.0, 500.0, 1.0) var gust_size_m := 60.0
## Speed (m/s) at which the gust pattern travels downwind across the level.
@export_range(0.0, 30.0, 0.1) var gust_travel_speed := 4.0
## Max local deviation of the wind direction taken from the noise (degrees).
@export_range(0.0, 90.0, 1.0) var local_direction_variation_deg := 25.0
## Seamless noise map used for the spatial variation (edit its FastNoiseLite for other looks).
@export var noise_texture: Texture2D = preload("res://scenes/environment/wind/wind_noise.tres")

@export_group("Gusts")
## Extra strength added at the peak of a gust (multiplier of `strength`).
@export_range(0.0, 3.0, 0.05) var gust_strength := 0.8
## How often gusts come (Hz-ish). 0.1 = a slow swell every ~10 s, 0.5 = choppy.
@export_range(0.0, 2.0, 0.01) var gust_frequency := 0.15
## Slow wandering of the direction (degrees of max deviation).
@export_range(0.0, 90.0, 1.0) var direction_wander_deg := 15.0

@export_group("Audio")
@export var audio_enabled := true
@export var audio_stream: AudioStream = preload("res://assets/audio/wind.mp3")
## Volume at full strength (1.0). Keep it low: ambience, not a storm.
@export_range(-60.0, 6.0, 0.5) var audio_volume_db := -18.0
## Volume in dead calm (strength 0). -60 = silent.
@export_range(-80.0, 0.0, 0.5) var audio_calm_volume_db := -40.0
## Strength at which the loop reaches audio_volume_db.
@export_range(0.1, 3.0, 0.05) var audio_full_strength := 1.2
## Slow random pitch drift (±fraction) so the loop never sounds identical.
@export_range(0.0, 0.3, 0.01) var audio_pitch_variation := 0.06
## How fast the volume follows the gusts (higher = snappier).
@export_range(0.1, 20.0, 0.1) var audio_volume_smoothing := 1.5
@export var audio_bus: StringName = &"Master"

const GLOBALS := ["wind_direction", "wind_strength", "wind_speed", "wind_turbulence",
	"wind_noise", "wind_noise_scale", "wind_noise_influence", "wind_noise_scroll", "wind_noise_dir_var"]

var _noise := FastNoiseLite.new()
var _time := 0.0
var _globals_ok := false
var _audio: AudioStreamPlayer
var _audio_volume := -80.0
## Current effective strength (steady + gust), read-only, for debugging/UI.
var current_strength := 0.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 1337
	# Shader globals are registered from project.godot at startup. If they were added
	# while the editor was open, the editor won't have them until it is restarted.
	_globals_ok = true
	for name in GLOBALS:
		if not ProjectSettings.has_setting("shader_globals/" + name):
			_globals_ok = false
	if not _globals_ok:
		push_warning("Wind: shader globals 'wind_*' missing from project.godot [shader_globals]; wind disabled.")
		set_process(false)
		return
	if Engine.is_editor_hint() and not RenderingServer.global_shader_parameter_get_list().has(&"wind_strength"):
		push_warning("Wind: the editor hasn't loaded the 'wind_*' shader globals yet. Restart the editor (Project > Reload Current Project).")
		set_process(false)
		return
	_setup_audio()
	_apply()


func _process(delta: float) -> void:
	_time += delta
	_apply()
	_update_audio(delta)


const DEFAULT_AUDIO := preload("res://assets/audio/wind.mp3")


func _setup_audio() -> void:
	if audio_stream == null:
		audio_stream = DEFAULT_AUDIO  # guard against a null override saved in a scene
	if Engine.is_editor_hint() or not audio_enabled or audio_stream == null:
		return
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"World"
	_audio.name = "Ambience"
	_audio.stream = audio_stream
	_audio.bus = audio_bus
	_audio.volume_db = audio_calm_volume_db
	_audio_volume = audio_calm_volume_db
	add_child(_audio)
	# Start at a random point so two launches don't sound the same.
	_audio.play(randf() * maxf(audio_stream.get_length() - 1.0, 0.0))
	# Safety net if the import isn't set to loop.
	_audio.finished.connect(func() -> void: _audio.play())


## Volume follows the effective strength (gusts included) and pitch drifts slowly.
func _update_audio(delta: float) -> void:
	if _audio == null:
		return
	var target_db := audio_calm_volume_db
	if enabled:
		var t := clampf(current_strength / audio_full_strength, 0.0, 1.0)
		target_db = lerpf(audio_calm_volume_db, audio_volume_db, sqrt(t))
	_audio_volume = lerpf(_audio_volume, target_db, 1.0 - exp(-audio_volume_smoothing * delta))
	_audio.volume_db = _audio_volume
	var drift := _noise.get_noise_1d(_time * 0.15 + 900.0)  # -1..1, very slow
	_audio.pitch_scale = 1.0 + drift * audio_pitch_variation


func _exit_tree() -> void:
	# Release the texture global so the noise texture isn't reported as leaked at exit.
	if _globals_ok:
		RenderingServer.global_shader_parameter_set("wind_noise", null)


func _apply() -> void:
	if not enabled:
		_set_globals(Vector2.RIGHT, 0.0)
		return
	# noise in [-1, 1] -> gust envelope in [0, 1]
	var gust := (_noise.get_noise_1d(_time * gust_frequency * 10.0) + 1.0) * 0.5
	current_strength = strength * (1.0 + gust * gust_strength)
	var wander := _noise.get_noise_1d(_time * 0.3 + 500.0) * direction_wander_deg
	var dir := Vector2.from_angle(deg_to_rad(direction_deg + wander))
	_set_globals(dir, current_strength)


func _set_globals(dir: Vector2, strength_value: float) -> void:
	var rs := RenderingServer
	rs.global_shader_parameter_set("wind_direction", dir)
	rs.global_shader_parameter_set("wind_strength", strength_value)
	rs.global_shader_parameter_set("wind_speed", speed)
	rs.global_shader_parameter_set("wind_turbulence", turbulence)
	rs.global_shader_parameter_set("wind_noise", noise_texture)
	rs.global_shader_parameter_set("wind_noise_scale", gust_size_m)
	rs.global_shader_parameter_set("wind_noise_influence", spatial_variation if enabled else 0.0)
	rs.global_shader_parameter_set("wind_noise_scroll", gust_travel_speed)
	rs.global_shader_parameter_set("wind_noise_dir_var", deg_to_rad(local_direction_variation_deg))
