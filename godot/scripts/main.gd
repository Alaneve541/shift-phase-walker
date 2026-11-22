extends Control

const SAMPLE_PAGE_SIZE = 6
const INSTRUCTIONS = [
	["此界无路，彼界有桥。按 SHIFT 找到能站住的那一边。", "A bridge missing here exists in the other world. Press SHIFT."],
	["向上爬。每一级楼梯都可能在另一个世界。", "Climb the alternating stairs. Read the ghost platforms before you shift."],
	["尖刺只伤害它所在世界的你。颜色比速度更重要。", "Spikes only hurt in their own world. Watch their color, not just your feet."],
	["墙壁也分世界。身体与另一侧的墙重叠时，不能切换。", "Walls belong to worlds, too. You cannot shift into solid matter."],
	["新能力：二段跳。空中松开空格，再按一次；落地恢复。", "DOUBLE JUMP unlocked. Release and press jump again in midair. Land to recharge."],
	["二段跳够到高台，SHIFT 找到落点。绿色旗帜是检查点。", "Combine double jump and SHIFT. Green beacons save your respawn point."],
	["别急着用掉第二跳。它也可以在下落时救你一次。", "Save your second jump: it can rescue you while falling, too."],
	["快到出口了。先找检查点，再决定从哪个世界走。", "One last climb. Find the checkpoint, then choose your way through."],
	["站上踏板后切换，留下三秒分身。赶到另一块踏板，一起开门。", "SHIFT on a plate to leave a 3-second double. Reach its partner to open the gate."]
]

@onready var game = $Game
@onready var view = $View/World
@onready var sound = $Sound
var font: SystemFont
var ui_theme: Theme
var overlay: Control
var overlay_box: VBoxContainer
var overlay_panel: PanelContainer
var overlay_margin: MarginContainer
var menu_backdrop: Control
var hud: Control
var hud_values: Array[Label] = []
var world_badge: Panel
var tip_panel: Panel
var toast_panel: Panel
var menu_tween: Tween
var hud_world = -1
var level_label: Label
var world_label: Label
var hint_label: Label
var tip_label: Label
var toast_label: Label
var toast_time = 0.0
var overlay_mode = ""
var sample_page = 0
var test_mode = false
var keyboard_active = false
var hud_buttons: Array = []

func _ready() -> void:
	test_mode = "--smoke-test" in OS.get_cmdline_user_args() or "--sample-smoke" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args()
	if test_mode:
		game.persistence_enabled = false
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans SC", "Microsoft YaHei", "Arial"])
	ui_theme = make_theme()
	theme = ui_theme
	view.setup(game, font)
	sound.setup(game)
	build_ui()
	game.state_changed.connect(update_state)
	game.level_loaded.connect(on_level_loaded)
	game.effect.connect(on_effect)
	show_title()
	if test_mode:
		call_deferred("run_sample_smoke" if "--sample-smoke" in OS.get_cmdline_user_args() else "run_smoke_test")

func tr_text(zh: String, en: String) -> String:
	return zh if game.language == "zh" else en

func panel_style(fill: Color, border: Color, radius: int = 12) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

func make_theme() -> Theme:
	var result = Theme.new()
	result.default_font = font
	result.default_font_size = 15
	result.set_color("font_color", "Label", Color("ecebdc"))
	for button_state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style = panel_style(Color("14252d"), Color("2e454b"), 9)
		if button_state == "hover":
			style.bg_color = Color("213b40")
			style.border_color = Color("86c6b8")
		elif button_state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("c6e8d9")
			style.set_border_width_all(2)
		elif button_state == "pressed":
			style.bg_color = Color("31534e")
		elif button_state == "disabled":
			style.bg_color = Color("101e26")
			style.border_color = Color("24363e")
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		result.set_stylebox(button_state, "Button", style)
	result.set_color("font_color", "Button", Color("e7ebe1"))
	result.set_color("font_hover_color", "Button", Color("ffffff"))
	result.set_color("font_disabled_color", "Button", Color("78888d"))
	return result

func primary_button(button: Button) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal", "hover", "pressed"]:
		var style = panel_style(Color("bfddcd") if state == "normal" else Color("e8e6ce"), Color("d2e9d9"), 5)
		style.content_margin_left = 24
		style.content_margin_right = 64
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.24)
		style.shadow_size = 8
		style.shadow_offset = Vector2(0, 4)
		if state == "pressed":
			style.bg_color = Color("97c6b5")
			style.shadow_size = 0
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("122e2e"))
	button.draw.connect(func():
		var edge: float = button.size.x - 52
		for y in range(8, int(button.size.y) - 7, 6):
			button.draw_line(Vector2(edge, y), Vector2(edge, y + 3), Color(0.07, 0.18, 0.18, 0.28), 1.0)
		var center := Vector2(button.size.x - 26, button.size.y * 0.5)
		button.draw_line(center - Vector2(7, 0), center + Vector2(7, 0), Color("244b44"), 1.5, true)
		button.draw_polyline(PackedVector2Array([center + Vector2(2, -5), center + Vector2(7, 0), center + Vector2(2, 5)]), Color("244b44"), 1.5, true)
	)

func place_label(parent: Control, text: String, at: Vector2, font_size: int, color: Color = Color("ecebdc")) -> Label:
	var label = make_label(text, font_size, color)
	label.position = at
	parent.add_child(label)
	return label

func rule(parent: Control, at: Vector2, width: float, color: Color = Color("2c4147")) -> void:
	var line = ColorRect.new()
	line.position = at
	line.size = Vector2(width, 1)
	line.color = color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func spacer(height: float) -> void:
	var space = Control.new()
	space.custom_minimum_size.y = height
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_box.add_child(space)

