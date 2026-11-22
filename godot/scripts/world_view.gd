extends Node2D

const VIEW = Vector2(960, 540)
const TILE = 36.0
const BODY = Vector2(22, 26)
const SOL = Color("#f1b17f")
const LUN = Color("#85dee5")
const INK = Color("#101724")
const PAPER = Color("#edf1e8")
const PURPLE = Color("#b695ef")
const RED = Color("#ff7079")
const MAX_FX = 216
const HINTS_EN = [
	["Arrow keys to move · Space to jump", "No path? SHIFT to the other world", "Diamonds are worth the detour"],
	["Amber platforms belong to SOL"],
	["Red spikes belong to SOL. SHIFT to pass"],
	["This wall only exists in one world", "SHIFT is blocked if the other side is solid"],
	["Release Space, then press again in the air", "Bright dot: one air jump left. Land to recharge", "Patrol in the way? Try SHIFT"],
	["Checkpoint · your new starting point"],
	["Jump → SHIFT in the air → find your landing"],
	["Checkpoint"],
	["Your past self can hold the other world", "SHIFT on SOL → run to the LUN plate", "This time, leave your LUN self behind", "SHIFT on LUN → run to the SOL plate"]
]

var _model: Node
var _font: Font
var _camera = 0.0
var _time = 0.0
var _world_width = 960.0
var _fx: Array[Dictionary] = []
var _trail: Array[Dictionary] = []
var _rng = RandomNumberGenerator.new()
var _trail_timer = 0.0
var _deny = 0.0
var _denied_at = Vector2.ZERO
var _squash = 0.0
var _last_position = Vector2.ZERO
var _gate_bounds: Array[Dictionary] = []
var _echo_label_rect = Rect2()
var _shift_at = Vector2(-1, -1)

func setup(model: Node, font: Font) -> void:
	if is_instance_valid(_model):
		if _model.effect.is_connected(_on_effect):
			_model.effect.disconnect(_on_effect)
		if _model.level_loaded.is_connected(_on_level_loaded):
			_model.level_loaded.disconnect(_on_level_loaded)
	_model = model
	_font = font if font != null else ThemeDB.fallback_font
	_model.effect.connect(_on_effect)
	_model.level_loaded.connect(_on_level_loaded)
	_on_level_loaded()

func _on_level_loaded() -> void:
	_fx.clear()
	_trail.clear()
	_gate_bounds.clear()
	_echo_label_rect = Rect2()
	_shift_at = Vector2(-1, -1)
	_deny = 0.0
	_squash = 0.0
	_trail_timer = 0.0
	_rng.seed = 7271 + (int(_model.sample_index) + 9 if _model.is_sample else int(_model.level_index)) * 193
	_world_width = float(_model.rows[0].length()) * TILE if not _model.rows.is_empty() else VIEW.x
	_camera = clampf(float(_model.p.x) - 350.0, 0.0, maxf(0.0, _world_width - VIEW.x))
	_last_position = _model.p
	_time = float(_model.clock)
	for relay in _model.relays:
		var top = VIEW.y
		var bottom = 0.0
		for row in range(_model.rows.size()):
			if _cell(int(relay.wall), row) == "G":
				top = minf(top, float(row) * TILE)
				bottom = maxf(bottom, float(row + 1) * TILE)
		_gate_bounds.append({"top": top, "bottom": bottom})
	queue_redraw()

func _process(delta: float) -> void:
	if not is_instance_valid(_model) or _model.state == "pause":
		return
	var dt = minf(delta, 0.05)
	_time = float(_model.clock)
	var limit = maxf(0.0, _world_width - VIEW.x)
	var target = clampf(float(_model.p.x) + BODY.x * 0.5 - 390.0 + float(_model.velocity.x) * 0.15, 0.0, limit)
	if _model.state == "title":
		target = limit * (0.34 + (0.0 if _model.reduced_motion else sin(_time * 0.09) * 0.16))
	elif _last_position.distance_to(_model.p) > 260.0:
		_camera = target
		_trail.clear()
	_camera = clampf(lerpf(_camera, target, 1.0 - exp(-dt * 6.5)), 0.0, limit)
	_last_position = _model.p
	_deny = maxf(0.0, _deny - dt)
	_squash = move_toward(_squash, 0.0, dt * 3.4)
	for i in range(_fx.size() - 1, -1, -1):
		var particle: Dictionary = _fx[i]
		particle.age += dt
		if particle.age >= particle.life:
			_fx.remove_at(i)
			continue
		particle.v.y += float(particle.gravity) * dt
		particle.p += particle.v * dt
	for i in range(_trail.size() - 1, -1, -1):
		_trail[i].age += dt
		if _trail[i].age >= 0.28:
			_trail.remove_at(i)
	_trail_timer -= dt
	if _model.state == "play" and not _model.reduced_motion and _model.dead_timer <= 0 and not _model.won:
		if _trail_timer <= 0.0 and Vector2(_model.velocity).length() > 120.0:
			_trail_timer = 0.028
			if _trail.size() >= 16:
				_trail.pop_front()
			_trail.append({"p": _model.p + Vector2(11, 15), "age": 0.0, "color": _phase_color(int(_model.world))})
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(_model):
		return
	var mix_value = clampf(float(_model.phase_mix), 0.0, 1.0)
	_draw_sky(mix_value)
	_draw_city(mix_value)
	_draw_fog(mix_value)
	if _model.is_sample:
		_draw_station(mix_value)
	_draw_tiles(mix_value)
	if _model.is_sample:
		_draw_platform_edge(mix_value)
		_draw_replay_route()
	_draw_relays()
	_draw_checkpoint()
	_draw_portal()
	_draw_shards()
	_draw_drones()
	_draw_trail()
	_draw_echo()
	_draw_hints()
	_draw_player()
	_draw_effects()
	_draw_frame()
	if _model.is_sample:
		_draw_replay_timeline()

func _screen(at: Vector2) -> Vector2:
	return at - Vector2(_camera, 0)

func _phase_color(world: int) -> Color:
	return SOL if world == 0 else LUN

func _alpha(color: Color, opacity: float) -> Color:
	return Color(color, clampf(opacity, 0.0, 1.0))

func _noise(value: float) -> float:
	return fposmod(sin(value * 12.9898 + 78.233) * 43758.5453, 1.0)

func _cell(col: int, row: int) -> String:
	if row < 0 or row >= _model.rows.size() or col < 0 or col >= _model.rows[row].length():
		return "."
	return _model.rows[row][col]

func _gradient(rect: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([top, top, bottom, bottom]))

func _ellipse(at: Vector2, radius: Vector2, color: Color) -> void:
	var points = PackedVector2Array()
	for i in range(24):
		var angle = float(i) * TAU / 24.0
		points.append(at + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)

func _glow(at: Vector2, radius: float, color: Color, strength: float = 1.0) -> void:
	for i in range(4, 0, -1):
		draw_circle(at, radius * float(i) / 4.0, _alpha(color, strength * 0.022 * float(5 - i)))

func _diamond(at: Vector2, radius: float, color: Color, filled: bool = true) -> void:
	var points = PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius * 0.7, 0), at + Vector2(0, radius), at + Vector2(-radius * 0.7, 0)])
	if filled:
		draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		draw_polyline(points, color, 1.0, true)

