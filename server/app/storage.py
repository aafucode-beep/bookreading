from __future__ import annotations

import hashlib
import io
import json
from dataclasses import dataclass
from pathlib import Path

from fastapi import HTTPException, UploadFile
from PIL import Image, ImageFilter, ImageOps, UnidentifiedImageError

from .config import Settings


@dataclass(slots=True)
class StoredImage:
    original_path: str
    display_path: str
    thumbnail_path: str
    mime_type: str
    sha256: str
    width: int
    height: int
    quality_issues: list[str]


ALLOWED_FORMATS = {"JPEG": "image/jpeg", "PNG": "image/png", "WEBP": "image/webp", "GIF": "image/gif"}


def _quality_issues(image: Image.Image) -> list[str]:
    issues: list[str] = []
    gray = ImageOps.grayscale(image.copy())
    edges = gray.filter(ImageFilter.FIND_EDGES)
    histogram = edges.histogram()
    count = max(1, sum(histogram))
    mean = sum(i * value for i, value in enumerate(histogram)) / count
    variance = sum(((i - mean) ** 2) * value for i, value in enumerate(histogram)) / count
    if variance < 180:
        issues.append("图片可能模糊，请检查文字是否清晰")

    bright_histogram = gray.histogram()
    bright_ratio = sum(bright_histogram[248:]) / max(1, sum(bright_histogram))
    if bright_ratio > 0.28:
        issues.append("图片可能有大面积眩光或过曝")
    if min(image.size) < 900:
        issues.append("图片分辨率偏低")
    return issues


async def store_upload(settings: Settings, book_id: int, upload: UploadFile, upload_key: str) -> StoredImage:
    raw = await upload.read(settings.max_image_bytes + 1)
    if len(raw) > settings.max_image_bytes:
        raise HTTPException(status_code=413, detail="单张图片不能超过 20MB")
    if not raw:
        raise HTTPException(status_code=400, detail="图片为空")

    try:
        image = Image.open(io.BytesIO(raw))
        image.load()
    except (UnidentifiedImageError, OSError) as exc:
        raise HTTPException(status_code=415, detail="不支持的图片格式") from exc
    if image.format not in ALLOWED_FORMATS:
        raise HTTPException(status_code=415, detail="仅支持 JPEG、PNG、GIF、WebP")

    image = ImageOps.exif_transpose(image).convert("RGB")
    digest = hashlib.sha256(raw).hexdigest()
    folder = settings.media_dir / f"book-{book_id}" / f"page-{upload_key}"
    folder.mkdir(parents=True, exist_ok=True)
    extension = {"JPEG": ".jpg", "PNG": ".png", "WEBP": ".webp", "GIF": ".gif"}[Image.open(io.BytesIO(raw)).format]
    original = folder / f"original{extension}"
    display = folder / "display.webp"
    thumbnail = folder / "thumbnail.webp"
    original.write_bytes(raw)

    display_image = image.copy()
    display_image.thumbnail((2200, 2200), Image.Resampling.LANCZOS)
    display_image.save(display, "WEBP", quality=86, method=6)
    thumb_image = image.copy()
    thumb_image.thumbnail((420, 420), Image.Resampling.LANCZOS)
    thumb_image.save(thumbnail, "WEBP", quality=78, method=6)

    return StoredImage(
        original_path=str(original.relative_to(settings.media_dir)),
        display_path=str(display.relative_to(settings.media_dir)),
        thumbnail_path=str(thumbnail.relative_to(settings.media_dir)),
        mime_type=ALLOWED_FORMATS[Image.open(io.BytesIO(raw)).format],
        sha256=digest,
        width=image.width,
        height=image.height,
        quality_issues=_quality_issues(image),
    )


def safe_media_path(settings: Settings, relative_path: str) -> Path:
    root = settings.media_dir.resolve()
    path = (root / relative_path).resolve()
    if root not in path.parents:
        raise HTTPException(status_code=404, detail="文件不存在")
    return path


def remove_book_media(settings: Settings, book_id: int) -> None:
    root = settings.media_dir.resolve()
    target = (root / f"book-{book_id}").resolve()
    if root not in target.parents or not target.exists():
        return
    for child in sorted(target.rglob("*"), reverse=True):
        if child.is_file() or child.is_symlink():
            child.unlink(missing_ok=True)
        elif child.is_dir():
            child.rmdir()
    target.rmdir()


def json_list(value: str) -> list:
    try:
        result = json.loads(value or "[]")
        return result if isinstance(result, list) else []
    except json.JSONDecodeError:
        return []

