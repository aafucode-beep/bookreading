from __future__ import annotations

import sqlite3
import tarfile

from app.backup import create_backup
from app.config import get_settings


def test_backup_contains_database_media_and_manifest(tmp_path, monkeypatch):
    data = tmp_path / "data"
    media = data / "media"
    media.mkdir(parents=True)
    (media / "sample.txt").write_text("sample", encoding="utf-8")
    database = data / "backup-test.db"
    with sqlite3.connect(database) as connection:
        connection.execute("create table sample(value text)")
        connection.execute("insert into sample values ('ok')")
        connection.commit()

    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("DATA_DIR", str(data))
    monkeypatch.setenv("MEDIA_DIR", str(media))
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{database.as_posix()}")
    get_settings.cache_clear()
    try:
        archive = create_backup()
        with tarfile.open(archive) as bundle:
            names = bundle.getnames()
        assert any(name.endswith("brave_growth.db") for name in names)
        assert any(name.endswith("sample.txt") for name in names)
        assert any(name.endswith("media-manifest.json") for name in names)
    finally:
        get_settings.cache_clear()