func _text(text: String, at: Vector2, size: int, color: Color, centered: bool = false) -> void:
	var x = at.x
	if centered:
		x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	draw_string(_font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_sky(mix_value: float) -> void:
	var top = Color("#161a27").lerp(Color("#11162b"), mix_value)
	var middle = Color("#443b43").lerp(Color("#283455"), mix_value)
	var horizon = Color("#99624c").lerp(Color("#344962"), mix_value)
	_gradient(Rect2(0, 0, 960, 290), top, middle)
	_gradient(Rect2(0, 290, 960, 250), middle, horizon)
	var motion_time = 0.0 if _model.reduced_motion else _time
	for i in range(70):
		var at = Vector2(fposmod(_noise(i * 1.7) * 1120.0 - _camera * 0.045, 1120.0) - 80.0, 17.0 + _noise(i + 15.0) * 267.0)
		var alpha = (0.12 + mix_value * 0.44) * (0.7 + sin(motion_time * 0.55 + i) * 0.3)
		var radius = 1.25 if i % 9 == 0 else 0.65
		draw_circle(at, radius, _alpha(Color("#dce0e9"), alpha))
		if i % 17 == 0:
			draw_line(at - Vector2(3, 0), at + Vector2(3, 0), _alpha(LUN, alpha * 0.45), 1.0)
	var sun = Vector2(751.0 - _camera * 0.07, 144.0)
	_glow(sun, 113.0, SOL, (1.0 - mix_value) * 0.85)
	draw_circle(sun, 48, _alpha(Color("#e8aa83"), (1.0 - mix_value) * 0.66))
	for i in range(7):
		var y = sun.y + 7.0 + float(i) * 5.5
		var half_width = sqrt(maxf(0.0, 48.0 * 48.0 - pow(y - sun.y, 2.0)))
		draw_line(Vector2(sun.x - half_width, y), Vector2(sun.x + half_width, y), _alpha(middle, (1.0 - mix_value) * 0.52), 1.8)
	var moon = sun + Vector2(13, -8)
	_glow(moon, 87, LUN, mix_value * 0.7)
	draw_circle(moon, 35, _alpha(Color("#b2ccd7"), mix_value * 0.77))
	draw_circle(moon + Vector2(13, -9), 31.5, _alpha(top.lerp(middle, 0.43), mix_value))
	draw_arc(moon, 51, -1.0, 2.4, 45, _alpha(LUN, mix_value * 0.12), 1.0, true)
	for i in range(5):
		var y = 218.0 + float(i) * 31.0
		var x = fposmod(float(i) * 233.0 - _camera * 0.12 + motion_time * (1.0 + i * 0.3), 1300.0) - 300.0
		draw_line(Vector2(x, y), Vector2(x + 210.0 + _noise(i) * 170.0, y), _alpha(horizon, 0.085), 2.0)

func _draw_city(mix_value: float) -> void:
	var motion_time = 0.0 if _model.reduced_motion else _time
	for layer in range(3):
		var parallax = 0.14 + float(layer) * 0.14
		var step = 91.0 + float(layer) * 34.0
		var horizon = 366.0 + float(layer) * 47.0
		var color = Color("#41404a").lerp(Color("#242e49"), mix_value).lerp(INK, float(layer) * 0.25)
		var first = floori(_camera * parallax / step) - 2
		var count = ceili(VIEW.x / step) + 5
		for i in range(first, first + count):
			var seed_value = float(i + layer * 93)
			var x = float(i) * step - _camera * parallax
			var width = step * (0.53 + _noise(seed_value) * 0.55)
			var height = 30.0 + _noise(seed_value + 9.0) * (85.0 + layer * 23.0)
			var roof = horizon - height
			draw_rect(Rect2(x, roof, width, VIEW.y - roof), color)
			draw_rect(Rect2(x - 3, roof, width + 6, 3), color.lightened(0.035))
			if i % 3 == 0:
				var antenna = Vector2(x + width * 0.6, roof - 34.0 - layer * 9.0)
				draw_line(antenna, antenna + Vector2(0, 36.0 + layer * 9.0), color, 2.0)
				draw_line(antenna + Vector2(-11, 12), antenna + Vector2(11, 12), color, 1.5)
				draw_line(antenna + Vector2(-7, 19), antenna + Vector2(7, 19), color, 1.0)
				var blink = 0.38 + 0.25 * sin(motion_time * 1.4 + seed_value)
				draw_circle(antenna, 1.4, _alpha(SOL.lerp(LUN, mix_value), blink))
			if i % 4 == 1:
				var tank = Vector2(x + width * 0.5, roof - 15)
				draw_rect(Rect2(tank - Vector2(15, 10), Vector2(30, 25)), color)
				_ellipse(tank - Vector2(0, 10), Vector2(15, 4), color)
				draw_line(tank + Vector2(-10, 13), tank + Vector2(-13, 23), color, 2.0)
				draw_line(tank + Vector2(10, 13), tank + Vector2(13, 23), color, 2.0)
			if layer > 0:
				for window in range(3):
					var wy = roof + 17.0 + float(window) * 22.0
					if wy > horizon - 8.0:
						break
					draw_rect(Rect2(x + 9, wy, 3, 6), _alpha(SOL.lerp(LUN, mix_value), 0.13 + _noise(seed_value + window) * 0.12))
					draw_rect(Rect2(x + 19, wy, 3, 6), _alpha(SOL.lerp(LUN, mix_value), 0.08))
			if layer == 1 and i % 5 == 0:
				var crane = Vector2(x + 19, roof)
				draw_line(crane, crane - Vector2(0, 62), color, 4.0)
				draw_line(crane - Vector2(23, 62), crane + Vector2(100, -62), color, 3.0)
				draw_line(crane - Vector2(0, 88), crane + Vector2(94, -62), color, 1.5)
				draw_line(crane - Vector2(0, 88), crane - Vector2(20, 62), color, 1.5)
				draw_line(crane + Vector2(86, -60), crane + Vector2(86, -23), color, 1.0)
			if layer == 2 and i % 3 == 1:
				var cable = PackedVector2Array()
				for segment in range(13):
					var fraction = float(segment) / 12.0
					cable.append(Vector2(x + width + fraction * step, roof + 15.0 + sin(fraction * PI) * 19.0))
				draw_polyline(cable, _alpha(color.lightened(0.05), 0.8), 1.0, true)

func _draw_fog(mix_value: float) -> void:
	var color = Color("#ad826b").lerp(Color("#7692b5"), mix_value)
	_gradient(Rect2(0, 315, 960, 115), _alpha(color, 0.0), _alpha(color, 0.07))
	_gradient(Rect2(0, 430, 960, 90), _alpha(color, 0.07), _alpha(color, 0.0))

func _draw_station(mix_value: float) -> void:
	# Background structure stays above the jump space; all supports are subdued.
	var accent = SOL.lerp(LUN, mix_value)
	var data: Dictionary = _model.current_level()
	var stages: Array = data.get("stages", [])
	for index in range(stages.size()):
		var stage: Dictionary = stages[index]
		var left = float(stage.x) - _camera
		var right = float(stages[index + 1].x) - _camera if index + 1 < stages.size() else _world_width - _camera
		if right < -20 or left > VIEW.x + 20:
			continue
		var x1 = maxf(-20, left + 12)
		var x2 = minf(VIEW.x + 20, right - 12)
		if x2 <= x1:
			continue
		_gradient(Rect2(x1, 176, x2 - x1, 31), Color("#1c2633"), Color("#141e2c"))
		draw_line(Vector2(x1, 177), Vector2(x2, 177), _alpha(accent, 0.28), 2.0)
		draw_line(Vector2(x1 + 4, 202), Vector2(x2 - 4, 202), _alpha(accent, 0.38), 2.0)
		for column in range(ceili((maxf(0, _camera - float(stage.x))) / 144.0), ceili((minf(_world_width, _camera + VIEW.x) - float(stage.x)) / 144.0)):
			var x = left + float(column) * 144.0 + 28.0
			if x > right - 24:
				break
			draw_line(Vector2(x, 180), Vector2(x + 24, 198), _alpha(PAPER, 0.045), 2.0)
		if index == 0:
			draw_circle(Vector2(left + 36, 191), 2, _alpha(SOL, 0.8))
			draw_circle(Vector2(left + 44, 191), 2, _alpha(LUN, 0.8))
			_text("%02d / %s" % [_model.sample_index + 1, data.name if _model.language == "zh" else data.en], Vector2(left + 55, 194), 10, _alpha(PAPER, 0.65))
		# Rear rail and posts are deliberately lower-contrast than collision tiles.
		for post in [left + 28.0, right - 28.0]:
			draw_line(Vector2(post, 207), Vector2(post, 468), _alpha(INK, 0.4), 5.0)
			draw_line(Vector2(post + 3, 208), Vector2(post + 3, 468), _alpha(accent, 0.08), 1.0)
		for rail_y in [421.0, 443.0]:
			draw_line(Vector2(x1, rail_y), Vector2(x2, rail_y), _alpha(accent, 0.09), 2.0)
		var sign_at = Vector2(left + 48, 219)
		if sign_at.x < -280 or sign_at.x > VIEW.x:
			continue
		draw_line(sign_at + Vector2(12, -14), sign_at + Vector2(12, 0), _alpha(PAPER, 0.22), 1.0)
		draw_line(sign_at + Vector2(264, -14), sign_at + Vector2(264, 0), _alpha(PAPER, 0.22), 1.0)
		draw_rect(Rect2(sign_at, Vector2(280, 42)), _alpha(INK, 0.88))
		draw_rect(Rect2(sign_at, Vector2(35, 42)), _alpha(accent, 0.12))
		_text("%02d" % int(stage.get("number", index + 1)), sign_at + Vector2(17, 27), 17, _alpha(accent, 0.85), true)
		_text(str(stage.get("name", "")), sign_at + Vector2(47, 17), 13, _alpha(PAPER, 0.8))
		_text(str(stage.get("en", "")), sign_at + Vector2(47, 33), 10, _alpha(accent, 0.65))

func _draw_platform_edge(mix_value: float) -> void:
	var accent = SOL.lerp(LUN, mix_value)
	draw_line(Vector2(0, 474), Vector2(VIEW.x, 474), _alpha(accent, 0.28), 2.0)
	draw_line(Vector2(0, 491), Vector2(VIEW.x, 491), _alpha(INK, 0.65), 3.0)
	draw_line(Vector2(0, 493), Vector2(VIEW.x, 493), _alpha(PAPER, 0.09), 1.0)
	for column in range(floori(_camera / TILE), ceili((_camera + VIEW.x) / TILE)):
		var x = float(column) * TILE - _camera
		draw_line(Vector2(x + 9, 474), Vector2(x + 19, 474), _alpha(accent, 0.52), 2.0)
		draw_circle(Vector2(x + 18, 495), 1.1, _alpha(PAPER, 0.14))

func _draw_tiles(mix_value: float) -> void:
	if _model.rows.is_empty():
		return
	var first = maxi(0, floori(_camera / TILE) - 1)
	var last = mini(_model.rows[0].length(), ceili((_camera + VIEW.x) / TILE) + 1)
	var base = Color("#29303b").lerp(Color("#202c41"), mix_value)
	var edge = Color("#768080").lerp(Color("#607d97"), mix_value)
	for row in range(_model.rows.size()):
		for col in range(first, last):
			var cell = _cell(col, row)
			var at = _screen(Vector2(col * TILE, row * TILE))
			if cell == "x" or cell == "a" or cell == "b":
				_draw_spikes(at, cell)
				continue
			if cell != "#" and cell != "A" and cell != "B":
				continue
			var world = 0 if cell == "A" else 1
			var phased = cell != "#"
			var accent = _phase_color(world) if phased else edge
			var active = not phased or int(_model.world) == world
			var rect = Rect2(at + Vector2(1, 1), Vector2(34, 34))
			if not active:
				draw_rect(rect, _alpha(accent, 0.035))
				draw_rect(rect, _alpha(accent, 0.28), false, 1.0)
				for dash in range(3):
					draw_line(at + Vector2(5 + dash * 11, 2), at + Vector2(10 + dash * 11, 2), _alpha(accent, 0.52), 1.0)
				draw_line(at + Vector2(12, 22), at + Vector2(23, 11), _alpha(accent, 0.16), 1.0)
				continue
			var face_color = base.lerp(accent, 0.15 if phased else 0.0)
			draw_rect(Rect2(at, Vector2(TILE, TILE)), face_color)
			draw_line(at + Vector2(35, 4), at + Vector2(35, 35), _alpha(INK, 0.58), 1.0)
			draw_line(at + Vector2(1, 35), at + Vector2(35, 35), _alpha(INK, 0.6), 1.0)
			var exposed = not _model.solid_cell(col, row - 1, int(_model.world))
			if exposed:
				draw_rect(Rect2(at, Vector2(36, 5)), accent.darkened(0.27 if phased else 0.44))
				draw_line(at, at + Vector2(36, 0), accent, 1.5)
				draw_line(at + Vector2(2, 6), at + Vector2(34, 6), _alpha(INK, 0.6), 1.0)
				if phased:
					draw_line(at + Vector2(0, -2), at + Vector2(36, -2), _alpha(accent, 0.15), 2.0)
			if phased:
				draw_rect(Rect2(at + Vector2(5, 12), Vector2(26, 14)), _alpha(INK, 0.24))
				draw_line(at + Vector2(10, 22), at + Vector2(15, 17), _alpha(accent, 0.65), 1.5)
				draw_line(at + Vector2(19, 22), at + Vector2(24, 17), _alpha(accent, 0.65), 1.5)
				draw_circle(at + Vector2(5, 30), 1.1, _alpha(accent, 0.4))
				draw_circle(at + Vector2(31, 30), 1.1, _alpha(accent, 0.4))
			elif (col + row * 3) % 5 == 0:
				draw_rect(Rect2(at + Vector2(6, 14), Vector2(23, 12)), _alpha(INK, 0.3), false, 1.0)
				for vent in range(3):
					draw_line(at + Vector2(10, 17 + vent * 3), at + Vector2(25, 17 + vent * 3), _alpha(edge, 0.14), 1.0)
			elif (col * 3 + row) % 7 == 0:
				draw_circle(at + Vector2(7, 12), 1.2, _alpha(edge, 0.24))
				draw_line(at + Vector2(7, 23), at + Vector2(18, 23), _alpha(edge, 0.12), 1.0)
			if not _model.solid_cell(col, row + 1, int(_model.world)):
				draw_line(at + Vector2(1, 35), at + Vector2(35, 35), _alpha(accent, 0.24), 1.0)

func _draw_spikes(at: Vector2, cell: String) -> void:
	var active = cell == "x" or (cell == "a" and _model.world == 0) or (cell == "b" and _model.world == 1)
	var color = LUN if cell == "b" else RED
	if active:
		draw_rect(Rect2(at + Vector2(2, 32), Vector2(32, 4)), color.darkened(0.55))
		draw_line(at + Vector2(2, 33), at + Vector2(34, 33), _alpha(color, 0.8), 1.0)
	for i in range(3):
		var x = 4.0 + float(i) * 10.0
		var points = PackedVector2Array([at + Vector2(x, 32), at + Vector2(x + 5, 15), at + Vector2(x + 10, 32)])
		if active:
			draw_colored_polygon(points, color.darkened(0.13))
			draw_line(points[0], points[1], color.lightened(0.22), 1.0, true)
			draw_line(points[1] + Vector2(1, 4), points[2] - Vector2(2, 1), color.darkened(0.4), 1.0, true)
		else:
			points.append(points[0])
			draw_polyline(points, _alpha(color, 0.31), 1.0, true)

func _draw_relays() -> void:
	for index in range(_model.relays.size()):
		var gate: Dictionary = _model.relays[index]
		var bounds: Dictionary = _gate_bounds[index]
		var x = float(gate.wall) * TILE - _camera
		var top = float(bounds.top)
		var bottom = float(bounds.bottom)
		for plate in gate.plates:
			var at = _screen(plate.p)
			var color = _phase_color(int(plate.w))
			var enabled = bool(plate.active)
			var wire_y = float(plate.p.y) + 13.0 + float(plate.w) * 4.0
			var start_x = clampf(at.x, -20, 980)
			var end_x = clampf(x + 18, -20, 980)
			draw_line(Vector2(start_x, wire_y), Vector2(end_x, wire_y), _alpha(color, 0.46 if enabled else 0.12), 1.0)
			if _model.is_sample:
				# Start at the actual plate height, including the raised LUN platform.
				var wire_color = _alpha(color, 0.52 if enabled else 0.2)
				if at.x >= -20 and at.x <= 980:
					draw_line(at + Vector2(0, 1), Vector2(at.x, wire_y), wire_color, 1.0)
				if x + 18 >= -20 and x + 18 <= 980 and bottom > top:
					var terminal = Vector2(x + 12 + float(plate.w) * 12, bottom - 9)
					draw_line(Vector2(x + 18, wire_y), Vector2(terminal.x, wire_y), wire_color, 1.0)
					draw_line(Vector2(terminal.x, wire_y), terminal, wire_color, 1.0)
					draw_circle(terminal, 2.0, wire_color)
			if at.x < -50 or at.x > 1010:
				continue
			if enabled:
				_glow(at - Vector2(0, 6), 27, color, 0.8)
			draw_rect(Rect2(at + Vector2(-19, -4), Vector2(38, 5)), INK)
			draw_rect(Rect2(at + Vector2(-16, -5 if enabled else -7), Vector2(32, 4)), _alpha(color, 1.0 if enabled else 0.5))
			draw_circle(at + Vector2(-21, -2), 1.6, color if enabled else color.darkened(0.7))
			_text("SOL" if plate.w == 0 else "LUN", at + Vector2(0, -15), 10, _alpha(color, 0.85), true)
			if enabled:
				draw_line(at + Vector2(-5, -32), at + Vector2(-1, -28), color, 1.4, true)
				draw_line(at + Vector2(-1, -28), at + Vector2(6, -35), color, 1.4, true)
		if x < -50 or x > 1010 or bottom <= top:
			continue
		var gate_color = PURPLE.darkened(0.56) if gate.open else PURPLE
		if _model.is_sample:
			gate_color = LUN.darkened(0.22) if gate.open else SOL
		draw_rect(Rect2(x + 1, top, 5, bottom - top), INK.lightened(0.06))
		draw_rect(Rect2(x + 30, top, 5, bottom - top), INK.lightened(0.06))
		draw_line(Vector2(x + 5, top), Vector2(x + 5, bottom), _alpha(gate_color, 0.7), 1.5)
		draw_line(Vector2(x + 30, top), Vector2(x + 30, bottom), _alpha(gate_color, 0.7), 1.5)
		draw_rect(Rect2(x - 2, top - 4, 40, 9), gate_color.darkened(0.5))
		if _model.is_sample:
			_draw_gate_signal(gate, Vector2(x + 18, top))
		if gate.open:
			if not _model.is_sample:
				_text("OPEN", Vector2(x + 18, top - 13), 10, _alpha(LUN, 0.7), true)
			continue
		draw_rect(Rect2(x + 7, top + 5, 22, bottom - top - 5), _alpha(gate_color, 0.14))
		for y in range(int(top + 12), int(bottom - 10), 18):
			draw_line(Vector2(x + 7, y), Vector2(x + 29, y + 12), _alpha(gate_color, 0.35), 1.0)
			draw_line(Vector2(x + 29, y), Vector2(x + 7, y + 12), _alpha(gate_color, 0.2), 1.0)
		var scan = top + fposmod(_time * (0.0 if _model.reduced_motion else 34.0), bottom - top)
		draw_line(Vector2(x + 7, scan), Vector2(x + 29, scan), _alpha(gate_color, 0.8), 2.0)
		if not _model.is_sample:
			_text("LINK", Vector2(x + 18, top - 13), 10, _alpha(PURPLE, 0.85), true)

func _draw_gate_signal(gate: Dictionary, at: Vector2) -> void:
	var live = str(gate.get("mode", "latch")) == "hold"
	var pressed = gate.plates.all(func(plate): return bool(plate.active))
	var color = LUN if gate.open else SOL
	var status = "等待 / WAIT" if live else "双触点 / PAIR"
	if gate.open:
		if not live:
			status = "已锁定 / LATCHED"
		elif pressed:
			status = "按住中 / HELD"
		else:
			# An open live gate is temporary, never presented as a completed link.
			var grace = clampf(float(gate.get("hold_time", 0.0)), 0.0, 0.55)
			status = "回落 / RELEASE %.1fs" % grace if grace > 0.0 else "让行 / CLEARING"
	var label = "HOLD / 按住" if live else "LINK / 联结"
	var width = maxf(_font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 12.0, 90.0)
	draw_rect(Rect2(at + Vector2(-width * 0.5, -44), Vector2(width, 38)), _alpha(INK, 0.9))
	_text(label, at + Vector2(0, -29), 10, color, true)
	_text(status, at + Vector2(0, -14), 9, _alpha(PAPER, 0.78), true)
	for index in range(gate.plates.size()):
		var plate: Dictionary = gate.plates[index]
		var signal_at = at + Vector2((float(index) - float(gate.plates.size() - 1) * 0.5) * 10.0, 0)
		var signal_color = _phase_color(int(plate.w))
		draw_circle(signal_at, 2.5, signal_color if plate.active or (gate.open and not live) else signal_color.darkened(0.7))
	if live and gate.open and not pressed:
		var fraction = clampf(float(gate.get("hold_time", 0.0)) / 0.55, 0.0, 1.0)
		draw_line(at + Vector2(-16, 7), at + Vector2(16, 7), _alpha(SOL, 0.18), 2.0)
		draw_line(at + Vector2(-16, 7), at + Vector2(-16 + 32 * fraction, 7), SOL, 2.0)

func _draw_checkpoint() -> void:
	for checkpoint in _model.checkpoints:
		var at = _screen(checkpoint.p)
		if checkpoint.p.x < 0 or at.x < -60 or at.x > 1020:
			continue
		var active = bool(checkpoint.active)
		var color = Color("#72e1ad")
		draw_rect(Rect2(at + Vector2(-12, -3), Vector2(24, 3)), color.darkened(0.5))
		draw_line(at - Vector2(0, 3), at - Vector2(0, 32), color.darkened(0.3), 2.0)
		var beacon = at - Vector2(0, 34)
		_glow(beacon, 28, color, 1.0 if active else 0.35)
		_diamond(beacon, 8, color, active)
		_diamond(beacon, 3, PAPER if active else color)
		if active:
			var pulse = fposmod(_time * 0.7, 1.0) if not _model.reduced_motion else 0.4
			draw_arc(beacon, 10 + pulse * 12, 0, TAU, 28, _alpha(color, (1.0 - pulse) * 0.3), 1.0, true)
			_text("已记录" if _model.language == "zh" else "SAVED", at - Vector2(0, 54), 10, _alpha(color, 0.85), true)

func _draw_portal() -> void:
	if _model.is_sample:
		_draw_train_door()
		return
	var at = _screen(_model.portal) - Vector2(0, 8)
	if at.x < -80 or at.x > 1040:
		return
	var active = _model.portal_world == -1 or _model.portal_world == _model.world
	var color = SOL.lerp(LUN, float(_model.phase_mix)) if _model.portal_world == -1 else _phase_color(int(_model.portal_world))
	var opacity = 1.0 if active else 0.34
	var turn = _time * 0.48 if not _model.reduced_motion else 0.0
	_glow(at, 59, color, opacity)
	_ellipse(at + Vector2(0, 25), Vector2(32, 5), _alpha(INK, 0.8))
	_ellipse(at + Vector2(0, 24), Vector2(25, 2), _alpha(color, opacity * 0.42))
	draw_circle(at, 21, _alpha(INK, 0.67))
	draw_arc(at, 24, 0, TAU, 64, _alpha(color, opacity * 0.25), 1.0, true)
	for i in range(3):
		var angle = turn + float(i) * TAU / 3.0
		draw_arc(at, 27, angle, angle + 1.3, 20, _alpha(color, opacity), 2.0, true)
		_diamond(at + Vector2.from_angle(angle) * 27, 3.0, _alpha(PAPER, opacity))
		draw_arc(at, 19, -angle, -angle + 0.8, 14, _alpha(color, opacity * 0.5), 1.0, true)
	draw_line(at + Vector2(-5, -10), at + Vector2(5, 0), _alpha(color, opacity), 2.0, true)
	draw_line(at + Vector2(5, 0), at + Vector2(-5, 10), _alpha(color, opacity), 2.0, true)
	var label = "出口" if _model.language == "zh" else "EXIT"
	if _model.portal_world != -1:
		label += " / " + ("SOL" if _model.portal_world == 0 else "LUN")
	_text(label, at - Vector2(0, 41), 11, _alpha(color, opacity * 0.9), true)

func _draw_train_door() -> void:
	var at = _screen(_model.portal) + Vector2(0, TILE * 0.5)
	if at.x < -140 or at.x > VIEW.x + 80:
		return
	var active = _model.portal_world == -1 or _model.portal_world == _model.world
	var opacity = 1.0 if active else 0.35
	# A waiting carriage, not a portal: the lit seat is the destination.
	draw_rect(Rect2(at + Vector2(-35, -86), Vector2(130, 86)), Color("#24313c"))
	draw_line(at + Vector2(-35, -86), at + Vector2(95, -86), _alpha(PAPER, 0.3), 2.0)
	draw_rect(Rect2(at + Vector2(-26, -77), Vector2(52, 76)), INK)
	_gradient(Rect2(at + Vector2(-22, -73), Vector2(44, 72)), _alpha(SOL, opacity * 0.24), _alpha(SOL, opacity * 0.06))
	for side in [-1.0, 1.0]:
		draw_line(at + Vector2(side * 27, -77), at + Vector2(side * 27, 0), _alpha(PAPER, opacity * 0.48), 2.0)
		draw_line(at + Vector2(side * 18, -48), at + Vector2(side * 18, -25), _alpha(SOL, opacity * 0.65), 2.0)
	draw_rect(Rect2(at + Vector2(37, -68), Vector2(45, 45)), INK)
	_gradient(Rect2(at + Vector2(39, -66), Vector2(41, 40)), _alpha(SOL, opacity * 0.24), _alpha(SOL, opacity * 0.07))
	draw_rect(Rect2(at + Vector2(46, -42), Vector2(26, 16)), SOL.darkened(0.68))
	draw_line(at + Vector2(44, -25), at + Vector2(75, -25), _alpha(SOL, opacity * 0.85), 3.0)
	draw_line(at + Vector2(48, -23), at + Vector2(48, -18), _alpha(PAPER, 0.25), 2.0)
	draw_line(at + Vector2(71, -23), at + Vector2(71, -18), _alpha(PAPER, 0.25), 2.0)
	draw_line(at + Vector2(46, -61), at + Vector2(73, -61), _alpha(SOL, opacity), 2.0)
	_glow(at + Vector2(60, -58), 23, SOL, opacity * 0.4)
	draw_line(at + Vector2(-30, -1), at + Vector2(30, -1), _alpha(SOL, opacity), 3.0)
	for index in range(2):
		draw_circle(at + Vector2(-7 + index * 14, -82), 2.2, _alpha(_phase_color(index), opacity))
	_text("上车 / BOARD", at + Vector2(0, -98), 11, _alpha(PAPER, opacity * 0.9), true)

func _draw_shards() -> void:
	for i in range(_model.shards.size()):
		var shard: Dictionary = _model.shards[i]
		if shard.taken:
			continue
		var at = _screen(shard.p)
		if at.x < -30 or at.x > 990:
			continue
		var bob = 0.0 if _model.reduced_motion else sin(_time * 2.2 + i * 1.8) * 3.0
		at.y += bob
		var color = Color("#f5d5a1")
		_glow(at, 22, color, 0.7)
		_diamond(at, 9.0, color)
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -9), at + Vector2(6.3, 0), at + Vector2(0, 4)]), PAPER)
		draw_line(at + Vector2(0, 4), at + Vector2(0, 9), color.darkened(0.32), 1.0)
		if i % 2 == 0:
			draw_circle(at + Vector2(13, -9 - bob), 1, _alpha(color, 0.5))

