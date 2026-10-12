extends AvatarController
## Процедурный 3D-аватар интервьюера (MVP, ТЗ раздел 4).
##
## Человекоподобная голова и верхняя часть тела собираются из примитивов
## Godot без внешних платных ассетов. Реализует интерфейс AvatarController:
##   - морфинг рта (set_mouth_openness) — синхронизация губ с речью;
##   - моргание — периодическое сжатие глазных яблок + опускание бровей;
##   - повороты головы и движение глаз (set_gaze);
##   - нейтральное выражение и реакции (set_emotion);
##   - анимации ожидания, слушания и разговора (set_state);
##   - жесты: nod (кивок), shake_head, shrug, think (рука к подбородку).

const SKIN := Color(0.87, 0.67, 0.53)
const SKIN_DARK := Color(0.78, 0.58, 0.45)
const SHIRT := Color(0.16, 0.24, 0.38)
const HAIR := Color(0.13, 0.09, 0.07)
const MOUTH := Color(0.35, 0.12, 0.12)

var _state: int = AvatarState.IDLE
var _emotion: int = Emotion.NEUTRAL
var _gaze_target := Vector3.ZERO
var _gaze_active := false
var _mouth_openness := 0.0

# Узлы, собираемые в _build()
var _head_pivot: Node3D          # точка поворота головы (шея)
var _head_mesh: MeshInstance3D
var _eye_l: MeshInstance3D
var _eye_r: MeshInstance3D
var _pupil_l: MeshInstance3D
var _pupil_r: MeshInstance3D
var _brow_l: MeshInstance3D
var _brow_r: MeshInstance3D
var _mouth: MeshInstance3D
var _arm_l: Node3D               # плечо-рука (pivot)
var _arm_r: Node3D
var _neck: Node3D

# Случайное поведение
var _blink_timer := 2.0
var _blink_phase := 0.0          # 0 = глаза открыты, 1 = закрыты
var _idle_seed := 0.0
var _head_target := Vector3.ZERO # целевые углы поворота головы
var _surprise_tween: Tween
var _base_brow_y := 0.0


func _ready() -> void:
	_idle_seed = randf() * 100.0
	_build()
	set_state(AvatarState.IDLE)
	set_emotion(Emotion.NEUTRAL)


func _process(delta: float) -> void:
	_update_blink(delta)
	_update_idle_motion(delta)
	_apply_mouth()


# ---------------------------------------------------------------- интерфейс

func set_state(state: int) -> void:
	_state = state
	match state:
		AvatarState.SPEAKING:
			# Взгляд на собеседника, лёгкие кивки добавляются в _update_idle_motion.
			_gaze_active = false
		AvatarState.LISTENING:
			_gaze_active = true
			_gaze_target = _default_gaze_point()
		AvatarState.THINKING:
			_gaze_active = true
			_gaze_target = _default_gaze_point() + Vector3(0.35, 0.15, 0.0)
		AvatarState.WAITING, AvatarState.IDLE:
			_gaze_active = false


func set_emotion(emotion: int) -> void:
	_emotion = emotion
	match emotion:
		Emotion.NEUTRAL:
			_set_brow_offset(0.0)
			_set_brow_tilt(0.0)
		Emotion.INTERESTED:
			_set_brow_offset(0.03)
			_set_brow_tilt(-0.12)
		Emotion.THOUGHTFUL:
			_set_brow_offset(-0.01)
			_set_brow_tilt(0.25)
		Emotion.SURPRISED:
			_set_brow_offset(0.06)
			_set_brow_tilt(-0.05)
			# Кратковременное поднятие бровей.
			if _surprise_tween:
				_surprise_tween.kill()
			_surprise_tween = create_tween()
			_surprise_tween.tween_interval(1.2)
			_surprise_tween.tween_callback(func() -> void:
				if _emotion == Emotion.SURPRISED:
					set_emotion(Emotion.NEUTRAL))


func set_gaze(target: Vector3) -> void:
	_gaze_target = target
	_gaze_active = true


func set_mouth_openness(value: float) -> void:
	_mouth_openness = clampf(value, 0.0, 1.0)


func play_gesture(gesture: StringName) -> void:
	match gesture:
		&"nod":
			_tween_rotation(_head_pivot, Vector3(0.22, 0.0, 0.0), 0.22, true)
		&"shake_head":
			_tween_rotation(_head_pivot, Vector3(0.0, 0.35, 0.0), 0.2, true)
		&"shrug":
			_tween_rotation(_arm_l, Vector3(0.0, 0.0, 0.7), 0.25, true)
			_tween_rotation(_arm_r, Vector3(0.0, 0.0, -0.7), 0.25, true)
		&"think":
			# Рука к подбородку + наклон головы, затем плавный возврат.
			_tween_rotation(_arm_r, Vector3(-0.55, 0.0, -0.5), 0.45, false)
			_tween_rotation(_head_pivot, Vector3(0.12, 0.15, 0.08), 0.4, false)
			var t := create_tween()
			t.tween_interval(2.0)
			t.tween_callback(func() -> void:
				var back := create_tween()
				back.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				back.tween_property(_arm_r, "rotation", Vector3.ZERO, 0.5)
				back.parallel().tween_property(
					_head_pivot, "rotation", Vector3.ZERO, 0.5))
		_:
			push_warning("Неизвестный жест: %s" % gesture)


