"""Типизированный протокол WebSocket-событий (ТЗ §9).

Каждое событие — JSON-объект с обязательным полем ``type`` и
идентификатором сессии ``session_id`` (кроме session.start, где сессия
ещё не создана). Реплики нумеруются ``utterance_id`` (UUID).

Бинарные аудиофреймы передаются отдельно от JSON-сообщений —
WebSocket-сообщения с opcode=binary внутри событий audio.input /
interviewer.audio (поле ``audio`` в JSON при этом не используется).
"""

from __future__ import annotations

import uuid
from enum import StrEnum
from typing import Literal, Optional

from pydantic import BaseModel, Field


class EventType(StrEnum):
    # Клиент → сервер
    SESSION_START = "session.start"
    AUDIO_INPUT = "audio.input"
    TRANSCRIPT_FINAL = "transcript.final"       # текст из клиента (mock-режим)
    INTERRUPTION = "interruption"
    SESSION_PAUSE = "session.pause"
    SESSION_RESUME = "session.resume"
    SESSION_END = "session.end"
    # Сервер → клиент
    SESSION_STARTED = "session.started"
    SPEECH_STARTED = "speech.started"
    SPEECH_ENDED = "speech.ended"
    TRANSCRIPT_PARTIAL = "transcript.partial"
    INTERVIEWER_THINKING = "interviewer.thinking"
    INTERVIEWER_TEXT = "interviewer.text"
    INTERVIEWER_AUDIO = "interviewer.audio"
    AVATAR_STATE = "avatar.state"
    SESSION_REPORT = "session.report"
    ERROR = "error"


def new_id() -> str:
    return str(uuid.uuid4())


# ------------------------------------------------------------------ события

class Event(BaseModel):
    type: EventType
    session_id: Optional[str] = None
    utterance_id: Optional[str] = None


class SessionStartPayload(BaseModel):
    """Параметры собеседования (ТЗ §6)."""

    position: str = Field(description="Должность, напр. python_backend")
    level: str = Field(description="Junior | Middle | Senior | Lead")
    interview_type: str = Field(default="technical", description="Тип интервью")
    duration_min: int = Field(default=15, ge=5, le=120)
    resume_text: Optional[str] = Field(default=None, description="Текст резюме")


class SessionStart(Event):
    type: Literal[EventType.SESSION_START] = EventType.SESSION_START
    payload: SessionStartPayload


class SessionStarted(Event):
    type: Literal[EventType.SESSION_STARTED] = EventType.SESSION_STARTED
    session_id: str
    started_at: str = Field(description="ISO-8601")


class AudioInput(Event):
    type: Literal[EventType.AUDIO_INPUT] = EventType.AUDIO_INPUT
    session_id: str
    # Бинарный фрейм передаётся отдельным WebSocket-сообщением (opcode=binary);
    # поле sample_rate нужно передать хотя бы раз до первого фрейма.
    sample_rate: Optional[int] = None
    last_frame: bool = Field(default=False, description="Конец высказывания")


class TranscriptFinal(Event):
    """Финальный распознанный текст кандидата (mock-режим без ASR)."""

    type: Literal[EventType.TRANSCRIPT_FINAL] = EventType.TRANSCRIPT_FINAL
    session_id: str
    text: str


class Interruption(Event):
    type: Literal[EventType.INTERRUPTION] = EventType.INTERRUPTION
    session_id: str


class SessionCommand(Event):
    session_id: str


class SessionPause(SessionCommand):
    type: Literal[EventType.SESSION_PAUSE] = EventType.SESSION_PAUSE


class SessionResume(SessionCommand):
    type: Literal[EventType.SESSION_RESUME] = EventType.SESSION_RESUME


class SessionEnd(SessionCommand):
    type: Literal[EventType.SESSION_END] = EventType.SESSION_END


# ------------------------------------------------------------------ ответы сервера

class SpeechStarted(Event):
    type: Literal[EventType.SPEECH_STARTED] = EventType.SPEECH_STARTED
    session_id: str


class SpeechEnded(Event):
    type: Literal[EventType.SPEECH_ENDED] = EventType.SPEECH_ENDED
    session_id: str


class TranscriptPartial(Event):
    type: Literal[EventType.TRANSCRIPT_PARTIAL] = EventType.TRANSCRIPT_PARTIAL
    session_id: str
    text: str


class InterviewerThinking(Event):
    type: Literal[EventType.INTERVIEWER_THINKING] = EventType.INTERVIEWER_THINKING
    session_id: str


class InterviewerText(Event):
    type: Literal[EventType.INTERVIEWER_TEXT] = EventType.INTERVIEWER_TEXT
    session_id: str
    utterance_id: str
    text: str


class InterviewerAudio(Event):
    """Аудиофрейм/файл реплики; бинарные данные — отдельным WS-сообщением."""

    type: Literal[EventType.INTERVIEWER_AUDIO] = EventType.INTERVIEWER_AUDIO
    session_id: str
    utterance_id: str
    sample_rate: int = 24000
    format: str = "pcm16"
    final: bool = True


class AvatarStateEvent(Event):
    type: Literal[EventType.AVATAR_STATE] = EventType.AVATAR_STATE
    session_id: str
    state: str = Field(description="idle | listening | thinking | speaking")
    emotion: Optional[str] = None
    mouth_openness: Optional[float] = Field(default=None, ge=0.0, le=1.0)


class AnswerReview(BaseModel):
    question: str
    answer: str
    score: float = Field(ge=0.0, le=5.0)
    justification: str


class SessionReportData(BaseModel):
    """Итоговый отчёт (ТЗ §7) — упрощённая версия для Этапа 2."""

    overall_score: float = Field(ge=0.0, le=5.0)
    reviews: list[AnswerReview] = Field(default_factory=list)
    questions_asked: int


class SessionReport(Event):
    type: Literal[EventType.SESSION_REPORT] = EventType.SESSION_REPORT
    session_id: str
    report: SessionReportData


class ErrorEvent(Event):
    type: Literal[EventType.ERROR] = EventType.ERROR
    code: str = Field(description="unknown_session | invalid_event | "
                                   "internal | not_implemented")
    message: str
