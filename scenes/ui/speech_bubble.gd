class_name SpeechBubble
extends Control
## Bocadillo de dialogo estilo A Short Hike: globo redondeado con rabito anclado sobre
## un punto 3D, texto que aparece letra a letra con ondulacion, y flecha parpadeante
## cuando la linea ha terminado. Vive en RetroRenderer.hud_layer (encima del post).
##
## Uso: bubble.say("texto")  -> escribe; bubble.is_typing() / bubble.complete()
##      bubble.close()       -> se encoge y se oculta
##      bubble.anchor = posicion mundo (cabeza del NPC), se reposiciona cada frame.

signal line_finished

@export var max_width := 150.0
@export_range(6, 32, 1) var font_size := 9
@export var font: Font
@export var text_color := Color(0.12, 0.1, 0.1)
@export var background_color := Color(1.0, 0.98, 0.94)
@export var border_color := Color(0.12, 0.1, 0.1)
@export_range(0.0, 4.0, 1.0) var border_width := 1.0
@export var corner_radius := 6
@export var padding := Vector2(8.0, 5.0)
## Rabito hacia el ancla (pixeles).
@export var tail_size := Vector2(8.0, 6.0)
## Separacion entre el ancla (cabeza) y la punta del rabito.
@export var gap_above_anchor := 4.0
## Letras por segundo.
@export var chars_per_second := 32.0
## Palabras clave: en el texto se marcan entre asteriscos (*asi*) y salen ondulando y en
## color; el resto del texto queda quieto. El BBCode normal tambien pasa tal cual.
@export var keyword_color := Color(0.85, 0.42, 0.12)
@export var wave_amplitude := 12.0
@export var wave_frequency := 4.0
@export var bob_pixels := 1.0
@export var bob_speed := 2.5
## Voz "animalese" (Animal Crossing): una silaba corta por letra, elegida y afinada segun
## la letra, con el tono base del personaje. Vacio = mudo.
@export var voice_streams: Array[AudioStream] = [
	preload("res://assets/audio/voice/animalese_a.wav"),
	preload("res://assets/audio/voice/animalese_e.wav"),
	preload("res://assets/audio/voice/animalese_i.wav"),
	preload("res://assets/audio/voice/animalese_o.wav"),
	preload("res://assets/audio/voice/animalese_u.wav"),
]
@export_range(-40.0, 6.0, 0.5) var voice_volume_db := -18.0
## Tono base de la voz (1 = medio; >1 agudo/pequeno, <1 grave/grande).
@export_range(0.5, 2.0, 0.01) var voice_pitch := 1.0
## Cuanto varia el tono entre letras distintas (0 = monotono).
@export_range(0.0, 0.6, 0.01) var voice_letter_variation := 0.22
## Minimo de segundos entre silabas (evita que a mucha velocidad se amontonen).
@export var voice_min_interval := 0.045

var anchor := Vector3.ZERO
## Camara del mundo (el bocadillo vive en el HUD, en otro viewport): la fija el NPC.
var camera: Camera3D

var _panel: PanelContainer
var _label: RichTextLabel
var _chars := 0.0
var _typing := false
var _finished_emitted := false
var _t := 0.0
var _tween: Tween
var _voice: AudioStreamPlayer
var _since_voice := 1.0
var _shouting := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = background_color
	sb.border_color = border_color
	sb.set_border_width_all(int(border_width))
	sb.set_corner_radius_all(corner_radius)
	sb.content_margin_left = padding.x
	sb.content_margin_right = padding.x
	sb.content_margin_top = padding.y
	sb.content_margin_bottom = padding.y
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(max_width, 0)
	_label.add_theme_color_override("default_color", text_color)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		_label.add_theme_font_size_override(k, font_size)
	if font:
		for k in ["normal_font", "bold_font", "italics_font", "bold_italics_font"]:
			_label.add_theme_font_override(k, font)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	if not voice_streams.is_empty():
		_voice = AudioStreamPlayer.new()
		_voice.volume_db = voice_volume_db
		_voice.max_polyphony = 3
		add_child(_voice)
	scale = Vector2.ZERO
	visible = false


## Color y tamano extra del texto cuando la linea es un grito.
@export var shout_color := Color("823f3a")
@export var shout_font_size_add := 3

## `shout` = linea gritada: mas grande, en rojo, escrita mas rapido y con la voz mas grave.
func say(text: String, shout := false) -> void:
	var body := _markup(text)
	if shout:
		body = "[color=#%s][font_size=%d]%s[/font_size][/color]" % [shout_color.to_html(false), font_size + shout_font_size_add, body]
	_shouting = shout
	_label.text = body
	_chars = 0.0
	_label.visible_characters = 0
	_typing = true
	_finished_emitted = false
	_since_voice = 1.0
	_fit()
	# Si habia un cierre en curso, cancelarlo: su callback ocultaria este bocadillo nuevo.
	if _tween:
		_tween.kill()
	visible = true
	if scale != Vector2.ONE:
		_pop(Vector2.ONE)


