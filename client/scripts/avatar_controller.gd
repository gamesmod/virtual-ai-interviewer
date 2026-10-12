class_name AvatarController
extends Node3D
## Базовый интерфейс контроллера аватара (ТЗ, раздел 4).
##
## Определяет контракт, который использует остальная часть клиента.
## Реализации:
##   - ProceduralAvatar (MVP) — аватар из примитивов Godot;
##   - в будущем — GLB-модель с blend shapes (та же сигнатура методов).

## Состояния аватара (анимации ожидания, слушания, разговора).
enum AvatarState { IDLE, LISTENING, THINKING, SPEAKING, WAITING }

## Реакции лица: нейтральное выражение, заинтересованность,
## размышление, удивление.
enum Emotion { NEUTRAL, INTERESTED, THOUGHTFUL, SURPRISED }

## Переводит аватар в одно из состояний AvatarState.
func set_state(state: int) -> void:
	push_warning("AvatarController.set_state() не реализован")


## Устанавливает выражение лица (Emotion).
func set_emotion(emotion: int) -> void:
	push_warning("AvatarController.set_emotion() не реализован")


## Направляет взгляд на точку в мировых координатах.
func set_gaze(target: Vector3) -> void:
	push_warning("AvatarController.set_gaze() не реализован")


## Задаёт степень открытия рта, value в диапазоне [0.0, 1.0].
## Используется для синхронизации губ с речью.
func set_mouth_openness(value: float) -> void:
	push_warning("AvatarController.set_mouth_openness() не реализован")


## Проигрывает жест по имени ("nod", "shake_head", "shrug", "think").
func play_gesture(gesture: StringName) -> void:
	push_warning("AvatarController.play_gesture() не реализован")