func _draw_drones() -> void:
	for drone in _model.drones:
		var at = _screen(drone.p)
		if at.x < -40 or at.x > 1000:
			continue
		var active = drone.w == _model.world
		var color = RED if drone.w == 0 else LUN
		var opacity = 1.0 if active else 0.23
		var angle = _time * float(drone.dir) * 2.4 if not _model.reduced_motion else 0.0
		if active:
			_glow(at, 25, color, 0.5)
		for i in range(4):
			var direction = Vector2.from_angle(angle + float(i) * PI * 0.5)
			var side = direction.orthogonal()
			var points = PackedVector2Array([at + direction * 9 + side * 4, at + direction * 17, at + direction * 9 - side * 4])
			if active:
				draw_colored_polygon(points, color.darkened(0.25))
			else:
				points.append(points[0])
				draw_polyline(points, _alpha(color, opacity), 1.0, true)
		draw_circle(at, 10, _alpha(INK, 0.95 if active else 0.3))
		draw_arc(at, 10, 0, TAU, 28, _alpha(color, opacity), 1.5, true)
		draw_line(at + Vector2(-5, -1), at + Vector2(5, -1), _alpha(color, opacity), 2.0)
		draw_circle(at + Vector2(float(drone.dir) * 2, -1), 2, _alpha(PAPER, opacity))
		draw_line(at + Vector2(-3, 5), at + Vector2(3, 5), _alpha(color, opacity * 0.5), 1.0)