func make_label(text: String, font_size: int = 16, color: Color = Color("e2e9f2")) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func make_button(text: String, callback: Callable, minimum: Vector2 = Vector2(0, 38)) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.pressed.connect(callback)
	button.mouse_entered.connect(func(): keyboard_active = false)
	return button

func build_ui() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	var top = ColorRect.new()
	top.color = Color("0b171f")
	top.size = Vector2(960, 64)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	rule(hud, Vector2(0, 63), 960)
	world_badge = Panel.new()
	world_badge.position = Vector2(20, 12)
	world_badge.size = Vector2(128, 40)
	world_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(world_badge)
	world_label = place_label(world_badge, "", Vector2(0, 9), 15)
	world_label.size.x = 128
	world_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label = place_label(hud, "", Vector2(168, 12), 12, Color("ced8d3"))
	level_label.size = Vector2(328, 42)
	level_label.clip_text = true
	for i in range(3):
		var value = place_label(hud, "", Vector2(524 + i * 88, 8), 10, Color("839b9e"))
		value.size = Vector2(82, 48)
		hud_values.append(value)
	var restart = make_button("R", func(): game.restart(), Vector2(40, 36))
	restart.name = "HudRestart"
	restart.position = Vector2(800, 14)
	restart.tooltip_text = "Restart / 重开"
	hud.add_child(restart)
	hud_buttons.append(restart)
	var pause = make_button("II", toggle_pause, Vector2(40, 36))
	pause.position = Vector2(850, 14)
	pause.tooltip_text = "Pause / 暂停 (Esc)"
	hud.add_child(pause)
	hud_buttons.append(pause)
	var mute = make_button("M", toggle_sound, Vector2(40, 36))
	mute.position = Vector2(900, 14)
	mute.tooltip_text = "Sound / 声音 (M)"
	hud.add_child(mute)
	hud_buttons.append(mute)
	for button in hud_buttons:
		button.focus_mode = Control.FOCUS_NONE
	var bottom = ColorRect.new()
	bottom.position = Vector2(0, 604)
	bottom.size = Vector2(960, 36)
	bottom.color = Color("0b171f")
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bottom)
	rule(hud, Vector2(0, 604), 960)
	hint_label = place_label(hud, "", Vector2(22, 614), 11, Color("91a7aa"))
	tip_panel = Panel.new()
	tip_panel.position = Vector2(140, 78)
	tip_panel.size = Vector2(680, 48)
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.add_theme_stylebox_override("panel", panel_style(Color(0.04, 0.09, 0.12, 0.9), Color("2e464b"), 10))
	hud.add_child(tip_panel)
	tip_label = place_label(tip_panel, "", Vector2(20, 7), 12, Color("cbd9d2"))
	tip_label.size = Vector2(640, 34)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_panel = Panel.new()
	toast_panel.position = Vector2(310, 140)
	toast_panel.size = Vector2(340, 36)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_theme_stylebox_override("panel", panel_style(Color("193834"), Color("49796b"), 18))
	hud.add_child(toast_panel)
	toast_label = place_label(toast_panel, "", Vector2(8, 7), 13, Color("c0e9cc"))
	toast_label.size = Vector2(324, 24)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	menu_backdrop = load("res://scripts/ui_backdrop.gd").new()
	menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(menu_backdrop)
	overlay_panel = PanelContainer.new()
	overlay_panel.draw.connect(func():
		if overlay_mode == "title":
			return
		var width: float = overlay_panel.size.x
		var height: float = overlay_panel.size.y
		overlay_panel.draw_line(Vector2(24, 10), Vector2(width * 0.5 - 4, 10), Color("bd9767"), 2.0)
		overlay_panel.draw_line(Vector2(width * 0.5 + 4, 10), Vector2(width - 24, 10), Color("82b9aa"), 2.0)
		for x in range(28, int(width) - 27, 8):
			overlay_panel.draw_line(Vector2(x, height - 12), Vector2(x + 3, height - 12), Color("30484b"), 1.0)
	)
	overlay.add_child(overlay_panel)
	overlay_margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		overlay_margin.add_theme_constant_override("margin_" + side, 24)
	overlay_panel.add_child(overlay_margin)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overlay_margin.add_child(scroll)
	overlay_box = VBoxContainer.new()
	overlay_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_box.add_theme_constant_override("separation", 10)
	scroll.add_child(overlay_box)
	if DisplayServer.is_touchscreen_available():
		build_touch_controls()

func build_touch_controls() -> void:
	var buttons = [["<", "left", Vector2(22, 537)], [">", "right", Vector2(105, 537)], ["SHIFT", "shift", Vector2(752, 537)], ["^", "jump", Vector2(861, 537)]]
	for entry in buttons:
		var button = Button.new()
		button.text = entry[0]
		button.position = entry[2]
		button.size = Vector2(76 if entry[1] != "shift" else 98, 56)
		button.focus_mode = Control.FOCUS_NONE
		button.modulate.a = 0.75
		button.button_down.connect(func(): game.action(entry[1], true, "touch-" + entry[1]))
		button.button_up.connect(func(): game.action(entry[1], false, "touch-" + entry[1]))
		hud.add_child(button)

