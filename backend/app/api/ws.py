"""WebSocket-эндпоинт собеседования (ТЗ §3, §9).

Маршрут: /ws?token=<auth_token> (если VAI_AUTH_TOKEN задан).

Поток событий после session.start:
    сервер: session.started → interviewer.thinking → interviewer.text
            → interviewer.audio (mock) → avatar.state(speaking→listening)
    клиент: transcript.final (ответ) → сервер снова thinking → …
    конец:  session.end → session.report → закрытие сокета.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from app.api.protocol import (
    AudioInput,
    ErrorEvent,
    Event,
    EventType,
    Interruption,
    InterviewerAudio,
    InterviewerText,
    InterviewerThinking,
    SessionEnd,
    SessionPause,
    SessionReport,
    SessionResume,
    SessionStart,
    SessionStarted,
    TranscriptFinal,
    AvatarStateEvent,
    new_id,
)
from app.core.config import settings
from app.interview.session import SessionManager, SessionPhase

logger = logging.getLogger(__name__)
router = APIRouter()
sessions = SessionManager()


def _error(code: str, message: str, session_id: str | None = None) -> str:
    return ErrorEvent(code=code, message=message,
                      session_id=session_id).model_dump_json()


async def _send(ws: WebSocket, event: Event) -> None:
    await ws.send_text(event.model_dump_json())


@router.websocket("/ws")
async def interview_ws(
    ws: WebSocket,
    token: str | None = Query(default=None),
) -> None:
    if settings.auth_token and token != settings.auth_token:
        await ws.close(code=4401, reason="unauthorized")
        return
    await ws.accept()
    logger.info("WS подключение: %s", ws.client)

    try:
        while True:
            message = await ws.receive()
            if message.get("type") == "websocket.disconnect":
                break
            if message.get("bytes") is not None:
                # Бинарный аудиофрейм (audio.input, opcode=binary).
                # Этап 3: маршрутизация в ASR; пока игнорируем.
                continue
            if "text" in message:
                await _handle_text(ws, message["text"])
    except WebSocketDisconnect:
        logger.info("WS отключение: %s", ws.client)
    except Exception:
        logger.exception("WS: необработанная ошибка")
        try:
            await ws.send_text(_error("internal", "Внутренняя ошибка сервера"))
        except Exception:
            pass


async def _handle_text(ws: WebSocket, text: str) -> None:
    try:
        data = json.loads(text)
        event_type = data.get("type")
    except json.JSONDecodeError:
        await ws.send_text(_error("invalid_event", "Невалидный JSON"))
        return

    if event_type == EventType.SESSION_START:
        await _on_session_start(ws, SessionStart(**data))
    elif event_type == EventType.TRANSCRIPT_FINAL:
        await _on_transcript(ws, TranscriptFinal(**data))
    elif event_type == EventType.SESSION_END:
        await _on_session_end(ws, SessionEnd(**data))
    elif event_type == EventType.SESSION_PAUSE:
        await _on_pause(ws, SessionPause(**data), paused=True)
    elif event_type == EventType.SESSION_RESUME:
        await _on_pause(ws, SessionResume(**data), paused=False)
    elif event_type == EventType.INTERRUPTION:
        await _on_interruption(ws, Interruption(**data))
    elif event_type == EventType.AUDIO_INPUT:
        AudioInput(**data)  # валидация схемы; обработка — Этап 3
    else:
        await ws.send_text(_error(
            "invalid_event", f"Неизвестный тип события: {event_type}",
            data.get("session_id")))


async def _on_session_start(ws: WebSocket, event: SessionStart) -> None:
    p = event.payload
    session = sessions.create(
        p.position, p.level, p.interview_type, p.duration_min)
    await _send(ws, SessionStarted(
        session_id=session.session_id,
        started_at=datetime.now(timezone.utc).isoformat()))
    greeting = session.start()
    await _send_interviewer_reply(ws, session, greeting)


async def _send_interviewer_reply(ws, session, text: str) -> None:
    utterance_id = new_id()
    logger.info("reply: phase=%s text=%s…", session.phase, text[:40])
    await _send(ws, InterviewerThinking(session_id=session.session_id))
    await _send(ws, AvatarStateEvent(
        session_id=session.session_id, state="thinking"))
    await _send(ws, InterviewerText(
        session_id=session.session_id,
        utterance_id=utterance_id,
        text=text))
    # Mock-TTS: аудиофрейм пустой, клиент озвучивает синтезатором
    # системы или имитирует движение губ по длительности текста.
    await _send(ws, InterviewerAudio(
        session_id=session.session_id,
        utterance_id=utterance_id,
        final=True))
    await _send(ws, AvatarStateEvent(
        session_id=session.session_id,
        state="speaking",
        emotion="neutral"))
    await _send(ws, AvatarStateEvent(
        session_id=session.session_id,
        state="listening",
        emotion="interested"))


async def _on_transcript(ws: WebSocket, event: TranscriptFinal) -> None:
    session = sessions.get(event.session_id)
    if session is None:
        await ws.send_text(_error(
            "unknown_session", "Сессия не найдена", event.session_id))
        return
    if session.paused or session.phase == SessionPhase.FINISHED:
        return
    logger.info("transcript.final (%s): %s…", session.phase, event.text[:30])
    reply = session.handle_answer(event.text)
    await _send_interviewer_reply(ws, session, reply)
    if session.phase == SessionPhase.FINISHED:
        await _send_report(ws, session)


async def _on_session_end(ws: WebSocket, event: SessionEnd) -> None:
    logger.info("session.end: %s", event.session_id)
    session = sessions.get(event.session_id)
    if session is None:
        await ws.send_text(_error(
            "unknown_session", "Сессия не найдена", event.session_id))
        return
    session.finish()
    await _send_report(ws, session)


async def _send_report(ws: WebSocket, session) -> None:
    logger.info("report: %s", session.session_id)
    await _send(ws, SessionReport(
        session_id=session.session_id, report=session.report()))
    sessions.drop(session.session_id)
    # Пауза перед close: даём клиенту прочитать фрейм с отчётом,
    # иначе close-фрейм может обогнать данные (наблюдалось в Godot).
    await asyncio.sleep(0.3)
    await ws.close(code=1000, reason="session finished")


async def _on_pause(ws: WebSocket, event, paused: bool) -> None:
    session = sessions.get(event.session_id)
    if session is None:
        await ws.send_text(_error(
            "unknown_session", "Сессия не найдена", event.session_id))
        return
    session.paused = paused


async def _on_interruption(ws: WebSocket, event: Interruption) -> None:
    """Прерывание речи интервьюера пользователем (ТЗ §5).

    Отменяет «устаревшую генерацию»: в mock-режиме — сбрасываем
    состояние speaking, переводим аватар в listening.
    """
    session = sessions.get(event.session_id)
    if session is None:
        return
    await _send(ws, AvatarStateEvent(
        session_id=session.session_id, state="listening"))
