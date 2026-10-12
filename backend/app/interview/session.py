"""Управление сессиями собеседований (ТЗ §3, §6).

Сценарий интервью управляется конечной машиной состояний
(ТЗ §6), а не только промптом LLM:

    GREETING → INTERVIEWING → CLOSING → FINISHED

Переходы:
  - GREETING → INTERVIEWING: отправлена приветственная реплика;
  - INTERVIEWING → CLOSING: вопросы сценария исчерпаны или session.end;
  - CLOSING → FINISHED: отправлено завершающее сообщение, формируется
    отчёт session.report.

Хранение — в памяти (Этап 2); PostgreSQL подключается на Этапе 5/6.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import StrEnum

from app.ai.mock_llm import MockInterviewer
from app.api.protocol import AnswerReview, SessionReportData


class SessionPhase(StrEnum):
    GREETING = "greeting"
    INTERVIEWING = "interviewing"
    CLOSING = "closing"
    FINISHED = "finished"


@dataclass
class Turn:
    question: str
    answer: str = ""


@dataclass
class InterviewSession:
    session_id: str
    position: str
    level: str
    interview_type: str
    duration_min: int
    interviewer: MockInterviewer
    phase: SessionPhase = SessionPhase.GREETING
    started_at: float = field(default_factory=time.time)
    turns: list[Turn] = field(default_factory=list)
    current_question: str = ""
    paused: bool = False

    @classmethod
    def create(cls, position: str, level: str, interview_type: str,
               duration_min: int) -> "InterviewSession":
        return cls(
            session_id=str(uuid.uuid4()),
            position=position,
            level=level,
            interview_type=interview_type,
            duration_min=duration_min,
            interviewer=MockInterviewer(position, level),
        )

    def start(self) -> str:
        """Приветствие и первый переход FSM."""
        self.phase = SessionPhase.INTERVIEWING
        greeting = self.interviewer.next_reply(None)
        assert greeting is not None
        return greeting

    def handle_answer(self, answer: str) -> str:
        """Ответ кандидата → реплика интервьюера по FSM."""
        if self.current_question:
            self.turns.append(Turn(question=self.current_question, answer=answer))
        reply = self.interviewer.next_reply(answer)
        if reply is None:
            self.phase = SessionPhase.CLOSING
            reply = self.interviewer.closing()
            self.phase = SessionPhase.FINISHED
            return reply
        self.current_question = reply
        return reply

    def finish(self) -> None:
        self.phase = SessionPhase.FINISHED

    def report(self) -> SessionReportData:
        """Упрощённая оценка для Этапа 2; полная рубрика 0–5 — Этап 5."""
        reviews: list[AnswerReview] = []
        for turn in self.turns:
            length = len(turn.answer.strip())
            score = min(5.0, 1.0 + length / 40.0)
            reviews.append(AnswerReview(
                question=turn.question,
                answer=turn.answer,
                score=round(score, 1),
                justification=(
                    "Оценка по длине и содержательности ответа "
                    "(mock-оценщик, Этап 2)."
                ),
            ))
        overall = round(
            sum(r.score for r in reviews) / len(reviews), 1) if reviews else 0.0
        return SessionReportData(
            overall_score=overall,
            reviews=reviews,
            questions_asked=len(self.turns),
        )


class SessionManager:
    """Реестр активных сессий."""

    def __init__(self) -> None:
        self._sessions: dict[str, InterviewSession] = {}

    def create(self, position: str, level: str, interview_type: str,
               duration_min: int) -> InterviewSession:
        session = InterviewSession.create(
            position, level, interview_type, duration_min)
        self._sessions[session.session_id] = session
        return session

    def get(self, session_id: str) -> InterviewSession | None:
        return self._sessions.get(session_id)

    def drop(self, session_id: str) -> None:
        self._sessions.pop(session_id, None)
