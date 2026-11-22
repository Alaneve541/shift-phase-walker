extends SceneTree

var scene
var game
var checks = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func capture(name: String) -> void:
	await settle()
	var saved = root.get_texture().get_image().save_png("res://build/ui-" + name + ".png")
	check(saved == OK, "capture " + name)

func click(name: String) -> void:
	await settle()
	var button = scene.overlay_box.find_child(name, true, false) as Button
	check(button != null, "button exists: " + name)
	if button == null:
		return
	var at = root.get_final_transform() * button.get_global_rect().get_center()
	var motion = InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await settle()

func key(code: Key, shift: bool = false) -> void:
	for down in [true, false]:
		var event = InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.shift_pressed = shift
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await settle()

func check_layout(name: String) -> void:
	await settle()
	var scroll: ScrollContainer = scene.overlay_box.get_parent()
	check(scene.overlay_box.size.x <= scroll.size.x + 1, name + " fits width")
	check(scene.overlay_box.size.y <= scroll.size.y + 1, name + " needs no vertical scrolling")
	var bounds = Rect2(Vector2.ZERO, Vector2(960, 640))
	var window_bounds = Rect2(Vector2.ZERO, Vector2(DisplayServer.window_get_size())).grow(1)
	var buttons = scene.overlay_box.find_children("*", "Button", true, false)
	for i in range(buttons.size()):
		var button: Button = buttons[i]
		var rect = button.get_global_rect()
		check(bounds.encloses(rect), name + " button inside viewport " + str(button.name))
		check(scroll.get_global_rect().grow(1).encloses(rect), name + " button inside panel " + str(button.name))
		check(window_bounds.encloses(root.get_final_transform() * rect), name + " button inside real window " + str(button.name))
		var style: StyleBox = button.get_theme_stylebox("normal")
		var font: Font = button.get_theme_font("font")
		var text_width: float = font.get_multiline_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
		var text_fits: bool = text_width <= button.size.x - style.get_content_margin(SIDE_LEFT) - style.get_content_margin(SIDE_RIGHT) + 1
		check(text_fits, name + " full text fits " + str(button.name))
		for j in range(i + 1, buttons.size()):
			check(not rect.grow(-1).intersects(buttons[j].get_global_rect().grow(-1)), name + " buttons do not overlap: " + str(button.name) + " / " + str(buttons[j].name))
	if scene.overlay_mode == "sample_chapters":
		check(scene.overlay_panel.size.is_equal_approx(Vector2(800, 508)), name + " retains 800x508 map panel")
		check(not scroll.get_v_scroll_bar().visible and scroll.scroll_vertical == 0, name + " has no vertical scrollbar or hidden scroll offset")
		var labels = scene.overlay_box.find_children("*", "Label", true, false)
		for i in range(labels.size()):
			var rect: Rect2 = labels[i].get_global_rect()
			check(scroll.get_global_rect().grow(1).encloses(rect), name + " label inside panel " + str(labels[i].name))
			check(window_bounds.encloses(root.get_final_transform() * rect), name + " label inside real window " + str(labels[i].name))
			for button in buttons:
				check(not rect.grow(-1).intersects(button.get_global_rect().grow(-1)), name + " labels do not overlap cards or navigation")
			for j in range(i + 1, labels.size()):
				check(not rect.grow(-1).intersects(labels[j].get_global_rect().grow(-1)), name + " labels do not overlap each other")

