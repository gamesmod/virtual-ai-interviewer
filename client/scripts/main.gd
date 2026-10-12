extends Node3D
## Точка входа клиента (Этап 1): сцена с процедурным 3D-аватаром,
## камерой, освещением, UI и тестовой имитацией разговора.
##
## Режимы запуска:
##   обычный — интерактивное окно;
##   --demo   — автоматический прогон имитации собеседования (для headless);
##   --server --server-url=ws://… — диалог с backend по WebSocket;
##   --screenshot=<путь> — сохранить кадр через 4 с и выйти (для проверок CI).

const ProceduralAvatarScript := preload("res://scripts/procedural_avatar.gd")
const ConversationDemoScript := preload("res://scripts/conversation_demo.gd")
const ServerConversationScript := preload("res://scripts/server_conversation.gd")

var avatar: AvatarController
var demo: ConversationDemo

var _label_line: Label
var _label_state: Label
var _mic_indicator: ColorRect
var _label_timer: Label
var _transcript: VBoxContainer
var _elapsed := 0.0
var _run_demo := false
var _run_server := false
var _server_url := "ws://127.0.0.1:8000/ws"
var _screenshot_path := ""
var _screenshot_taken := false


func _ready() -> void:
	_parse_args()
	_build_environment()
	_build_avatar()
	_build_ui()
	# Демонстрация реакций вне зависимости от режима.
	avatar.play_gesture(&"nod")
	if _run_server:
		var server_conv = ServerConversationScript.new()
		server_conv.avatar = avatar
		add_child(server_conv)
		server_conv.finished.connect(func() -> void:
			print("SERVER: finished")
			get_tree().quit())
		server_conv.start(_server_url)
	elif _run_demo:
		demo = ConversationDemoScript.new()
		demo.avatar = avatar
		add_child(demo)
		demo.interviewer_text.connect(_on_interviewer_text)
		demo.user_answer_simulated.connect(_on_user_answer)
		demo.start()


func _process(delta: float) -> void:
	_elapsed += delta
	if _label_timer:
		_label_timer.text = _format_time(_elapsed)
	if avatar != null and _label_state != null:
		_label_state.text = "Состояние: %s" % _state_name(avatar._state)
	# Индикатор микрофона: «горит», когда аватар слушает.
	if _mic_indicator and demo:
		var listening: bool = demo._phase == ConversationDemo.Phase.LISTENING
		_mic_indicator.color = Color(0.2, 0.9, 0.3) if listening else Color(0.35, 0.35, 0.35)
	if _screenshot_path != "" and not _screenshot_taken and _elapsed >= 4.0:
		_screenshot_taken = true
		_take_screenshot(_screenshot_path)
		get_tree().quit()


# ---------------------------------------------------------------- сцена

func _build_environment() -> void:
	# Камера напротив аватара (уровень глаз).
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.55, 2.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.45, 0.0))
	camera.current = true

	var light := DirectionalLight3D.new()
	light.position = Vector3(2.0, 4.0, 3.0)
	light.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	light.light_energy = 1.6
	add_child(light)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.5, 2.0, 1.5)
	fill.light_energy = 0.6
	add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.27, 0.32)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

	# Пол.
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10.0, 10.0)
	floor.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.14, 0.15, 0.18)
	floor.material_override = floor_mat
	add_child(floor)


func _build_avatar() -> void:
	avatar = ProceduralAvatarScript.new()
	avatar.position = Vector3(0.0, 0.0, 0.0)
	add_child(avatar)


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Панель внизу: реплика интервьюера.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -170.0
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	_label_line = Label.new()
	_label_line.text = "…"
	_label_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_line.add_theme_font_size_override("font_size", 24)
	margin.add_child(_label_line)

	# Верхняя панель: состояние, таймер, индикатор микрофона.
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 48.0
	layer.add_child(top)
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_left", 16)
	tm.add_theme_constant_override("margin_top", 10)
	top.add_child(tm)
	_label_state = Label.new()
	_label_state.text = "Состояние: —"
	_label_state.add_theme_font_size_override("font_size", 20)
	tm.add_child(_label_state)
	_label_timer = Label.new()
	_label_timer.text = "00:00"
	_label_timer.add_theme_font_size_override("font_size", 20)
	top.add_child(_label_timer)
	top.add_spacer(false)
	var mic_label := Label.new()
	mic_label.text = "Микрофон "
	mic_label.add_theme_font_size_override("font_size", 20)
	top.add_child(mic_label)
	_mic_indicator = ColorRect.new()
	_mic_indicator.custom_minimum_size = Vector2(20, 20)
	_mic_indicator.color = Color(0.35, 0.35, 0.35)
	top.add_child(_mic_indicator)

	# Транскрипт справа.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	scroll.offset_left = -420.0
	scroll.offset_top = 60.0
	scroll.offset_bottom = -180.0
	layer.add_child(scroll)
	_transcript = VBoxContainer.new()
	_transcript.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_transcript)


func _add_transcript_line(speaker: String, text: String) -> void:
	if _transcript == null:
		return
	var l := Label.new()
	l.text = "%s: %s" % [speaker, text]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 16)
	_transcript.add_child(l)


# ---------------------------------------------------------------- события

func _on_interviewer_text(text: String) -> void:
	_label_line.text = text
	_add_transcript_line("Интервьюер", text)


func _on_user_answer(text: String) -> void:
	_add_transcript_line("Кандидат", text)


func _state_name(state: int) -> String:
	match state:
		AvatarController.AvatarState.IDLE: return "ожидание"
		AvatarController.AvatarState.LISTENING: return "слушание"
		AvatarController.AvatarState.THINKING: return "размышление"
		AvatarController.AvatarState.SPEAKING: return "разговор"
		AvatarController.AvatarState.WAITING: return "пауза"
	return "?"


# ---------------------------------------------------------------- служебное

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo":
			_run_demo = true
		elif arg == "--server":
			_run_server = true
		elif arg.begins_with("--server-url="):
			_server_url = arg.trim_prefix("--server-url=")
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.trim_prefix("--screenshot=")


func _format_time(sec: float) -> String:
	var m := int(sec) / 60
	var s := int(sec) % 60
	return "%02d:%02d" % [m, s]


func _take_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
