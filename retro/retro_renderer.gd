extends Node
## Autoload "RetroRenderer" (escena res://retro/retro_renderer.tscn).
##
## Captura la escena actual del SceneTree y la mete en un SubViewport que renderiza
## a la resolución interna; un ColorRect a pantalla completa aplica retro_post.gdshader
## sobre esa textura (un único pase). Con `retro_enabled = false` devuelve la escena
## al root, oculta el post, desactiva el SubViewport y restaura el escalado de
## ventana estándar: render normal, sin artefactos.
##
## Por qué autoload y no escena raíz: el juego no necesita saber que existe, funciona
## con F5/F6 sobre cualquier escena, se puede alternar en runtime y sobrevive a
## change_scene_to_*() (captura la nueva current_scene cuando entra en el root).

signal profile_applied(profile: RetroProfile)

# Uniforms globales que escribe este nodo. Deben existir en project.godot [shader_globals]
# (los shaders que los declaran no compilan si faltan): retro_internal_resolution (vec2),
# retro_snap_strength, retro_affine_strength, retro_fog_density (float),
# retro_fog_enabled (bool), retro_fog_color (color).

## Flag global: true = pipeline retro, false = render estándar.
@export var retro_enabled := true:
	set = set_retro_enabled
## Preset activo. Se aplica en _ready y cada vez que llamas a apply_profile().
@export var profile: RetroProfile
## Escalado por enteros al subir a la ventana (evita píxeles desiguales; deja bandas negras).
@export var integer_scaling := true
## Modo de escalado de ventana al desactivar el pipeline.
@export var standard_scale_mode: Window.ContentScaleMode = Window.CONTENT_SCALE_MODE_DISABLED
## Acción que muestra/oculta el panel de tuneo sobre el juego (F1). Vacío = desactivado.
@export var tuning_panel_action: StringName = &"retro_tuning"
## Acción que alterna ventana / pantalla completa (P). Vacío = desactivado.
@export var fullscreen_action: StringName = &"toggle_fullscreen"

const TUNING_PANEL_SCRIPT := preload("res://retro/demo/demo_panel.gd")

## CanvasLayer drawn ABOVE the post pass (no vignette / dither / quantize), still at the
## internal resolution. Put HUD elements here: `RetroRenderer.hud_layer.add_child(ctrl)`.
var hud_layer: CanvasLayer:
	get:
		if _hud_layer == null:
			_hud_layer = CanvasLayer.new()
			_hud_layer.name = "HudLayer"
			_hud_layer.layer = 50
			add_child(_hud_layer)
		return _hud_layer
var _hud_layer: CanvasLayer
var _tuning_layer: CanvasLayer
var _tuning_panel: PanelContainer
var _mouse_mode_before_panel := Input.MOUSE_MODE_VISIBLE

@onready var game_viewport: SubViewport = $GameViewport
@onready var post: ColorRect = $Post

var _post_material: ShaderMaterial
var _captured_scene: Node
var _original_scale_size: Vector2i
var _original_scale_aspect: Window.ContentScaleAspect


func _ready() -> void:
	# Un SubViewport no escucha audio 3D por defecto; el juego vive aqui dentro.
	game_viewport.audio_listener_enable_3d = true
	_post_material = post.material as ShaderMaterial
	_post_material.set_shader_parameter("screen_tex", game_viewport.get_texture())
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var root := get_tree().root
	_original_scale_size = root.content_scale_size
	_original_scale_aspect = root.content_scale_aspect
	root.child_entered_tree.connect(_on_root_child_entered)
	root.mouse_exited.connect(_on_window_mouse_exited)

	if profile == null:
		profile = RetroProfile.new()
	_update_mode()


