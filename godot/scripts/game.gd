extends Node

signal effect(kind: String, at: Vector2)
signal level_loaded
signal state_changed
signal completed

const TILE = 36.0
const BODY = Vector2(22, 26)
const MAX_SPEED = 265.0
const SAVE_PATH = "user://progress.json"

var levels: Array = []
var sample_levels: Array = []
var sample_index = 0
var sample_unlocked = 0
var is_sample = false
var double_jump_enabled = false
var history: Array = []
var history_time = 0.0
var rows: Array = []
var level_index = 0
var world = 0
var phase_mix = 0.0
var state = "title"
var p = Vector2.ZERO
var velocity = Vector2.ZERO
var grounded = false
var air_jump_ready = true
var coyote = 0.0
var jump_buffer = 0.0
var jump_sources: Dictionary = {}
var held: Dictionary = {}
var face = 1
var cooldown = 0.0
var hit_stop = 0.0
var clock = 0.0
var elapsed = 0.0
var deaths = 0
var shifts = 0
var collected = 0
var dead_timer = 0.0
var win_timer = 0.0
var won = false
var shards: Array = []
var drones: Array = []
var relays: Array = []
var echoes: Array = []
var checkpoints: Array = []
var checkpoint_active = false
var portal = Vector2.ZERO
var portal_world = -1
var spawn: Dictionary = {}
var assist = false
var muted = false
var reduced_motion = false
var language = "zh"
var unlocked = 0
var best: Dictionary = {}
var persistence_enabled = true

func _ready() -> void:
	levels = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))
	sample_levels = [JSON.parse_string(FileAccess.get_file_as_string("res://data/sample.json"))]
	sample_levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://data/sample_levels.json")))
	if persistence_enabled:
		load_progress()
	start_level(0)
	set_state("title")

func set_state(next: String) -> void:
	state = next
	clear_input()
	state_changed.emit()

func clear_input() -> void:
	held.clear()
	jump_sources.clear()
	jump_buffer = 0.0

func action(name: String, down: bool, source: String = "") -> void:
	if source.is_empty():
		source = name
	if name == "jump":
		if down:
			if state != "play" or dead_timer > 0 or won or jump_sources.has(source):
				return
			if jump_sources.is_empty():
				jump_buffer = 0.12
			jump_sources[source] = true
		elif jump_sources.erase(source):
			if jump_sources.is_empty() and velocity.y < -200:
				velocity.y = -200
	elif name == "shift":
		if down:
			try_shift()
	elif down and state == "play":
		held[source] = name
	else:
		held.erase(source)

func current_level() -> Dictionary:
	return sample_levels[sample_index] if is_sample else levels[level_index]

func start_sample(index: int = 0) -> void:
	is_sample = true
	sample_index = clampi(index, 0, sample_levels.size() - 1)
	level_index = 0
	load_level()

func start_level(index: int) -> void:
	is_sample = false
	level_index = clampi(index, 0, levels.size() - 1)
	load_level()

func restart() -> void:
	if not is_sample:
		start_level(level_index)
	elif checkpoint_active and not won:
		deaths += 1
		echoes.clear()
		for gate in relays:
			if gate.mode == "hold":
				gate.open = false
				gate.hold_time = 0.0
			for plate in gate.plates:
				plate.active = false
		respawn()
		set_state("play")
	else:
		start_sample(sample_index)

