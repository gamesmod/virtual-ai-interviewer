class_name ServerConversation
extends Node
## Диалог с сервером по WebSocket (Этап 2).
##
## Заменяет ConversationDemo при запуске с флагом --server:
##   1. отправляет session.start;
##   2. по interviewer.text переводит аватар в speaking и имитирует
##      движение губ на время «речи» (пока нет TTS-аудио);
##   3. по avatar.state=listening отправляет эмулированный ответ
##      кандидата (transcript.final) — до тех пор, пока есть ответы;
##   4. по session.report печатает отчёт и завершает сцену.
##
## Все ключевые события печатаются в stdout с префиксом SERVER —
## по ним headless-проверка определяет успешность диалога.

signal finished

const DEMO_ANSWERS: Array[String] = [
	"Работаю с Python пять лет, последние три — backend на FastAPI.",
	"Пишу тесты на pytest, использую mypy и ruff.",
	"Строил асинхронные сервисы с aiohttp и asyncio.",
	"Оптимизировал запросы к PostgreSQL.",
	"Руководил небольшой командой из трёх разработчиков.",
	"Проектировал REST API и интеграции с внешними сервисами.",
]

var avatar: AvatarController
var client: WSClient

var _answer_index := 0
var _session_id := ""
var _speaking_left := 0.0
var _current_text := ""


func start(url: String) -> void:
	client = WSClient.new()
	add_child(client)
	client.event_received.connect(_on_event)
	client.connected_ok.connect(_on_connected)
	client.socket_error.connect(func(m): printerr("SERVER ERROR: ", m))
	client.connect_to(url)


func _process(delta: float) -> void:
	if _speaking_left > 0.0:
		_speaking_left -= delta
		# Имитация речевого сигнала до прихода TTS (Этап 3).
		var t := Time.get_ticks_msec() / 1000.0
		var amp := 0.5 + 0.5 * sin(t * 11.0) * sin(t * 5.3 + 1.7)
		avatar.set_mouth_openness(amp * 0.75 + randf() * 0.25)
		if _speaking_left <= 0.0:
			avatar.set_mouth_openness(0.0)


func _on_connected() -> void:
	print("SERVER: connected")
	client.send_event({
		"type": "session.start",
		"payload": {
			"position": "python_backend",
			"level": "Middle",
			"interview_type": "technical",
			"duration_min": 15,
		},
	})


func _on_event(event: Dictionary) -> void:
	var t: String = event.get("type", "")
	match t:
		"session.started":
			_session_id = event.get("session_id", "")
			print("SERVER: session.started ", _session_id)
		"interviewer.text":
			_current_text = event.get("text", "")
			print("SERVER: interviewer.text: ",
				_current_text.substr(0, 60))
		"avatar.state":
			var state: String = event.get("state", "")
			if state == "speaking":
				avatar.set_state(AvatarController.AvatarState.SPEAKING)
				_speaking_left = clampf(
					_current_text.length() / 14.0, 1.0, 6.0)
			elif state == "listening":
				avatar.set_state(AvatarController.AvatarState.LISTENING)
				_send_answer()
			elif state == "thinking":
				avatar.set_state(AvatarController.AvatarState.THINKING)
		"session.report":
			print("SERVER: session.report: ",
				JSON.stringify(event.get("report", {})))
			finished.emit()
		"error":
			printerr("SERVER: error: ", event.get("message", ""))
			finished.emit()


func _send_answer() -> void:
	if _answer_index >= DEMO_ANSWERS.size():
		# Ответы закончились — завершаем сессию явно.
		print("SERVER: answers exhausted, sending session.end")
		client.send_event({
			"type": "session.end", "session_id": _session_id})
		return
	var answer: String = DEMO_ANSWERS[_answer_index]
	_answer_index += 1
	print("SERVER: transcript.final: ", answer.substr(0, 50))
	client.send_event({
		"type": "transcript.final",
		"session_id": _session_id,
		"text": answer,
	})
