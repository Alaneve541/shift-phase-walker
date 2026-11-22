extends SceneTree

var game
var failures: Array = []
var checks = 0
const DT = 1.0 / 60.0
const ROUTES = {
	5: [[259,0,1],[439,1,0],[619,0,0],[691,0,0],[799,1,1],[979,0,0],[1190,1,0],[1411,1,0]],
	6: [[259,0,0],[439,1,1],[709,0,1],[925,1,1],[1087,0,1],[1267,0,1],[1483,1,1,30],[1711,0,0],[1789,0,0]],
	7: [[223,1,1],[475,0,1,30],[655,0,1],[799,1,0],[943,0,0],[1051,0,0],[1303,1,0],[1519,0,1,0],[1735,0,0],[1879,0,0]]
}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func step(count: int = 1) -> void:
	for i in range(count):
		game.tick(DT)

func move_to(x: float) -> void:
	var dir = 1 if game.p.x < x else -1
	var key = "right" if dir > 0 else "left"
	game.action(key, true)
	for i in range(350):
		if (x - game.p.x) * dir <= 0 or game.dead_timer > 0 or game.won:
			break
		step()
	game.action(key, false)
	step(12)

func leave_echo() -> void:
	game.start_level(8)
	step(3)
	move_to(211)
	game.try_shift()
	step(4)

func hop(first: int, second: int, row: int) -> void:
	game.action("right", true)
	game.action("jump", true)
	step(first)
	game.action("jump", false)
	game.action("jump", true)
	step(second)
	game.action("right", false)
	for i in range(120):
		if game.grounded or game.dead_timer > 0:
			break
		step()
	game.action("jump", false)
	step(12)
	check(game.grounded and absf(game.p.y + 26 - row * 36) < 0.02, "level 5 landed on row %d" % row)
	check(game.air_jump_ready, "landing recharges jump")

func single_hop(x: float, target_world: int, shift_frame: int = 10) -> void:
	game.action("jump", true)
	for frame in range(160):
		if frame == 20:
			game.action("jump", false)
		if frame == shift_frame and game.world != target_world:
			game.try_shift()
		var speed = clampf((x - game.p.x) * 6, -265, 265)
		game.action("right", speed > game.velocity.x + 15)
		game.action("left", speed < game.velocity.x - 15)
		step()
		if game.dead_timer > 0 or game.won:
			break
		if frame > 23 and game.grounded and absf(game.p.x - x) < 5 and absf(game.velocity.x) < 20:
			break
	game.action("jump", false)
	game.action("left", false)
	game.action("right", false)

