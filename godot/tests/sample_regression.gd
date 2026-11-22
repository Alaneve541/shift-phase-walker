extends SceneTree

const DT = 1.0 / 60.0
var game
var scene
var checks = 0
var failures: Array = []

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
		if scene != null:
			scene.view._process(DT)
			scene._process(DT)

func input_action(action: String, down: bool) -> void:
	if scene == null:
		game.action(action, down)
	else:
		var keys = {"right": KEY_D, "left": KEY_A, "jump": KEY_SPACE, "shift": KEY_SHIFT}
		scene.smoke_key(keys[action], down)

func move_to(x: float) -> void:
	for i in range(360):
		var speed = clampf((x - game.p.x) * 6, -265, 265)
		input_action("right", speed > game.velocity.x + 15)
		input_action("left", speed < game.velocity.x - 15)
		step()
		if absf(game.p.x - x) < 3 and absf(game.velocity.x) < 20 or game.won:
			break
	input_action("right", false)
	input_action("left", false)
	step(8)

func hop_to(x: float) -> void:
	input_action("jump", true)
	for frame in range(160):
		if frame == 20:
			input_action("jump", false)
		var speed = clampf((x - game.p.x) * 6, -265, 265)
		input_action("right", speed > game.velocity.x + 15)
		input_action("left", speed < game.velocity.x - 15)
		step()
		if frame > 23 and game.grounded and absf(game.p.x - x) < 4 and absf(game.velocity.x) < 20:
			break
	input_action("jump", false)
	input_action("right", false)
	input_action("left", false)
	step(8)

func capture(title: String) -> void:
	if scene == null or DisplayServer.get_name() == "headless":
		return
	scene.view._camera = clampf(game.p.x - 390, 0, game.rows[0].length() * 36 - 960)
	await process_frame
	await RenderingServer.frame_post_draw
	var saved = root.get_texture().get_image().save_png("res://build/" + title + ".png")
	check(saved == OK, "native sample screenshot " + title)

func first_stage() -> void:
	move_to(295)
	step(180)
	check(game.relays[0].plates[0].active, "first amber plate powered")
	check(game.try_shift(), "first plate permits SHIFT")
	step(4)
	move_to(394)
	hop_to(475)
	await capture("sample-replay")
	move_to(710)
	check(game.p.x > 684, "first live door crossed using replay")
	move_to(940)
	check(game.checkpoints[0].active, "first checkpoint reached")

func second_stage() -> void:
	if game.world != 0:
		game.try_shift()
	step(4)
	move_to(1267)
	var recorded: Array = game.history.duplicate(true)
	var shifts: int = game.shifts
	check(not game.try_shift() and game.world == 0, "cannot leave static double inside LUN cage")
	check(game.history == recorded and game.shifts == shifts, "denied shift preserves recorded route and shift count")
	step(75)
	move_to(1350)
	check(game.try_shift(), "walk beyond plate then SHIFT in clear gap")
	step(4)
	hop_to(1530)
	await capture("sample-walk-away")
	move_to(1725)
	check(game.p.x > 1692, "second door crossed after past walk powers it")
	move_to(1930)
	check(game.checkpoints[1].active, "second checkpoint reached")

func last_stage() -> void:
	if game.world != 0:
		game.try_shift()
	step(4)
	move_to(2239)
	check(not game.try_shift(), "last floor plate also forbids static shift")
	step(90)
	move_to(2324)
	check(game.try_shift(), "final replay begins outside cage")
	step(4)
	hop_to(2455)
	check(game.grounded and absf(game.p.y + 26 - 396) < 0.1, "single jump reaches upper LUN plate")
	step(32)
	check(game.relays[2].plates.all(func(plate): return plate.active), "final solution lights both plates at the same time")
	await capture("sample-together")
	step(48)
	check(game.relays[2].open, "past SOL and present LUN latch final door together")
	hop_to(2540)
	move_to(game.portal.x)
	step(80)
	check(game.state == "win" and game.deaths == 0, "complete sample using controls and no teleports")
	check(game.collected == 3, "collect all three sample shards")
	await capture("sample-ending")

