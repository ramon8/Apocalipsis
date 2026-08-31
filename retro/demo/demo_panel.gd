extends PanelContainer
## Panel de sliders generado automáticamente a partir de los @export de RetroProfile.
## Cualquier parámetro nuevo que añadas al perfil aparece aquí sin tocar este script.

const PRESETS := {
	"crisp": "res://retro/profiles/crisp.tres",
	"psx_crudo": "res://retro/profiles/psx_crudo.tres",
	"suave": "res://retro/profiles/suave.tres",
}
const PALETTES_DIR := "res://retro/palettes"
const CUSTOM_SAVE_PATH := "res://retro/profiles/custom.tres"

var _profile: RetroProfile
var _rows: VBoxContainer
var _preset_button: OptionButton


func _ready() -> void:
	_build_chrome()
	# Trabajamos sobre una copia: el .tres del preset no se modifica hasta que pulses Guardar.
	var active := RetroRenderer.profile as RetroProfile
	_select_preset_item(active.resource_path)
	_set_profile(active.duplicate(true))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_TAB:
		visible = not visible


func load_preset(path: String) -> void:
	var p := load(path) as RetroProfile
	if p:
		_select_preset_item(path)
		_set_profile(p.duplicate(true))


func _select_preset_item(path: String) -> void:
	var idx: int = PRESETS.values().find(path)
	if idx >= 0:
		_preset_button.select(idx)


# ------------------------------------------------------------------ UI build

func _build_chrome() -> void:
	var root := VBoxContainer.new()
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)

	var enabled := CheckBox.new()
	enabled.text = "retro_enabled"
	enabled.button_pressed = RetroRenderer.retro_enabled
	enabled.toggled.connect(func(v: bool) -> void: RetroRenderer.retro_enabled = v)
	top.add_child(enabled)

	_preset_button = OptionButton.new()
	for name in PRESETS:
		_preset_button.add_item(name)
	_preset_button.item_selected.connect(func(i: int) -> void: load_preset(PRESETS.values()[i]))
	top.add_child(_preset_button)

	var save := Button.new()
	save.text = "Guardar custom.tres"
	save.pressed.connect(_save_custom)
	top.add_child(save)

	var dump := Button.new()
	dump.text = "Imprimir"
	dump.pressed.connect(_print_values)
	top.add_child(dump)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)


func _set_profile(p: RetroProfile) -> void:
	_profile = p
	RetroRenderer.apply_profile(_profile)
	_rebuild_rows()


func _rebuild_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for prop in _profile.get_property_list():
		var usage: int = prop.usage
		if usage & PROPERTY_USAGE_GROUP:
			if prop.name == "Resource":
				continue
			var header := Label.new()
			header.text = "— %s" % prop.name
			header.modulate = Color(1.0, 0.85, 0.5)
			_rows.add_child(header)
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		var editor := _make_editor(prop)
		if editor == null:
			continue
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = prop.name
		label.custom_minimum_size.x = 130
		row.add_child(label)
		editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(editor)
		_rows.add_child(row)


func _make_editor(prop: Dictionary) -> Control:
	var name: String = prop.name
	var value = _profile.get(name)
	match prop.type:
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = value
			cb.toggled.connect(func(v: bool) -> void: _apply_value(name, v))
			return cb
		TYPE_FLOAT, TYPE_INT:
			if prop.hint == PROPERTY_HINT_ENUM:
				var ob := OptionButton.new()
				for entry in String(prop.hint_string).split(","):
					var parts := entry.split(":")
					ob.add_item(parts[0], int(parts[1]) if parts.size() > 1 else ob.item_count)
				ob.select(ob.get_item_index(int(value)))
				ob.item_selected.connect(func(i: int) -> void: _apply_value(name, ob.get_item_id(i)))
				return ob
			var range_parts := String(prop.hint_string).split(",")
			var box := HBoxContainer.new()
			var slider := HSlider.new()
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if prop.hint == PROPERTY_HINT_RANGE and range_parts.size() >= 2:
				slider.min_value = float(range_parts[0])
				slider.max_value = float(range_parts[1])
				slider.step = float(range_parts[2]) if range_parts.size() >= 3 else 0.01
			else:
				slider.min_value = 0.0
				slider.max_value = 100.0
				slider.step = 1.0 if prop.type == TYPE_INT else 0.01
			slider.value = value
			var readout := Label.new()
			readout.custom_minimum_size.x = 44
			readout.text = _fmt(value)
			slider.value_changed.connect(func(v: float) -> void:
				var typed = int(v) if prop.type == TYPE_INT else v
				readout.text = _fmt(typed)
				_apply_value(name, typed))
			box.add_child(slider)
			box.add_child(readout)
			return box
		TYPE_COLOR:
			var picker := ColorPickerButton.new()
			picker.color = value
			picker.edit_alpha = false
			picker.custom_minimum_size.x = 60
			picker.color_changed.connect(func(c: Color) -> void: _apply_value(name, c))
			return picker
		TYPE_VECTOR2I:
			var box := HBoxContainer.new()
			for axis in 2:
				var spin := SpinBox.new()
				spin.min_value = 16
				spin.max_value = 4096
				spin.value = value[axis]
				spin.value_changed.connect(func(v: float) -> void:
					var cur: Vector2i = _profile.get(name)
					cur[axis] = int(v)
					_apply_value(name, cur))
				box.add_child(spin)
			return box
		TYPE_OBJECT:
			if prop.hint_string == "Texture2D":
				var ob := OptionButton.new()
				var paths: Array[String] = []
				for f in DirAccess.get_files_at(PALETTES_DIR):
					if f.ends_with(".png"):
						paths.append(PALETTES_DIR.path_join(f))
						ob.add_item(f)
				var current: String = value.resource_path if value else ""
				for i in paths.size():
					if paths[i] == current:
						ob.select(i)
				ob.item_selected.connect(func(i: int) -> void: _apply_value(name, load(paths[i])))
				return ob
	return null


func _apply_value(prop: String, value) -> void:
	_profile.set(prop, value)
	RetroRenderer.apply_profile(_profile)


func _fmt(v) -> String:
	return str(v) if v is int else "%.3f" % v


func _save_custom() -> void:
	var copy := _profile.duplicate(true) as RetroProfile
	var err := ResourceSaver.save(copy, CUSTOM_SAVE_PATH)
	print("RetroProfile guardado en %s (%s)" % [CUSTOM_SAVE_PATH, error_string(err)])


func _print_values() -> void:
	print("--- RetroProfile ---")
	for prop in _profile.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_EDITOR:
			print("%s = %s" % [prop.name, _profile.get(prop.name)])
