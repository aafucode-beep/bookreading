from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import Settings
from .models import (
    AnalysisRun,
    AudioAsset,
    Book,
    BookPage,
    BookStatus,
    CompletenessStatus,
    FamilySettings,
    JobStatus,
    ProcessingJob,
    ProviderAttempt,
)
from .providers import AudioResult, ProviderError, ProviderResult, ProviderRouter, content_sha256
from .storage import json_list, safe_media_path


def _now() -> datetime:
    return datetime.now(timezone.utc)


def enqueue_job(session: Session, book_id: int, kind: str, idempotency_key: str) -> ProcessingJob:
    existing = session.scalar(select(ProcessingJob).where(ProcessingJob.idempotency_key == idempotency_key))
    if existing:
        if existing.book_id != book_id or existing.kind != kind:
            raise ValueError("幂等键已用于其他操作")
        return existing
    job = ProcessingJob(book_id=book_id, kind=kind, idempotency_key=idempotency_key)
    session.add(job)
    session.commit()
    session.refresh(job)
    return job


def _attempt(
    session: Session,
    *,
    book_id: int,
    job_id: int,
    provider: str,
    operation: str,
    success: bool,
    model: str = "",
    error: str = "",
    request_id: str = "",
) -> None:
    session.add(
        ProviderAttempt(
            book_id=book_id,
            job_id=job_id,
            provider=provider,
            operation=operation,
            success=success,
            model=model,
            error=error[:4000],
            request_id=request_id,
        )
    )


async def _routed_call(
    session: Session,
    router: ProviderRouter,
    job: ProcessingJob,
    operation: str,
    *args,
) -> ProviderResult | AudioResult:
    try:
        result, failures = await router.call(operation, *args)
    except ProviderError as exc:
        _attempt(
            session,
            book_id=job.book_id,
            job_id=job.id,
            provider="all",
            operation=operation,
            success=False,
            error=str(exc),
        )
        session.commit()
        raise
    for provider, error in failures:
        _attempt(
            session,
            book_id=job.book_id,
            job_id=job.id,
            provider=provider,
            operation=operation,
            success=False,
            error=error,
        )
    _attempt(
        session,
        book_id=job.book_id,
        job_id=job.id,
        provider=result.provider,
        operation=operation,
        success=True,
        model=result.model,
        request_id=result.request_id,
    )
    session.commit()
    return result


def _validate_page_result(data: dict) -> dict:
    required = {"language", "original_blocks", "original_text", "zh_text", "en_text", "explanation", "question"}
    if not required.issubset(data):
        raise ProviderError(f"页面分析缺少字段: {sorted(required - set(data))}")
    if data["language"] not in {"zh", "en", "bilingual", "unknown"}:
        data["language"] = "unknown"
    if not isinstance(data["original_blocks"], list):
        raise ProviderError("original_blocks 必须是列表")
    return data


async def analyze_book(session: Session, settings: Settings, job: ProcessingJob) -> None:
    book = session.get(Book, job.book_id)
    if not book:
        raise RuntimeError("绘本不存在")
    pages = list(
        session.scalars(
            select(BookPage)
            .where(BookPage.book_id == book.id, BookPage.is_cover.is_(False))
            .order_by(BookPage.order_index)
        )
    )
    cover = session.scalar(select(BookPage).where(BookPage.book_id == book.id, BookPage.is_cover.is_(True)))
    if not pages:
        raise RuntimeError("至少需要上传一页正文")

    family = session.get(FamilySettings, 1)
    router = ProviderRouter(settings, family.preferred_provider if family else None)
    run = AnalysisRun(book_id=book.id, status=JobStatus.RUNNING.value)
    session.add(run)
    session.commit()

    page_payloads: list[dict] = []
    for index, page in enumerate(pages, start=1):
        image_path = safe_media_path(settings, page.display_path)
        result = await _routed_call(session, router, job, "analyze_page", image_path, index)
        assert isinstance(result, ProviderResult)
        data = _validate_page_result(result.data)
        page.detected_language = data["language"]
        page.original_blocks_json = json.dumps(data["original_blocks"], ensure_ascii=False)
        page.original_text = str(data["original_text"]).strip()
        page.zh_text = str(data["zh_text"]).strip()
        page.en_text = str(data["en_text"]).strip()
        page.explanation = str(data["explanation"]).strip()
        page.question = str(data["question"]).strip()
        page_payloads.append(
            {
                "page": index,
                "language": page.detected_language,
                "original_text": page.original_text,
                "zh_text": page.zh_text,
                "en_text": page.en_text,
            }
        )
        session.commit()

    result = await _routed_call(session, router, job, "synthesize_book", page_payloads)
    assert isinstance(result, ProviderResult)
    data = result.data
    status_value = data.get("completeness_status", CompletenessStatus.UNKNOWN.value)
    if status_value not in {item.value for item in CompletenessStatus}:
        status_value = CompletenessStatus.UNKNOWN.value
    issues = [str(item) for item in data.get("issues", [])]
    if cover is None:
        issues.append("未上传封面")
        status_value = CompletenessStatus.NEEDS_REVIEW.value
    duplicate_hashes: set[str] = set()
    seen_hashes: set[str] = set()
    for page in pages:
        if page.sha256 in seen_hashes:
            duplicate_hashes.add(page.sha256)
        seen_hashes.add(page.sha256)
        issues.extend(json_list(page.quality_issues_json))
    if duplicate_hashes:
        issues.append("发现疑似重复页面")
        status_value = CompletenessStatus.NEEDS_REVIEW.value

    book.title = str(data.get("title") or book.title)[:240]
    book.summary = str(data.get("summary") or "")[:4000]
    book.completeness_status = status_value
    book.completeness_issues_json = json.dumps(list(dict.fromkeys(issues)), ensure_ascii=False)
    book.status = BookStatus.REVIEW_REQUIRED.value
    book.manifest_version += 1
    run.status = JobStatus.SUCCEEDED.value
    run.result_json = json.dumps(data, ensure_ascii=False)
    run.completed_at = _now()
    session.commit()