func clear_overlay(mode: String) -> void:
	var entering = not overlay.visible or overlay_mode != mode
	overlay_mode = mode
	for child in overlay_box.get_children():
		overlay_box.remove_child(child)
		child.queue_free()
	var bounds = Rect2(164, 86, 632, 468)
	if mode == "title":
		bounds = Rect2(24, 16, 912, 608)
	elif mode == "chapters" or mode == "sample_chapters":
		bounds = Rect2(80, 66, 800, 508)
	elif mode == "win":
		bounds = Rect2(148, 96, 664, 448)
	overlay_panel.custom_minimum_size = bounds.size
	overlay_panel.position = bounds.position
	overlay_panel.size = bounds.size
	var style = panel_style(Color("101f27"), Color("42595b"), 16)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 24
	if mode == "title":
		style = panel_style(Color.TRANSPARENT, Color.TRANSPARENT, 0)
	overlay_panel.add_theme_stylebox_override("panel", style)
	overlay_panel.queue_redraw()
	menu_backdrop.mode = mode
	menu_backdrop.queue_redraw()
	if menu_tween != null:
		menu_tween.kill()
	overlay_panel.modulate.a = 1
	if entering and not game.reduced_motion and not test_mode:
		overlay_panel.modulate.a = 0
		menu_tween = create_tween()
		menu_tween.tween_property(overlay_panel, "modulate:a", 1.0, 0.18)
	overlay.show()
	hud.visible = mode != "title" and mode != "chapters" and mode != "sample_chapters"

func heading(eyebrow: String, title: String, subtitle: String) -> void:
	var small = make_label(eyebrow, 10, Color("baaa86"))
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(small)
	var large = make_label(title, 32 if game.language == "en" else 34)
	large.name = "OverlayTitle"
	large.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(large)
	var text = make_label(subtitle, 13, Color("9eb5b4"))
	text.name = "OverlaySubtitle"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_box.add_child(text)

func result_metrics() -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	overlay_box.add_child(row)
	var titles = [tr_text("旅途用时", "TRAVEL TIME"), tr_text("收集碎片", "SHARDS"), tr_text("失误次数", "RETRIES"), tr_text("世界切换", "SHIFTS")]
	var values = [format_time(game.elapsed), "%d / %d" % [game.collected, game.shards.size()], str(game.deaths), str(game.shifts)]
	for i in range(4):
		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 84)
		card.add_theme_stylebox_override("panel", panel_style(Color("152a30"), Color("30484b"), 8))
		row.add_child(card)
		var box = VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 6)
		card.add_child(box)
		var caption = make_label(titles[i], 10, Color("8fabac"))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(caption)
		var value = make_label(values[i], 23, Color("d6e7d6") if i != 1 else Color("efd1a8"))
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(value)

func show_title() -> void:
	if game.state != "title":
		game.set_state("title")
		return
	clear_overlay("title")
	var page = Control.new()
	page.custom_minimum_size = Vector2(864, 556)
	overlay_box.add_child(page)
	place_label(page, "S / S     SHIFT STATION", Vector2(0, 0), 12, Color("b7d6c7"))
	place_label(page, "GAME OFF 2026     /     A GAME ABOUT SHIFT", Vector2(552, 0), 10, Color("8b9f9f"))
	rule(page, Vector2(0, 30), 864)
	place_label(page, tr_text("双 界 行 者", "P H A S E   W A L K E R"), Vector2(2, 63), 15, Color("d2b28d"))
	var logo = place_label(page, "SHIFT", Vector2(-5, 78), 94)
	logo.add_theme_constant_override("outline_size", 1)
	place_label(page, tr_text("换个世界，和自己一起出发。", "Another world. The same you."), Vector2(2, 196), 21)
	var copy = place_label(page, tr_text("让刚才的你，替现在的你留一扇门。\n两个世界之间，总有一条回家的路。", "Let your past self hold the door.\nFind a way home between two worlds."), Vector2(2, 237), 14, Color("a0b3b2"))
	copy.add_theme_constant_override("line_spacing", 6)
	var route = Panel.new()
	route.position = Vector2(510, 66)
	route.size = Vector2(354, 30)
	route.mouse_filter = Control.MOUSE_FILTER_IGNORE
	route.add_theme_stylebox_override("panel", panel_style(Color(0.04, 0.09, 0.12, 0.85), Color("46615b"), 4))
	page.add_child(route)
	place_label(route, "SOL  /  DAY", Vector2(14, 8), 10, Color("edc39a"))
	place_label(route, "←  03 SEC  →", Vector2(137, 8), 10, Color("d2d8c7"))
	place_label(route, "LUN  /  NIGHT", Vector2(257, 8), 10, Color("a9d9d1"))
	var demo = make_button(sample_journey_title(), func(): game.start_sample(game.sample_unlocked), Vector2(370, 56))
	demo.name = "DemoStart"
	demo.position = Vector2(0, 313)
	demo.add_theme_font_size_override("font_size", 17)
	primary_button(demo)
	page.add_child(demo)
	var start = make_button(tr_text("原版九关 · 开始旅程" if game.unlocked == 0 else "原版九关 · 继续旅程", "ORIGINAL JOURNEY · BEGIN" if game.unlocked == 0 else "ORIGINAL JOURNEY · CONTINUE"), func(): game.start_level(game.unlocked), Vector2(370, 44))
	start.name = "CampaignStart"
	start.position = Vector2(0, 379)
	page.add_child(start)
	var maps = [
		["SampleChapterSelect", tr_text("等我一下   /   %d 站地图   →", "WAIT FOR ME   /   %02d STOPS   →") % game.sample_levels.size(), show_sample_chapters],
		["ChapterSelect", tr_text("原版地图   /   09 个关卡   →", "ORIGINAL MAP   /   09 CHAPTERS   →"), show_chapters]
	]
	for i in range(maps.size()):
		var chapters = make_button(maps[i][1], maps[i][2], Vector2(370, 28))
		chapters.name = maps[i][0]
		chapters.position = Vector2(0, 435 + i * 30)
		chapters.add_theme_font_size_override("font_size", 12)
		for state in ["normal", "hover", "pressed", "focus"]:
			var style: StyleBoxFlat = ui_theme.get_stylebox(state, "Button").duplicate()
			style.content_margin_top = 4
			style.content_margin_bottom = 4
			if state == "normal":
				style.bg_color = Color.TRANSPARENT
				style.border_color = Color.TRANSPARENT
			chapters.add_theme_stylebox_override(state, style)
		page.add_child(chapters)
	rule(page, Vector2(0, 499), 864)
	var options = HBoxContainer.new()
	options.position = Vector2(0, 515)
	options.add_theme_constant_override("separation", 8)
	page.add_child(options)
	var language = make_button("English" if game.language == "zh" else "简体中文", toggle_language, Vector2(88, 32))
	language.name = "TitleLanguage"
	options.add_child(language)
	var audio = make_button(tr_text("声音  关" if game.muted else "声音  开", "Sound  OFF" if game.muted else "Sound  ON"), toggle_sound, Vector2(106, 32))
	audio.name = "TitleSound"
	options.add_child(audio)
	options.add_child(make_button(tr_text("退出", "Quit"), func(): get_tree().quit(), Vector2(65, 32)))
	place_label(page, "ALANEVE541   /   QODER + MEOWA", Vector2(600, 519), 10, Color("99b2ad"))
	place_label(page, "GODOT NATIVE  ·  AI ASSISTED  ·  2026", Vector2(600, 536), 9, Color("718e8c"))
	demo.grab_focus()