func shift_to(target: int) -> void:
	if game.world != target:
		input_action("shift", true)
		input_action("shift", false)
		step(4)
	check(game.world == target, "route SHIFT reaches world %d" % target)

func two_doors(pause_frames: int = 45) -> void:
	move_to(295)
	step(pause_frames)
	move_to(475)
	step(pause_frames)
	move_to(550)
	shift_to(1)
	move_to(1005)
	check(game.p.x > 936 and game.shifts == 1, "one moving replay crosses two timed doors without replacement")

func upstairs_pair(upper: float, lower: float, echo_world: int, gate_index: int) -> void:
	shift_to(echo_world)
	move_to(upper - 108)
	hop_to(upper)
	check(game.grounded and absf(game.p.y + 26 - 396) < 0.1, "reach raised recording plate with a single jump")
	step(135)
	shift_to(1 - echo_world)
	move_to(lower)
	check(game.relays[gate_index].plates.all(func(plate): return plate.active), "recorded high plate and present low plate light together")
	check(game.relays[gate_index].open, "height-separated pair latches its gate")

func jump_back_pair(upper: float, lower: float, echo_world: int, gate_index: int) -> void:
	shift_to(echo_world)
	move_to(upper - 108)
	hop_to(upper)
	check(game.grounded and absf(game.p.y + 26 - 396) < 0.1, "recording starts on a reachable raised plate")
	step(60)
	shift_to(1 - echo_world)
	check(game.echoes.size() == 1 and game.echoes[0].track.any(func(pose): return not pose.grounded), "replay preserves airborne frames of the recorded jump")
	move_to(lower)
	step(75)
	check(game.relays[gate_index].open, "returning left lets the recorded landing latch the door")

func three_doors(pause_frames: int = 20) -> void:
	for x in [259, 295, 367]:
		move_to(x)
		step(pause_frames)
	move_to(415)
	shift_to(1)
	move_to(1015)
	check(game.p.x > 900 and game.shifts == 1, "one replay opens three consecutive doors (%d-frame pauses, x=%.1f)" % [pause_frames, game.p.x])

func hop_shift_to(x: float) -> void:
	input_action("jump", true)
	for frame in range(160):
		if frame == 8:
			check(not game.grounded, "world change happens in midair")
			shift_to(1)
		if frame == 20:
			input_action("jump", false)
		var speed = clampf((x - game.p.x) * 6, -265, 265)
		input_action("right", speed > game.velocity.x + 15)
		input_action("left", speed < game.velocity.x - 15)
		step()
		if frame > 23 and game.grounded and absf(game.p.x - x) < 4 and absf(game.velocity.x) < 20:
			break
	input_action("jump", false)
	input_action("right", false)
	input_action("left", false)
	step(8)
	check(game.world == 1 and game.grounded and absf(game.p.y + 26 - 324) < 0.1, "air SHIFT lands on the higher blue stepping stone")