func check_sample_map() -> void:
	check(game.state == "title" and scene.overlay_mode == "sample_chapters", "journey map uses independent title overlay")
	check(not scene.hud.visible and scene.menu_backdrop.mode == "sample_chapters", "journey map hides HUD and retains station backdrop")
	var page: int = scene.sample_page
	check(page == 0 or page == 1, "ten stops use exactly two pages")
	if page < 0 or page > 1:
		return
	var first_index = page * 6
	var end_index = mini(first_index + 6, game.sample_levels.size())
	var first = scene.overlay_box.find_child("SampleChapter%d" % (first_index + 1), true, false) as Button
	check(first != null, "first sample card on current page exists")
	if first == null:
		return
	var grid = first.get_parent() as GridContainer
	check(grid != null and grid.columns == 3 and grid.get_child_count() == end_index - first_index, "current page has six or four native cards in three columns")
	for i in range(game.sample_levels.size()):
		var button = scene.overlay_box.find_child("SampleChapter%d" % (i + 1), true, false) as Button
		if i < first_index or i >= end_index:
			check(button == null, "off-page card is absent from input and layout: %d" % (i + 1))
			continue
		check(button != null, "sample card exists: %d" % (i + 1))
		if button == null:
			continue
		var reached: bool = i <= game.sample_unlocked
		check(button.disabled == (not reached), "sample lock %d follows independent progress" % (i + 1))
		check(button.focus_mode == (Control.FOCUS_ALL if reached else Control.FOCUS_NONE), "locked cards cannot take keyboard focus")
		check(button.custom_minimum_size == Vector2(240, 98), "sample cards retain 240x98 minimum size")
		var data: Dictionary = game.sample_levels[i]
		var name_text: String = data.name if game.language == "zh" else data.en
		var status_text: String = ("待出发" if game.language == "zh" else "READY TO DEPART") if reached else ("尚未抵达" if game.language == "zh" else "NOT YET REACHED")
		var score: Dictionary = game.best.get(str(data.id), {})
		if reached and score.has("stars"):
			status_text = "%d / 3  ·  %s" % [score.stars, scene.format_time(float(score.get("time", 0.0)))]
		check(button.text == "%02d / %02d\n%s\n%s" % [i + 1, game.sample_levels.size(), name_text, status_text], "sample card uses localized name, count and id-based score only when unlocked")
		check(button.tooltip_text == name_text + "\n" + status_text, "full name and lock/score remain available in tooltip")
		if i - first_index < 3:
			check(is_equal_approx(button.position.y, first.position.y), "sample card in first row")
		else:
			check(button.position.y > first.position.y, "sample card in second row")
	var previous = scene.overlay_box.find_child("SamplePagePrevious", true, false) as Button
	var next = scene.overlay_box.find_child("SamplePageNext", true, false) as Button
	var page_label = scene.overlay_box.find_child("SamplePageLabel", true, false) as Label
	check(previous != null and next != null and page_label != null, "named native pagination controls exist")
	if previous == null or next == null or page_label == null:
		return
	check(previous.disabled == (page == 0) and next.disabled == (page == 1), "pagination disables both outer boundaries")
	for button in [previous, next]:
		check(button.focus_mode == (Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL), "disabled pagination is excluded from keyboard focus")
	check(page_label.text == ("第 %d / 2 页" if game.language == "zh" else "PAGE %d / 2") % (page + 1), "localized page counter follows current page")
	var focus = root.gui_get_focus_owner() as Button
	check(focus != null and not focus.disabled and focus.focus_mode == Control.FOCUS_ALL and (focus.get_parent() == grid or focus == previous or focus == next), "map rebuild puts focus on a current-page card or available navigation")
	var title: Label = scene.overlay_box.find_child("OverlayTitle", true, false)
	check(title.text == ("等我一下 · %d 站旅程" if game.language == "zh" else "WAIT FOR ME · %d STOPS") % game.sample_levels.size(), "map heading derives journey count from data")
	var subtitle: Label = scene.overlay_box.find_child("OverlaySubtitle", true, false)
	var hint: Label = scene.overlay_box.find_child("SampleChaptersHint", true, false)
	check(subtitle.text.contains("三秒" if game.language == "zh" else "three seconds"), "map explains three-second replay above cards")
	check(hint.text.contains("替换分身" if game.language == "zh" else "replaces your double"), "map explains double replacement below cards")

