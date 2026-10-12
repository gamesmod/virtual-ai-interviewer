# Virtual AI Interviewer

Виртуальный тренажёр собеседований: пользователь отвечает на вопросы
человекоподобного 3D-интервьюера голосом на русском языке, получает
итоговую оценку и отчёт.

## Структура репозитория

```
virtual-ai-interviewer/
├── client/                  # Godot 4.x (GDScript) — клиентское приложение
│   ├── scenes/              # сцены
│   ├── scripts/             # скрипты (аватар, демо-разговор, UI)
│   ├── avatars/             # будущие GLB-модели аватаров
│   ├── assets/              # иконки и прочие ресурсы
│   └── tests/               # автотесты (запускаются headless)
├── backend/                 # FastAPI — серверное API (этап 2)
├── infrastructure/          # Docker, Yandex Cloud, скрипты (этап 6)
├── docs/                    # документация и скриншоты
└── PROGRESS.md              # состояние проекта и план
```

## Запуск

Требуется Godot 4.3+ (<https://godotengine.org/download>) и Python 3.11+.

Клиент (без сервера — имитация разговора):

```bash
cd client
godot --path .                 # обычный запуск
godot --path . -- --demo       # автоматическая имитация собеседования
```

Backend (mock-режим, без GPU):

```bash
cd backend
pip install -e ".[dev]"
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Клиент + сервер (полный диалог по WebSocket):

```bash
godot --path . -- --server --server-url=ws://127.0.0.1:8000/ws
```

Проверки (headless):

```bash
cd backend && python -m pytest tests/ -v
cd client && godot --headless --script tests/test_avatar.gd
godot --path . -- --demo --screenshot=/tmp/shot.png
```

> В средах без звуковой карты Godot переключается на dummy-драйвер
> аудио — это штатное поведение, на рендер не влияет.

## Текущее состояние

См. [PROGRESS.md](PROGRESS.md). Реализованы Этапы 1–2: Godot MVP
(процедурный 3D-аватар с интерфейсом `AvatarController`, UI, имитация
разговора) и Backend (FastAPI, WebSocket-протокол событий, сессии с
конечным автоматом сценария, mock-LLM, отчёт 0–5, pytest, CI).
Интеграция «Godot-клиент ↔ сервер» проверена end-to-end.