func expansion_route(index: int) -> void:
	game.start_sample(index)
	match index:
		1:
			two_doors()
			await capture("journey-02-two-doors")
		2:
			upstairs_pair(367, 619, 0, 0)
			move_to(970)
			check(game.checkpoints[0].active, "upstairs checkpoint reached")
			upstairs_pair(1231, 1447, 1, 1)
			await capture("journey-03-upstairs")
		3:
			move_to(1879)
			step(135)
			move_to(1800)
			shift_to(1)
			move_to(1380)
			check(game.checkpoints[1].active, "leftward route reaches first checkpoint")
			move_to(1231)
			step(135)
			move_to(1155)
			shift_to(0)
			move_to(979)
			check(game.relays[1].plates.all(func(plate): return plate.active), "leftward replay lights paired floor plates")
			move_to(700)
			check(game.checkpoints[0].active, "leftward route reaches second checkpoint")
			shift_to(1)
			move_to(295)
			await capture("journey-04-other-way")
			shift_to(0)
		4:
			move_to(295)
			step(135)
			move_to(380)
			shift_to(1)
			move_to(810)
			check(game.checkpoints[0].active, "day shift checkpoint reached")
			move_to(979)
			step(135)
			move_to(1080)
			shift_to(0)
			move_to(1500)
			check(game.checkpoints[1].active, "night shift checkpoint reached")
			move_to(1663)
			step(135)
			move_to(1738)
			shift_to(1)
			hop_to(1843)
			step(24)
			check(game.relays[2].plates.all(func(plate): return plate.active), "final handover lights high and low plates")
			await capture("journey-05-handover")
		5:
			two_doors()
			move_to(1100)
			check(game.checkpoints[1].active, "finale ticket checkpoint reached")
			upstairs_pair(1303, 1519, 0, 2)
			move_to(1870)
			check(game.checkpoints[2].active, "finale upper platform checkpoint reached")
			upstairs_pair(2095, 2311, 1, 3)
			await capture("journey-06-last-handover")
			move_to(2670)
			check(game.checkpoints[3].active, "finale train checkpoint reached")
			shift_to(1)
		6:
			jump_back_pair(511, 331, 0, 0)
			move_to(885)
			check(game.checkpoints[0].active, "jump replay checkpoint reached")
			jump_back_pair(1303, 1123, 1, 1)
			await capture("journey-07-recorded-jump")
		7:
			move_to(691)
			step(135)
			move_to(619)
			shift_to(1)
			move_to(367)
			check(game.relays[0].open, "return trip latches the first door")
			shift_to(0)
			check(game.relays[0].open, "replacing a double preserves the latched route")
			move_to(1060)
			check(game.checkpoints[0].active, "backtrack checkpoint reached")
			shift_to(1)
			move_to(1519)
			step(135)
			move_to(1447)
			shift_to(0)
			move_to(1195)
			check(game.relays[1].open, "reverse-colour return trip latches the second door")
			await capture("journey-08-come-back")
			shift_to(1)
		8:
			three_doors()
			await capture("journey-09-three-doors")
			move_to(1100)
			check(game.checkpoints[1].active, "three-door run checkpoint reached")
			shift_to(0)
			move_to(1663)
			step(135)
			move_to(1738)
			shift_to(1)
			hop_to(1879)
			step(24)
			check(game.relays[3].open, "three-door chapter ends with a paired landing")
		9:
			move_to(223)
			hop_to(331)
			check(game.grounded and absf(game.p.y + 26 - 396) < 0.1, "amber stepping stone is reachable with one jump")
			move_to(367)
			hop_shift_to(475)
			await capture("journey-10-air-shift")
			move_to(511)
			hop_to(655)
			check(game.checkpoints[0].active, "raised safe landing activates its checkpoint")
			move_to(810)
			check(game.checkpoints[2].active, "sunrise floor checkpoint reached")
			upstairs_pair(1087, 1303, 1, 0)
			check(game.world == 0 and game.portal_world == 0, "last destination is the SOL sunrise exit")
	move_to(game.portal.x - 11)
	step(80)
	check(game.state == "win" and game.deaths == 0, "chapter %d complete without teleport or retry (x=%.1f y=%.1f)" % [index + 1, game.p.x, game.p.y])
	check(game.collected == 3 and game.stars() == 3, "chapter %d all three shards and full rating" % [index + 1])
	check(game.best.has(game.current_level().id), "chapter %d has an independent record" % [index + 1])
	await capture("journey-%02d-ending" % (index + 1))

