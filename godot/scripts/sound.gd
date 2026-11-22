extends Node

const SAMPLE_RATE: int = 22050
const BEAT: float = 0.625
const LOOP_SECONDS: float = BEAT * 16.0
const VOICE_COUNT: int = 8
const MUSIC_GAIN: float = 0.30
const EFFECT_GAIN: float = 0.58
const CUE_LENGTHS: Dictionary = {
	"jump": 0.24, "air_jump": 0.36, "shift": 0.58, "shift_down": 0.58,
	"deny": 0.25, "land": 0.20, "shard": 0.64, "checkpoint": 1.10,
	"gate": 0.86, "death": 0.72, "win": 1.90,
}
const PRIORITIES: Dictionary = {
	"land": 0, "deny": 1, "jump": 2, "air_jump": 2, "shift": 2,
	"shard": 3, "gate": 3, "checkpoint": 4, "death": 5, "win": 6,
}

var _model: Node
var _initialized: bool = false
var _music: Array[AudioStreamPlayer] = []
var _voices: Array[AudioStreamPlayer] = []
var _voice_priority: Array[int] = []
var _voice_order: Array[int] = []
var _cues: Dictionary = {}
var _order: int = 0
var _fade: float = 0.0
var _pause_gain: float = 1.0
var _was_muted: bool = false


func _init() -> void:
	set_process(false)


