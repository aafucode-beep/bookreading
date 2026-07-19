from __future__ import annotations

import hashlib
import json
import shutil
import sqlite3
import tarfile
import time
from datetime import datetime, timezone
from pathlib import Path

from .config import get_settings


def _database_path(database_url: str) -> Path:
    prefix = "sqlite:///"
    if not database_url.startswith(prefix):
        raise RuntimeError("自动备份仅支持本地 SQLite")
    return Path(database_url[len(prefix) :])


def _manifest(root: Path) -> list[dict]:
    entries = []
    if not root.exists():
        return entries
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        entries.append(
            {
                "path": str(path.relative_to(root)),
                "size": path.stat().st_size,
                "sha256": digest.hexdigest(),
            }
        )
    return entries


def _retain(directory: Path, pattern: str, count: int) -> None:
    files = sorted(directory.glob(pattern), key=lambda item: item.stat().st_mtime, reverse=True)
    for path in files[count:]:
        path.unlink(missing_ok=True)


def create_backup() -> Path:
    settings = get_settings()
    backup_root = Path("backups")
    daily = backup_root / "daily"
    weekly = backup_root / "weekly"
    daily.mkdir(parents=True, exist_ok=True)
    weekly.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc)
    stamp = now.strftime("%Y%m%d-%H%M%S")
    staging = backup_root / f"staging-{stamp}"
    staging.mkdir(parents=True)
    try:
        source_path = _database_path(settings.database_url)
        with sqlite3.connect(source_path) as source, sqlite3.connect(staging / "brave_growth.db") as destination:
            source.backup(destination)
        (staging / "media-manifest.json").write_text(
            json.dumps(_manifest(settings.media_dir), ensure_ascii=False, indent=2), encoding="utf-8"
        )
        safe_config = {
            "app_name": settings.app_name,
            "environment": settings.environment,
            "preferred_provider": settings.preferred_provider,
            "max_book_pages": settings.max_book_pages,
            "apk_version": settings.apk_version,
        }
        (staging / "config.json").write_text(json.dumps(safe_config, ensure_ascii=False, indent=2), encoding="utf-8")
        archive = daily / f"brave-growth-{stamp}.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(staging, arcname="snapshot")
            if settings.media_dir.exists():
                tar.add(settings.media_dir, arcname="media")
        if now.weekday() == 6:
            shutil.copy2(archive, weekly / archive.name)
        _retain(daily, "*.tar.gz", 7)
        _retain(weekly, "*.tar.gz", 4)
        return archive
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def main() -> None:
    while True:
        try:
            print(f"backup created: {create_backup()}", flush=True)
        except Exception as exc:
            print(f"backup failed: {exc}", flush=True)
        time.sleep(86400)


if __name__ == "__main__":
    main()