func load_level() -> void:
	var data: Dictionary = current_level()
	double_jump_enabled = bool(data.get("double_jump", level_index >= 4))
	rows = data.map.duplicate()
	shards.clear()
	drones.clear()
	relays.clear()
	echoes.clear()
	checkpoints.clear()
	checkpoint_active = false
	for row in range(rows.size()):
		for col in range(rows[row].length()):
			var cell: String = rows[row][col]
			var center = Vector2((col + 0.5) * TILE, (row + 0.5) * TILE)
			match cell:
				"S":
					spawn = {"p": Vector2(col * TILE + 7, (row + 1) * TILE - BODY.y), "world": 0}
				"*":
					shards.append({"p": center, "taken": false})
				"C":
					checkpoints.append({"p": Vector2(center.x, (row + 1) * TILE), "active": false})
				"E", "P", "Q":
					portal = center
					portal_world = -1 if cell == "E" else (0 if cell == "P" else 1)
	for drone in data.get("drones", []):
		drones.append({"p": Vector2(drone.x1 * TILE, drone.y * TILE), "w": int(drone.w), "x1": drone.x1 * TILE, "x2": drone.x2 * TILE, "speed": drone.spd, "dir": 1})
	for gate in data.get("relays", []):
		var plates: Array = []
		for plate in gate.plates:
			plates.append({"p": Vector2((plate.x + 0.5) * TILE, float(plate.get("y", 13)) * TILE), "w": int(plate.w), "active": false})
		relays.append({"wall": int(gate.wall), "mode": gate.get("mode", "latch"), "open": false, "plates": plates, "hold_time": 0.0, "release": float(gate.get("release", 0.55))})
	world = 0
	phase_mix = 0
	p = spawn.p
	velocity = Vector2.ZERO
	grounded = rect_solid(Rect2(p + Vector2(0, 0.1), BODY), world)
	air_jump_ready = true
	coyote = 0
	face = 1
	cooldown = 0
	hit_stop = 0
	elapsed = 0
	deaths = 0
	shifts = 0
	collected = 0
	dead_timer = 0
	win_timer = 0
	won = false
	reset_history()
	set_state("play")
	level_loaded.emit()

func solid_cell(col: int, row: int, target: int) -> bool:
	if col < 0 or col >= rows[0].length():
		return true
	if row < 0 or row >= rows.size():
		return false
	var cell: String = rows[row][col]
	if cell == "G":
		for gate in relays:
			if gate.wall == col and not gate.open:
				return true
	return cell == "#" or (cell == "A" and target == 0) or (cell == "B" and target == 1)

func rect_solid(rect: Rect2, target: int) -> bool:
	for row in range(floori(rect.position.y / TILE), floori((rect.end.y - 0.01) / TILE) + 1):
		for col in range(floori(rect.position.x / TILE), floori((rect.end.x - 0.01) / TILE) + 1):
			if solid_cell(col, row, target):
				return true
	return false

func try_shift() -> bool:
	if state != "play" or dead_timer > 0 or won or cooldown > 0:
		return false
	var target = 1 - world
	if rect_solid(Rect2(p + Vector2(2, 2), BODY - Vector2(4, 4)), target):
		cooldown = 0.22
		effect.emit("deny", p + BODY / 2)
		return false
	if not relays.is_empty():
		echoes.clear()
	if is_sample:
		var track: Array = history.duplicate(true)
		for pose in track:
			pose.t -= history_time - 3.0
		var first: Dictionary = track[0]
		echoes.append({"p": first.p, "w": world, "grounded": first.grounded, "face": first.face, "life": 3.0, "max_life": 3.0, "track": track, "cursor": 0})
	else:
		var duration = 3.0 if not relays.is_empty() else 0.45
		echoes.append({"p": p, "w": world, "grounded": grounded, "face": face, "life": duration, "max_life": duration})
	world = target
	reset_history()
	cooldown = 0.28
	hit_stop = 0.0 if reduced_motion else 0.045
	shifts += 1
	effect.emit("shift", p + BODY / 2)
	return true

func reset_history() -> void:
	history.clear()
	history_time = 0.0
	if is_sample:
		history.append({"p": p, "t": -3.0, "grounded": grounded, "face": face})
		history.append({"p": p, "t": 0.0, "grounded": grounded, "face": face})

func record_history(dt: float) -> void:
	if not is_sample:
		return
	history_time += dt
	history.append({"p": p, "t": history_time, "grounded": grounded, "face": face})
	while history.size() > 2 and history[1].t < history_time - 3.0:
		history.pop_front()

func advance_echoes(dt: float) -> void:
	for echo in echoes:
		echo.life -= dt
		if not echo.has("track"):
			continue
		var age: float = echo.max_life - echo.life
		var track: Array = echo.track
		while echo.cursor + 1 < track.size() and track[echo.cursor + 1].t <= age:
			echo.cursor += 1
		var pose: Dictionary = track[echo.cursor]
		echo.p = pose.p
		echo.grounded = pose.grounded
		echo.face = pose.face
		if echo.cursor + 1 < track.size():
			var next: Dictionary = track[echo.cursor + 1]
			var blend = clampf((age - pose.t) / (next.t - pose.t), 0.0, 1.0)
			echo.p = pose.p.lerp(next.p, blend)
	echoes = echoes.filter(func(e): return e.life > 0)