func show_chapters() -> void:
	clear_overlay("chapters")
	heading("THE ORIGINAL JOURNEY  /  09 STOPS", tr_text("下一站，去哪里？", "CHOOSE YOUR NEXT STOP"), tr_text("从学会切换，到和过去的自己并肩。", "From your first SHIFT to working with your past self."))
	spacer(4)
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	overlay_box.add_child(grid)
	for i in range(game.levels.size()):
		var name_text: String = game.levels[i].name if game.language == "zh" else game.levels[i].en.capitalize()
		var score: Dictionary = game.best.get(str(i), {})
		var status_text = tr_text("待出发", "READY TO DEPART") if i <= game.unlocked else tr_text("尚未抵达", "NOT YET REACHED")
		if score.has("stars"):
			status_text = "%d / 3  ·  %s" % [score.stars, format_time(score.time)]
		var button = make_button("%02d   %s\n%s" % [i + 1, name_text, status_text], func(): game.start_level(i), Vector2(240, 73))
		button.name = "Chapter%d" % (i + 1)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		button.disabled = i > game.unlocked
		button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		grid.add_child(button)
	spacer(4)
	var back = make_button(tr_text("←  返回车站", "←  BACK TO STATION"), show_title)
	back.name = "ChaptersBack"
	overlay_box.add_child(back)
	back.grab_focus()

func sample_journey_title() -> String:
	return tr_text("等我一下 · %d 站旅程", "WAIT FOR ME · %d STOPS") % game.sample_levels.size()

func sample_stop_text() -> String:
	return tr_text("第 %02d / %02d 站", "STOP %02d / %02d") % [game.sample_index + 1, game.sample_levels.size()]

func show_sample_chapters(page: int = -1) -> void:
	if game.state != "title":
		game.set_state("title")
	var page_count = maxi(1, ceili(float(game.sample_levels.size()) / SAMPLE_PAGE_SIZE))
	# Fresh visits follow progress; navigation and preference refreshes pass a page.
	sample_page = clampi(floori(float(game.sample_unlocked) / SAMPLE_PAGE_SIZE) if page < 0 else page, 0, page_count - 1)
	clear_overlay("sample_chapters")
	heading("WAIT FOR ME  /  %02d STOPS" % game.sample_levels.size(), sample_journey_title(), tr_text("按 SHIFT，让分身重走刚才三秒的路。", "Press SHIFT to let your double replay your last three seconds."))
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	overlay_box.add_child(grid)
	var first_stop = sample_page * SAMPLE_PAGE_SIZE
	var focus_target: Button = null
	for i in range(first_stop, mini(first_stop + SAMPLE_PAGE_SIZE, game.sample_levels.size())):
		var data: Dictionary = game.sample_levels[i]
		var name_text: String = data.name if game.language == "zh" else data.en
		var score: Dictionary = game.best.get(str(data.id), {})
		var reached: bool = i <= game.sample_unlocked
		var status_text = tr_text("待出发", "READY TO DEPART") if reached else tr_text("尚未抵达", "NOT YET REACHED")
		if reached and score.has("stars"):
			status_text = "%d / 3  ·  %s" % [score.stars, format_time(float(score.get("time", 0.0)))]
		var button = make_button("%02d / %02d\n%s\n%s" % [i + 1, game.sample_levels.size(), name_text, status_text], func(): game.start_sample(i), Vector2(240, 98))
		button.name = "SampleChapter%d" % (i + 1)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = name_text + "\n" + status_text
		button.disabled = not reached
		button.focus_mode = Control.FOCUS_ALL if reached else Control.FOCUS_NONE
		grid.add_child(button)
		if reached:
			focus_target = button
	var navigation = HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 10)
	overlay_box.add_child(navigation)
	var previous = make_button(tr_text("←  上一页", "←  PREVIOUS"), show_sample_chapters.bind(sample_page - 1), Vector2(160, 36))
	previous.name = "SamplePagePrevious"
	previous.disabled = sample_page == 0
	previous.focus_mode = Control.FOCUS_NONE if previous.disabled else Control.FOCUS_ALL
	navigation.add_child(previous)
	var page_label = make_label(tr_text("第 %d / %d 页", "PAGE %d / %d") % [sample_page + 1, page_count], 13, Color("9eb5b4"))
	page_label.name = "SamplePageLabel"
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	navigation.add_child(page_label)
	var next = make_button(tr_text("下一页  →", "NEXT  →"), show_sample_chapters.bind(sample_page + 1), Vector2(160, 36))
	next.name = "SamplePageNext"
	next.disabled = sample_page == page_count - 1
	next.focus_mode = Control.FOCUS_NONE if next.disabled else Control.FOCUS_ALL
	navigation.add_child(next)
	var help_text = make_label(tr_text("再次切换会替换分身。只有一次跳跃；和过去的自己一起开门。", "The next SHIFT replaces your double. Single jump only; open doors together."), 12, Color("9eb5b4"))
	help_text.name = "SampleChaptersHint"
	help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(help_text)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	overlay_box.add_child(actions)
	var back = make_button(tr_text("←  返回车站", "←  BACK TO STATION"), show_title)
	back.name = "SampleChaptersBack"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(back)
	var language = make_button("English" if game.language == "zh" else "简体中文", toggle_language, Vector2(140, 38))
	language.name = "SampleChaptersLanguage"
	actions.add_child(language)
	if focus_target == null:
		focus_target = previous if not previous.disabled else (next if not next.disabled else back)
	focus_target.grab_focus()