func _draw_trail() -> void:
	for item in _trail:
		var progress = float(item.age) / 0.28
		var at = _screen(item.p)
		var color: Color = item.color
		_ellipse(at, Vector2(6, 3) * (1.0 - progress * 0.6), _alpha(color, (1.0 - progress) * 0.2))

func _draw_replay_route() -> void:
	if (_model.state != "play" and _model.state != "pause") or _model.won:
		return
	var replaying = not _model.echoes.is_empty() and _model.echoes.back().has("track")
	var records: Array = _model.echoes.back().track if replaying else _model.history
	if records.is_empty():
		return
	var world = int(_model.echoes.back().w) if replaying else int(_model.world)
	var color = _phase_color(world)
	var first = clampi(int(_model.echoes.back().get("cursor", 0)), 0, records.size() - 1) if replaying else 0
	var step = maxi(1, ceili(float(records.size() - first) / 96.0))
	var previous = Vector2(-10000, -10000)
	# Static, spatially separated dots: no extra motion, and at most 96 route marks.
	for index in range(first, records.size(), step):
		var record: Dictionary = records[index]
		var at = _screen(Vector2(record.p) + BODY * 0.5)
		if at.x < -8 or at.x > VIEW.x + 8 or at.distance_to(previous) < 9.0:
			continue
		previous = at
		draw_circle(at, 1.5 if replaying else 1.2, _alpha(color, 0.3 if replaying else 0.15))
		if bool(record.grounded) and _record_on_plate(record, world):
			draw_line(at + Vector2(-3, 7), at + Vector2(3, 7), _alpha(color, 0.55 if replaying else 0.25), 1.5)
	# Keep the historical origin visible even after the double has moved on.
	var start = _screen(records.front().p)
	var span = minf(3.0, maxf(0.0, float(records.back().t) - float(records.front().t)))
	if start.x >= -22 and start.x <= VIEW.x:
		var opacity = 0.5 if replaying else 0.3
		draw_rect(Rect2(start, BODY), _alpha(color, opacity * 0.5), false, 1.0)
		_diamond(start + Vector2(11, 30), 3, _alpha(color, opacity), false)
		var label = "−%.1fs 起点 / START" % span
		var width = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 10.0
		var center = Vector2(clampf(start.x + 11, width * 0.5 + 4, VIEW.x - width * 0.5 - 4), minf(487, start.y + 44))
		draw_rect(Rect2(center - Vector2(width * 0.5, 11), Vector2(width, 15)), _alpha(INK, 0.75))
		_text(label, center, 9, _alpha(color, 0.76 if replaying else 0.5), true)
	if replaying:
		var shifted = _screen(_shift_at if _shift_at.x >= 0 else Vector2(records.back().p) + BODY * 0.5)
		if shifted.x >= 0 and shifted.x <= VIEW.x:
			draw_arc(shifted, 6, 0, TAU, 16, _alpha(PAPER, 0.26), 1.0, true)
			draw_line(shifted - Vector2(3, 0), shifted + Vector2(3, 0), _alpha(PAPER, 0.4), 1.0)
			if shifted.distance_to(start + BODY * 0.5) > 120:
				_text("SHIFT", Vector2(clampf(shifted.x, 23, VIEW.x - 23), minf(487, shifted.y + 31)), 9, _alpha(PAPER, 0.45), true)

