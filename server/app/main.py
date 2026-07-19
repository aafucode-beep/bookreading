from __future__ import annotations

import json
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

from fastapi import (
    Depends,
    FastAPI,
    File,
    Form,
    HTTPException,
    Request,
    UploadFile,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from .config import get_settings
from .database import db, get_session
from .jobs import enqueue_job
from .models import (
    AudioAsset,
    Book,
    BookPage,
    BookStatus,
    FamilySettings,
    JobStatus,
    ProcessingJob,
    ProviderAttempt,
    User,
)
from .rate_limit import RateLimitMiddleware
from .schemas import (
    AudioItem,
    BookCreate,
    BookReviewUpdate,
    BookSummary,
    JobRequest,
    JobResponse,
    LoginRequest,
    ManifestPage,
    OfflineManifest,
    RefreshRequest,
    ReorderRequest,
    TokenResponse,
)
from .security import (
    authenticate,
    create_token,
    decode_token,
    get_current_user,
    issue_token_pair,
    require_parent_pin,
)
from .storage import json_list, remove_book_media, safe_media_path, store_upload


@asynccontextmanager
async def lifespan(_app: FastAPI):
    db.create_all()
    with db.session_factory() as session:
        if not session.get(FamilySettings, 1):
            session.add(FamilySettings(id=1, preferred_provider=get_settings().preferred_provider))
            session.commit()
    yield


app = FastAPI(title="勇敢成长 API", version="0.1.0", lifespan=lifespan)
settings = get_settings()
app.add_middleware(RateLimitMiddleware)
if settings.cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )


def _book_or_404(session: Session, book_id: int) -> Book:
    book = session.get(Book, book_id)
    if not book:
        raise HTTPException(status_code=404, detail="绘本不存在")
    return book


def _job_response(job: ProcessingJob) -> JobResponse:
    return JobResponse.model_validate(job)


def _book_summary(session: Session, book: Book) -> BookSummary:
    body_count = session.scalar(
        select(func.count(BookPage.id)).where(BookPage.book_id == book.id, BookPage.is_cover.is_(False))
    ) or 0
    cover = session.scalar(select(BookPage).where(BookPage.book_id == book.id, BookPage.is_cover.is_(True)))
    return BookSummary(
        id=book.id,
        title=book.title,
        summary=book.summary,
        status=book.status,
        completeness_status=book.completeness_status,
        created_at=book.created_at,
        updated_at=book.updated_at,
        page_count=body_count,
        cover_url=f"{settings.api_prefix}/media/{cover.id}/thumbnail" if cover else None,
    )


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": settings.app_name, "ai_mode": settings.ai_mode}


@app.post(f"{settings.api_prefix}/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, session: Session = Depends(get_session)) -> TokenResponse:
    user = authenticate(session, payload.username, payload.password)
    if not user:
        raise HTTPException(status_code=401, detail="账号或密码错误")
    pair = issue_token_pair(user.id, settings)
    return TokenResponse(
        access_token=pair.access_token,
        refresh_token=pair.refresh_token,
        expires_in=pair.expires_in,
    )


@app.post(f"{settings.api_prefix}/auth/refresh", response_model=TokenResponse)
def refresh(payload: RefreshRequest, session: Session = Depends(get_session)) -> TokenResponse:
    decoded = decode_token(payload.refresh_token, settings, "refresh")
    user = session.get(User, int(decoded["sub"]))
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="账号不可用")
    pair = issue_token_pair(user.id, settings)
    return TokenResponse(
        access_token=pair.access_token,
        refresh_token=pair.refresh_token,
        expires_in=pair.expires_in,
    )


@app.get(f"{settings.api_prefix}/me")
def me(user: User = Depends(get_current_user)) -> dict:
    return {"id": user.id, "username": user.username}


@app.get(f"{settings.api_prefix}/books", response_model=list[BookSummary])
def list_books(
    _user: User = Depends(get_current_user), session: Session = Depends(get_session)
) -> list[BookSummary]:
    books = list(session.scalars(select(Book).order_by(Book.updated_at.desc())))
    return [_book_summary(session, item) for item in books]


@app.post(f"{settings.api_prefix}/books", response_model=BookSummary, status_code=201)
def create_book(
    payload: BookCreate,
    _user: User = Depends(require_parent_pin),
    session: Session = Depends(get_session),
) -> BookSummary:
    book = Book(title=payload.title.strip() or "未命名绘本")
    session.add(book)
    session.commit()
    session.refresh(book)
    return _book_summary(session, book)


