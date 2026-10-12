class_name ConversationDemo
extends Node
## Тестовая имитация разговора (Этап 1, ТЗ).
##
## Пока нет сервера: генерирует реплики «интервьюера» из очереди,
## переводит аватар по конечному циклу состояний
##   THINKING → SPEAKING → LISTENING → (ответ пользователя) → …
## Движение губ во время SPEAKING имитирует аудио-сигнал
## (в Этапе 3 будет заменено на амплитуду TTS-аудио).
## Эмитит сигналы, которые UI подписывает на реплики и состояния.

signal interviewer_text(text: String)
signal state_changed(state: int)
signal user_answer_simulated(text: String)

## Реплики для тестового прогона (русский язык).
const DEMO_LINES: Array[String] = [
	"Здравствуйте! Расскажите, пожалуйста, о своём опыте работы с Python.",
	"Интересно. Какие фреймворки вы использовали в последних проектах?",
	"Понятно. А как вы подходите к тестированию своего кода?",
	"Хорошо. Расскажите о самой сложной задаче, которую вам приходилось решать.",
	"Спасибо! Это были все мои вопросы на сегодня.",
]

var avatar: AvatarController
var active := false

var _lines: Array[String] = []
var _line_index := 0
var _phase: int = Phase.THINKING
var _phase_time := 0.0
var _speech_duration := 0.0
var _phase_duration := 0.0
var _listening_left := 0.0

## Текущая реплика, которую «произносит» аватар.
var current_line := ""

## Длительность паузы «слушания» после каждой реплики, сек.
const LISTEN_DURATION := 2.5

enum Phase { THINKING, SPEAKING, LISTENING, FINISHED }


func start() -> void:
	if active:
		return
	active = true
	_lines = DEMO_LINES.duplicate()
	_line_index = 0
	_set_phase(Phase.THINKING)


func stop() -> void:
	active = false
	_set_phase(Phase.FINISHED)


func _process(delta: float) -> void:
	if not active:
		return
	_phase_time += delta
	match _phase:
		Phase.THINKING:
			if _phase_time >= _phase_duration:
				_start_next_line()
		Phase.SPEAKING:
			# Имитация речевого сигнала: сумма синусоид + шум.
			var t := _phase_time
			var amp := 0.5 + 0.5 * sin(t * 11.0) * sin(t * 5.3 + 1.7)
			amp = amp * 0.75 + randf() * 0.25
			avatar.set_mouth_openness(amp)
			if _phase_time >= _phase_duration:
				avatar.set_mouth_openness(0.0)
				_set_phase(Phase.LISTENING)
		Phase.LISTENING:
			_listening_left -= delta
			if _listening_left <= 0.0:
				if _line_index >= _lines.size():
					active = false
					_set_phase(Phase.FINISHED)
				else:
					_set_phase(Phase.THINKING)
		Phase.FINISHED:
			pass


func _set_phase(phase: int) -> void:
	_phase = phase
	_phase_time = 0.0
	match phase:
		Phase.THINKING:
			_phase_duration = randf_range(0.6, 1.2)
			avatar.set_state(AvatarController.AvatarState.THINKING)
			avatar.set_emotion(AvatarController.Emotion.THOUGHTFUL)
			avatar.play_gesture(&"think")
		Phase.SPEAKING:
			avatar.set_state(AvatarController.AvatarState.SPEAKING)
			avatar.set_emotion(AvatarController.Emotion.NEUTRAL)
		Phase.LISTENING:
			_listening_left = LISTEN_DURATION
			avatar.set_state(AvatarController.AvatarState.LISTENING)
			avatar.set_emotion(AvatarController.Emotion.INTERESTED)
			avatar.play_gesture(&"nod")
			# Эмулируем ответ пользователя (на Этапе 3 — речь из микрофона).
			var answer := _fake_user_answer()
			user_answer_simulated.emit(answer)
		Phase.FINISHED:
			avatar.set_state(AvatarController.AvatarState.IDLE)
			avatar.set_emotion(AvatarController.Emotion.NEUTRAL)
	state_changed.emit(phase)


func _start_next_line() -> void:
	if _line_index >= _lines.size():
		active = false
		_set_phase(Phase.FINISHED)
		return
	current_line = _lines[_line_index]
	_line_index += 1
	# Грубая оценка длительности речи: ~14 символов в секунду.
	_speech_duration = clampf(current_line.length() / 14.0, 1.5, 6.0)
	_phase_duration = _speech_duration
	interviewer_text.emit(current_line)
	_set_phase(Phase.SPEAKING)


func _fake_user_answer() -> String:
	var answers: Array[String] = [
		"[эмуляция] Я работал с Python около пяти лет, в основном backend.",
		"[эмуляция] Использовал FastAPI, Django и немного aiohttp.",
		"[эмуляция] Пишу unit-тесты на pytest, стараюсь покрывать критичные места.",
		"[эмуляция] Оптимизировал медленные запросы к PostgreSQL.",
		"[эмуляция] Спасибо за интервью!",
	]
	return answers[mini(_line_index - 1, answers.size() - 1)]
