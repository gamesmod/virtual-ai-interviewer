# PROGRESS — состояние проекта

## Статус: Этапы 1–2 завершены (Godot MVP + Backend и протокол)

### Этап 1 — Godot MVP: выполнено

- Проверка инструментов: Python 3.12, Git 2.39, Godot 4.3 stable
  (headless-сборка использовалась для проверок).
- Структура репозитория по ТЗ §12.
- Клиент Godot 4.3 (`client/`):
  - `scripts/avatar_controller.gd` — интерфейс `AvatarController`:
    `set_state`, `set_emotion`, `set_gaze`, `set_mouth_openness`,
    `play_gesture` (ТЗ §4);
  - `scripts/procedural_avatar.gd` — процедурный аватар (голова, торс,
    руки, глаза, брови, рот) из примитивов Godot: моргание, повороты
    головы, движение зрачков за точкой взгляда, морфинг рта,
    реакции (нейтральное/заинтересованность/размышление/удивление),
    жесты nod / shake_head / shrug / think;
  - `scripts/conversation_demo.gd` — тестовая имитация разговора:
    цикл THINKING → SPEAKING → LISTENING, движение губ от
    имитированного речевого сигнала, эмуляция ответов кандидата;
  - `scripts/main.gd` — сцена: камера, освещение, пол, UI
    (текущая реплика, состояние, таймер, индикатор микрофона,
    транскрипт), режимы `--demo` и `--screenshot=<путь>`.
- Тесты: `client/tests/test_avatar.gd` — 9 проверок, все пройдены
  (headless, Godot 4.3).
- Ручная проверка: прогон демо 20 с (600 кадров) без ошибок скриптов;
  скриншот сцены сохранён в `docs/screenshots/avatar_demo_stage1.png`.

### Этап 2 — Backend и протокол: выполнено

- `backend/app/main.py` — FastAPI: `/health`, WebSocket `/ws`.
- `backend/app/api/protocol.py` — типизированные события ТЗ §9
  (pydantic-модели): session.start/started, audio.input,
  speech.started/ended, transcript.partial/final, interviewer.thinking/
  text/audio, avatar.state, interruption, session.pause/resume/end,
  session.report, error. Бинарные аудиофреймы — отдельными
  WS-сообщениями.
- `backend/app/interview/session.py` — сессии и конечная машина
  состояний сценария (ТЗ §6): GREETING → INTERVIEWING → CLOSING →
  FINISHED; отчёт 0–5 с обоснованием по каждому ответу.
- `backend/app/ai/mock_llm.py` — mock-интервьюер (сценарии по
  должностям и уровням, уточняющие вопросы), заменяется на Qwen3/vLLM
  на Этапе 4 без изменения интерфейса.
- `backend/app/api/ws.py` — обработка событий, ошибки протокола
  (unknown_session, invalid_event), interruption, pause/resume.
- Клиент: `scripts/ws_client.gd` (WebSocketPeer + JSON-события),
  `scripts/server_conversation.gd` — серверный диалог вместо
  ConversationDemo при флаге `--server --server-url=...`.
- Тесты: `backend/tests/test_ws.py` — 4 теста (health, полный диалог
  E2E против реального uvicorn, unknown_session, invalid_event) —
  все пройдены. Интеграционная проверка «Godot-клиент ↔ сервер»:
  полный диалог, получение session.report, корректный выход (код 0).
- `.github/workflows/ci.yml` — CI: pytest backend + headless-тесты
  Godot.

### Найденные и исправленные ошибки

- `look_at` до добавления камеры в дерево — исправлено.
- Возврат руки после жеста «think» твинил к текущей (поднятой)
  позиции — исправлено.
- Волосы закрывали глаза — подняты.
- Закрытие WS сервером сразу после отправки отчёта обгоняло данные
  на клиенте Godot — добавлена пауза 0.3 с перед close.
- Отключение WS (websocket.disconnect) не обрабатывалось — KeyError.

### Ограничения тестирования (зафиксировано)

- В песочнице нет звуковой карты — ALSA недоступен, Godot использует
  dummy-аудиодрайвер. Проверка захвата/воспроизведения микрофона
  возможна только на машине пользователя.
- Рендер проверялся через Mesa llvmpipe (программный GL) в Xvfb;
  в проекте выбран GL Compatibility. На GPU можно переключить на
  Forward+.
- Интерактивный запуск (окно, ввод) не проверялся — только headless.
- PostgreSQL, GPU и облачные ресурсы не подключались (не создавались
  без разрешения, ТЗ §14.9).

### Решения

- Процедурный аватар собирается кодом, не сценой — надёжнее для
  headless-проверок и отвечает допуску ТЗ §4 для MVP.
- `project.godot` настроен на Full HD 1920×1080 с масштабированием UI.
- Сессии хранятся в памяти (Этап 2); PostgreSQL — на Этапе 5/6.

## Следующие задачи (Этап 3 — Голос)

1. Захват микрофона в Godot (AudioEffectCapture) и потоковая отправка
   audio.input.
2. faster-whisper ASR на backend (режим VAI_ASR_MODE), VAD для
   определения начала/конца речи.
3. Silero TTS (VAI_TTS_MODE), воспроизведение аудио в Godot,
   синхронизация рта по амплитуде.
4. Прерывание речи интервьюера пользователем (interruption уже в
   протоколе) с отменой устаревшей генерации.
