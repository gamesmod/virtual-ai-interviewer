"""FastAPI-приложение Virtual AI Interviewer (ТЗ §3, §10)."""

import logging

from fastapi import FastAPI

from app.api import ws
from app.core.config import settings

logging.basicConfig(
    level=settings.log_level.upper(),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s")

app = FastAPI(title="Virtual AI Interviewer", version="0.1.0")
app.include_router(ws.router)


@app.get("/health")
async def health() -> dict:
    """Health-check (ТЗ §10)."""
    return {"status": "ok", "llm_mode": settings.llm_mode,
            "tts_mode": settings.tts_mode, "asr_mode": settings.asr_mode}


@app.get("/")
async def root() -> dict:
    return {"service": "virtual-ai-interviewer", "ws": "/ws",
            "health": "/health"}
