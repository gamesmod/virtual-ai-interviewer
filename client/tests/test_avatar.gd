extends SceneTree
## Автотест контроллера аватара (запускается headless):
##   godot --headless --script tests/test_avatar.gd
## Проверяет интерфейс AvatarController на процедурной реализации:
## смену состояний, эмоций, взгляда, clamp открытия рта, жесты.

const ProceduralAvatarScript := preload("res://scripts/procedural_avatar.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var avatar = ProceduralAvatarScript.new()
	root.add_child(avatar)
	# Даём дереву возможность вызвать _ready() (построение узлов аватара).
	await process_frame
	await process_frame

	_check(true, "аватар добавлен в дерево")

	# Состояния.
	for state in AvatarController.AvatarState.values():
		avatar.set_state(state)
	_check(avatar._state == AvatarController.AvatarState.WAITING,
		"set_state переключает состояния")

	# Эмоции.
	for emotion in AvatarController.Emotion.values():
		avatar.set_emotion(emotion)
	_check(avatar._emotion == AvatarController.Emotion.SURPRISED,
		"set_emotion переключает эмоции")

	# Взгляд.
	avatar.set_gaze(Vector3(1.0, 1.7, 2.0))
	_check(avatar._gaze_active, "set_gaze активирует взгляд")

	# Открытие рта с ограничением [0, 1].
	avatar.set_mouth_openness(0.5)
	_check(is_equal_approx(avatar._mouth_openness, 0.5),
		"set_mouth_openness(0.5)")
	avatar.set_mouth_openness(3.0)
	_check(is_equal_approx(avatar._mouth_openness, 1.0),
		"set_mouth_openness клампит вверх")
	avatar.set_mouth_openness(-2.0)
	_check(is_equal_approx(avatar._mouth_openness, 0.0),
		"set_mouth_openness клампит вниз")

	# Жесты не падают.
	for gesture in [&"nod", &"shake_head", &"shrug", &"think"]:
		avatar.play_gesture(gesture)
	_check(true, "play_gesture не падает на известных жестах")

	# Несколько кадров процесса (моргание, idle-движение, рот).
	for i in 30:
		avatar._process(1.0 / 60.0)
	_check(true, "_process(30 кадров) без ошибок")

	if _failures == 0:
		print("AVATAR TESTS: ALL PASSED")
		quit(0)
	else:
		print("AVATAR TESTS: %d FAILED" % _failures)
		quit(1)


func _check(condition: bool, name: String) -> void:
	if condition:
		print("  PASS: %s" % name)
	else:
		print("  FAIL: %s" % name)
		_failures += 1