# ---------------------------------------------------------------- построение

func _build() -> void:
	# --- торс ---
	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.34
	torso_mesh.height = 0.9
	torso.mesh = torso_mesh
	torso.material_override = _mat(SHIRT)
	torso.position = Vector3(0.0, 0.75, 0.0)
	add_child(torso)

	# --- плечи и руки (упрощённые цилиндры на pivot) ---
	_arm_l = _make_arm(Vector3(-0.44, 1.05, 0.0))
	_arm_r = _make_arm(Vector3(0.44, 1.05, 0.0))
	add_child(_arm_l)
	add_child(_arm_r)

	# --- шея и pivot головы ---
	_neck = Node3D.new()
	_neck.position = Vector3(0.0, 1.28, 0.0)
	add_child(_neck)

	_head_pivot = Node3D.new()
	_neck.add_child(_head_pivot)

	var neck_mesh := MeshInstance3D.new()
	var neck_cyl := CylinderMesh.new()
	neck_cyl.top_radius = 0.11
	neck_cyl.bottom_radius = 0.13
	neck_cyl.height = 0.22
	neck_mesh.mesh = neck_cyl
	neck_mesh.material_override = _mat(SKIN)
	neck_mesh.position = Vector3(0.0, 0.08, 0.0)
	_head_pivot.add_child(neck_mesh)

	# --- голова ---
	_head_mesh = MeshInstance3D.new()
	var head_sphere := SphereMesh.new()
	head_sphere.radius = 0.26
	head_sphere.height = 0.52
	_head_mesh.mesh = head_sphere
	_head_mesh.material_override = _mat(SKIN)
	_head_mesh.position = Vector3(0.0, 0.42, 0.0)
	_head_pivot.add_child(_head_mesh)

	# волосы: слегка увеличенная сфера с вырезом спереди не нужна — делаем
	# полусферу сверху (is_hemisphere) чуть большего радиуса.
	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.265
	hair_mesh.height = 0.53
	hair_mesh.is_hemisphere = true
	hair.mesh = hair_mesh
	hair.material_override = _mat(HAIR)
	hair.position = Vector3(0.0, 0.56, -0.03)
	_head_pivot.add_child(hair)

	# --- глаза ---
	_eye_l = _make_eye(Vector3(-0.1, 0.46, 0.21))
	_eye_r = _make_eye(Vector3(0.1, 0.46, 0.21))
	_head_pivot.add_child(_eye_l)
	_head_pivot.add_child(_eye_r)

	# --- брови ---
	_brow_l = _make_brow(Vector3(-0.1, 0.585, 0.225))
	_brow_r = _make_brow(Vector3(0.1, 0.585, 0.225))
	_head_pivot.add_child(_brow_l)
	_head_pivot.add_child(_brow_r)
	_base_brow_y = _brow_l.position.y

	# --- нос ---
	var nose := MeshInstance3D.new()
	var nose_mesh := SphereMesh.new()
	nose_mesh.radius = 0.035
	nose_mesh.height = 0.07
	nose.mesh = nose_mesh
	nose.material_override = _mat(SKIN_DARK)
	nose.position = Vector3(0.0, 0.4, 0.265)
	nose.scale = Vector3(0.8, 1.3, 1.0)
	_head_pivot.add_child(nose)

	# --- рот (морфинг через масштаб) ---
	_mouth = MeshInstance3D.new()
	var mouth_mesh := SphereMesh.new()
	mouth_mesh.radius = 0.07
	mouth_mesh.height = 0.14
	_mouth.mesh = mouth_mesh
	_mouth.material_override = _mat(MOUTH)
	_mouth.position = Vector3(0.0, 0.27, 0.22)
	_mouth.scale = Vector3(1.4, 0.15, 0.6)
	_head_pivot.add_child(_mouth)