func _record_on_plate(record: Dictionary, world: int) -> bool:
	if not bool(record.grounded):
		return false
	for gate in _model.relays:
		for plate in gate.plates:
			if _model.on_plate(record.p, world, true, plate):
				return true
	return false

func _draw_replay_timeline() -> void:
	if (_model.state != "play" and _model.state != "pause") or _model.won:
		return
	var replaying = not _model.echoes.is_empty() and _model.echoes.back().has("track")
	var echo: Dictionary = _model.echoes.back() if replaying else {}
	var records: Array = echo.track if replaying else _model.history
	var color = _phase_color(int(echo.w) if replaying else int(_model.world))
	# The first pose may precede zero; playback is relative to the three-second window.
	var window_start = 0.0 if replaying else float(_model.history_time) - 3.0
	var elapsed = clampf(float(echo.get("max_life", 3.0)) - float(echo.get("life", 0.0)), 0.0, 3.0) if replaying else 3.0
	var recorded = minf(3.0, float(records.back().t) - float(records.front().t)) if records.size() > 1 else 0.0
	var label = "重放 / REPLAY %.1fs" % float(echo.life) if replaying else "记录 / REC %.1fs" % recorded
	var left = 576.0
	var right = 930.0
	var y = 516.0
	draw_rect(Rect2(562, 493, 382, 44), _alpha(INK, 0.94))
	draw_line(Vector2(562, 493), Vector2(944, 493), _alpha(color, 0.35), 1.0)
	_text(label, Vector2(left, 505), 10, _alpha(color, 0.94))
	_text("落地 GROUND", Vector2(745, 505), 9, _alpha(PAPER, 0.65))
	_text("触板 PLATE", Vector2(851, 505), 9, color)
	draw_line(Vector2(left, y), Vector2(right, y), _alpha(PAPER, 0.16), 1.0)
	# Uniform time bins represent the padded hold without depending on record density.
	var bins = PackedByteArray()
	bins.resize(90)
	var record_index = 0
	for bin_index in range(bins.size()):
		if records.is_empty():
			break
		var sample_time = window_start + float(bin_index) * 3.0 / 89.0
		if sample_time < float(records.front().t) or sample_time > float(records.back().t) + 0.001:
			continue
		while record_index + 1 < records.size() and float(records[record_index + 1].t) <= sample_time:
			record_index += 1
		var pose: Dictionary = records[record_index]
		var sample_position: Vector2 = pose.p
		if record_index + 1 < records.size():
			var next: Dictionary = records[record_index + 1]
			var blend = clampf((sample_time - float(pose.t)) / maxf(0.001, float(next.t) - float(pose.t)), 0.0, 1.0)
			sample_position = sample_position.lerp(next.p, blend)
		var sample_pose = {"p": sample_position, "grounded": bool(pose.grounded)}
		bins[bin_index] = 3 if _record_on_plate(sample_pose, int(echo.w) if replaying else int(_model.world)) else (2 if pose.grounded else 1)
	for index in range(bins.size()):
		if bins[index] == 0:
			continue
		var x = lerpf(left, right, float(index) / 89.0)
		var height = 4.0 if bins[index] == 3 else (2.5 if bins[index] == 2 else 1.0)
		var tick_color = color if bins[index] == 3 else _alpha(PAPER, 0.5 if bins[index] == 2 else 0.18)
		draw_line(Vector2(x, y - height), Vector2(x, y + height), tick_color, 2.0)
	for second in range(4):
		var x = lerpf(left, right, float(second) / 3.0)
		draw_line(Vector2(x, y + 5), Vector2(x, y + 8), _alpha(PAPER, 0.3), 1.0)
		_text("−%ds" % (3 - second) if second < 3 else "SHIFT", Vector2(x, 533), 8, _alpha(PAPER, 0.55), true)
	if not records.is_empty():
		var origin_fraction = clampf((float(records.front().t) - window_start) / 3.0, 0.0, 1.0)
		_diamond(Vector2(lerpf(left, right, origin_fraction), y), 4, color, false)
	var cursor_x = lerpf(left, right, elapsed / 3.0)
	draw_line(Vector2(cursor_x, y - 7), Vector2(cursor_x, y + 7), PAPER if replaying else _alpha(color, 0.65), 1.0)
	if replaying:
		draw_circle(Vector2(cursor_x, y - 7), 2, PAPER)

