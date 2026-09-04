class_name FootstepAudio
extends Node
## Pasos sincronizados con el esqueleto, para cualquier personaje animado.
## Cada par de huesos (pie izq / pie der; patas delanteras / traseras...) dispara un paso
## cuando cambia el signo de (altura A - altura B): el pie que oscilaba acaba de aterrizar.
## Comparar los dos huesos del par anula el balanceo del cuerpo. Un bipedo usa un par; un
## cuadrupedo dos (delante y detras) y aproxima las cuatro pisadas del trote.
## Solo suena mientras el dueno dice que hay un clip de locomocion: llama a tick() cada
## frame de fisica.

@export var enabled := true
@export var stream: AudioStream = preload("res://assets/audio/step.wav")
## Pares de huesos. Cada par dispara sus propios pasos.
@export var bone_pairs: Array[PackedStringArray] = [PackedStringArray(["foot.l", "foot.r"])]
## true = AudioStreamPlayer3D posicionado en el personaje (NPCs, companeros);
## false = AudioStreamPlayer plano (el jugador, que siempre esta en el centro).
@export var spatial := false

@export_group("Sound")
## Volumen base. Bajo: los pasos se sienten, no se oyen.
@export_range(-40.0, 6.0, 0.5) var volume_db := -16.0
## Tono base (un perro pequeno patea mas agudo que unas botas).
@export_range(0.5, 2.0, 0.05) var pitch := 1.0
## Rango de tono aleatorio por paso (1.12 = +-12%).
@export_range(1.0, 2.0, 0.01) var random_pitch := 1.12
@export_range(0.0, 12.0, 0.5) var random_volume_db := 3.0
## Extra de volumen y multiplicador de tono al correr (pasos mas pesados).
@export_range(-12.0, 12.0, 0.5) var run_volume_boost_db := 3.0
@export_range(0.5, 1.5, 0.01) var run_pitch_mul := 0.95

@export_group("Timing")
## Pequeno retardo para que el sonido caiga en el punto mas bajo de la zancada.
@export_range(0.0, 0.2, 0.01) var delay := 0.04
## Minimo entre dos pasos (filtra el jitter de los blends; un trote cruza pares rapido).
@export_range(0.02, 0.5, 0.01) var min_interval := 0.15

var _skeleton: Skeleton3D
var _player: Node  # AudioStreamPlayer o AudioStreamPlayer3D
var _pairs: Array[PackedInt32Array] = []
var _signs: PackedInt32Array
var _since_last := INF


## Resuelve los huesos y crea el reproductor. Sin esqueleto o sin pares validos queda apagado.
func setup(skeleton: Skeleton3D) -> void:
	if not enabled or stream == null or skeleton == null:
		return
	for pair in bone_pairs:
		if pair.size() != 2:
			continue
		var a := skeleton.find_bone(pair[0])
		var b := skeleton.find_bone(pair[1])
		if a < 0 or b < 0:
			push_warning("%s: huesos %s no encontrados; ese par queda mudo." % [get_path(), pair])
			continue
		_pairs.append(PackedInt32Array([a, b]))
		_signs.append(0)
	if _pairs.is_empty():
		return
	_skeleton = skeleton
	var randomizer := AudioStreamRandomizer.new()
	randomizer.add_stream(0, stream)
	randomizer.random_pitch = random_pitch
	randomizer.random_volume_offset_db = random_volume_db
	_player = AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
	_player.name = "Audio"
	_player.stream = randomizer
	_player.max_polyphony = 4
	add_child(_player)


## `locomotion`: hay un clip de andar/correr sonando. `running`: es el de correr.
func tick(delta: float, locomotion: bool, running: bool) -> void:
	if _player == null:
		return
	_since_last += delta
	if not locomotion:
		_signs.fill(0)
		return
	for i in _pairs.size():
		var diff := _skeleton.get_bone_global_pose(_pairs[i][0]).origin.y \
				- _skeleton.get_bone_global_pose(_pairs[i][1]).origin.y
		var s := signi(int(sign(diff)))
		if s != 0 and _signs[i] != 0 and s != _signs[i] and _since_last >= min_interval:
			_since_last = 0.0
			if delay > 0.0:
				get_tree().create_timer(delay).timeout.connect(_play.bind(running))
			else:
				_play(running)
		if s != 0:
			_signs[i] = s


func _play(running: bool) -> void:
	if not is_instance_valid(_player):
		return
	_player.volume_db = volume_db + (run_volume_boost_db if running else 0.0)
	_player.pitch_scale = pitch * (run_pitch_mul if running else 1.0)
	_player.play()