func check_expansion() -> void:
	check(game.sample_levels.size() == 10, "ten replay chapters including original sample")
	var ids: Dictionary = {}
	for index in range(game.sample_levels.size()):
		game.start_sample(index)
		var data: Dictionary = game.current_level()
		check(not ids.has(data.id), "unique score key: " + str(data.id))
		ids[data.id] = true
		check(game.rows.all(func(row): return row.length() == game.rows[0].length()), "chapter %d rectangular" % (index + 1))
		check(game.shards.size() == 3 and not game.double_jump_enabled, "chapter %d has three shards and single jump" % (index + 1))
		step(180)
		check(game.deaths == 0 and game.grounded, "chapter %d safe idle spawn" % (index + 1))
		for gate in game.relays:
			for plate in gate.plates:
				var at: Vector2 = plate.p - Vector2(11, 26)
				check(not game.rect_solid(Rect2(at, Vector2(22, 26)), plate.w), "plate has standing room in its world")
				check(game.rect_solid(Rect2(at + Vector2(0, 0.1), Vector2(22, 26)), plate.w), "plate has solid support in its world")
	var campaign_unlock: int = game.unlocked
	var original_best: Dictionary = game.best.get("sample_wait_for_me", {}).duplicate(true)
	for assisted in [false, true]:
		game.assist = assisted
		game.reduced_motion = assisted
		for index in range(1, game.sample_levels.size()):
			await expansion_route(index)
			check(game.sample_unlocked >= mini(index + 1, game.sample_levels.size() - 1), "new chapter completion unlocks the next stop")
			game.restart()
			check(game.sample_index == index and game.is_sample and game.collected == 0 and game.deaths == 0 and game.history_time == 0, "winning retry restarts current chapter, not first sample")
	check(game.unlocked == campaign_unlock and game.best.get("sample_wait_for_me", {}) == original_best, "expansion never overwrites campaign or original sample results")
	for pause_frames in [30, 60]:
		game.start_sample(1)
		two_doors(pause_frames)
		move_to(game.portal.x - 11)
		step(80)
		check(game.won and game.deaths == 0, "sequential doors tolerate %d-frame pauses" % pause_frames)
	for assisted in [false, true]:
		game.assist = assisted
		game.reduced_motion = assisted
		for pause_frames in [14, 26]:
			game.start_sample(8)
			three_doors(pause_frames)
			check(game.deaths == 0, "three-door timing tolerates %d-frame pauses" % pause_frames)
	game.start_sample(9)
	move_to(223)
	var pit_spawn: Vector2 = game.spawn.p
	input_action("right", true)
	for frame in range(90):
		step()
		if game.dead_timer > 0:
			break
	input_action("right", false)
	check(game.deaths == 1 and game.echoes.is_empty(), "falling into the new gap clears the recording")
	step(50)
	check(game.p.distance_to(pit_spawn) < 1 and game.world == 0, "gap death returns to the safe SOL checkpoint")
	move_to(223)
	hop_to(331)
	move_to(367)
	hop_shift_to(475)
	move_to(511)
	hop_to(655)
	var high_spawn: Vector2 = game.spawn.p
	var high_shards: int = game.collected
	move_to(687)
	game.restart()
	check(game.p == high_spawn and game.world == 1 and game.sample_index == 9, "raised checkpoint retry preserves LUN and chapter ten")
	step(90)
	check(game.grounded and absf(game.p.y + 26 - 324) < 0.1 and game.collected == high_shards, "raised checkpoint remains supported and preserves collected shards")
	game.start_sample(3)
	move_to(1879)
	step(135)
	move_to(1800)
	shift_to(1)
	move_to(1380)
	var saved_spawn: Vector2 = game.spawn.p
	var saved_time: float = game.elapsed
	move_to(1340)
	var saved_shards: int = game.collected
	game.restart()
	check(game.sample_index == 3 and game.p == saved_spawn and game.world == 1, "reverse checkpoint retry keeps correct chapter and world")
	check(game.deaths == 1 and game.elapsed >= saved_time and game.collected == saved_shards, "new chapter retry preserves elapsed and shards")
	check(game.echoes.is_empty() and game.history_time == 0, "new chapter retry resets stale recording")
	game.start_sample(5)
	check(game.shards.all(func(shard): return not shard.taken) and game.relays.all(func(gate): return not gate.open), "changing chapters resets gates and collectibles")
	game.start_level(0)
	check(not game.is_sample and game.history.is_empty() and game.sample_unlocked == 9, "returning to campaign preserves ten-stop progress")