func tick(dt: float) -> void:
	if state == "pause":
		return
	clock += dt
	if hit_stop > 0:
		hit_stop -= dt
		return
	phase_mix = lerpf(phase_mix, float(world), minf(1, dt * 7.5))
	cooldown = maxf(0, cooldown - dt)
	if state != "play":
		return
	if not won:
		elapsed += dt
	if dead_timer > 0:
		dead_timer -= dt
		if dead_timer <= 0:
			respawn()
		return
	if won:
		win_timer -= dt
		if win_timer <= 0:
			set_state("win")
			completed.emit()
		return
	var direction = int(held.values().has("right")) - int(held.values().has("left"))
	if direction != 0:
		face = direction
		velocity.x = clampf(velocity.x + direction * (2600.0 if grounded else 1900.0) * dt, -MAX_SPEED, MAX_SPEED)
	else:
		velocity.x = move_toward(velocity.x, 0, (2200.0 if grounded else 770.0) * dt)
	coyote = 0.1 if grounded else maxf(0, coyote - dt)
	jump_buffer = maxf(0, jump_buffer - dt)
	if jump_buffer > 0 and (coyote > 0 or (double_jump_enabled and air_jump_ready)):
		var air = coyote <= 0
		if air:
			air_jump_ready = false
		velocity.y = -500.0 if air else -565.0
		jump_buffer = 0
		coyote = 0
		grounded = false
		effect.emit("air_jump" if air else "jump", p + Vector2(BODY.x / 2, BODY.y))
	var gravity = 1500.0
	if absf(velocity.y) < 70 and not jump_sources.is_empty():
		gravity *= 0.82
	velocity.y = minf(velocity.y + gravity * dt, 720)
	p.x += velocity.x * dt
	if rect_solid(Rect2(p, BODY), world):
		p.x = floorf((p.x + BODY.x) / TILE) * TILE - BODY.x - 0.01 if velocity.x > 0 else (floorf(p.x / TILE) + 1) * TILE + 0.01
		velocity.x = 0
	var was_grounded = grounded
	p.y += velocity.y * dt
	grounded = false
	if rect_solid(Rect2(p, BODY), world):
		if velocity.y > 0:
			p.y = floorf((p.y + BODY.y) / TILE) * TILE - BODY.y - 0.01
			grounded = true
			air_jump_ready = true
			if not was_grounded and velocity.y > 300:
				effect.emit("land", p + Vector2(BODY.x / 2, BODY.y))
		else:
			p.y = (floorf(p.y / TILE) + 1) * TILE + 0.01
		velocity.y = 0
	if hazard_at(Rect2(p + Vector2(4, 5), BODY - Vector2(8, 5))) or p.y > rows.size() * TILE + 60:
		die()
	for drone in drones:
		if drone.w != world:
			continue
		var near = Vector2(clampf(drone.p.x, p.x, p.x + BODY.x), clampf(drone.p.y, p.y, p.y + BODY.y))
		if near.distance_to(drone.p) < (10 if assist else 13):
			die()
	if dead_timer > 0:
		return
	record_history(dt)
	advance_echoes(dt)
	update_relays(dt)
	var center = p + BODY / 2
	for shard in shards:
		if not shard.taken and absf(center.x - shard.p.x) < 21 and absf(center.y - shard.p.y) < 25:
			shard.taken = true
			collected += 1
			effect.emit("shard", shard.p)
	for checkpoint in checkpoints:
		if not checkpoint.active and absf(center.x - checkpoint.p.x) < 24 and absf(center.y - checkpoint.p.y + 18) < 34:
			checkpoint.active = true
			checkpoint_active = true
			spawn = {"p": checkpoint.p - Vector2(BODY.x / 2, BODY.y), "world": world}
			if is_sample:
				echoes.clear()
				reset_history()
			effect.emit("checkpoint", checkpoint.p - Vector2(0, 22))
	if (portal_world == -1 or portal_world == world) and center.distance_to(portal) < 34:
		finish_level()
	for drone in drones:
		drone.p.x += drone.dir * drone.speed * (0.6 if assist else 1.0) * dt
		if drone.p.x > drone.x2:
			drone.p.x = drone.x2
			drone.dir = -1
		if drone.p.x < drone.x1:
			drone.p.x = drone.x1
			drone.dir = 1