## Aplica un perfil (por defecto el activo). Se puede llamar en cada cambio de slider.
func apply_profile(p: RetroProfile = null) -> void:
	if p != null:
		profile = p
	if not is_node_ready():
		return
	var res := profile.get_internal_resolution()
	game_viewport.size = res
	if retro_enabled:
		get_tree().root.content_scale_size = res

	var m := _post_material
	m.set_shader_parameter("internal_resolution", Vector2(res))
	m.set_shader_parameter("pixel_size", profile.pixel_size)
	m.set_shader_parameter("dither_enabled", profile.dither_enabled)
	m.set_shader_parameter("dither_strength", profile.dither_strength)
	m.set_shader_parameter("dither_space", int(profile.dither_space))
	m.set_shader_parameter("dither_spread", profile.dither_spread)
	m.set_shader_parameter("quantize_enabled", profile.quantize_enabled)
	m.set_shader_parameter("quantize_mode", int(profile.quantize_mode))
	m.set_shader_parameter("quantize_strength", profile.quantize_strength)
	m.set_shader_parameter("color_levels", profile.color_levels)
	m.set_shader_parameter("palette_tex", profile.palette)
	m.set_shader_parameter("palette_size", profile.get_palette_size())
	m.set_shader_parameter("grain_enabled", profile.grain_enabled)
	m.set_shader_parameter("grain_strength", profile.grain_strength)
	m.set_shader_parameter("grain_speed", profile.grain_speed)
	m.set_shader_parameter("vignette_enabled", profile.vignette_enabled)
	m.set_shader_parameter("vignette_strength", profile.vignette_strength)
	m.set_shader_parameter("vignette_radius", profile.vignette_radius)
	m.set_shader_parameter("vignette_softness", profile.vignette_softness)

	_apply_psx_globals(retro_enabled)
	profile_applied.emit(profile)


## Desplaza el patrón de dither en píxeles internos (p.ej. para anclarlo a una cámara 2D/orto).
func set_dither_offset(offset: Vector2) -> void:
	_post_material.set_shader_parameter("dither_offset", offset)


func set_retro_enabled(value: bool) -> void:
	if retro_enabled == value:
		return
	retro_enabled = value
	if is_node_ready():
		_update_mode()


func get_internal_resolution() -> Vector2i:
	return profile.get_internal_resolution()


## Escena de juego actual, esté capturada en el SubViewport o en el root.
var current_scene: Node:
	get:
		return _captured_scene if is_instance_valid(_captured_scene) else get_tree().current_scene


## Sustituto de get_tree().reload_current_scene() (que falla mientras retro está activo).
func reload_current_scene() -> Error:
	var scene := current_scene
	if scene == null or scene.scene_file_path.is_empty():
		return ERR_UNCONFIGURED
	return get_tree().change_scene_to_file(scene.scene_file_path)


# ------------------------------------------------------------------ internals

func _update_mode() -> void:
	var root := get_tree().root
	if retro_enabled:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_stretch = (Window.CONTENT_SCALE_STRETCH_INTEGER if integer_scaling
				else Window.CONTENT_SCALE_STRETCH_FRACTIONAL)
		game_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		post.visible = true
		apply_profile()
		# Diferido: en _ready el root puede estar aún añadiendo la escena principal.
		_capture_scene.call_deferred(get_tree().current_scene)
	else:
		_release_scene()
		post.visible = false
		game_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.content_scale_mode = standard_scale_mode
		root.content_scale_aspect = _original_scale_aspect
		root.content_scale_size = _original_scale_size
		_apply_psx_globals(false)


func _apply_psx_globals(enabled: bool) -> void:
	var rs := RenderingServer
	rs.global_shader_parameter_set("retro_internal_resolution", Vector2(profile.get_internal_resolution()))
	rs.global_shader_parameter_set("retro_snap_strength", profile.vertex_snap_strength if enabled else 0.0)
	rs.global_shader_parameter_set("retro_affine_strength", profile.affine_strength if enabled else 0.0)
	rs.global_shader_parameter_set("retro_fog_enabled", profile.fog_enabled and enabled)
	rs.global_shader_parameter_set("retro_fog_color", profile.fog_color)
	rs.global_shader_parameter_set("retro_fog_density", profile.fog_density)


func _on_root_child_entered(node: Node) -> void:
	# current_scene se asigna justo después de add_child: comprobar en diferido.
	_try_capture.call_deferred(node)


func _try_capture(node: Node) -> void:
	if retro_enabled and is_instance_valid(node) and node == get_tree().current_scene:
		_capture_scene(node)