func _draw_echo() -> void:
	_echo_label_rect = Rect2()
	if _model.echoes.is_empty():
		return
	var echo: Dictionary = _model.echoes.back()
	var at = _screen(echo.p)
	if at.x < -70 or at.x > 1030:
		return
	var duration = maxf(0.001, float(echo.get("max_life", 3.0 if not _model.relays.is_empty() else 0.45)))
	var opacity = minf(1.0, float(echo.life) / 0.3)
	var color = _phase_color(int(echo.w))
	_glow(at + BODY * 0.5, 31, color, opacity * 0.45)
	_draw_courier(at, int(echo.get("face", 1)), color, opacity * (0.57 if _model.is_sample else 0.4), true)
	for line in range(4):
		draw_line(at + Vector2(2, 3 + line * 6), at + Vector2(20, 3 + line * 6), _alpha(color, opacity * 0.6), 1.0)
	var label = ("分身 " if _model.language == "zh" else "ECHO ") + "%.1fs" % float(echo.life)
	if _model.is_sample:
		label = "刚才的你 / PAST YOU  %.1fs" % maxf(0.0, float(echo.life))
	var width = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 12.0
	var center = Vector2(clampf(at.x + 11, width * 0.5 + 6, 954 - width * 0.5), at.y - 17)
	_echo_label_rect = Rect2(center - Vector2(width * 0.5, 13), Vector2(width, 19))
	draw_rect(_echo_label_rect, _alpha(INK, opacity * 0.92))
	_text(label, center, 10, _alpha(color, opacity), true)
	draw_line(center + Vector2(-width * 0.5, 6), center + Vector2(width * 0.5, 6), _alpha(color, opacity * 0.2), 2.0)
	draw_line(center + Vector2(-width * 0.5, 6), center + Vector2(-width * 0.5 + width * clampf(float(echo.life) / duration, 0.0, 1.0), 6), _alpha(color, opacity), 2.0)