func hazard_at(rect: Rect2) -> bool:
	for row in range(maxi(0, floori(rect.position.y / TILE)), mini(rows.size() - 1, floori(rect.end.y / TILE)) + 1):
		for col in range(maxi(0, floori(rect.position.x / TILE)), mini(rows[0].length() - 1, floori(rect.end.x / TILE)) + 1):
			var cell: String = rows[row][col]
			if cell != "x" and not (cell == "a" and world == 0) and not (cell == "b" and world == 1):
				continue
			var gx = 7 if assist else 5
			var gy = 20 if assist else 15
			if rect.intersects(Rect2(col * TILE + gx, row * TILE + gy, TILE - gx * 2, TILE - gy)):
				return true
	return false

func on_plate(at: Vector2, actor_world: int, on_ground: bool, plate: Dictionary) -> bool:
	return actor_world == plate.w and on_ground and absf(at.x + BODY.x / 2 - plate.p.x) < 22 and absf(at.y + BODY.y - plate.p.y) < 5

func update_relays(dt: float = 1.0 / 60.0) -> void:
	for gate in relays:
		for plate in gate.plates:
			plate.active = on_plate(p, world, grounded, plate)
			for echo in echoes:
				plate.active = plate.active or on_plate(echo.p, echo.w, echo.grounded, plate)
		var powered: bool = gate.plates.all(func(plate): return plate.active)
		var was_open: bool = gate.open
		if gate.mode == "hold":
			gate.hold_time = gate.release if powered else maxf(0.0, gate.hold_time - dt)
			var occupied = false
			for row in range(rows.size()):
				if rows[row][gate.wall] == "G" and Rect2(p, BODY).intersects(Rect2(gate.wall * TILE, row * TILE, TILE, TILE)):
					occupied = true
			gate.open = gate.hold_time > 0 or (was_open and occupied)
		else:
			gate.open = was_open or powered
		if gate.open and not was_open:
			effect.emit("gate", Vector2((gate.wall + 0.5) * TILE, 12 * TILE))

func die() -> void:
	if dead_timer > 0 or won:
		return
	dead_timer = 0.72
	deaths += 1
	echoes.clear()
	history.clear()
	clear_input()
	effect.emit("death", p + BODY / 2)

func respawn() -> void:
	world = spawn.world
	phase_mix = float(world)
	p = spawn.p
	velocity = Vector2.ZERO
	grounded = rect_solid(Rect2(p + Vector2(0, 0.1), BODY), world)
	air_jump_ready = true
	coyote = 0
	cooldown = 0
	hit_stop = 0
	dead_timer = 0
	clear_input()
	reset_history()

func finish_level() -> void:
	if won or dead_timer > 0:
		return
	won = true
	win_timer = 0.8
	clear_input()
	var key: String = current_level().id if is_sample else str(level_index)
	var previous: Dictionary = best.get(key, {})
	best[key] = {"stars": maxi(stars(), int(previous.get("stars", 0))), "time": minf(elapsed, float(previous.get("time", INF)))}
	if is_sample:
		sample_unlocked = maxi(sample_unlocked, mini(sample_index + 1, sample_levels.size() - 1))
	else:
		unlocked = maxi(unlocked, mini(level_index + 1, levels.size() - 1))
	save_progress()
	effect.emit("win", portal)

func stars() -> int:
	return 1 + int(collected == shards.size()) + int(deaths == 0)

func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		return
	unlocked = clampi(int(data.get("unlocked", 0)), 0, 8)
	if data.get("best") is Dictionary:
		best = data.best
	for i in range(sample_levels.size()):
		if best.has(sample_levels[i].id):
			sample_unlocked = maxi(sample_unlocked, mini(i + 1, sample_levels.size() - 1))
	assist = bool(data.get("assist", false))
	muted = bool(data.get("muted", false))
	reduced_motion = bool(data.get("reduced_motion", false))
	language = "en" if data.get("language") == "en" else "zh"

func save_progress() -> void:
	if not persistence_enabled:
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"unlocked": unlocked, "best": best, "assist": assist, "muted": muted, "reduced_motion": reduced_motion, "language": language}))