## *palabra clave* -> [color][wave]palabra clave[/wave][/color]
func _markup(text: String) -> String:
	var out := ""
	var parts := text.split("*")
	for i in parts.size():
		if i % 2 == 1 and i < parts.size() - 1:
			out += "[color=#%s][wave amp=%.1f freq=%.1f connected=1]%s[/wave][/color]" % [
					keyword_color.to_html(false), wave_amplitude, wave_frequency, parts[i]]
		else:
			out += parts[i] if i % 2 == 0 else "*" + parts[i]  # asterisco sin cerrar: literal
	return out


func is_typing() -> bool:
	return _typing


## Muestra la linea entera de golpe.
func complete() -> void:
	if _typing:
		_label.visible_characters = -1
		_typing = false
		_emit_finished()


func close() -> void:
	_typing = false
	_pop(Vector2.ZERO, true)


func _fit() -> void:
	# Ancho al contenido (hasta max_width), alto segun el texto envuelto.
	var f := _label.get_theme_font("normal_font")
	var text_w: float = f.get_string_size(_label.get_parsed_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_label.custom_minimum_size.x = minf(text_w + 2.0, max_width)
	_panel.reset_size()
	await get_tree().process_frame
	size = _panel.size
	pivot_offset = Vector2(size.x * 0.5, size.y + tail_size.y)  # crece desde el rabito


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_since_voice += delta
	if _typing:
		_chars += chars_per_second * (1.8 if _shouting else 1.0) * delta
		var total := _label.get_total_character_count()
		var shown := mini(int(_chars), total)
		if shown != _label.visible_characters:
			var parsed := _label.get_parsed_text()
			for i in range(_label.visible_characters, shown):
				if i < parsed.length():
					_speak_letter(parsed[i])
			_label.visible_characters = shown
		if shown >= total:
			_typing = false
			_emit_finished()
	_reposition()
	queue_redraw()


## Una silaba por letra: la vocal la decide la letra (vocales -> la suya, consonantes ->
## una fija por letra), el tono sube/baja segun la letra y un pelin de azar.
func _speak_letter(ch: String) -> void:
	if _voice == null or _since_voice < voice_min_interval:
		return
	var c := ch.to_lower()
	if c.is_empty() or not (c.unicode_at(0) >= 97 and c.unicode_at(0) <= 122 or c in "áéíóúñ"):
		return  # espacios, puntuacion y numeros: silencio
	var code := c.unicode_at(0)
	var idx := "aeiou".find(c)
	if idx < 0:
		idx = code % voice_streams.size()
	else:
		idx = mini(idx, voice_streams.size() - 1)
	_since_voice = 0.0
	_voice.stream = voice_streams[idx]
	var letter_t := float(code % 26) / 25.0  # 0..1 estable por letra
	_voice.pitch_scale = voice_pitch * (0.78 if _shouting else 1.0) \
			* (1.0 + (letter_t - 0.5) * 2.0 * voice_letter_variation) * randf_range(0.97, 1.03)
	_voice.volume_db = voice_volume_db + (6.0 if _shouting else 0.0)
	_voice.play()


func _emit_finished() -> void:
	if not _finished_emitted:
		_finished_emitted = true
		line_finished.emit()


func _reposition() -> void:
	var cam := camera if is_instance_valid(camera) else get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.unproject_position(anchor)
	var bob := sin(_t * bob_speed) * bob_pixels
	global_position = (p - Vector2(size.x * 0.5, size.y + tail_size.y + gap_above_anchor) + Vector2(0.0, bob)).round()


func _draw() -> void:
	# Rabito bajo el centro del globo, apuntando al ancla.
	var base_y := size.y - border_width
	var cx := size.x * 0.5
	var tri := PackedVector2Array([
		Vector2(cx - tail_size.x * 0.5, base_y),
		Vector2(cx + tail_size.x * 0.5, base_y),
		Vector2(cx, base_y + tail_size.y),
	])
	draw_colored_polygon(tri, background_color)
	if border_width > 0.0:
		draw_line(tri[0] + Vector2(0, 0.5), tri[2], border_color, border_width)
		draw_line(tri[1] + Vector2(0, 0.5), tri[2], border_color, border_width)
	# Flecha "continuar" parpadeante cuando la linea ha terminado.
	if not _typing and _label.visible_characters != 0 and fmod(_t, 0.8) < 0.5:
		var ax := size.x - padding.x - 2.0
		var ay := size.y - padding.y * 0.5 - 1.0
		draw_colored_polygon(PackedVector2Array([Vector2(ax - 4, ay - 3), Vector2(ax, ay - 3), Vector2(ax - 2, ay)]), text_color)


func _pop(target: Vector2, hide_after := false) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(self, "scale", target, 0.22)
	if hide_after:
		_tween.tween_callback(func() -> void: visible = false)