func _make_arm(pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	var arm := MeshInstance3D.new()
	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.09
	arm_mesh.height = 0.62
	arm.mesh = arm_mesh
	arm.material_override = _mat(SHIRT)
	arm.position = Vector3(0.0, -0.28, 0.0)
	pivot.add_child(arm)
	var hand := MeshInstance3D.new()
	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.08
	hand_mesh.height = 0.16
	hand.mesh = hand_mesh
	hand.material_override = _mat(SKIN)
	hand.position = Vector3(0.0, -0.58, 0.0)
	pivot.add_child(hand)
	return pivot


func _make_eye(pos: Vector3) -> MeshInstance3D:
	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.055
	eye_mesh.height = 0.11
	eye.mesh = eye_mesh
	eye.material_override = _mat(Color.WHITE)
	eye.position = pos
	# Зрачок — чёрная сфера, выступающая вперёд; следит за целью взгляда.
	var pupil := MeshInstance3D.new()
	var pupil_mesh := SphereMesh.new()
	pupil_mesh.radius = 0.024
	pupil_mesh.height = 0.048
	pupil.mesh = pupil_mesh
	pupil.material_override = _mat(Color(0.05, 0.05, 0.08))
	pupil.position = Vector3(0.0, 0.0, 0.045)
	eye.add_child(pupil)
	if pos.x < 0.0:
		_pupil_l = pupil
	else:
		_pupil_r = pupil
	return eye


func _make_brow(pos: Vector3) -> MeshInstance3D:
	var brow := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.018, 0.02)
	brow.mesh = box
	brow.material_override = _mat(HAIR)
	brow.position = pos
	return brow


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m


# ---------------------------------------------------------------- анимации

func _update_blink(delta: float) -> void:
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(1.8, 4.5)
		_blink_phase = 1.0
	if _blink_phase > 0.0:
		_blink_phase = maxf(0.0, _blink_phase - delta * 9.0)
	# Быстрое закрытие, медленное открытие.
	var close_amount := _blink_phase
	if _blink_phase > 0.5:
		close_amount = 1.0 - (_blink_phase - 0.5) * 2.0
	var eye_scale_y := lerpf(1.0, 0.08, close_amount)
	_eye_l.scale.y = eye_scale_y
	_eye_r.scale.y = eye_scale_y


func _update_idle_motion(delta: float) -> void:
	# Плавный поворот головы к целевым углам.
	var speed := 3.0
	var target := _head_target
	if _gaze_active:
		# Поворачиваем голову в сторону точки взгляда.
		var local := _head_pivot.global_transform.affine_inverse() * _gaze_target
		target.y = clampf(atan2(local.x, local.z) * 0.35, -0.5, 0.5)
		target.x = clampf(-atan2(local.y - 0.42, maxf(0.2, local.z)) * 0.3, -0.3, 0.35)
	else:
		# Спонтанные покачивания + кивки во время речи.
		var t := Time.get_ticks_msec() / 1000.0 + _idle_seed
		target.y = sin(t * 0.4) * 0.06
		target.x = sin(t * 0.53) * 0.04
		if _state == AvatarState.SPEAKING:
			target.x += sin(t * 5.1) * 0.03
		elif _state == AvatarState.LISTENING:
			target.x += sin(t * 1.1) * 0.02
	_head_pivot.rotation.x = lerpf(_head_pivot.rotation.x, target.x, delta * speed)
	_head_pivot.rotation.y = lerpf(_head_pivot.rotation.y, target.y, delta * speed)

	# Движение зрачков к цели взгляда.
	if _gaze_active:
		var lp := _eye_l.to_local(_gaze_target)
		var rp := _eye_r.to_local(_gaze_target)
		_pupil_l.position = _pupil_l.position.lerp(
			_pupil_offset(lp), delta * 6.0)
		_pupil_r.position = _pupil_r.position.lerp(
			_pupil_offset(rp), delta * 6.0)
	else:
		var base := Vector3(0.0, 0.0, 0.045)
		_pupil_l.position = _pupil_l.position.lerp(base, delta * 6.0)
		_pupil_r.position = _pupil_r.position.lerp(base, delta * 6.0)


func _pupil_offset(local_target: Vector3) -> Vector3:
	var dir := (local_target - Vector3(0.0, 0.0, 0.0)).normalized()
	return Vector3(dir.x, dir.y, 0.0).limit_length(0.02) + Vector3(0.0, 0.0, 0.045)


func _apply_mouth() -> void:
	# Открытие рта: масштаб Y от 0.15 (закрыт) до 1.6 (открыт).
	_mouth.scale.y = lerpf(0.15, 1.6, _mouth_openness)


func _set_brow_offset(dy: float) -> void:
	_brow_l.position.y = _base_brow_y + dy
	_brow_r.position.y = _base_brow_y + dy


func _set_brow_tilt(angle: float) -> void:
	_brow_l.rotation.z = angle
	_brow_r.rotation.z = -angle


func _tween_rotation(node: Node3D, offset: Vector3, dur: float, and_back: bool) -> void:
	var base := node.rotation
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(node, "rotation", base + offset, dur)
	if and_back:
		t.tween_property(node, "rotation", base, dur * 1.4)
		t = null
	else:
		# Возврат в исходное положение вызывает жест "think" отдельно.
		pass


func _default_gaze_point() -> Vector3:
	# Точка перед аватаром на уровне глаз — «камера собеседника».
	return global_transform * Vector3(0.0, 1.7, 2.0)