func run() -> void:
	if "--sample-tour" in OS.get_cmdline_user_args():
		scene = load("res://main.tscn").instantiate()
		game = scene.get_node("Game")
		game.persistence_enabled = false
		root.add_child(scene)
		scene.test_mode = true
		game.language = "zh"
	else:
		game = load("res://scripts/game.gd").new()
		game.persistence_enabled = false
		root.add_child(game)
	game.start_sample()
	check(game.levels.size() == 9 and game.is_sample, "sample separate from nine-level campaign")
	check(game.rows.size() == 15 and not game.double_jump_enabled, "sample is a single-jump puzzle")
	for row in game.rows:
		check(row.length() == 80, "sample map rectangular")
	step(180)
	check(game.deaths == 0, "sample idle spawn safe")
	input_action("jump", true)
	step(5)
	input_action("jump", false)
	input_action("jump", true)
	step()
	check(game.velocity.y > -250 and game.air_jump_ready, "sample has no midair jump")
	game.start_sample()
	game.best = {"0": {"stars": 2, "time": 12.5}}
	game.unlocked = 0
	var campaign_best: Dictionary = game.best.duplicate(true)
	var unlocked: int = game.unlocked
	await first_stage()
	await second_stage()
	await last_stage()
	check(game.best.has("sample_wait_for_me") and game.unlocked == unlocked, "sample result never unlocks campaign")
	for key in game.best:
		if key != "sample_wait_for_me":
			check(game.best[key] == campaign_best.get(key), "sample preserves campaign record")
	var end_time: float = game.elapsed
	step(120)
	check(game.elapsed == end_time, "sample result time frozen")
	game.restart()
	check(game.is_sample and not game.checkpoint_active and game.deaths == 0, "restart after winning resets sample")
	move_to(295)
	step(240)
	check(game.history.size() <= 183, "recording memory bounded at three seconds")
	move_to(440)
	var shift_position: Vector2 = game.p
	game.try_shift()
	check(game.echoes.size() == 1 and game.echoes[0].p.x < shift_position.x - 100, "double begins in the past, not at SHIFT position")
	step(30)
	var old_position: Vector2 = game.echoes[0].p
	step(130)
	check(game.echoes[0].p.x > old_position.x + 10, "double replays recorded movement")
	game.set_state("pause")
	var frozen_history: Array = game.history.duplicate(true)
	var frozen_echo: Array = game.echoes.duplicate(true)
	var paused_time: float = game.elapsed
	step(120)
	check(game.history == frozen_history and game.echoes == frozen_echo and game.elapsed == paused_time, "pause freezes record, replay and time")
	game.set_state("play")
	step(40)
	check(game.echoes.is_empty(), "replay expires after three seconds")
	step(50)
	check(not game.relays[0].open, "momentary door closes after release grace")
	game.try_shift()
	step(20)
	game.try_shift()
	check(game.echoes.size() == 1 and game.echoes[0].w == 0, "next SHIFT replaces old double")
	game.die()
	check(game.echoes.is_empty() and game.history.is_empty(), "death clears replay and recording")
	step(65)
	check(not game.history.is_empty() and game.is_sample and game.world == 0, "respawn starts a fresh single-world recording")
	game.start_sample()
	await first_stage()
	var checkpoint_spawn: Vector2 = game.spawn.p
	var elapsed: float = game.elapsed
	move_to(1050)
	game.restart()
	check(game.p == checkpoint_spawn and game.world == game.spawn.world, "retry restores checkpoint position and world")
	check(game.deaths == 1 and game.elapsed >= elapsed and game.is_sample, "checkpoint retry keeps honest elapsed time and counts retry")
	check(game.echoes.is_empty() and game.history_time == 0, "retry discards stale replay")
	game.start_sample()
	game.p = Vector2(18 * 36 + 4, 442)
	game.relays[0].open = true
	game.update_relays(1.0)
	check(game.relays[0].open, "closing hold door cannot crush occupying player")
	game.p.x = 710
	game.update_relays(1.0)
	check(not game.relays[0].open, "door closes once player clears it")
	game.start_sample()
	game.p = Vector2(295, 350)
	game.grounded = false
	game.reset_history()
	game.try_shift()
	step(4)
	check(not game.relays[0].plates[0].active, "airborne recorded double cannot press floor plate")
	game.start_sample()
	game.reduced_motion = true
	game.assist = true
	await first_stage()
	await second_stage()
	await last_stage()
	check(game.state == "win", "sample remains solvable with reduced motion and assist")
	game.start_level(8)
	check(not game.is_sample and game.double_jump_enabled and game.history.is_empty(), "campaign returns to original jump and static double rules")
	step(3)
	move_to(211)
	game.try_shift()
	check(not game.echoes[0].has("track"), "original final puzzle keeps static doubles")
	await check_expansion()
	if scene != null:
		scene.free()
	else:
		game.free()
	print("SAMPLE_REGRESSION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