async def synthesize_audio(session: Session, settings: Settings, job: ProcessingJob) -> None:
    book = session.get(Book, job.book_id)
    if not book:
        raise RuntimeError("绘本不存在")
    pages = list(
        session.scalars(
            select(BookPage)
            .where(BookPage.book_id == book.id, BookPage.is_cover.is_(False))
            .order_by(BookPage.order_index)
        )
    )
    family = session.get(FamilySettings, 1)
    router = ProviderRouter(settings, family.preferred_provider if family else None)

    for page in pages:
        variants = {"original": page.original_text, "zh": page.zh_text, "en": page.en_text}
        for language, text in variants.items():
            text = (text or "").strip()
            if not text:
                continue
            existing = session.scalar(
                select(AudioAsset).where(AudioAsset.page_id == page.id, AudioAsset.language == language)
            )
            if existing:
                continue
            result = await _routed_call(session, router, job, "synthesize_speech", text, language)
            assert isinstance(result, AudioResult)
            extension = ".wav" if result.mime_type == "audio/wav" else ".mp3"
            folder = settings.media_dir / f"book-{book.id}" / "audio"
            folder.mkdir(parents=True, exist_ok=True)
            target = folder / f"page-{page.id}-{language}{extension}"
            target.write_bytes(result.content)
            session.add(
                AudioAsset(
                    page_id=page.id,
                    language=language,
                    path=str(target.relative_to(settings.media_dir)),
                    mime_type=result.mime_type,
                    sha256=content_sha256(result.content),
                    provider=result.provider,
                    model=result.model,
                )
            )
            session.commit()

    book.status = BookStatus.READY.value
    book.manifest_version += 1
    session.commit()


async def run_job(session: Session, settings: Settings, job: ProcessingJob) -> None:
    if job.status == JobStatus.SUCCEEDED.value:
        return
    book = session.get(Book, job.book_id)
    job.status = JobStatus.RUNNING.value
    job.started_at = _now()
    job.attempts += 1
    job.error = ""
    session.commit()
    try:
        if job.kind == "analyze":
            if book:
                book.status = BookStatus.ANALYZING.value
                session.commit()
            await analyze_book(session, settings, job)
        elif job.kind == "audio":
            if book:
                book.status = BookStatus.PREPARING_AUDIO.value
                session.commit()
            await synthesize_audio(session, settings, job)
        else:
            raise RuntimeError(f"未知任务类型: {job.kind}")
        job.status = JobStatus.SUCCEEDED.value
        job.completed_at = _now()
        session.commit()
    except Exception as exc:
        job.error = str(exc)[:4000]
        job.status = JobStatus.PENDING.value if job.attempts < job.max_attempts else JobStatus.FAILED.value
        if book:
            book.status = BookStatus.FAILED.value if job.status == JobStatus.FAILED.value else book.status
        session.commit()
        raise


async def process_next_job(session: Session, settings: Settings) -> bool:
    job = session.scalar(
        select(ProcessingJob)
        .where(ProcessingJob.status == JobStatus.PENDING.value)
        .order_by(ProcessingJob.created_at)
        .limit(1)
    )
    if not job:
        return False
    try:
        await run_job(session, settings, job)
    except Exception:
        pass
    return True


async def worker_loop(session_factory, settings: Settings, poll_seconds: float = 2.0) -> None:
    while True:
        with session_factory() as session:
            processed = await process_next_job(session, settings)
        if not processed:
            await asyncio.sleep(poll_seconds)