func check_sample_keyboard() -> void:
	# Traverse the real native focus chain in both directions, including its wrap.
	var enabled: Array[Button] = []
	for button in scene.overlay_box.find_children("*", "Button", true, false):
		if not button.disabled:
			enabled.append(button)
	var start = enabled.find(root.gui_get_focus_owner())
	check(start >= 0, "keyboard traversal starts on an enabled map action")
	if start < 0:
		return
	for reverse in [false, true]:
		for step in range(1, enabled.size() + 1):
			await key(KEY_TAB, reverse)
			var expected = (start + (-step if reverse else step) + enabled.size()) % enabled.size()
			check(root.gui_get_focus_owner() == enabled[expected], "Tab/Shift+Tab skip locked cards and disabled page buttons, including wrap")

func check_sample_preferences() -> void:
	var page: int = scene.sample_page
	var language: String = game.language
	var muted: bool = game.muted
	for i in range(2):
		await click("SampleChaptersLanguage")
		check(scene.sample_page == page, "language refresh preserves browsed page rather than following unlocks")
		check(game.language != language if i == 0 else game.language == language, "map language control toggles and restores language")
		check_sample_map()
	for i in range(2):
		await key(KEY_M)
		check(scene.sample_page == page, "mute refresh preserves browsed page rather than following unlocks")
		check(game.muted != muted if i == 0 else game.muted == muted, "map mute shortcut toggles and restores sound")
		check_sample_map()

func check_sample_play(index: int) -> void:
	check(game.state == "play" and game.is_sample and game.sample_index == index, "playing sample stop %d" % (index + 1))
	check(game.level_index == 0 and not game.double_jump_enabled, "sample remains isolated and single-jump")
	check(game.current_level().id == game.sample_levels[index].id, "current sample data follows selection")
	check(not scene.overlay.visible and scene.hud.visible, "sample play restores HUD and hides overlay")
	check(scene.level_label.text.contains("%02d / %02d" % [index + 1, game.sample_levels.size()]), "HUD includes sample station number")
	var data: Dictionary = game.current_level()
	check(scene.level_label.text.contains(data.name if game.language == "zh" else data.en), "HUD includes real chapter name")
	var stage: Dictionary = data.stages[0]
	for candidate in data.stages:
		if game.p.x >= float(candidate.x):
			stage = candidate
	check(scene.tip_label.text == (stage.hint if game.language == "zh" else stage.hint_en), "stage hint remains localized at spawn")
	if index == 3:
		check(scene.level_label.text.contains("01 / 03"), "right-to-left chapter begins with stage one")

func fake_win() -> void:
	# UI fixture only: never call finish_level or award/save progress.
	var best_before: Dictionary = game.best.duplicate(true)
	var campaign_before: int = game.unlocked
	var sample_before: int = game.sample_unlocked
	game.set_state("win")
	await settle()
	check(game.best == best_before and game.unlocked == campaign_before and game.sample_unlocked == sample_before, "fake result does not award progress")
	check(not game.persistence_enabled, "UI fixture never enables player saves")
	if game.is_sample:
		var data: Dictionary = game.current_level()
		check(scene.overlay_box.find_child("OverlayTitle", true, false).text == (data.name if game.language == "zh" else data.en), "sample result shows actual chapter name")
		check(scene.overlay_box.find_child("OverlaySubtitle", true, false).text.contains("%02d / %02d" % [game.sample_index + 1, game.sample_levels.size()]), "sample result shows station number")
		var final_stop: bool = game.sample_index == game.sample_levels.size() - 1
		var expected_next: String = ("返回旅程地图" if game.language == "zh" else "JOURNEY MAP") if final_stop else ("下一站，一起出发" if game.language == "zh" else "NEXT STOP, TOGETHER")
		check(scene.overlay_box.find_child("SampleNext", true, false).text == expected_next, "only the final stop offers the journey map; all other results offer Next")
		check(root.gui_get_focus_owner() == scene.overlay_box.find_child("SampleNext", true, false), "next stop is primary keyboard action")