func show_pause() -> void:
	clear_overlay("pause")
	var data: Dictionary = game.current_level()
	var level_name: String = data.name if game.language == "zh" else data.en
	var subtitle = sample_stop_text() + " · " + level_name if game.is_sample else "%02d · %s" % [game.level_index + 1, level_name]
	heading("JOURNEY ON HOLD  /  PAUSED", tr_text("歇一会儿，车会等你。", "THE TRAIN CAN WAIT."), subtitle)
	spacer(3)
	var resume = make_button(tr_text("继续旅程", "RESUME JOURNEY"), toggle_pause, Vector2(0, 46))
	resume.name = "Resume"
	primary_button(resume)
	overlay_box.add_child(resume)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	overlay_box.add_child(actions)
	var restart = make_button(tr_text("从检查点重试", "RETRY CHECKPOINT") if game.is_sample else tr_text("重开这一关", "RESTART CHAPTER"), func(): game.restart())
	restart.name = "PauseRestart"
	restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(restart)
	var back = make_button(tr_text("返回车站", "BACK TO STATION"), func(): game.set_state("title"))
	back.name = "PauseBack"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(back)
	spacer(2)
	var options_label = make_label(tr_text("旅途偏好  /  PREFERENCES", "MAKE YOURSELF COMFORTABLE"), 10, Color("9bb1ac"))
	overlay_box.add_child(options_label)
	var options = GridContainer.new()
	options.columns = 2
	options.add_theme_constant_override("h_separation", 10)
	options.add_theme_constant_override("v_separation", 8)
	overlay_box.add_child(options)
	var assist_button = make_button(tr_text("休闲模式", "Assist mode") + ("   ON" if game.assist else "   OFF"), func(): game.assist = not game.assist; game.save_progress(); show_pause())
	assist_button.name = "AssistToggle"
	options.add_child(assist_button)
	var motion_button = make_button(tr_text("减少动态", "Reduced motion") + ("   ON" if game.reduced_motion else "   OFF"), func(): game.reduced_motion = not game.reduced_motion; game.save_progress(); show_pause())
	motion_button.name = "MotionToggle"
	options.add_child(motion_button)
	var audio = make_button(tr_text("游戏声音", "Game audio") + ("   OFF" if game.muted else "   ON"), toggle_sound)
	audio.name = "SoundToggle"
	options.add_child(audio)
	var language = make_button("语言   /   English" if game.language == "zh" else "Language   /   简体中文", toggle_language)
	language.name = "LanguageToggle"
	options.add_child(language)
	for button in options.get_children():
		button.custom_minimum_size.x = 286
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
	var help_text = make_label(tr_text("A D 移动 · 空格跳跃 · SHIFT 切换 · ESC 继续\n休闲模式降低巡逻速度、缩小尖刺判定。支持手柄。", "A D move · SPACE jump · SHIFT switch · ESC resume\nAssist slows patrols and reduces spike hitboxes. Gamepad supported."), 12, Color("839fa4"))
	if game.is_sample:
		help_text.text = tr_text("暂停时，过去与现在一起停下。\nSHIFT 重放刚才三秒；再次切换会替换分身。\nA D 移动 · 空格单次跳跃 · R 检查点重试 · ESC 继续", "Past and present both wait while paused.\nSHIFT replays your last 3s; the next SHIFT replaces the double.\nA D move · SPACE single jump · R checkpoint · ESC resume")
	help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_text.add_theme_constant_override("line_spacing", 4)
	overlay_box.add_child(help_text)
	resume.grab_focus()

func show_sample_win() -> void:
	clear_overlay("win")
	var data: Dictionary = game.current_level()
	var final_stop: bool = game.sample_index == game.sample_levels.size() - 1
	heading("ARRIVAL TICKET  /  WAIT FOR ME", data.name if game.language == "zh" else data.en, sample_stop_text() + tr_text(" · 这次，一起走。", " · THIS TIME, TOGETHER."))
	spacer(6)
	var journey = make_label("SOL     ———     SHIFT     ———     LUN", 12, Color("c2d8c7"))
	journey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(journey)
	spacer(2)
	result_metrics()
	spacer(4)
	var next = make_button(tr_text("返回旅程地图" if final_stop else "下一站，一起出发", "JOURNEY MAP" if final_stop else "NEXT STOP, TOGETHER"), func():
		if final_stop:
			show_sample_chapters(floori(float(game.sample_index) / SAMPLE_PAGE_SIZE))
		else:
			game.start_sample(game.sample_index + 1), Vector2(0, 48))
	next.name = "SampleNext"
	primary_button(next)
	overlay_box.add_child(next)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	overlay_box.add_child(actions)
	var retry = make_button(tr_text("重走这一站", "REPLAY THIS STOP"), func(): game.start_sample(game.sample_index))
	retry.name = "SampleRetry"
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(retry)
	var back = make_button(tr_text("返回车站", "BACK TO STATION"), func(): game.set_state("title"))
	back.name = "ResultBack"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(back)
	next.grab_focus()

