@tool
class_name HayBale
extends Node3D
## Fardo de heno instanciable. Sustituye el material plano del import por el shader de
## paja procedural (heno_straw.gdshader); la colision viene del import (-col).

@export_group("Straw")
@export var straw_light := Color(0.7529412, 0.75686276, 0.53333336):
	set(v):
		straw_light = v
		_set_param("straw_light", v)
@export var straw_dark := Color(0.5254902, 0.3882353, 0.3137255):
	set(v):
		straw_dark = v
		_set_param("straw_dark", v)
@export var straw_green := Color(0.627451, 0.59607846, 0.47058824):
	set(v):
		straw_green = v
		_set_param("straw_green", v)
@export_range(0.0, 1.0, 0.05) var green_amount := 0.3:
	set(v):
		green_amount = v
		_set_param("green_amount", v)
## Hebras por unidad de objeto a lo ancho.
@export_range(2.0, 40.0, 1.0) var strand_density := 5.0:
	set(v):
		strand_density = v
		_set_param("strand_density", v)
@export_range(1.0, 20.0, 0.5) var strand_stretch := 7.0:
	set(v):
		strand_stretch = v
		_set_param("strand_stretch", v)
@export_range(0.0, 1.0, 0.05) var strand_contrast := 0.75:
	set(v):
		strand_contrast = v
		_set_param("strand_contrast", v)

@export_group("Twine")
@export var twine_enabled := true:
	set(v):
		twine_enabled = v
		_set_param("twine_enabled", v)
@export var twine_color := Color(0.10980392, 0.0627451, 0.03529412):
	set(v):
		twine_color = v
		_set_param("twine_color", v)
@export_range(0.0, 1.0, 0.05) var twine_offset := 0.65:
	set(v):
		twine_offset = v
		_set_param("twine_offset", v)
@export_range(0.005, 0.1, 0.005) var twine_width := 0.065:
	set(v):
		twine_width = v
		_set_param("twine_width", v)

@export_group("Retro")
@export_range(1.0, 32.0, 1.0) var texels_per_unit := 8.0:
	set(v):
		texels_per_unit = v
		_set_param("texels_per_unit", v)
@export_range(0, 16) var levels := 6:
	set(v):
		levels = v
		_set_param("levels", v)
## Variacion aleatoria del patron entre fardos (semilla por posicion si es 0).
@export var seed := 0

const STRAW_SHADER := preload("res://scenes/props/heno/shaders/heno_straw.gdshader")

var _mats: Array[ShaderMaterial] = []


func _ready() -> void:
	_apply_materials.call_deferred()


func _set_param(pname: String, value: Variant) -> void:
	for m in _mats:
		m.set_shader_parameter(pname, value)


func _apply_materials() -> void:
	var model := get_node_or_null("Model")
	if model == null:
		push_warning("HayBale: falta el hijo 'Model' (instancia de heno.glb).")
		return
	_mats.clear()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = mi.get_aabb()
		for i in mi.get_surface_override_material_count():
			var sm := ShaderMaterial.new()
			sm.shader = STRAW_SHADER
			for p in ["straw_light", "straw_dark", "straw_green", "green_amount", "strand_density",
					"strand_stretch", "strand_contrast", "twine_enabled", "twine_color",
					"twine_offset", "twine_width", "texels_per_unit", "levels"]:
				sm.set_shader_parameter(p, get(p))
			sm.set_shader_parameter("half_length", aabb.size.x * 0.5)
			var s := seed if seed != 0 else hash(global_position.snapped(Vector3.ONE * 0.01))
			sm.set_shader_parameter("seed_offset", float(s % 1000))
			mi.set_surface_override_material(i, sm)
			_mats.append(sm)
