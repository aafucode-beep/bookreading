from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "勇敢成长"
    environment: str = "development"
    api_prefix: str = "/api/v1"
    secret_key: str = "change-me-before-production"
    access_token_minutes: int = 30
    refresh_token_days: int = 30
    admin_cookie_hours: int = 8

    data_dir: Path = Path("data")
    database_url: str = "sqlite:///data/brave_growth.db"
    media_dir: Path = Path("data/media")
    max_book_pages: int = 64
    max_image_bytes: int = 20 * 1024 * 1024
    public_base_url: str = "http://localhost:8000"
    apk_version: str = "0.1.0"
    apk_download_url: str = "/downloads/brave-growth.apk"

    ai_mode: str = "mock"
    preferred_provider: str = "minimax"
    provider_timeout_seconds: int = 90
    provider_concurrency: int = 2

    minimax_api_key: str = ""
    minimax_chat_url: str = "https://api.minimaxi.com/v1/chat/completions"
    minimax_tts_url: str = "https://api.minimaxi.com/v1/t2a_v2"
    minimax_model: str = ""
    minimax_voice_id: str = "male-qn-qingse"
    minimax_mcp_command: str = "uvx"
    minimax_mcp_args: str = "minimax-coding-plan-mcp,-y"

    openai_api_key: str = ""
    openai_base_url: str = "https://api.openai.com/v1"
    openai_vision_model: str = ""
    openai_tts_model: str = "gpt-4o-mini-tts"
    openai_voice: str = "coral"

    cors_origins: list[str] = Field(default_factory=list)

    def ensure_directories(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.media_dir.mkdir(parents=True, exist_ok=True)


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.ensure_directories()
    return settings

