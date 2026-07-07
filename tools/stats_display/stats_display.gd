extends Control

var stats_label: RichTextLabel
var stats_timer: Timer
var play_session_start_time: float = 0.0

func _ready():

	# Label
	if not stats_label:
		stats_label = RichTextLabel.new()
		stats_label.bbcode_enabled = true
		add_child(stats_label)

	# Timer
	if not stats_timer:
		stats_timer = Timer.new()
		add_child(stats_timer)
		stats_timer.timeout.connect(_on_stats_timer_timeout)

	# UI
	setup_ui_positioning()
	setup_label_style()

	# Start
	play_session_start_time = Time.get_unix_time_from_system()
	stats_timer.wait_time = 0.5
	stats_timer.start()


func setup_ui_positioning():
	var _screen_size = get_viewport().get_visible_rect().size
	size = Vector2(250, 200)
	position = Vector2(_screen_size.x - size.x - 10, 10)
	#position = Vector2(1720, 10)
	z_index = 1000


func setup_label_style():
	if stats_label:
		stats_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stats_label.scroll_active = false


func _on_stats_timer_timeout():
	if not stats_label:
		return

	var fps := Engine.get_frames_per_second()
	var frame_ms := get_process_delta_time() * 1000.0
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	var ram := OS.get_static_memory_usage() / (1024.0 * 1024.0)

	var uptime_seconds = int(Time.get_unix_time_from_system() - play_session_start_time)
	var uptime_string = Time.get_time_string_from_unix_time(uptime_seconds)

	# Цвета
	var fps_color = "green" if fps >= 50 else ("yellow" if fps >= 30 else "red")
	var frame_color = "green" if frame_ms < 16.7 else ("yellow" if frame_ms < 33.0 else "red")
	var proc_color = "green" if proc_ms < 4.0 else ("yellow" if proc_ms < 8.0 else "red")
	var phys_color = "green" if phys_ms < 4.0 else ("yellow" if phys_ms < 8.0 else "red")

	# BBCode текст для RichTextLabel
	var stats_text = (
		"[b]FPS:[/b] [color=%s]%d[/color]\n" % [fps_color, fps] +
		"[b]Frame:[/b] [color=%s]%.2f ms[/color]\n" % [frame_color, frame_ms] +
		"[b]Proc:[/b] [color=%s]%.2f ms[/color]\n" % [proc_color, proc_ms] +
		"[b]Physics:[/b] [color=%s]%.2f ms[/color]\n" % [phys_color, phys_ms] +
		"[b]Draw:[/b] %d\n" % draw_calls +
		"[b]VRAM:[/b] %.1f MB\n" % vram +
		"[b]RAM:[/b] %.1f MB\n" % ram +
		"[b]Uptime:[/b] %s" % uptime_string
	)
	
	stats_label.bbcode_text = stats_text

	# Вывод в консоль. Здесь мы используем обычный текст, без BBCode
	var _console_text = (
		"FPS: %d\n" % fps +
		"Frame: %.2f ms\n" % frame_ms +
		"Proc: %.2f ms\n" % proc_ms +
		"Physics: %.2f ms\n" % phys_ms +
		"Draw: %d\n" % draw_calls +
		"VRAM: %.1f MB\n" % vram +
		"RAM: %.1f MB\n" % ram +
		"Uptime: %s" % uptime_string
	)
	
	#print(console_text)
