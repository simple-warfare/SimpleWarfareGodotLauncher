extends Control

const CONTENT_ROOT := "res://assets/content_packages"

@onready var _title: Label = %Title
@onready var _mod_list: VBoxContainer = %ModList
@onready var _back_button: Button = %BackButton
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	print("[Mods] _ready called, nodes: title=", _title, " list=", _mod_list, " back=", _back_button, " status=", _status_label)
	_back_button.pressed.connect(_go_back)
	_refresh_mod_list()


func _refresh_mod_list() -> void:
	for child in _mod_list.get_children():
		child.queue_free()

	var packages := _scan_content_packages()
	if packages.is_empty():
		_status_label.text = "未找到内容包（检查 assets/content_packages 目录）"
		return

	var test := Label.new()
	test.text = "DEBUG: mod_list ready, child_count=%d" % _mod_list.get_child_count()
	test.add_theme_font_size_override("font_size", 16)
	test.add_theme_color_override("font_color", Color.RED)
	_mod_list.add_child(test)

	_status_label.text = "共 %d 个内容包" % packages.size()
	for pkg in packages:
		_mod_list.add_child(_make_mod_card(pkg))


func _scan_content_packages() -> Array:
	print("[Mods] scanning ", CONTENT_ROOT)
	var result: Array = []
	var dir := DirAccess.open(CONTENT_ROOT)
	if dir == null:
		var err := DirAccess.get_open_error()
		_status_label.text = "无法访问内容包目录: %s (error=%d)" % [CONTENT_ROOT, err]
		print("[Mods] DirAccess.open failed: error=", err)
		return result

	dir.list_dir_begin()
	var entry := dir.get_next()
	while !entry.is_empty():
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue

		var pkg_path := CONTENT_ROOT.path_join(entry)
		print("[Mods] found entry: ", entry, " is_dir=", dir.current_is_dir())
		if !dir.current_is_dir():
			entry = dir.get_next()
			continue

		var manifest_path := pkg_path.path_join("manifest.toml")
		print("[Mods] checking manifest: ", manifest_path, " exists=", FileAccess.file_exists(manifest_path))
		if !FileAccess.file_exists(manifest_path):
			entry = dir.get_next()
			continue

		var manifest := _parse_manifest(manifest_path)
		print("[Mods] manifest parsed: ", manifest)
		if manifest.is_empty():
			entry = dir.get_next()
			continue

		var map_count := _count_files(pkg_path.path_join("maps"), [".toml"])
		var unit_count := _count_files(pkg_path.path_join("units"), [".toml"])
		var terrain_count := _count_files(pkg_path.path_join("terrain"), [".toml"])
		var has_package_lock := FileAccess.file_exists(pkg_path.path_join("package_lock.toml"))

		manifest["dir_name"] = entry
		manifest["map_count"] = map_count
		manifest["unit_count"] = unit_count
		manifest["terrain_count"] = terrain_count
		manifest["has_package_lock"] = has_package_lock
		result.append(manifest)

		entry = dir.get_next()

	dir.list_dir_end()
	return result


func _parse_manifest(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var content := file.get_as_text()
	file.close()

	var manifest: Dictionary = {}
	for line in content.split("\n"):
		var stripped := line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("#"):
			continue
		var parts := stripped.split("=", true, 1)
		if parts.size() != 2:
			continue
		var key := parts[0].strip_edges()
		var raw_value := parts[1].strip_edges().trim_prefix('"').trim_suffix('"')
		manifest[key] = raw_value

	return manifest


func _count_files(dir_path: String, extensions: Array) -> int:
	var d := DirAccess.open(dir_path)
	if d == null:
		return 0

	var count := 0
	d.list_dir_begin()
	var f := d.get_next()
	while !f.is_empty():
		if f != "." and f != "..":
			for ext in extensions:
				if f.ends_with(ext):
					count += 1
					break
		f = d.get_next()
	d.list_dir_end()
	return count


func _make_mod_card(pkg: Dictionary) -> Control:
	var card := MarginContainer.new()
	card.add_theme_constant_override("margin_left", 8)
	card.add_theme_constant_override("margin_top", 6)
	card.add_theme_constant_override("margin_right", 8)
	card.add_theme_constant_override("margin_bottom", 6)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	card.add_child(content)

	# Row 1: title + version
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	content.add_child(row1)

	var title := Label.new()
	title.text = str(pkg.get("title", pkg.get("id", "???")))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 0.8))
	row1.add_child(title)

	var ver := Label.new()
	ver.text = "v%s" % pkg.get("version", "?")
	ver.add_theme_color_override("font_color", Color(0.5, 0.65, 0.4))
	row1.add_child(ver)

	# Row 2: tags
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	content.add_child(row2)

	row2.add_child(_tag("地图 %d" % pkg.get("map_count", 0), Color(0.3, 0.5, 0.7)))
	row2.add_child(_tag("单位 %d" % pkg.get("unit_count", 0), Color(0.6, 0.4, 0.2)))
	row2.add_child(_tag("地形 %d" % pkg.get("terrain_count", 0), Color(0.35, 0.5, 0.25)))

	var has_lock := bool(pkg.get("has_package_lock", false))
	if has_lock:
		row2.add_child(_tag("已锁定", Color(0.15, 0.5, 0.15)))
	else:
		row2.add_child(_tag("未锁定", Color(0.6, 0.45, 0.1)))

	# Row 3: id + path
	var row3 := HBoxContainer.new()
	content.add_child(row3)

	var id_label := Label.new()
	id_label.text = str(pkg.get("id", "?"))
	id_label.add_theme_font_size_override("font_size", 11)
	id_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.35))
	row3.add_child(id_label)

	var dir_label := Label.new()
	dir_label.text = str(pkg.get("dir_name", ""))
	dir_label.add_theme_font_size_override("font_size", 11)
	dir_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.3))
	row3.add_child(dir_label)

	return card


func _tag(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	return l


func _go_back() -> void:
	SceneRouter.go_to_main_menu()
