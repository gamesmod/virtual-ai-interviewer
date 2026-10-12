"""End-to-end тест WebSocket-протокола (ТЗ §9, критерии MVP).

Запускается реальный uvicorn-сервер на случайном порту; клиент —
библиотека websockets с таймаутами на каждое событие.

Сценарий: session.start → session.started → interviewer.text →
несколько transcript.final → interviewer.text → session.end →
session.report → закрытие сокета.
"""

import asyncio
import json
import threading

import pytest
import uvicorn
import websockets
from fastapi.testclient import TestClient

from app.main import app

TIMEOUT = 5.0


def _event(raw: str) -> dict:
    return json.loads(raw)


@pytest.fixture()
def ws_port():
    """Поднимает uvicorn с приложением на случайном порту."""
    config = uvicorn.Config(app, host="127.0.0.1", port=0,
                            log_level="warning")
    server = uvicorn.Server(config)
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    while not server.started:
        asyncio.Event()  # noop; просто даём потоку стартовать
        import time
        time.sleep(0.01)
    yield server.servers[0].sockets[0].getsockname()[1]
    server.should_exit = True
    thread.join(timeout=5)


def test_health():
    client = TestClient(app)
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


@pytest.mark.asyncio
async def test_full_interview_dialog(ws_port):
    uri = f"ws://127.0.0.1:{ws_port}/ws"
    async with websockets.connect(uri) as ws:
        async def recv() -> dict:
            return _event(await asyncio.wait_for(ws.recv(), TIMEOUT))

        async def recv_until(target: str, limit: int = 20) -> dict:
            for _ in range(limit):
                event = await recv()
                assert event["type"] != "error", event
                if event["type"] == target:
                    return event
            raise AssertionError(f"Событие {target} не получено")

        # 1. Старт сессии.
        await ws.send(json.dumps({
            "type": "session.start",
            "payload": {
                "position": "python_backend",
                "level": "Middle",
                "interview_type": "technical",
                "duration_min": 15,
            },
        }))
        started = await recv_until("session.started")
        session_id = started["session_id"]
        await recv_until("interviewer.text")
        await recv_until("avatar.state")

        # 2. Ответы кандидата до завершения сценария. После каждого
        # ответа сервер присылает 6 событий реплики, а при завершении
        # сценария — 7-е: session.report.
        answers = [
            "Работаю с Python пять лет, последние три — backend на FastAPI.",
            "Пишу тесты на pytest, использую mypy и ruff.",
            "Строил асинхронные сервисы с aiohttp и asyncio.",
            "Оптимизировал запросы к PostgreSQL.",
            "Руководил небольшой командой из трёх разработчиков.",
            "Проектировал REST API и интеграции с внешними сервисами.",
        ]
        report = None
        for answer in answers:
            await ws.send(json.dumps({
                "type": "transcript.final",
                "session_id": session_id,
                "text": answer,
            }))
            try:
                event = await asyncio.wait_for(
                    _drain_until(ws, "session.report"), TIMEOUT)
                report = event["report"]
            except asyncio.TimeoutError:
                pass  # сценарий продолжается, ждём следующего ответа
            if report is not None:
                break

        # 3. Явное завершение, если сценарий не исчерпан.
        if report is None:
            await ws.send(json.dumps({
                "type": "session.end", "session_id": session_id}))
            report = (await recv_until("session.report"))["report"]

        assert report["questions_asked"] >= 1
        assert 0.0 <= report["overall_score"] <= 5.0
        for review in report["reviews"]:
            assert 0.0 <= review["score"] <= 5.0
            assert review["justification"]


async def _drain_until(ws, target: str) -> dict:
    while True:
        event = _event(await ws.recv())
        if event["type"] == target:
            return event


@pytest.mark.asyncio
async def test_unknown_session_error(ws_port):
    uri = f"ws://127.0.0.1:{ws_port}/ws"
    async with websockets.connect(uri) as ws:
        await ws.send(json.dumps({
            "type": "transcript.final",
            "session_id": "00000000-0000-0000-0000-000000000000",
            "text": "привет",
        }))
        event = _event(await asyncio.wait_for(ws.recv(), TIMEOUT))
        assert event["type"] == "error"
        assert event["code"] == "unknown_session"


@pytest.mark.asyncio
async def test_invalid_event_error(ws_port):
    uri = f"ws://127.0.0.1:{ws_port}/ws"
    async with websockets.connect(uri) as ws:
        await ws.send("{not json")
        event = _event(await asyncio.wait_for(ws.recv(), TIMEOUT))
        assert event["type"] == "error"
        assert event["code"] == "invalid_event"