func _capture_scene(scene: Node) -> void:
	if not retro_enabled or scene == null or not is_instance_valid(scene):
		return
	if scene == _captured_scene or scene == self or scene.get_parent() != get_tree().root:
		return
	if is_instance_valid(_captured_scene) and _captured_scene != scene:
		# Ha entrado una escena nueva por change_scene_to_*(): el SceneTree no ha podido
		# liberar la anterior (para él current_scene era null), lo hacemos nosotros.
		_captured_scene.queue_free()
	_captured_scene = null
	scene.reparent(game_viewport, false)
	# LIMITACIÓN: SceneTree.current_scene sólo admite hijos del root, así que mientras
	# retro está activo get_tree().current_scene es null. change_scene_to_*() funciona
	# (ver arriba); para leer la escena o recargarla usa RetroRenderer.current_scene /
	# RetroRenderer.reload_current_scene().
	_captured_scene = scene
	scene.tree_exited.connect(_on_captured_scene_exited, CONNECT_ONE_SHOT)


func _release_scene() -> void:
	if _captured_scene == null or not is_instance_valid(_captured_scene):
		_captured_scene = null
		return
	if _captured_scene.tree_exited.is_connected(_on_captured_scene_exited):
		_captured_scene.tree_exited.disconnect(_on_captured_scene_exited)
	if _captured_scene.get_parent() == game_viewport:
		var scene := _captured_scene
		scene.reparent(get_tree().root, false)
		get_tree().current_scene = scene
	_captured_scene = null


func _on_captured_scene_exited() -> void:
	_captured_scene = null


## El SubViewport no cuelga de un SubViewportContainer, así que le reenviamos el input.
## Root y SubViewport tienen el mismo tamaño (resolución interna): coordenadas 1:1.
## También hay que avisarle de que el ratón está "dentro" (lo que haría un
## SubViewportContainer): sin ese aviso su GUI descarta el movimiento del ratón sin
## botón pulsado (hover, cámaras que siguen al ratón...).
var _mouse_inside_viewport := false


func _input(event: InputEvent) -> void:
	if not tuning_panel_action.is_empty() and event.is_action_pressed(tuning_panel_action):
		toggle_tuning_panel()
		get_viewport().set_input_as_handled()
		return
	if not fullscreen_action.is_empty() and event.is_action_pressed(fullscreen_action):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	# While the panel is open the game gets no input (so the camera doesn't spin under the mouse).
	if _tuning_panel and _tuning_panel.visible:
		return
	if retro_enabled and _captured_scene != null:
		if event is InputEventMouse and not _mouse_inside_viewport:
			_mouse_inside_viewport = true
			game_viewport.notification(NOTIFICATION_VP_MOUSE_ENTER)
		game_viewport.push_input(event)


## Alterna entre ventana y pantalla completa (sin bordes, sin cambiar la resolución del
## monitor). El escalado del pipeline se adapta solo (integer_scaling deja bandas si no cuadra).
func toggle_fullscreen() -> void:
	var win := get_tree().root
	if win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		win.mode = Window.MODE_WINDOWED
	else:
		win.mode = Window.MODE_FULLSCREEN
		# An embedded game window (editor "Embed Game" mode) ignores mode changes.
		await get_tree().process_frame
		if win.mode != Window.MODE_FULLSCREEN:
			push_warning("Fullscreen not applied. If you run from the editor, disable 'Embed Game' "
					+ "in the Game panel toolbar (or Editor Settings > Run > Window Placement > Game Embed Mode).")


## Panel de sliders (el de demo.tscn) sobre la escena actual, para tunear con el juego real.
func toggle_tuning_panel() -> void:
	if _tuning_panel == null:
		_tuning_layer = CanvasLayer.new()
		_tuning_layer.name = "TuningLayer"
		_tuning_layer.layer = 100
		_tuning_panel = PanelContainer.new()
		_tuning_panel.name = "TuningPanel"
		_tuning_panel.position = Vector2(6, 6)
		var theme := Theme.new()
		theme.default_font_size = 10
		_tuning_panel.theme = theme
		_tuning_panel.set_script(TUNING_PANEL_SCRIPT)
		_tuning_layer.add_child(_tuning_panel)
		add_child(_tuning_layer)
		_mouse_mode_before_panel = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	_tuning_panel.visible = not _tuning_panel.visible
	if _tuning_panel.visible:
		_mouse_mode_before_panel = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = _mouse_mode_before_panel


func _on_window_mouse_exited() -> void:
	if _mouse_inside_viewport:
		_mouse_inside_viewport = false
		game_viewport.notification(NOTIFICATION_VP_MOUSE_EXIT)