func show_win() -> void:
	if game.is_sample:
		show_sample_win()
		return
	clear_overlay("win")
	var final_level = game.level_index == game.levels.size() - 1
	heading("SHIFT COMPLETE", tr_text("这次真的下班了" if final_level else "过关！", "TIME TO GO HOME" if final_level else "NICE WORK"), tr_text("两个世界不能同在，但过去的你可以。" if final_level else "路总在另一边。下一段，换个走法。", "Two worlds cannot coexist. Your past self can." if final_level else "There is always another way through."))
	var rating = make_label(tr_text("旅途评级   %d / 3", "JOURNEY RATING   %d / 3") % game.stars(), 14, Color("ebcca3"))
	rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(rating)
	result_metrics()
	var checklist = make_label(tr_text("通关 / 全部碎片 / 零失误，各获一颗星", "One star each: finish / all shards / no retries"), 11, Color("8ba6a6"))
	checklist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_box.add_child(checklist)
	var next = make_button(tr_text("回到选关" if final_level else "下一关", "LEVEL SELECT" if final_level else "NEXT LEVEL"), func():
		if final_level:
			game.set_state("title")
		else:
			game.start_level(game.level_index + 1), Vector2(0, 46))
	primary_button(next)
	overlay_box.add_child(next)
	overlay_box.add_child(make_button(tr_text("再试一次，拿满三颗星", "Try again for all three stars"), func(): game.start_level(game.level_index)))
	if not final_level:
		overlay_box.add_child(make_button(tr_text("回到选关", "Level select"), func(): game.set_state("title")))
	next.grab_focus()

func toggle_pause() -> void:
	if game.state == "play":
		game.set_state("pause")
	elif game.state == "pause":
		game.set_state("play")

func toggle_language() -> void:
	game.language = "en" if game.language == "zh" else "zh"
	game.save_progress()
	view.queue_redraw()
	on_level_loaded()
	update_state()

func toggle_sound() -> void:
	game.muted = not game.muted
	game.save_progress()
	if game.state != "play":
		update_state()

func update_state() -> void:
	match game.state:
		"title":
			if overlay_mode == "chapters":
				show_chapters()
			elif overlay_mode == "sample_chapters":
				show_sample_chapters(sample_page)
			else:
				show_title()
		"pause": show_pause()
		"win": show_win()
		"play":
			overlay.hide()
			hud.show()
			get_viewport().gui_release_focus()

func on_level_loaded() -> void:
	toast_time = 0
	toast_label.text = ""
	refresh_hud()

func on_effect(kind: String, _at: Vector2) -> void:
	match kind:
		"checkpoint": toast(tr_text("检查点已保存", "CHECKPOINT SAVED"))
		"gate": toast(tr_text("门开了，走吧！", "GATE OPEN. LET'S GO!"))
		"deny": toast(tr_text("另一边是墙，先移开一点", "SOLID MATTER. MOVE CLEAR FIRST."))

func toast(text: String) -> void:
	toast_label.text = text
	toast_time = 2.2

func format_time(seconds: float) -> String:
	return "%d:%04.1f" % [int(seconds / 60), fmod(seconds, 60)]

func _physics_process(dt: float) -> void:
	if test_mode:
		return
	if game.state == "play":
		var devices = Input.get_connected_joypads()
		if not devices.is_empty():
			var axis = Input.get_joy_axis(devices[0], JOY_AXIS_LEFT_X)
			game.action("left", axis < -0.3, "axis-left")
			game.action("right", axis > 0.3, "axis-right")
	game.tick(dt)

func _process(dt: float) -> void:
	if game.state != "pause":
		toast_time = maxf(0, toast_time - dt)
	toast_panel.visible = toast_time > 0
	refresh_hud()

