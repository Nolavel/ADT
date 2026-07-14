# ProjectScanner.gd
@tool
extends Node

# === СИГНАЛЫ ===
signal scan_completed(folder_count: int, file_count: int)
signal line_count_completed(script_file_count: int, total_line_count: int)
signal scene_stats_completed(scene_count: int, project_size_bytes: int)

# === НАСТРОЙКИ ===
@export var excluded_folders: Array[String] = [
	".git", ".godot", ".mono", "bin", "obj", "shader_cache",
	"temp", "addons", "metadata", "Debug", "ref", "refint", "builds"
]

@export var target_extensions: Array[String] = [".gd", ".cs", ".gdshader"]

# === СЧЁТЧИКИ ===
var total_folders: int = 0
var total_files: int = 0
var script_file_count: int = 0
var script_line_count: int = 0
var scene_file_count: int = 0
var total_project_size_bytes: int = 0

func _ready():
	# Добавляем в группу для поиска из UI
	add_to_group("project_scanner")
	call_deferred("start_scan")

func start_scan():
	# Сброс счётчиков
	total_folders = 0
	total_files = 0
	script_file_count = 0
	script_line_count = 0
	scene_file_count = 0
	total_project_size_bytes = 0
	
	var root_path = ProjectSettings.globalize_path("res://")
	scan_directory_recursive(root_path)
	
	# Эмитим все сигналы
	emit_signal("scan_completed", total_folders, total_files)
	emit_signal("line_count_completed", script_file_count, script_line_count)
	emit_signal("scene_stats_completed", scene_file_count, total_project_size_bytes)

func scan_directory_recursive(directory_path: String):
	var dir = DirAccess.open(directory_path)
	
	if dir == null:
		push_error("❌ Не удалось открыть директорию: " + directory_path)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = directory_path.path_join(file_name)
		
		# Обработка поддиректорий
		if dir.current_is_dir():
			if not is_folder_excluded(file_name):
				total_folders += 1
				scan_directory_recursive(full_path)
		else:
			# Обработка файлов
			process_file(full_path, file_name)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

func process_file(file_path: String, file_name: String):
	var ext = file_path.get_extension().to_lower()
	
	# Пропускаем служебные файлы
	if file_name.ends_with(".import") or file_name.ends_with(".tmp") or file_name == ".DS_Store":
		return
	
	total_files += 1
	
	# Подсчёт размера файла
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		total_project_size_bytes += file.get_length()
		file.close()
	else:
		push_warning("⚠️ Не удалось получить размер '%s'" % file_path)
	
	# Подсчёт сцен
	if ext == "tscn":
		scene_file_count += 1
	
	# Подсчёт строк в скриптах
	if not ("." + ext) in target_extensions:
		return
	
	count_script_lines(file_path, ext)

func count_script_lines(file_path: String, ext: String):
	var file = FileAccess.open(file_path, FileAccess.READ)
	
	if file == null:
		push_error("❌ Ошибка при чтении '%s'" % file_path)
		return
	
	var valid_lines = 0
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		
		# Пропускаем пустые строки
		if line.is_empty():
			continue
		
		# Пропускаем комментарии
		if ext == "gd" or ext == "gdshader":
			if line.begins_with("#"):
				continue
		elif ext == "cs":
			if line.begins_with("//"):
				continue
		
		valid_lines += 1
	
	file.close()
	
	if valid_lines > 0:
		script_file_count += 1
	
	script_line_count += valid_lines

func is_folder_excluded(folder_name: String) -> bool:
	for excluded in excluded_folders:
		if folder_name.to_lower() == excluded.to_lower():
			return true
	return false
