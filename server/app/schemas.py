from __future__ import annotations

from datetime import datetime
from enum import Enum

from pydantic import BaseModel, ConfigDict, Field


class LoginRequest(BaseModel):
    username: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class BookCreate(BaseModel):
    title: str = "未命名绘本"


class BookSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    title: str
    summary: str
    status: str
    completeness_status: str
    created_at: datetime
    updated_at: datetime
    page_count: int = 0
    cover_url: str | None = None


class PageUpdate(BaseModel):
    order_index: int | None = None
    original_text: str | None = None
    zh_text: str | None = None
    en_text: str | None = None
    explanation: str | None = None
    question: str | None = None


class BookReviewUpdate(BaseModel):
    title: str = Field(min_length=1, max_length=240)
    summary: str = Field(max_length=4000)
    completeness_status: str
    pages: dict[int, PageUpdate] = Field(default_factory=dict)


class ReorderRequest(BaseModel):
    page_ids: list[int]


class JobRequest(BaseModel):
    idempotency_key: str = Field(min_length=8, max_length=100)


class JobResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    book_id: int
    kind: str
    status: str
    attempts: int
    error: str
    created_at: datetime


class ReadingMode(str, Enum):
    FOLLOW = "follow"
    CHINESE = "zh"
    ENGLISH = "en"
    ZH_THEN_EN = "zh_then_en"
    EN_THEN_ZH = "en_then_zh"


class AudioItem(BaseModel):
    language: str
    url: str
    mime_type: str
    sha256: str
    duration_ms: int | None = None


class ManifestPage(BaseModel):
    id: int
    order_index: int
    image_url: str
    thumbnail_url: str
    original_blocks: list[dict]
    detected_language: str
    original_text: str
    zh_text: str
    en_text: str
    explanation: str
    question: str
    audio: dict[str, AudioItem]


class OfflineManifest(BaseModel):
    book_id: int
    version: int
    title: str
    summary: str
    cover_url: str | None
    pages: list[ManifestPage]
    generated_at: datetime