func refresh_hud() -> void:
	var data: Dictionary = game.current_level()
	world_label.text = tr_text("阳界 · SOL" if game.world == 0 else "阴界 · LUN", "SOL / DAY" if game.world == 0 else "LUN / NIGHT")
	var color = Color("edc39a") if game.world == 0 else Color("a5d9d0")
	world_label.add_theme_color_override("font_color", color)
	if hud_world != game.world:
		hud_world = game.world
		world_badge.add_theme_stylebox_override("panel", panel_style(Color("302e27") if game.world == 0 else Color("193337"), color.darkened(0.55), 8))
	var captions = [tr_text("碎片", "SHARDS"), tr_text("用时", "TIME"), tr_text("失误", "RETRIES")]
	var values = ["%d / %d" % [game.collected, game.shards.size()], format_time(game.elapsed), "%02d" % game.deaths]
	for i in range(3):
		hud_values[i].text = captions[i] + "\n" + values[i]
		hud_values[i].add_theme_font_size_override("font_size", 13)
		hud_values[i].add_theme_color_override("font_color", Color("afc7be"))
	hint_label.add_theme_font_size_override("font_size", 11)
	if game.is_sample:
		var stages: Array = data.stages
		var stage_index = 0
		for i in range(stages.size()):
			if game.p.x >= float(stages[i].x):
				stage_index = i
		var stage: Dictionary = stages[stage_index]
		level_label.text = "%s · %s\n%02d / %02d · %s" % [sample_stop_text(), data.name if game.language == "zh" else data.en, int(stage.get("number", stage_index + 1)), stages.size(), stage.name if game.language == "zh" else stage.en]
		tip_label.text = stage.hint if game.language == "zh" else stage.hint_en
		hint_label.text = tr_text("A D / ← → 移动   空格 跳跃   SHIFT 切换   R 检查点重试   ESC 暂停   ·   重走过去3秒 · 再切换会替换分身", "A D / ARROWS move · SPACE jump · SHIFT switch · R checkpoint · ESC pause · Replay last 3s; next SHIFT replaces double")
		hud_buttons[0].tooltip_text = tr_text("从检查点重试 (R)", "Retry checkpoint (R)")
	else:
		level_label.text = "%02d · %s" % [game.level_index + 1, data.name if game.language == "zh" else data.en.capitalize()]
		var info: Array = INSTRUCTIONS[game.level_index]
		tip_label.text = info[0] if game.language == "zh" else info[1]
		hint_label.text = tr_text("A D / ← → 移动   空格 跳跃   SHIFT 切换   R 重开   ESC 暂停", "A D / ARROWS move   SPACE jump   SHIFT switch   R restart   ESC pause")
		if game.double_jump_enabled:
			hint_label.text += tr_text("   ·   松开再按：二段跳", "   ·   Release + press: double jump")
		hud_buttons[0].tooltip_text = tr_text("重开这一关 (R)", "Restart this level (R)")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		var key = event.physical_keycode
		if event.pressed and key == KEY_ESCAPE:
			toggle_pause()
			get_viewport().set_input_as_handled()
			return
		if event.pressed and key == KEY_M:
			toggle_sound()
			return
		if event.pressed and key == KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		if game.state != "play":
			return
		match key:
			KEY_A, KEY_LEFT: game.action("left", event.pressed, str(key))
			KEY_D, KEY_RIGHT: game.action("right", event.pressed, str(key))
			KEY_SPACE, KEY_W, KEY_UP: game.action("jump", event.pressed, str(key))
			KEY_SHIFT: game.action("shift", event.pressed)
			KEY_R:
				if event.pressed:
					game.restart()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		if event.button_index == JOY_BUTTON_START and event.pressed:
			toggle_pause()
		elif game.state == "play":
			match event.button_index:
				JOY_BUTTON_A: game.action("jump", event.pressed, "pad-jump")
				JOY_BUTTON_X, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER: game.action("shift", event.pressed)
				JOY_BUTTON_DPAD_LEFT: game.action("left", event.pressed, "pad-left")
				JOY_BUTTON_DPAD_RIGHT: game.action("right", event.pressed, "pad-right")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(game):
		if game.state == "play" and not test_mode:
			game.set_state("pause")
		else:
			game.clear_input()

func smoke_key(code: Key, down: bool) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run_sample_smoke() -> void:
	game.language = "zh"
	# This movement route exercises the original sample, not a saved later stop.
	game.sample_unlocked = 0
	assert(game.sample_levels.size() == 10)
	show_title()
	var campaign_unlocked: int = game.unlocked
	assert(game.levels.size() == 9)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless" and OS.has_feature("editor"):
		DirAccess.make_dir_recursive_absolute("res://build")
		var saved = get_viewport().get_texture().get_image().save_png("res://build/sample-title.png")
		assert(saved == OK)
	var demo = overlay_box.find_child("DemoStart", true, false) as Button
	assert(demo != null and demo.text == "等我一下 · %d 站旅程" % game.sample_levels.size())
	assert(overlay_box.find_child("CampaignStart", true, false) != null)
	assert(overlay_box.find_child("SampleChapterSelect", true, false) != null)
	assert(overlay_box.find_child("ChapterSelect", true, false) != null)
	demo.pressed.emit()
	assert(game.is_sample and game.state == "play" and game.level_index == 0 and game.sample_index == 0)
	assert(not game.double_jump_enabled)
	assert(level_label.text.contains("等我一下"))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless" and OS.has_feature("editor"):
		var saved = get_viewport().get_texture().get_image().save_png("res://build/sample-start.png")
		assert(saved == OK)
	var start: Vector2 = game.p
	smoke_key(KEY_D, true)
	for i in range(12):
		game.tick(1.0 / 60)
	smoke_key(KEY_D, false)
	for i in range(10):
		game.tick(1.0 / 60)
	assert(game.p.x > start.x)
	smoke_key(KEY_SPACE, true)
	for i in range(4):
		game.tick(1.0 / 60)
	smoke_key(KEY_SPACE, false)
	assert(game.history.size() > 1 and game.history_time > 0)
	var old_world: int = game.world
	smoke_key(KEY_SHIFT, true)
	smoke_key(KEY_SHIFT, false)
	assert(game.world != old_world and game.echoes.size() == 1)
	for i in range(12):
		game.tick(1.0 / 60)
	assert(not game.history.is_empty() and not game.echoes.is_empty())
	smoke_key(KEY_ESCAPE, true)
	smoke_key(KEY_ESCAPE, false)
	assert(game.state == "pause")
	var frozen_position: Vector2 = game.p
	var frozen_time: float = game.history_time
	var frozen_elapsed: float = game.elapsed
	var frozen_history: Array = game.history.duplicate(true)
	var frozen_echoes: Array = game.echoes.duplicate(true)
	smoke_key(KEY_SHIFT, true)
	smoke_key(KEY_SHIFT, false)
	game.tick(1.0)
	assert(game.p == frozen_position and game.elapsed == frozen_elapsed)
	assert(game.history_time == frozen_time and game.history == frozen_history)
	assert(game.echoes == frozen_echoes)
	overlay_box.find_child("LanguageToggle", true, false).pressed.emit()
	assert(game.language == "en" and game.state == "pause")
	assert(level_label.text.contains("WAIT FOR ME"))
	assert(tip_label.text == game.current_level().stages[0].hint_en)
	assert(hint_label.text.contains("next SHIFT replaces double"))
	assert(overlay_box.find_child("PauseRestart", true, false).text == "RETRY CHECKPOINT")
	assert(game.history == frozen_history and game.echoes == frozen_echoes)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless" and OS.has_feature("editor"):
		var saved = get_viewport().get_texture().get_image().save_png("res://build/sample-pause.png")
		assert(saved == OK)
	overlay_box.find_child("Resume", true, false).pressed.emit()
	assert(game.state == "play")
	game.tick(1.0 / 60)
	assert(game.history_time > frozen_time and game.echoes[0].life < frozen_echoes[0].life)
	smoke_key(KEY_R, true)
	smoke_key(KEY_R, false)
	assert(game.is_sample and game.state == "play" and game.level_index == 0)
	hud.find_child("HudRestart", true, false).pressed.emit()
	assert(game.is_sample and game.state == "play")
	smoke_key(KEY_ESCAPE, true)
	smoke_key(KEY_ESCAPE, false)
	overlay_box.find_child("PauseRestart", true, false).pressed.emit()
	assert(game.is_sample and game.state == "play" and game.level_index == 0)
	assert(game.current_level().en == "WAIT FOR ME" and not game.double_jump_enabled)
	assert(game.unlocked == campaign_unlocked and game.levels.size() == 9)
	game.set_state("title")
	assert(overlay_box.find_child("DemoStart", true, false).text == "WAIT FOR ME · %d STOPS" % game.sample_levels.size())
	game.sample_unlocked = 2
	overlay_box.find_child("DemoStart", true, false).pressed.emit()
	assert(game.is_sample and game.state == "play" and game.sample_index == 2)
	assert(game.current_level().id == game.sample_levels[2].id)
	assert(game.level_index == 0 and not game.double_jump_enabled and game.unlocked == campaign_unlocked)
	print("SAMPLE_UI_SMOKE_OK")
	get_tree().quit()