func run() -> void:
	game = load("res://scripts/game.gd").new()
	game.persistence_enabled = false
	root.add_child(game)
	check(game.levels.size() == 9, "nine levels imported")
	for level in range(9):
		game.start_level(level)
		check(game.rows.size() == 15, "15 map rows in level %d" % (level + 1))
		for row in game.rows:
			check(row.length() == game.rows[0].length(), "rectangular level %d" % (level + 1))
		step(180)
		check(game.deaths == 0, "idle spawn safe level %d" % (level + 1))
		game.start_level(level)
		game.action("jump", true)
		step()
		check(game.air_jump_ready, "immediate ground jump does not consume reserve")
		game.action("jump", false)
		step(3)
		game.action("jump", true)
		step()
		check((game.velocity.y < -450) == (level >= 4), "double jump unlock at level 5")
	game.start_level(0)
	game.action("right", true)
	var shifted = false
	var jumping = false
	for i in range(600):
		if game.won:
			break
		if not shifted and game.p.x > 330:
			game.try_shift()
			shifted = true
		var jump = (game.p.x > 368 and game.p.x < 460) or (game.p.x > 690 and game.p.x < 780)
		if jump != jumping:
			game.action("jump", jump)
			jumping = jump
		step()
	check(game.won and game.deaths == 0 and game.collected == 2, "level 1 keyboard clear with all shards")
	game.start_level(1)
	move_to(166)
	for target in [[295,0],[439,1],[583,0],[745,1],[763,1]]:
		single_hop(target[0], target[1])
	move_to(807)
	single_hop(1027, 1)
	move_to(1170)
	step(80)
	check(game.state == "win" and game.deaths == 0 and game.collected == 4, "level 2 full collection single-jump staircase")
	game.start_level(2)
	move_to(172)
	single_hop(295, 1, 0)
	move_to(435)
	single_hop(547, 0, 0)
	move_to(667)
	single_hop(799, 1, 0)
	move_to(894)
	single_hop(951, 1)
	move_to(game.portal.x)
	step(80)
	check(game.state == "win" and game.deaths == 0 and game.collected == 3, "level 3 full collection avoiding world spikes")
	game.start_level(3)
	move_to(243)
	single_hop(403, 1, 0)
	move_to(456)
	single_hop(619, 0, 0)
	move_to(789)
	single_hop(943, 1, 0)
	single_hop(967, 0, 0)
	move_to(1120)
	single_hop(1223, 0)
	move_to(game.portal.x)
	step(80)
	check(game.state == "win" and game.deaths == 0 and game.collected == 4, "level 4 full collection through phase walls")
	game.start_level(4)
	game.action("jump", true)
	step(8)
	game.action("jump", true, "other-key")
	check(game.air_jump_ready, "overlapping jump inputs do not consume reserve")
	game.action("jump", false)
	check(not game.jump_sources.is_empty(), "releasing one key preserves held jump")
	game.action("jump", false, "other-key")
	game.action("jump", true)
	step(8)
	check(not game.air_jump_ready, "second jump consumes reserve")
	game.action("jump", false)
	game.action("jump", true)
	step()
	check(game.velocity.y > -200, "third jump denied")
	game.try_shift()
	step(5)
	check(not game.air_jump_ready, "shift does not recharge jump")
	game.action("jump", false)
	step(150)
	check(game.grounded and game.air_jump_ready, "landing restores reserve")
	game.start_level(4)
	game.p.y = 290
	game.grounded = false
	game.coyote = 0
	game.velocity.y = 300
	game.action("jump", true)
	step()
	check(game.velocity.y < -450 and not game.air_jump_ready, "falling rescue jump")
	game.start_level(4)
	game.p.y = 360
	game.grounded = false
	game.coyote = 0.08
	game.action("jump", true)
	step()
	check(game.air_jump_ready and game.velocity.y < -500, "coyote jump preserves reserve")
	game.start_level(4)
	game.p.x = 320
	game.action("jump", true)
	step(3)
	game.action("jump", false)
	game.action("jump", true)
	var ceiling = false
	for i in range(12):
		step()
		if not game.grounded and game.velocity.y == 0:
			ceiling = true
			break
	check(ceiling and not game.air_jump_ready, "ceiling does not recharge jump")
	game.start_level(4)
	move_to(196)
	hop(16, 11, 10)
	move_to(372)
	hop(23, 29, 8)
	move_to(647)
	hop(23, 26, 10)
	move_to(937)
	hop(23, 15, 8)
	move_to(1123)
	move_to(1370)
	step(80)
	check(game.state == "win" and game.collected == 4 and game.deaths == 0, "level 5 four platforms, all shards, no deaths")
	for level in [5, 6, 7]:
		game.start_level(level)
		step(3)
		for target in ROUTES[level]:
			game.action("jump", true)
			for frame in range(160):
				if frame == 20:
					game.action("jump", false)
				if frame == 22 and target[2]:
					game.action("jump", true)
				var shift_frame = target[3] if target.size() > 3 else 10
				if frame == shift_frame and game.world != target[1]:
					game.try_shift()
				var speed = clampf((target[0] - game.p.x) * 6, -265, 265)
				game.action("right", speed > game.velocity.x + 15)
				game.action("left", speed < game.velocity.x - 15)
				step()
				if game.dead_timer > 0 or game.won:
					break
				if frame > 23 and game.grounded and absf(game.p.x - target[0]) < 5 and absf(game.velocity.x) < 20:
					break
			game.action("jump", false)
		game.action("right", false)
		game.action("left", false)
		step(80)
		check(game.state == "win" and game.deaths == 0 and game.collected == game.shards.size(), "level %d all shards / zero deaths" % (level + 1))
		check(game.checkpoint_active and game.spawn.p.x > 600, "later-level checkpoint activated")
		var saved: Vector2 = game.spawn.p
		var saved_world: int = game.spawn.world
		game.won = false
		game.set_state("play")
		game.die()
		step(65)
		check(game.world == saved_world and game.p.distance_to(saved) < 1 and game.air_jump_ready, "checkpoint respawn restores world and jump")
	leave_echo()
	check(game.echoes.size() == 1 and game.echoes[0].w == 0, "shift leaves SOL double")
	move_to(427)
	check(game.relays[0].open, "first relay unlocked")
	move_to(787)
	game.try_shift()
	step(4)
	move_to(1003)
	check(game.relays[1].open, "second relay unlocked")
	move_to(1330)
	step(80)
	check(game.state == "win" and game.deaths == 0 and game.shifts == 2, "final puzzle completed using two doubles")
	var finish_time: float = game.elapsed
	step(120)
	check(game.elapsed == finish_time, "win animation freezes recorded time")
	leave_echo()
	var remaining: float = game.echoes[0].life
	var pause_time: float = game.elapsed
	game.action("right", true)
	game.set_state("pause")
	game.action("jump", true)
	step(300)
	check(game.echoes[0].life == remaining and game.elapsed == pause_time and game.held.is_empty() and game.jump_sources.is_empty(), "pause freezes timers and releases input")
	game.set_state("play")
	step(200)
	move_to(427)
	check(game.echoes.is_empty() and not game.relays[0].open, "expired double cannot open gate")
	move_to(700)
	check(game.p.x + 22 <= 16 * 36, "closed gate blocks movement")
	leave_echo()
	game.die()
	check(game.echoes.is_empty(), "death removes double")
	step(65)
	check(game.dead_timer <= 0 and game.world == 0 and game.air_jump_ready, "spawn reset")
	game.start_level(8)
	check(game.relays.all(func(g): return not g.open) and game.echoes.is_empty(), "restart clears gate state")
	game.start_level(8)
	step(3)
	move_to(211)
	game.action("jump", true)
	step(10)
	game.try_shift()
	step(4)
	check(not game.relays[0].plates[0].active, "floating double does not press plate")
	for timing in [10, 18, 23, 28, 35]:
		game.start_level(8)
		move_to(468)
		game.action("right", true)
		game.action("jump", true)
		step(timing)
		game.action("jump", false)
		game.action("jump", true)
		step(100)
		check(not game.relays[0].open and game.p.x + 22 <= 16 * 36, "double jump cannot skip final gate")
	game.start_level(3)
	step(3)
	game.try_shift()
	step(30)
	game.p = Vector2(293, 360)
	game.try_shift()
	check(game.world == 1 and game.shifts == 1, "cannot shift into a wall")
	game.start_level(2)
	game.p = Vector2(225, 424)
	step()
	check(game.dead_timer > 0, "spikes collide normally")
	game.assist = true
	game.start_level(2)
	game.p = Vector2(225, 424)
	step()
	check(game.dead_timer <= 0, "assist relaxes spike hitboxes")
	game.free()
	print("GODOT_REGRESSION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