func _draw_player() -> void:
	if _model.dead_timer > 0:
		return
	var at = _screen(_model.p)
	var foot = Vector2(_model.p) + Vector2(11, 26)
	var column = floori(foot.x / TILE)
	var floor_y = -1.0
	for row in range(maxi(0, floori(foot.y / TILE)), mini(_model.rows.size(), floori(foot.y / TILE) + 6)):
		if _model.solid_cell(column, row, int(_model.world)):
			floor_y = float(row) * TILE
			break
	if floor_y >= 0:
		var distance = maxf(0, floor_y - foot.y)
		_ellipse(Vector2(foot.x - _camera, floor_y + 1), Vector2(maxf(5, 13 - distance * 0.04), 2.5), _alpha(INK, maxf(0.1, 0.65 - distance * 0.003)))
	_draw_courier(at, int(_model.face), PAPER, 1.0, false)
	if _model.double_jump_enabled:
		var color = _phase_color(int(_model.world))
		var indicator = at + Vector2(11, -8)
		if _model.air_jump_ready:
			_glow(indicator, 10, color, 0.55)
			draw_circle(indicator, 2.7, color)
			draw_circle(indicator - Vector2(0.6, 0.7), 0.8, PAPER)
		else:
			draw_arc(indicator, 2.6, 0, TAU, 16, _alpha(color, 0.45), 1.0, true)
			draw_line(indicator - Vector2(2, 2), indicator + Vector2(2, 2), _alpha(color, 0.4), 1.0)

func _draw_courier(at: Vector2, facing: int, color: Color, opacity: float, is_echo: bool) -> void:
	var speed = 0.0 if is_echo else absf(float(_model.velocity.x))
	var stride = sin(_time * 22.0) * minf(2.3, speed * 0.012) if not is_echo and _model.grounded else 0.0
	if _model.is_sample and _model.reduced_motion:
		stride = 0.0
	var motion = 0.0 if _model.reduced_motion else sin(_time * 12.0) * 2.0
	var stretch = 0.0 if is_echo or _model.reduced_motion else _squash
	draw_set_transform(at + Vector2(11, 26), 0.0, Vector2(1.0 + stretch * 0.12, 1.0 - stretch * 0.14))
	var origin = Vector2(-11, -26)
	var scarf_color = _alpha(color if is_echo else Color("#ec8872"), opacity)
	var knot = origin + Vector2(11 - facing * 6, 14)
	var length = 14.0 + minf(10.0, speed * 0.035)
	var scarf = PackedVector2Array([knot, knot + Vector2(-facing * length * 0.5, -3 + motion), knot + Vector2(-facing * length, -1 - motion), knot + Vector2(-facing * (length - 3), 4 - motion), knot + Vector2(-facing * length * 0.5, 2 + motion), knot + Vector2(0, 4)])
	draw_colored_polygon(scarf, scarf_color)
	draw_rect(Rect2(origin + Vector2(4, 21 + stride), Vector2(6, 5 - stride)), _alpha(color.darkened(0.15), opacity))
	draw_rect(Rect2(origin + Vector2(13, 21 - stride), Vector2(6, 5 + stride)), _alpha(color.darkened(0.15), opacity))
	draw_rect(Rect2(origin + Vector2(3, 25), Vector2(8, 2)), _alpha(INK, opacity))
	draw_rect(Rect2(origin + Vector2(12, 25), Vector2(8, 2)), _alpha(INK, opacity))
	draw_rect(Rect2(origin + Vector2(4, 12), Vector2(15, 11)), _alpha(color.darkened(0.11), opacity))
	var hood = PackedVector2Array([origin + Vector2(4, 0), origin + Vector2(18, 0), origin + Vector2(21, 3), origin + Vector2(21, 12), origin + Vector2(18, 15), origin + Vector2(4, 15), origin + Vector2(1, 12), origin + Vector2(1, 3)])
	draw_colored_polygon(hood, _alpha(color, opacity))
	draw_line(origin + Vector2(5, 2), origin + Vector2(17, 2), _alpha(Color.WHITE, opacity * 0.7), 1.0)
	var visor = origin + Vector2(5 + facing * 2, 6)
	draw_rect(Rect2(visor, Vector2(12, 5)), _alpha(INK, opacity * 0.92))
	draw_rect(Rect2(visor + Vector2(3, 1), Vector2(2, 2)), _alpha(LUN if is_echo else PAPER, opacity))
	draw_rect(Rect2(visor + Vector2(8, 1), Vector2(2, 2)), _alpha(LUN if is_echo else PAPER, opacity))
	draw_rect(Rect2(origin + Vector2(3, 13), Vector2(17, 3)), scarf_color)
	var pack = origin + Vector2(0 if facing > 0 else 17, 16)
	draw_rect(Rect2(pack, Vector2(5, 7)), _alpha(color.darkened(0.4), opacity))
	draw_line(pack + Vector2(1, 2), pack + Vector2(4, 2), _alpha(SOL, opacity * 0.75), 1.0)
	draw_rect(Rect2(origin + Vector2(12 if facing > 0 else 6, 18), Vector2(4, 4)), _alpha(color.lightened(0.05), opacity))
	draw_set_transform(Vector2.ZERO)