func run_smoke_test() -> void:
	# Keep the original nine-stop movement route independent of saved progress.
	game.unlocked = 0
	show_title()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless" and OS.has_feature("editor"):
		get_viewport().get_texture().get_image().save_png("res://build/title.png")
	overlay_box.find_child("CampaignStart", true, false).pressed.emit()
	assert(game.state == "play")
	smoke_key(KEY_D, true)
	for i in range(12):
		game.tick(1.0 / 60)
	smoke_key(KEY_D, false)
	assert(game.p.x > 100)
	smoke_key(KEY_ESCAPE, true)
	smoke_key(KEY_ESCAPE, false)
	assert(game.state == "pause")
	var muted_before: bool = game.muted
	smoke_key(KEY_M, true)
	smoke_key(KEY_M, false)
	assert(game.muted != muted_before)
	smoke_key(KEY_M, true)
	smoke_key(KEY_M, false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless" and OS.has_feature("editor"):
		get_viewport().get_texture().get_image().save_png("res://build/pause.png")
	overlay_box.find_child("Resume", true, false).pressed.emit()
	assert(game.state == "play")
	smoke_key(KEY_R, true)
	smoke_key(KEY_R, false)
	assert(game.p.x == 79)
	game.start_level(4)
	on_level_loaded()
	smoke_key(KEY_SPACE, true)
	for i in range(16):
		game.tick(1.0 / 60)
	smoke_key(KEY_SPACE, false)
	smoke_key(KEY_SPACE, true)
	game.tick(1.0 / 60)
	assert(not game.air_jump_ready and game.velocity.y < -450)
	var before: Vector2 = game.p
	toggle_pause()
	game.tick(1.0)
	assert(game.p == before)
	toggle_pause()
	assert(game.state == "play")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless" and OS.has_feature("editor"):
		get_viewport().get_texture().get_image().save_png("res://build/level-five.png")
	game.start_level(8)
	for i in range(3):
		game.tick(1.0 / 60)
	game.action("right", true)
	for i in range(300):
		if game.p.x >= 211:
			break
		game.tick(1.0 / 60)
	game.action("right", false)
	for i in range(12):
		game.tick(1.0 / 60)
	game.try_shift()
	for i in range(4):
		game.tick(1.0 / 60)
	game.action("right", true)
	for i in range(16):
		game.tick(1.0 / 60)
	game.action("right", false)
	for i in range(8):
		game.tick(1.0 / 60)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless" and OS.has_feature("editor"):
		get_viewport().get_texture().get_image().save_png("res://build/level-nine.png")
	for target in [427, 787, 1003, 1330]:
		game.action("right", true)
		for i in range(350):
			if game.p.x >= target or game.won:
				break
			game.tick(1.0 / 60)
		game.action("right", false)
		for i in range(12):
			game.tick(1.0 / 60)
		if target == 787:
			game.try_shift()
			for i in range(4):
				game.tick(1.0 / 60)
	for i in range(80):
		game.tick(1.0 / 60)
	assert(game.state == "win" and game.deaths == 0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless" and OS.has_feature("editor"):
		get_viewport().get_texture().get_image().save_png("res://build/finale.png")
	game.set_state("title")
	toggle_language()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless" and OS.has_feature("editor"):
		get_viewport().get_texture().get_image().save_png("res://build/title-en.png")
	print("NATIVE_UI_SMOKE_OK")
	get_tree().quit()
