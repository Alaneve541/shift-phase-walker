extends SceneTree

func _initialize() -> void:
	var file = FileAccess.open("res://build/LICENSE-Godot.txt", FileAccess.WRITE)
	if file == null:
		printerr("Cannot write engine license notices")
		quit(1)
		return
	file.store_line("Godot Engine and included third-party components\n")
	file.store_line(Engine.get_license_text())
	for component in Engine.get_copyright_info():
		file.store_line("\n" + str(component.get("name", "")))
		for part in component.get("parts", []):
			for notice in part.get("copyright", []):
				file.store_line(str(notice))
			file.store_line("License: " + str(part.get("license", "")))
	var licenses = Engine.get_license_info()
	for name in licenses:
		file.store_line("\n" + str(name) + "\n" + str(licenses[name]))
	file.close()
	quit()
