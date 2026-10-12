class_name WSClient
extends Node
## WebSocket-клиент протокола собеседования (ТЗ §3, §9).
##
## Оборачивает WebSocketPeer: подключение, сериализация JSON-событий,
## разбор входящих сообщений (текстовые JSON; бинарные аудиофреймы —
## Этап 3).

signal event_received(event: Dictionary)
signal connected_ok
signal disconnected
signal socket_error(message: String)


var socket := WebSocketPeer.new()
var _url := ""
var is_connected := false


func connect_to(url: String) -> void:
	_url = url
	var err := socket.connect_to_url(url)
	if err != OK:
		socket_error.emit("Не удалось подключиться: %s" % error_string(err))


func send_event(event: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(event))


func close() -> void:
	socket.close()


func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not is_connected:
				is_connected = true
				connected_ok.emit()
			while socket.get_available_packet_count() > 0:
				_handle_packet(socket.get_packet(),
					socket.was_string_packet())
		WebSocketPeer.STATE_CLOSED:
			# Дочитываем пакеты, пришедшие вместе с закрытием
			# (например, session.report перед close).
			while socket.get_available_packet_count() > 0:
				_handle_packet(socket.get_packet(),
					socket.was_string_packet())
			if is_connected:
				is_connected = false
				disconnected.emit()
			set_process(false)


func _handle_packet(packet: PackedByteArray, is_text: bool) -> void:
	if not is_text:
		# Бинарный аудиофрейм (interviewer.audio) — Этап 3.
		event_received.emit({"type": "_binary", "size": packet.size()})
		return
	if OS.get_cmdline_user_args().has("--ws-debug"):
		print("WS DBG: ", packet.get_string_from_utf8())
	var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if parsed is Dictionary:
		event_received.emit(parsed)