@app.get(f"{settings.api_prefix}/books/{{book_id}}")
def get_book(
    book_id: int,
    _user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict:
    book = _book_or_404(session, book_id)
    pages = list(session.scalars(select(BookPage).where(BookPage.book_id == book.id).order_by(BookPage.is_cover.desc(), BookPage.order_index)))
    return {
        **_book_summary(session, book).model_dump(),
        "completeness_issues": json_list(book.completeness_issues_json),
        "pages": [
            {
                "id": page.id,
                "order_index": page.order_index,
                "is_cover": page.is_cover,
                "thumbnail_url": f"{settings.api_prefix}/media/{page.id}/thumbnail",
                "quality_issues": json_list(page.quality_issues_json),
                "detected_language": page.detected_language,
                "original_text": page.original_text,
                "zh_text": page.zh_text,
                "en_text": page.en_text,
                "explanation": page.explanation,
                "question": page.question,
            }
            for page in pages
        ],
    }


@app.post(f"{settings.api_prefix}/books/{{book_id}}/pages", status_code=201)
async def upload_page(
    book_id: int,
    file: UploadFile = File(...),
    upload_key: str = Form(...),
    order_index: int = Form(...),
    is_cover: bool = Form(False),
    _user: User = Depends(require_parent_pin),
    session: Session = Depends(get_session),
) -> dict:
    book = _book_or_404(session, book_id)
    existing = session.scalar(
        select(BookPage).where(BookPage.book_id == book_id, BookPage.upload_key == upload_key)
    )
    if existing:
        return {"id": existing.id, "deduplicated": True}
    if is_cover and session.scalar(
        select(BookPage).where(BookPage.book_id == book_id, BookPage.is_cover.is_(True))
    ):
        raise HTTPException(status_code=409, detail="封面已存在，请先删除或重拍")
    body_count = session.scalar(
        select(func.count(BookPage.id)).where(BookPage.book_id == book_id, BookPage.is_cover.is_(False))
    ) or 0
    if not is_cover and body_count >= settings.max_book_pages:
        raise HTTPException(status_code=422, detail=f"单本绘本最多 {settings.max_book_pages} 页")
    stored = await store_upload(settings, book_id, file, upload_key)
    page = BookPage(
        book_id=book_id,
        order_index=-1 if is_cover else order_index,
        is_cover=is_cover,
        upload_key=upload_key,
        original_path=stored.original_path,
        display_path=stored.display_path,
        thumbnail_path=stored.thumbnail_path,
        mime_type=stored.mime_type,
        sha256=stored.sha256,
        width=stored.width,
        height=stored.height,
        quality_issues_json=json.dumps(stored.quality_issues, ensure_ascii=False),
    )
    session.add(page)
    book.status = BookStatus.UPLOADING.value
    book.manifest_version += 1
    session.commit()
    session.refresh(page)
    return {"id": page.id, "deduplicated": False, "quality_issues": stored.quality_issues}


@app.put(f"{settings.api_prefix}/books/{{book_id}}/pages/reorder")
def reorder_pages(
    book_id: int,
    payload: ReorderRequest,
    _user: User = Depends(require_parent_pin),
    session: Session = Depends(get_session),
) -> dict:
    book = _book_or_404(session, book_id)
    pages = list(
        session.scalars(
            select(BookPage).where(BookPage.book_id == book_id, BookPage.is_cover.is_(False))
        )
    )
    if set(payload.page_ids) != {page.id for page in pages} or len(payload.page_ids) != len(pages):
        raise HTTPException(status_code=422, detail="排序列表必须包含全部正文页且不能重复")
    by_id = {page.id: page for page in pages}
    for index, page_id in enumerate(payload.page_ids, start=1):
        by_id[page_id].order_index = index
    book.manifest_version += 1
    session.commit()
    return {"page_ids": payload.page_ids}


@app.delete(f"{settings.api_prefix}/books/{{book_id}}/pages/{{page_id}}", status_code=204)
def delete_page(
    book_id: int,
    page_id: int,
    _user: User = Depends(require_parent_pin),
    session: Session = Depends(get_session),
):
    book = _book_or_404(session, book_id)
    page = session.get(BookPage, page_id)
    if not page or page.book_id != book_id:
        raise HTTPException(status_code=404, detail="页面不存在")
    folder = safe_media_path(settings, page.original_path).parent
    session.delete(page)
    book.manifest_version += 1
    session.commit()
    if folder.exists():
        for child in folder.iterdir():
            child.unlink(missing_ok=True)
        folder.rmdir()


@app.post(f"{settings.api_prefix}/books/{{book_id}}/analyze", response_model=JobResponse, status_code=202)
def request_analysis(
    book_id: int,
    payload: JobRequest,
    _user: User = Depends(require_parent_pin),
    session: Session = Depends(get_session),
) -> JobResponse:
    book = _book_or_404(session, book_id)
    count = session.scalar(
        select(func.count(BookPage.id)).where(BookPage.book_id == book_id, BookPage.is_cover.is_(False))
    ) or 0
    if count < 1:
        raise HTTPException(status_code=422, detail="请至少上传一页正文")
    try:
        job = enqueue_job(session, book_id, "analyze", payload.idempotency_key)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    book.status = BookStatus.ANALYZING.value
    session.commit()
    return _job_response(job)


@app.get(f"{settings.api_prefix}/jobs/{{job_id}}", response_model=JobResponse)
def get_job(
    job_id: int,
    _user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> JobResponse:
    job = session.get(ProcessingJob, job_id)
    if not job:
        raise HTTPException(status_code=404, detail="任务不存在")
    return _job_response(job)


@app.put(f"{settings.api_prefix}/books/{{book_id}}/review")
def save_review(
    book_id: int,
    payload: BookReviewUpdate,
    _user: User = Depends(require_parent_pin),
    session: Session = Depends(get_session),
) -> dict:
    book = _book_or_404(session, book_id)
    if payload.completeness_status not in {"likely_complete", "needs_review", "unknown"}:
        raise HTTPException(status_code=422, detail="完整性状态无效")
    book.title = payload.title.strip()
    book.summary = payload.summary.strip()
    book.completeness_status = payload.completeness_status
    for page_id, changes in payload.pages.items():
        page = session.get(BookPage, page_id)
        if not page or page.book_id != book_id:
            raise HTTPException(status_code=422, detail=f"页面 {page_id} 不属于该绘本")
        for field, value in changes.model_dump(exclude_none=True).items():
            setattr(page, field, value)
    book.manifest_version += 1
    session.commit()
    return {"saved": True, "manifest_version": book.manifest_version}


@app.post(f"{settings.api_prefix}/books/{{book_id}}/confirm", response_model=JobResponse, status_code=202)
def confirm_book(
    book_id: int,
    payload: JobRequest,
    _user: User = Depends(require_parent_pin),
    session: Session = Depends(get_session),
) -> JobResponse:
    book = _book_or_404(session, book_id)
    if book.status not in {BookStatus.REVIEW_REQUIRED.value, BookStatus.FAILED.value}:
        raise HTTPException(status_code=409, detail="请先完成内容分析与家长校对")
    job = enqueue_job(session, book_id, "audio", payload.idempotency_key)
    book.status = BookStatus.PREPARING_AUDIO.value
    session.commit()
    return _job_response(job)


@app.get(f"{settings.api_prefix}/books/{{book_id}}/manifest", response_model=OfflineManifest)
def manifest(
    book_id: int,
    _user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> OfflineManifest:
    book = session.scalar(
        select(Book).where(Book.id == book_id).options(selectinload(Book.pages).selectinload(BookPage.audio_assets))
    )
    if not book:
        raise HTTPException(status_code=404, detail="绘本不存在")
    cover = next((page for page in book.pages if page.is_cover), None)
    pages = []
    for page in sorted((item for item in book.pages if not item.is_cover), key=lambda item: item.order_index):
        audio = {
            asset.language: AudioItem(
                language=asset.language,
                url=f"{settings.api_prefix}/audio/{asset.id}",
                mime_type=asset.mime_type,
                sha256=asset.sha256,
                duration_ms=asset.duration_ms,
            )
            for asset in page.audio_assets
        }
        pages.append(
            ManifestPage(
                id=page.id,
                order_index=page.order_index,
                image_url=f"{settings.api_prefix}/media/{page.id}/display",
                thumbnail_url=f"{settings.api_prefix}/media/{page.id}/thumbnail",
                original_blocks=json_list(page.original_blocks_json),
                detected_language=page.detected_language,
                original_text=page.original_text,
                zh_text=page.zh_text,
                en_text=page.en_text,
                explanation=page.explanation,
                question=page.question,
                audio=audio,
            )
        )
    return OfflineManifest(
        book_id=book.id,
        version=book.manifest_version,
        title=book.title,
        summary=book.summary,
        cover_url=f"{settings.api_prefix}/media/{cover.id}/display" if cover else None,
        pages=pages,
        generated_at=datetime.now(timezone.utc),
    )


@app.get(f"{settings.api_prefix}/media/{{page_id}}/{{variant}}")
def page_media(
    page_id: int,
    variant: str,
    _user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    page = session.get(BookPage, page_id)
    if not page:
        raise HTTPException(status_code=404, detail="文件不存在")
    choices = {"original": page.original_path, "display": page.display_path, "thumbnail": page.thumbnail_path}
    if variant not in choices:
        raise HTTPException(status_code=404, detail="文件不存在")
    path = safe_media_path(settings, choices[variant])
    if not path.exists():
        raise HTTPException(status_code=404, detail="文件不存在")
    return FileResponse(path)


@app.get(f"{settings.api_prefix}/audio/{{asset_id}}")
def audio_media(
    asset_id: int,
    _user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    asset = session.get(AudioAsset, asset_id)
    if not asset:
        raise HTTPException(status_code=404, detail="音频不存在")
    path = safe_media_path(settings, asset.path)
    return FileResponse(path, media_type=asset.mime_type)


@app.delete(f"{settings.api_prefix}/books/{{book_id}}", status_code=204)
def delete_book(
    book_id: int,
    _user: User = Depends(require_parent_pin),
    session: Session = Depends(get_session),
):
    book = _book_or_404(session, book_id)
    session.delete(book)
    session.commit()
    remove_book_media(settings, book_id)


@app.get(f"{settings.api_prefix}/version")
def version() -> dict:
    return {"android": {"latest": settings.apk_version, "download_url": settings.apk_download_url}}


def _admin_user(request: Request, session: Session) -> User | None:
    token = request.cookies.get("brave_admin", "")
    if not token:
        return None
    try:
        payload = decode_token(token, settings, "admin")
    except HTTPException:
        return None
    return session.get(User, int(payload["sub"]))


ADMIN_STYLE = """
<style>
:root{--night:#07192f;--ice:#d9f5ff;--aurora:#70e2cd;--coral:#ff8e7a;--ink:#102b46}
*{box-sizing:border-box}body{margin:0;font-family:'Trebuchet MS',sans-serif;background:radial-gradient(circle at 20% 0,#184b67,transparent 35%),var(--night);color:var(--ice);min-height:100vh}
main{max-width:1080px;margin:auto;padding:48px 24px}.card{background:#f4fbff;color:var(--ink);border:1px solid #ffffff66;border-radius:24px;padding:24px;box-shadow:0 24px 70px #0005;margin:18px 0}h1{font-family:Georgia,serif;font-size:42px;margin:0 0 8px}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:12px;border-bottom:1px solid #cde1eb}button{background:var(--coral);border:0;border-radius:999px;padding:10px 18px;font-weight:700;color:#31120d}input,select{width:100%;padding:12px;border:1px solid #b8d2df;border-radius:12px;margin:8px 0 16px}.pill{padding:5px 10px;border-radius:99px;background:#d9f5ff}.muted{color:#58758b}a{color:#8ff4e0}
</style>
"""


@app.get("/admin", response_class=HTMLResponse)
def admin_home(request: Request, session: Session = Depends(get_session)):
    user = _admin_user(request, session)
    if not user:
        return HTMLResponse(
            ADMIN_STYLE + "<main><h1>勇敢成长</h1><p>家长运维台</p><form class='card' method='post' action='/admin/login'><label>账号</label><input name='username' required><label>密码</label><input name='password' type='password' required><button>进入雪屋</button></form></main>"
        )
    books = list(session.scalars(select(Book).order_by(Book.updated_at.desc()).limit(50)))
    jobs = list(session.scalars(select(ProcessingJob).order_by(ProcessingJob.created_at.desc()).limit(30)))
    family = session.get(FamilySettings, 1)
    attempts = list(session.scalars(select(ProviderAttempt).order_by(ProviderAttempt.created_at.desc()).limit(15)))
    rows = "".join(f"<tr><td>{b.id}</td><td>{b.title}</td><td><span class='pill'>{b.status}</span></td><td>{b.updated_at:%m-%d %H:%M}</td></tr>" for b in books) or "<tr><td colspan='4'>尚无绘本</td></tr>"
    job_rows = "".join(f"<tr><td>{j.id}</td><td>{j.kind}</td><td>{j.status}</td><td>{j.attempts}</td><td><form method='post' action='/admin/jobs/{j.id}/retry'><button>重试</button></form></td></tr>" for j in jobs) or "<tr><td colspan='5'>尚无任务</td></tr>"
    attempt_rows = "".join(f"<tr><td>{a.provider}</td><td>{a.operation}</td><td>{'成功' if a.success else '失败'}</td><td class='muted'>{a.error[:80]}</td></tr>" for a in attempts) or "<tr><td colspan='4'>尚无调用记录</td></tr>"
    return HTMLResponse(ADMIN_STYLE + f"<main><h1>勇敢成长</h1><p>只读内容运维台 · 不展示绘本原图</p><section class='card'><h2>AI 路由</h2><form method='post' action='/admin/provider'><select name='provider'><option {'selected' if family and family.preferred_provider=='minimax' else ''}>minimax</option><option {'selected' if family and family.preferred_provider=='openai' else ''}>openai</option></select><button>保存首选供应商</button></form></section><section class='card'><h2>绘本</h2><table><tr><th>ID</th><th>标题</th><th>状态</th><th>更新时间</th></tr>{rows}</table></section><section class='card'><h2>任务</h2><table><tr><th>ID</th><th>类型</th><th>状态</th><th>次数</th><th></th></tr>{job_rows}</table></section><section class='card'><h2>供应商调用</h2><table><tr><th>供应商</th><th>操作</th><th>结果</th><th>信息</th></tr>{attempt_rows}</table></section></main>")


@app.post("/admin/login")
def admin_login(username: str = Form(...), password: str = Form(...), session: Session = Depends(get_session)):
    user = authenticate(session, username, password)
    if not user:
        return HTMLResponse(ADMIN_STYLE + "<main><div class='card'>账号或密码错误。<a href='/admin'>返回</a></div></main>", status_code=401)
    response = RedirectResponse("/admin", status_code=303)
    response.set_cookie("brave_admin", create_token(user.id, "admin", settings.admin_cookie_hours * 3600, settings), httponly=True, secure=settings.environment == "production", samesite="strict", max_age=settings.admin_cookie_hours * 3600)
    return response


@app.post("/admin/provider")
def admin_provider(request: Request, provider: str = Form(...), session: Session = Depends(get_session)):
    if not _admin_user(request, session):
        raise HTTPException(status_code=401)
    if provider not in {"minimax", "openai"}:
        raise HTTPException(status_code=422)
    family = session.get(FamilySettings, 1) or FamilySettings(id=1)
    family.preferred_provider = provider
    session.add(family)
    session.commit()
    return RedirectResponse("/admin", status_code=303)


@app.post("/admin/jobs/{job_id}/retry")
def admin_retry(request: Request, job_id: int, session: Session = Depends(get_session)):
    if not _admin_user(request, session):
        raise HTTPException(status_code=401)
    job = session.get(ProcessingJob, job_id)
    if not job:
        raise HTTPException(status_code=404)
    job.status = JobStatus.PENDING.value
    job.error = ""
    session.commit()
    return RedirectResponse("/admin", status_code=303)


@app.get("/downloads/brave-growth.apk")
def download_apk():
    path = Path("downloads/brave-growth.apk")
    if not path.exists():
        raise HTTPException(status_code=404, detail="APK 尚未发布")
    return FileResponse(path, filename="brave-growth.apk", media_type="application/vnd.android.package-archive")


@app.get("/", response_class=HTMLResponse)
def landing() -> str:
    return ADMIN_STYLE + "<main><h1>勇敢成长</h1><p>把纸上的故事，变成会陪伴孩子的声音。</p><div class='card'><h2>Android 版</h2><p>请使用家长设备下载安装。首次安装需要允许浏览器安装外部应用。</p><a href='/downloads/brave-growth.apk'><button>下载 APK</button></a></div><p><a href='/admin'>家长运维台</a></p></main>"