func setup(model: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _initialized or not is_instance_valid(model) or not model.has_signal("effect"):
		return
	_model = model
	process_mode = Node.PROCESS_MODE_ALWAYS
	for world in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "SOL" if world == 0 else "LUN"
		player.stream = _make_music(world)
		player.volume_linear = 0.0
		add_child(player)
		_music.append(player)
	for kind in CUE_LENGTHS:
		_cues[kind] = _make_cue(str(kind), float(CUE_LENGTHS[kind]))
	for index in range(VOICE_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "Cue%d" % index
		player.volume_linear = 0.0
		add_child(player)
		_voices.append(player)
		_voice_priority.append(0)
		_voice_order.append(0)
	_pause_gain = 0.22 if _is_paused() else 1.0
	_was_muted = bool(_model.get("muted"))
	_initialized = true
	_model.connect("effect", _on_effect)
	for player in _music:
		player.play()
	set_process(true)


func _process(delta: float) -> void:
	if not is_instance_valid(_model):
		for player in _music:
			player.stop()
		for player in _voices:
			player.stop()
		set_process(false)
		return
	var muted: bool = bool(_model.get("muted"))
	if muted and not _was_muted:
		for player in _voices:
			player.stop()
	if _was_muted and not muted:
		_fade = 0.0
	_was_muted = muted
	_fade = minf(1.0, _fade + delta / 1.2)
	var target: float = 0.22 if _is_paused() else 1.0
	_pause_gain = lerpf(_pause_gain, target, 1.0 - exp(-delta * 9.0))
	var mix: float = clampf(float(_model.get("phase_mix")), 0.0, 1.0)
	var master: float = 0.0 if muted else _pause_gain
	_music[0].volume_linear = MUSIC_GAIN * master * _fade * sqrt(1.0 - mix)
	_music[1].volume_linear = MUSIC_GAIN * master * _fade * sqrt(mix)
	for player in _voices:
		player.volume_linear = EFFECT_GAIN * master


func _exit_tree() -> void:
	for player in _music + _voices:
		player.stop()
		player.stream = null
	_music.clear()
	_voices.clear()
	_cues.clear()


func _is_paused() -> bool:
	return str(_model.get("state")) == "pause" or (is_inside_tree() and get_tree().paused)


func _on_effect(kind: String, _at: Vector2) -> void:
	if not _initialized or not is_instance_valid(_model):
		return
	if bool(_model.get("muted")) or _is_paused():
		return
	var key: String = kind
	if kind == "shift" and int(_model.get("world")) == 1:
		key = "shift_down"
	if not _cues.has(key):
		return
	var priority: int = int(PRIORITIES.get(kind, 2))
	var slot: int = _find_voice(priority)
	if slot < 0:
		return
	var player: AudioStreamPlayer = _voices[slot]
	player.stop()
	player.stream = _cues[key]
	player.volume_linear = EFFECT_GAIN * _pause_gain
	_order += 1
	_voice_order[slot] = _order
	_voice_priority[slot] = priority
	player.play()


func _find_voice(priority: int) -> int:
	var candidate: int = -1
	for index in range(_voices.size()):
		if not _voices[index].playing:
			return index
		if _voice_priority[index] > priority:
			continue
		if candidate < 0:
			candidate = index
		elif _voice_priority[index] < _voice_priority[candidate]:
			candidate = index
		elif _voice_priority[index] == _voice_priority[candidate]:
			if _voice_order[index] < _voice_order[candidate]:
				candidate = index
	return candidate


func _make_music(world: int) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(roundi(LOOP_SECONDS * SAMPLE_RATE) * 2)
	var chords: Array = [
		[62, 66, 69], [59, 62, 67], [59, 62, 66], [57, 61, 64],
	]
	var roots: Array[int] = [38, 43, 47, 45]
	var melody: Array[int] = [74, 78, 76, 73, 71, 74, 73, 69]
	if world == 1:
		chords = [[62, 65, 69], [58, 62, 65], [58, 62, 67], [57, 60, 64]]
		roots = [38, 46, 43, 45]
		melody = [74, 77, 76, 72, 70, 74, 72, 69]
	for bar in range(4):
		var start: float = float(bar) * BEAT * 4.0
		for note in range(3):
			var pan: float = float(note - 1) * 0.48
			_mix_tone(samples, start, BEAT * 4.8, _hz(int(chords[bar][note])),
				0.065, 0, pan, -1.0, 0.30, 0.85, true)
		_mix_tone(samples, start, BEAT * 3.8, _hz(roots[bar]),
			0.10, 2, 0.0, -1.0, 0.12, 0.70, true)
	var beats: Array[float] = [0.0, 1.5, 4.0, 6.5, 8.0, 9.5, 12.0, 14.0]
	for note in range(melody.size()):
		var start: float = beats[note] * BEAT
		var pan: float = -0.23 if note % 2 == 0 else 0.23
		var frequency: float = _hz(melody[note])
		_mix_tone(samples, start, BEAT * 2.4, frequency,
			0.12, 1 if world == 1 else 0, pan, -1.0, 0.018, 0.72, true)
		_mix_tone(samples, start + BEAT * 0.75, BEAT * 1.9, frequency,
			0.027, 1, -pan, -1.0, 0.08, 0.65, true)
		_mix_tone(samples, start + BEAT * 1.5, BEAT * 1.7, frequency,
			0.012, 1, pan, -1.0, 0.09, 0.65, true)
	return _to_wav(samples, true)


func _make_cue(kind: String, seconds: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(ceili(seconds * SAMPLE_RATE) * 2)
	match kind:
		"jump":
			_mix_tone(samples, 0.0, 0.22, 235.0, 0.27, 0, 0.0, 470.0, 0.008, 0.13)
		"air_jump":
			_mix_tone(samples, 0.0, 0.21, 440.0, 0.21, 1, -0.18, 880.0, 0.008, 0.15)
			_mix_tone(samples, 0.075, 0.27, 660.0, 0.14, 1, 0.18, 1320.0, 0.01, 0.20)
		"shift", "shift_down":
			var down: bool = kind == "shift_down"
			var from: float = 587.33 if down else 196.0
			var to: float = 196.0 if down else 587.33
			_mix_tone(samples, 0.0, 0.55, from, 0.23, 0, -0.28, to, 0.055, 0.26)
			_mix_tone(samples, 0.025, 0.52, from * 1.5, 0.11, 1, 0.28,
				to * 1.5, 0.08, 0.30)
			_mix_noise(samples, 0.04, 0.42, 0.055, 0.04)
		"deny":
			for hit in range(2):
				var start: float = float(hit) * 0.115
				_mix_tone(samples, start, 0.11, 155.56, 0.23, 3, -0.1, 138.59, 0.006, 0.08)
				_mix_tone(samples, start, 0.11, 164.81, 0.12, 3, 0.1, 146.83, 0.006, 0.08)
		"land":
			_mix_tone(samples, 0.0, 0.18, 115.0, 0.32, 2, 0.0, 48.0, 0.004, 0.15)
			_mix_noise(samples, 0.0, 0.11, 0.12, 0.075)
		"shard":
			_mix_tone(samples, 0.0, 0.42, _hz(86), 0.21, 1, -0.25, -1.0, 0.004, 0.35)
			_mix_tone(samples, 0.10, 0.52, _hz(93), 0.15, 1, 0.25, -1.0, 0.005, 0.44)
		"checkpoint":
			var notes: Array[int] = [74, 78, 81]
			for note in range(notes.size()):
				_mix_tone(samples, float(note) * 0.14, 0.79, _hz(notes[note]),
					0.18, 0, float(note - 1) * 0.3, -1.0, 0.015, 0.60)
		"gate":
			_mix_noise(samples, 0.0, 0.33, 0.18, 0.055)
			_mix_tone(samples, 0.0, 0.40, 73.42, 0.27, 3, 0.0, 146.83, 0.025, 0.20)
			_mix_tone(samples, 0.20, 0.63, _hz(62), 0.20, 0, -0.22, -1.0, 0.035, 0.46)
			_mix_tone(samples, 0.29, 0.54, _hz(69), 0.16, 1, 0.22, -1.0, 0.025, 0.43)
		"death":
			_mix_tone(samples, 0.0, 0.67, 260.0, 0.27, 3, -0.15, 47.0, 0.012, 0.45)
			_mix_tone(samples, 0.03, 0.61, 277.18, 0.14, 0, 0.15, 55.0, 0.025, 0.42)
			_mix_noise(samples, 0.02, 0.48, 0.10, 0.05)
		"win":
			var notes: Array[int] = [74, 78, 81, 86]
			for note in range(notes.size()):
				_mix_tone(samples, float(note) * 0.16, 1.10, _hz(notes[note]),
					0.17, 1, float(note) * 0.16 - 0.24, -1.0, 0.014, 0.86)
			for note in [62, 66, 69]:
				_mix_tone(samples, 0.48, 1.38, _hz(int(note)),
					0.09, 0, 0.0, -1.0, 0.14, 0.90)
	return _to_wav(samples, false)


func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)


func _mix_tone(samples: PackedFloat32Array, start: float, duration: float,
		frequency: float, gain: float, color: int, pan: float = 0.0,
		end_frequency: float = -1.0, attack: float = 0.01,
		release: float = 0.15, wrap: bool = false) -> void:
	var frames: int = samples.size() >> 1
	var first: int = roundi(start * SAMPLE_RATE)
	var count: int = maxi(2, roundi(duration * SAMPLE_RATE))
	var left: float = sqrt((1.0 - clampf(pan, -1.0, 1.0)) * 0.5)
	var right: float = sqrt((1.0 + clampf(pan, -1.0, 1.0)) * 0.5)
	var destination: float = frequency if end_frequency <= 0.0 else end_frequency
	var phase: float = 0.0
	for frame in range(count):
		var target: int = first + frame
		if wrap:
			target %= frames
		elif target >= frames:
			break
		var time: float = float(frame) / float(SAMPLE_RATE)
		var progress: float = float(frame) / float(count - 1)
		var remaining: float = float(count - 1 - frame) / float(SAMPLE_RATE)
		var envelope: float = smoothstep(0.0, attack, time)
		envelope *= smoothstep(0.0, release, remaining)
		var value: float = sin(phase)
		match color:
			0:
				value = (value + 0.20 * sin(phase * 2.0) + 0.055 * sin(phase * 3.0)) / 1.255
			1:
				value = (value + 0.26 * sin(phase * 2.0) * exp(-time * 6.0)
					+ 0.12 * sin(phase * 3.997) * exp(-time * 9.0)) / 1.38
				envelope *= exp(-time * 2.3)
			2:
				value = (value + 0.08 * sin(phase * 2.0)) / 1.08
			3:
				value = (value + 0.24 * sin(phase * 3.0) + 0.08 * sin(phase * 5.0)) / 1.32
		value *= gain * envelope
		samples[target * 2] += value * left
		samples[target * 2 + 1] += value * right
		phase = fmod(phase + TAU * lerpf(frequency, destination, progress) / SAMPLE_RATE, TAU * 1000.0)


func _mix_noise(samples: PackedFloat32Array, start: float, duration: float,
		gain: float, softness: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71357
	var first: int = roundi(start * SAMPLE_RATE)
	var count: int = maxi(2, roundi(duration * SAMPLE_RATE))
	var frames: int = samples.size() >> 1
	var filtered: float = 0.0
	for frame in range(count):
		var target: int = first + frame
		if target >= frames:
			break
		var time: float = float(frame) / SAMPLE_RATE
		var progress: float = float(frame) / float(count - 1)
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), softness)
		var envelope: float = smoothstep(0.0, 0.012, time) * pow(1.0 - progress, 2.0)
		var value: float = filtered * gain * envelope
		samples[target * 2] += value
		samples[target * 2 + 1] += value


func _to_wav(samples: PackedFloat32Array, looping: bool) -> AudioStreamWAV:
	var frames: int = samples.size() >> 1
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	var edge_seconds: float = 0.025 if looping else 0.004
	for frame in range(frames):
		var edge: float = float(mini(frame, frames - 1 - frame)) / SAMPLE_RATE
		var envelope: float = smoothstep(0.0, edge_seconds, edge)
		for channel in range(2):
			var index: int = frame * 2 + channel
			var value: float = samples[index] * envelope
			pcm.encode_s16(index * 2, clampi(roundi(value * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = pcm
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = frames if looping else 0
	return stream
