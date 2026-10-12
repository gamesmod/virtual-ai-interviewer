"""Mock-LLM для разработки без GPU (ТЗ §10).

Имитирует интервьюера детерминированными ответами: задаёт вопросы
по сценарию, реагирует на ответы кандидата, завершает собеседование.
Заменяется на Qwen3/vLLM на Этапе 4 без изменения интерфейса.
"""

from __future__ import annotations

import random


class MockInterviewer:
    """Генератор реплик интервьюера без нейросети."""

    def __init__(self, position: str, level: str) -> None:
        self.position = position
        self.level = level
        self.asked: list[str] = []
        self._followups = [
            "Понятно. Можете подробнее рассказать о деталях?",
            "Интересно. Какие сложности возникали в этом проекте?",
            "Хорошо. А как бы вы решили эту задачу иначе?",
        ]
        self._pool = self._questions_for(position, level)

    @staticmethod
    def _questions_for(position: str, level: str) -> list[str]:
        base = {
            "python_backend": [
                "Расскажите о своём опыте работы с Python.",
                "Какие фреймворки использовали: FastAPI, Django, aiohttp?",
                "Как вы подходите к тестированию кода?",
                "Как устроены генераторы и зачем они нужны?",
                "Как работает асинхронность в Python?",
            ],
            "data_engineer": [
                "Расскажите об опыте построения ETL-пайплайнов.",
                "Какие системы хранения данных вы использовали?",
                "Как обеспечиваете качество данных?",
            ],
        }
        questions = base.get(position, [
            "Расскажите о вашем профильном опыте.",
            "Какими инструментами вы чаще всего пользуетесь?",
            "Опишите самый сложный проект, в котором участвовали.",
        ])
        suffix = {"Junior": "", "Middle": " Покажите понимание архитектуры.",
                  "Senior": " Ответьте с учётом масштабируемости.",
                  "Lead": " Сфокусируйтесь на управлении сложностью."}.get(level, "")
        return [q + suffix if i == 1 else q for i, q in enumerate(questions)]

    def opening(self) -> str:
        return (f"Здравствуйте! Начнём собеседование на позицию "
                f"{self.position} ({self.level}).")

    def next_reply(self, candidate_answer: str | None) -> str | None:
        """Следующая реплика интервьюера; None — вопросы закончились."""
        if candidate_answer is None:
            return self.opening()
        if self._pool:
            if random.random() < 0.35 and len(self.asked) >= 1:
                return random.choice(self._followups)
            question = self._pool.pop(0)
            self.asked.append(question)
            return question
        return None

    def closing(self) -> str:
        return "Спасибо за ответы! Это были все мои вопросы."
