class_name ResourceBootstrap
extends RefCounted

const TARGET_ROOT := "user://assets"
const MODS_ROOT := "user://mods"
const SOURCE_CONTENT_PACKAGES_ROOT := "res://assets/content_packages"
const TARGET_CONTENT_PACKAGES_ROOT := TARGET_ROOT + "/content_packages"
const DEFAULT_PACKAGE_NAME := "simple_warfare_core_v0_1"
const BOOTSTRAP_VERSION := "3"
const VERSION_FILE := TARGET_ROOT + "/.bootstrap_version"


func ensure_ready(force := false) -> Dictionary:
	var result := {
		"ok": false,
		"status": "not_started",
		"message": "",
	}

	var was_current_version_ready := !force && _is_current_version_ready()

	for directory_path in [TARGET_ROOT, MODS_ROOT]:
		var dir_error := DirAccess.make_dir_recursive_absolute(directory_path)
		if dir_error != OK:
			result.status = "failed"
			result.message = "failed to create runtime directory %s: %s" % [directory_path, error_string(dir_error)]
			return result

	var sync_error := _sync_directory(SOURCE_CONTENT_PACKAGES_ROOT, TARGET_CONTENT_PACKAGES_ROOT)
	if sync_error != OK:
		result.status = "failed"
		result.message = "failed to sync content packages: %s" % error_string(sync_error)
		return result

	var version_error := _write_text(VERSION_FILE, BOOTSTRAP_VERSION)
	if version_error != OK:
		result.status = "failed"
		result.message = "failed to write bootstrap version: %s" % error_string(version_error)
		return result

	result.ok = true
	result.status = "ready" if was_current_version_ready else "initialized"
	result.message = "runtime resource directories initialized and content packages synced"
	return result


func _is_current_version_ready() -> bool:
	if !FileAccess.file_exists(VERSION_FILE):
		return false

	var file := FileAccess.open(VERSION_FILE, FileAccess.READ)
	if file == null:
		return false

	return file.get_as_text().strip_edges() == BOOTSTRAP_VERSION


func _write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(text)
	return OK


func _sync_directory(source_path: String, target_path: String) -> Error:
	var source_dir := DirAccess.open(source_path)
	if source_dir == null:
		return DirAccess.get_open_error()

	var make_dir_error := DirAccess.make_dir_recursive_absolute(target_path)
	if make_dir_error != OK:
		return make_dir_error

	source_dir.list_dir_begin()
	while true:
		var entry_name := source_dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." || entry_name == "..":
			continue

		var source_entry := source_path.path_join(entry_name)
		var target_entry := target_path.path_join(entry_name)

		if source_dir.current_is_dir():
			var child_error := _sync_directory(source_entry, target_entry)
			if child_error != OK:
				source_dir.list_dir_end()
				return child_error
		else:
			var copy_error := _copy_file(source_entry, target_entry)
			if copy_error != OK:
				source_dir.list_dir_end()
				return copy_error

	source_dir.list_dir_end()
	return OK


func _copy_file(source_path: String, target_path: String) -> Error:
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return FileAccess.get_open_error()

	var target_file := FileAccess.open(target_path, FileAccess.WRITE)
	if target_file == null:
		return FileAccess.get_open_error()

	target_file.store_buffer(source_file.get_buffer(source_file.get_length()))
	return OK