func run() -> void:
	check(DisplayServer.get_name() != "headless", "UI regression requires a real native window")
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(960, 640))
	scene = load("res://main.tscn").instantiate()
	# Disable persistence before Game._ready, including preferences and fixtures.
	game = scene.get_node("Game")
	game.persistence_enabled = false
	game.reduced_motion = true
	root.add_child(scene)
	scene.test_mode = true
	if scene.menu_tween != null:
		scene.menu_tween.kill()
	scene.overlay_panel.modulate.a = 1.0
	game.language = "zh"
	game.unlocked = 0
	game.sample_unlocked = 0
	game.assist = false
	game.muted = false
	game.best.clear()
	game.reduced_motion = false
	check(game.levels.size() == 9 and game.sample_levels.size() == 10, "nine original chapters plus ten independent stops")
	if game.sample_levels.size() != 10:
		scene.free()
		quit(1)
		return
	game.best["0"] = {"stars": 3, "time": 11.0}
	game.best[str(game.sample_levels[0].id)] = {"stars": 2, "time": 74.2}
	game.best[str(game.sample_levels[2].id)] = {"stars": 1, "time": 125.6}
	game.best[str(game.sample_levels[6].id)] = {"stars": 3, "time": 98.4}
	game.best[str(game.sample_levels[9].id)] = {"stars": 2, "time": 143.2}
	var expected_best: Dictionary = game.best.duplicate(true)
	check(DirAccess.make_dir_recursive_absolute("res://build") == OK, "capture directory exists")
	scene.show_title()
	check(scene.overlay_box.find_child("DemoStart", true, false).text == "等我一下 · 10 站旅程", "Chinese ten-stop title CTA")
	check(scene.overlay_box.find_child("SampleChapterSelect", true, false).text.contains("10 站地图"), "Chinese title map count follows data")
	await check_layout("Chinese title")
	await capture("title-zh")
	await click("SampleChapterSelect")
	check(scene.sample_page == 0, "fresh progress opens first page")
	check_sample_map()
	await check_layout("Chinese journey map page 1")
	await capture("sample-chapters-zh")
	await click("SamplePagePrevious")
	check(scene.sample_page == 0, "disabled Previous cannot leave first page")
	await click("SampleChapter2")
	check(game.state == "title" and scene.overlay_mode == "sample_chapters", "mouse cannot start a locked sample")
	game.unlocked = 8
	scene.update_state()
	await settle()
	check_sample_map()
	check(scene.overlay_box.find_child("SampleChapter6", true, false).disabled, "campaign unlocks cannot unlock sample stops")
	await click("SamplePageNext")
	check(scene.sample_page == 1, "mouse Next shows new stops on second page")
	check_sample_map()
	check(root.gui_get_focus_owner() == scene.overlay_box.find_child("SamplePagePrevious", true, false), "all-locked second page focuses usable Previous")
	var locked_index: int = game.sample_index
	for i in range(6, 10):
		await click("SampleChapter%d" % (i + 1))
		check(game.state == "title" and scene.overlay_mode == "sample_chapters" and game.sample_index == locked_index and game.sample_unlocked == 0, "mouse cannot start locked new stop %d even with campaign unlocked" % (i + 1))
	await click("SamplePageNext")
	check(scene.sample_page == 1, "disabled Next cannot leave second page")
	await check_sample_preferences()
	await check_sample_keyboard()
	await check_layout("Chinese all-locked journey map page 2")
	await capture("sample-chapters-locked-page2-zh")
	await click("SamplePagePrevious")
	check(scene.sample_page == 0, "mouse Previous returns to first page")
	check_sample_map()
	game.unlocked = 0
	await click("SampleChaptersLanguage")
	check(game.language == "en", "map language button switches to English")
	check_sample_map()
	await check_layout("English journey map page 1")
	await capture("sample-chapters-en")
	await check_sample_preferences()
	await check_sample_keyboard()
	# Only the first card is enabled; Tab skips five locked cards and Previous.
	await key(KEY_TAB)
	check(root.gui_get_focus_owner() == scene.overlay_box.find_child("SamplePageNext", true, false), "Tab skips locked cards and disabled Previous")
	await key(KEY_ENTER)
	check(scene.sample_page == 1, "keyboard Next opens second page")
	check_sample_map()
	await check_layout("English all-locked journey map page 2")
	await capture("sample-chapters-locked-page2-en")
	await key(KEY_ENTER)
	check(scene.sample_page == 0, "keyboard Previous returns from all-locked second page")
	await key(KEY_TAB)
	await key(KEY_TAB)
	check(root.gui_get_focus_owner() == scene.overlay_box.find_child("SampleChaptersBack", true, false), "keyboard reaches Back after page navigation")
	await key(KEY_ENTER)
	check(scene.overlay_mode == "title", "keyboard returns from sample map to title")
	check(scene.overlay_box.find_child("DemoStart", true, false).text == "WAIT FOR ME · 10 STOPS", "English ten-stop title CTA")
	check(scene.overlay_box.find_child("SampleChapterSelect", true, false).text.contains("10 STOPS"), "English title map count follows data")
	await check_layout("English title")
	await capture("title-en")
	await click("SampleChapterSelect")
	await click("SampleChaptersLanguage")
	check(game.language == "zh", "map language button switches back to Chinese")
	check_sample_map()
	await click("SampleChaptersBack")
	await click("ChapterSelect")
	check(scene.overlay_mode == "chapters" and not scene.hud.visible, "mouse opens original map without HUD")
	check(scene.overlay_box.find_child("Chapter1", true, false).get_parent().get_child_count() == 9, "original map retains all nine cards")
	check(scene.overlay_box.find_child("Chapter2", true, false).disabled, "original levels remain locked")
	check(scene.overlay_box.find_child("Chapter1", true, false).text.contains("3 / 3  ·  0:11.0"), "original score remains independent of sample id")
	await click("Chapter2")
	check(game.state == "title" and scene.overlay_mode == "chapters", "mouse cannot start locked original chapter")
	await check_layout("Chinese chapters")
	await capture("chapters-zh")
	await click("Chapter1")
	check(game.state == "play" and not game.is_sample and game.level_index == 0, "mouse chapter selection starts campaign")
	await key(KEY_ESCAPE)
	check(game.state == "pause", "real Escape pauses campaign")
	await click("PauseBack")
	check(game.state == "title" and scene.overlay_mode == "title", "pause back returns title")
	await click("TitleLanguage")
	check(game.language == "en", "title language control works")
	await click("ChapterSelect")
	await check_layout("English chapters")
	await capture("chapters-en")
	await click("ChaptersBack")
	await click("DemoStart")
	check_sample_play(0)
	await capture("hud-en")
	await key(KEY_ESCAPE)
	check(scene.overlay_box.find_child("OverlaySubtitle", true, false).text.contains("STOP 01 / 10"), "pause uses station number, not DEMO")
	await check_layout("English pause")
	await capture("pause-en")
	var initial_mute: bool = game.muted
	await click("SoundToggle")
	check(game.muted != initial_mute and game.state == "pause", "sound toggle keeps pause")
	await click("SoundToggle")
	await click("MotionToggle")
	check(game.reduced_motion, "reduced motion control works")
	await click("AssistToggle")
	check(game.assist, "assist control works")
	await click("LanguageToggle")
	check(game.language == "zh" and game.state == "pause", "language change retains pause")
	check(scene.overlay_box.find_child("OverlaySubtitle", true, false).text.contains("第 01 / 10 站"), "Chinese pause includes sample station")
	await check_layout("Chinese pause")
	await capture("pause-zh")
	await click("Resume")
	check(game.state == "play" and not scene.overlay.visible, "real mouse resumes play")
	var start: Vector2 = game.p
	scene.smoke_key(KEY_D, true)
	for i in range(20):
		game.tick(1.0 / 60.0)
	scene.smoke_key(KEY_D, false)
	check(game.p.x > start.x, "movement unaffected by HUD")
	# Unlock fixtures model completed arrivals without invoking completion logic.
	game.sample_unlocked = 1
	await fake_win()
	await check_layout("Chinese sample result")
	await capture("result-zh")
	scene.toggle_language()
	await settle()
	check(game.language == "en" and game.state == "win", "language switch retains sample result")
	await check_layout("English sample result")
	await capture("result-en")
	await key(KEY_ENTER)
	check_sample_play(1)
	await key(KEY_ESCAPE)
	await click("PauseBack")
	game.sample_unlocked = 2
	await click("DemoStart")
	check_sample_play(2)
	await key(KEY_ESCAPE)
	await click("PauseRestart")
	check_sample_play(2)
	await key(KEY_R)
	check_sample_play(2)
	await fake_win()
	await click("SampleRetry")
	check_sample_play(2)
	game.sample_unlocked = 3
	await fake_win()
	await click("SampleNext")
	check_sample_play(3)
	await fake_win()
	await click("ResultBack")
	check(game.state == "title" and scene.overlay_mode == "title", "sample ResultBack returns title, not either map")
	await key(KEY_ENTER)
	check_sample_play(3)
	await key(KEY_ESCAPE)
	await click("PauseBack")
	await click("SampleChapterSelect")
	check_sample_map()
	await click("SampleChapter1")
	check_sample_play(0)
	await fake_win()
	await click("ResultBack")
	game.sample_unlocked = 5
	await click("DemoStart")
	check_sample_play(5)
	await fake_win()
	check(scene.overlay_box.find_child("SampleNext", true, false).text == "NEXT STOP, TOGETHER", "old sixth-stop finale now offers normal Next")
	await click("SampleRetry")
	check_sample_play(5)
	game.sample_unlocked = 6
	await fake_win()
	await click("SampleNext")
	check_sample_play(6)
	await key(KEY_ESCAPE)
	await click("PauseBack")
	await click("SampleChapterSelect")
	check(scene.sample_page == 1, "unlocking seventh stop makes fresh map visits open second page")
	check_sample_map()
	check(root.gui_get_focus_owner() == scene.overlay_box.find_child("SampleChapter7", true, false), "partially unlocked second page focuses reached seventh stop")
	await check_sample_keyboard()
	await key(KEY_TAB)
	check(root.gui_get_focus_owner() == scene.overlay_box.find_child("SamplePagePrevious", true, false), "Tab skips locked stops eight through ten")
	await key(KEY_TAB)
	check(root.gui_get_focus_owner() == scene.overlay_box.find_child("SampleChaptersBack", true, false), "Tab skips disabled second-page Next")
	await key(KEY_TAB, true)
	await key(KEY_TAB, true)
	await key(KEY_ENTER)
	check_sample_play(6)
	await key(KEY_ESCAPE)
	await click("PauseBack")
	await click("SampleChapterSelect")
	await click("SamplePagePrevious")
	check(scene.sample_page == 0, "reached later stops do not prevent browsing earlier page")
	await check_sample_preferences()
	await click("SampleChaptersBack")
	await click("SampleChapterSelect")
	check(scene.sample_page == 1, "reopening map follows highest unlock instead of last browsed page")
	await click("SampleChaptersBack")
	# Each appended chapter starts through its own second-page mouse card.
	for i in range(6, 10):
		game.sample_unlocked = i
		await click("SampleChapterSelect")
		check(scene.sample_page == 1, "new stop %d opens on second page" % (i + 1))
		check_sample_map()
		await click("SampleChapter%d" % (i + 1))
		check_sample_play(i)
		await key(KEY_ESCAPE)
		await click("PauseBack")
	await click("DemoStart")
	check_sample_play(9)
	await fake_win()
	check(scene.overlay_box.find_child("SampleNext", true, false).text == "JOURNEY MAP", "tenth stop primary action returns to journey map")
	await click("SampleRetry")
	check_sample_play(9)
	await fake_win()
	await click("SampleNext")
	check(scene.sample_page == 1, "final result returns directly to second page")
	check_sample_map()
	check(root.gui_get_focus_owner() == scene.overlay_box.find_child("SampleChapter10", true, false), "final map return focuses tenth stop")
	await click("SamplePagePrevious")
	await click("SampleChapter5")
	check_sample_play(4)
	await key(KEY_ESCAPE)
	await click("PauseBack")
	# Sample progress must not unlock any original chapter.
	await click("ChapterSelect")
	check(scene.overlay_box.find_child("Chapter2", true, false).disabled and game.unlocked == 0, "ten-stop completion fixture leaves original locks intact")
	await click("ChaptersBack")
	game.unlocked = 8
	for i in range(9):
		await click("ChapterSelect")
		await click("Chapter%d" % (i + 1))
		check(game.state == "play" and not game.is_sample and game.level_index == i, "original chapter %d still starts via mouse" % (i + 1))
		check(game.sample_unlocked == 9, "campaign selection preserves ten-stop progress")
		if i == 0 or i == 8:
			await fake_win()
			await check_layout("English campaign result %d" % (i + 1))
			await capture("campaign-result" if i == 0 else "campaign-finale")
			game.set_state("title")
		else:
			await key(KEY_ESCAPE)
			await click("PauseBack")
	# Test both pages/languages at native and downscaled physical window sizes.
	for window_size in [Vector2i(960, 640), Vector2i(768, 512)]:
		DisplayServer.window_set_size(window_size)
		await settle()
		check(DisplayServer.window_get_size() == window_size, "native window resized to requested test dimensions")
		for language in ["zh", "en"]:
			game.language = language
			scene.show_title()
			var tag = "%dpx-%s" % [window_size.x, language]
			await check_layout(tag + " title")
			await capture("title-" + tag)
			await click("SampleChapterSelect")
			check(scene.sample_page == 1, tag + " fresh map opens highest unlocked page")
			check_sample_map()
			await check_layout(tag + " journey map page 2")
			await capture("sample-chapters-page2-" + tag)
			await check_sample_keyboard()
			await click("SamplePageNext")
			check(scene.sample_page == 1, tag + " disabled Next keeps last page")
			await click("SamplePagePrevious")
			check(scene.sample_page == 0, tag + " mouse Previous changes page")
			check_sample_map()
			await check_sample_preferences()
			await check_sample_keyboard()
			await check_layout(tag + " journey map page 1")
			await capture("sample-chapters-page1-" + tag)
			await click("SamplePagePrevious")
			check(scene.sample_page == 0, tag + " disabled Previous keeps first page")
			await click("SamplePageNext")
			check(scene.sample_page == 1, tag + " mouse Next changes page")
			check_sample_map()
			# New cards also receive real transformed mouse clicks at both sizes.
			for i in range(6, 10):
				await click("SampleChapter%d" % (i + 1))
				check_sample_play(i)
				await key(KEY_ESCAPE)
				await check_layout(tag + " new-stop %d pause" % (i + 1))
				await click("PauseBack")
				await click("SampleChapterSelect")
				check(scene.sample_page == 1, tag + " return to later-page mouse choices")
			await click("SamplePagePrevious")
			await click("SampleChapter3")
			check_sample_play(2)
			await key(KEY_ESCAPE)
			await check_layout(tag + " pause")
			await click("Resume")
			await fake_win()
			await check_layout(tag + " middle-stop result")
			await click("SampleRetry")
			check_sample_play(2)
			await fake_win()
			await click("ResultBack")
			await click("DemoStart")
			check_sample_play(9)
			await fake_win()
			await check_layout(tag + " tenth-stop result")
			await capture("sample-finale-" + tag)
			await click("SampleRetry")
			check_sample_play(9)
			await fake_win()
			await key(KEY_ENTER)
			check(scene.sample_page == 1, tag + " final keyboard action returns to second page")
			check_sample_map()
			await click("SampleChaptersBack")
			await click("ChapterSelect")
			await check_layout(tag + " original nine-stop map")
			await click("ChaptersBack")
	check(game.best == expected_best, "all fake results and UI actions preserve score fixtures")
	check(game.unlocked == 8 and game.sample_unlocked == 9, "UI does not alter either unlock fixture")
	check(not game.persistence_enabled, "player persistence stays disabled throughout regression")
	scene.free()
	print("UI_REGRESSION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