func _draw_hints() -> void:
	if _model.state != "play" and _model.state != "pause":
		return
	if _model.won:
		return
	var data: Dictionary = _model.current_level()
	var hints: Array = data.get("hints", [])
	var candidates: Array[Dictionary] = []
	for i in range(hints.size()):
		var hint: Dictionary = hints[i]
		var world_at = Vector2(float(hint.x), float(hint.y)) * TILE
		var distance = absf(world_at.x - float(_model.p.x) - 11.0)
		var at = _screen(world_at)
		if distance > 410 or at.x < -60 or at.x > 1020:
			continue
		candidates.append({"index": i, "at": at, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	var occupied: Array[Rect2] = []
	var player_rect = Rect2(_screen(_model.p) - Vector2(9, 18), BODY + Vector2(18, 26))
	for candidate in candidates:
		if occupied.size() >= 2:
			break
		var index = int(candidate.index)
		var text = str(hints[index].t)
		if _model.language != "zh":
			if _model.is_sample:
				text = str(hints[index].get("en", text))
			elif _model.level_index >= 0 and _model.level_index < HINTS_EN.size() and index < HINTS_EN[_model.level_index].size():
				text = HINTS_EN[_model.level_index][index]
		var size = 13
		var width = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if width > 416:
			size = 12
			width = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var center: Vector2 = candidate.at
		center.x = clampf(center.x, width * 0.5 + 24, VIEW.x - width * 0.5 - 24)
		var rect = Rect2(center - Vector2(width * 0.5 + 12, 20), Vector2(width + 24, 29))
		if _model.is_sample:
			for stage in data.get("stages", []):
				var sign_rect = Rect2(float(stage.x) - _camera + 48, 219, 280, 42)
				if rect.grow(5).intersects(sign_rect):
					var offset = sign_rect.end.y + 8.0 - rect.position.y
					rect.position.y += offset
					center.y += offset
			if _echo_label_rect.has_area() and rect.grow(6).intersects(_echo_label_rect):
				rect.position.y -= 40
				center.y -= 40
		if rect.grow(8).intersects(player_rect):
			rect.position.y -= 42
			center.y -= 42
		if _model.is_sample:
			if rect.grow(4).intersects(player_rect) or (_echo_label_rect.has_area() and rect.grow(4).intersects(_echo_label_rect)):
				continue
			var over_sign = false
			for stage in data.get("stages", []):
				if rect.grow(3).intersects(Rect2(float(stage.x) - _camera + 48, 219, 280, 42)):
					over_sign = true
					break
			if over_sign:
				continue
		var overlap = false
		for prior in occupied:
			if prior.grow(2).intersects(rect):
				overlap = true
				break
		if overlap:
			continue
		occupied.append(rect)
		var opacity = clampf((410.0 - float(candidate.distance)) / 125.0, 0.0, 1.0)
		draw_rect(rect, _alpha(INK, opacity * 0.77))
		draw_line(rect.position, rect.position + Vector2(0, rect.size.y), _alpha(SOL.lerp(LUN, float(_model.phase_mix)), opacity * 0.6), 2.0)
		_text(text, center, size, _alpha(Color("#d4d9df"), opacity * 0.96), true)

func _add_fx(at: Vector2, velocity: Vector2, color: Color, life: float, size: float, form: String = "spark", gravity: float = 90.0) -> void:
	if _fx.size() >= MAX_FX:
		_fx.pop_front()
	_fx.append({"p": at, "v": velocity, "color": color, "life": life, "age": 0.0, "size": size, "form": form, "gravity": gravity})

func _burst(at: Vector2, count: int, color: Color, speed: float, upward: bool = false, form: String = "spark") -> void:
	if _model.reduced_motion:
		count = maxi(2, count / 3)
		speed *= 0.55
	for i in range(count):
		var angle = _rng.randf_range(-PI, 0.0) if upward else _rng.randf_range(0.0, TAU)
		var velocity = Vector2.from_angle(angle) * _rng.randf_range(speed * 0.25, speed)
		_add_fx(at + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)), velocity, color.lerp(PAPER, _rng.randf_range(0, 0.42)), _rng.randf_range(0.3, 0.72), _rng.randf_range(1.5, 3.5), form, 120.0)

func _on_effect(kind: String, at: Vector2) -> void:
	if not is_instance_valid(_model) or _model.state == "pause":
		return
	var color = _phase_color(int(_model.world))
	match kind:
		"shift":
			if _model.is_sample:
				_shift_at = at
			_burst(at, 24, color, 135)
			_add_fx(at, Vector2.ZERO, color, 0.55, 80 if not _model.reduced_motion else 35, "ring", 0)
			_add_fx(at, Vector2.ZERO, PAPER, 0.3, 43, "ring", 0)
		"jump":
			_squash = -0.7
			_burst(at, 7, Color("#b6c0c8"), 60, true)
			_add_fx(at, Vector2.ZERO, color, 0.24, 20, "ripple", 0)
		"air_jump":
			_squash = -1.0
			_burst(at, 14, color, 100)
			_add_fx(at, Vector2.ZERO, color, 0.35, 33, "ring", 0)
		"land":
			_squash = 1.0
			_burst(at, 10, Color("#a4b2bf"), 65, true)
			_add_fx(at, Vector2.ZERO, color, 0.3, 26, "ripple", 0)
		"death":
			_trail.clear()
			_burst(at, 26, RED, 158, false, "chip")
			_add_fx(at, Vector2.ZERO, RED, 0.45, 44, "ring", 0)
		"shard":
			_burst(at, 14, Color("#f5d5a1"), 95, true, "diamond")
			_add_fx(at, Vector2.ZERO, SOL, 0.35, 26, "ring", 0)
		"checkpoint":
			_burst(at, 18, LUN, 110, true)
			_add_fx(at, Vector2.ZERO, LUN, 0.6, 50, "ring", 0)
		"gate":
			if _model.is_sample:
				_burst(at, 6, LUN, 48, true)
				_add_fx(at, Vector2.ZERO, LUN, 0.25, 18, "ring", 0)
			else:
				_burst(at, 25, PURPLE, 140, true, "chip")
				_add_fx(at, Vector2.ZERO, PURPLE, 0.5, 62, "ring", 0)
		"win":
			_burst(at, 38, Color("#f5d5a1"), 165, false, "diamond")
			_add_fx(at, Vector2.ZERO, PAPER, 0.7, 95, "ring", 0)
		"deny":
			_deny = 0.6
			_denied_at = at
			_burst(at, 6, RED, 60)
	queue_redraw()

func _draw_effects() -> void:
	for particle in _fx:
		var at = _screen(particle.p)
		if at.x < -110 or at.x > 1070:
			continue
		var progress = float(particle.age) / float(particle.life)
		var color = _alpha(particle.color, (1.0 - progress) * 0.85)
		var size = float(particle.size)
		match particle.form:
			"ring":
				var radius = 6.0 + size * (1.0 - pow(1.0 - progress, 3.0))
				draw_arc(at, radius, 0, TAU, 56, color, maxf(1, 2.5 * (1.0 - progress)), true)
			"ripple":
				var radius = 4.0 + size * progress
				var points = PackedVector2Array()
				for i in range(33):
					var angle = float(i) * TAU / 32.0
					points.append(at + Vector2(cos(angle) * radius, sin(angle) * radius * 0.2))
				draw_polyline(points, color, 1.0, true)
			"chip":
				draw_rect(Rect2(at - Vector2.ONE * size * 0.5, Vector2.ONE * size), color)
			"diamond":
				_diamond(at, size * (1.0 - progress * 0.4), color)
			_:
				var velocity: Vector2 = particle.v
				draw_line(at, at - velocity.normalized() * size * 2.0, color, 1.5, true)
	if _deny > 0:
		var opacity = minf(1.0, _deny * 4.0)
		var at = _screen(_denied_at)
		draw_arc(at, 22, 0, TAU, 40, _alpha(RED, opacity * 0.8), 1.8, true)
		draw_line(at + Vector2(-16, -16), at + Vector2(16, 16), _alpha(RED, opacity * 0.6), 1.6, true)
		var label = "彼界被阻挡" if _model.language == "zh" else "OTHER SIDE BLOCKED"
		var width = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 16
		var position = Vector2(clampf(at.x, width * 0.5 + 8, 952 - width * 0.5), maxf(30, at.y - 43))
		draw_rect(Rect2(position - Vector2(width * 0.5, 15), Vector2(width, 23)), _alpha(INK, opacity * 0.95))
		_text(label, position, 11, _alpha(RED, opacity), true)

func _draw_frame() -> void:
	_gradient(Rect2(0, 0, 960, 34), Color(0.03, 0.05, 0.09, 0.2), Color(0.03, 0.05, 0.09, 0.0))
	_gradient(Rect2(0, 514, 960, 26), Color(0.03, 0.05, 0.09, 0.0), Color(0.03, 0.05, 0.09, 0.3))
