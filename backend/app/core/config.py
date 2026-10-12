"""Конфигурация backend (ТЗ §10: конфигурация через переменные окружения)."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="VAI_", env_file=".env")

    host: str = "0.0.0.0"
    port: int = 8000
    log_level: str = "info"

    # Режимы AI-компонентов: mock — без GPU, реальные — на этапах 3–4.
    llm_mode: str = "mock"   # mock | vllm
    tts_mode: str = "mock"   # mock | silero
    asr_mode: str = "mock"   # mock | faster-whisper

    vllm_base_url: str = "http://localhost:8001/v1"
    vllm_model: str = "Qwen/Qwen3-8B"
    vllm_api_key: str = ""

    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "virtual_interviewer"
    db_user: str = "postgres"
    db_password: str = ""

    auth_token: str = ""
    max_upload_mb: int = 10


settings = Settings()
