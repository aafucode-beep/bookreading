from __future__ import annotations

import asyncio
import io
import uuid

from PIL import Image, ImageDraw

from app.config import get_settings
from app.database import db
from app.jobs import run_job
from app.models import ProcessingJob


def image_bytes(label: str, color=(90, 175, 210)) -> bytes:
    image = Image.new("RGB", (1200, 900), color)
    draw = ImageDraw.Draw(image)
    draw.rectangle((80, 80, 1120, 820), outline="white", width=12)
    draw.text((150, 400), label, fill="white")
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=92)
    return buffer.getvalue()


def create_book(client, headers):
    response = client.post("/api/v1/books", json={"title": "新绘本"}, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()["id"]


def upload(client, headers, book_id, key, index, cover=False):
    response = client.post(
        f"/api/v1/books/{book_id}/pages",
        headers=headers,
        data={"upload_key": key, "order_index": index, "is_cover": str(cover).lower()},
        files={"file": (f"{key}.jpg", image_bytes(key), "image/jpeg")},
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_auth_rejects_bad_password(client):
    response = client.post("/api/v1/auth/login", json={"username": "parent", "password": "wrong"})
    assert response.status_code == 401


def test_parent_pin_protects_creation(client, auth_headers):
    response = client.post("/api/v1/books", json={"title": "no pin"}, headers=auth_headers)
    assert response.status_code == 403


def test_complete_book_flow(client, parent_headers, auth_headers):
    book_id = create_book(client, parent_headers)
    upload(client, parent_headers, book_id, "cover", 0, True)
    first = upload(client, parent_headers, book_id, "page-1", 1)
    second = upload(client, parent_headers, book_id, "page-2", 2)

    duplicate = upload(client, parent_headers, book_id, "page-2", 2)
    assert duplicate["deduplicated"] is True

    response = client.put(
        f"/api/v1/books/{book_id}/pages/reorder",
        json={"page_ids": [second["id"], first["id"]]},
        headers=parent_headers,
    )
    assert response.status_code == 200

    response = client.post(
        f"/api/v1/books/{book_id}/analyze",
        json={"idempotency_key": f"analyze-{uuid.uuid4()}"},
        headers=parent_headers,
    )
    assert response.status_code == 202
    job_id = response.json()["id"]
    with db.session_factory() as session:
        asyncio.run(run_job(session, get_settings(), session.get(ProcessingJob, job_id)))

    detail = client.get(f"/api/v1/books/{book_id}", headers=auth_headers)
    assert detail.status_code == 200
    assert detail.json()["status"] == "review_required"
    assert detail.json()["title"] == "极光下的勇气"
    body_pages = [item for item in detail.json()["pages"] if not item["is_cover"]]
    assert len(body_pages) == 2
    assert body_pages[0]["zh_text"]

    response = client.put(
        f"/api/v1/books/{book_id}/review",
        json={"title": "勇敢的小雪狐", "summary": "一起出发。", "completeness_status": "likely_complete", "pages": {}},
        headers=parent_headers,
    )
    assert response.status_code == 200

    response = client.post(
        f"/api/v1/books/{book_id}/confirm",
        json={"idempotency_key": f"audio-{uuid.uuid4()}"},
        headers=parent_headers,
    )
    assert response.status_code == 202
    audio_job_id = response.json()["id"]
    with db.session_factory() as session:
        asyncio.run(run_job(session, get_settings(), session.get(ProcessingJob, audio_job_id)))

    manifest = client.get(f"/api/v1/books/{book_id}/manifest", headers=auth_headers)
    assert manifest.status_code == 200
    assert manifest.json()["title"] == "勇敢的小雪狐"
    assert set(manifest.json()["pages"][0]["audio"]) == {"original", "zh", "en"}
    audio_url = manifest.json()["pages"][0]["audio"]["zh"]["url"]
    assert client.get(audio_url, headers=auth_headers).status_code == 200


def test_upload_rejects_non_image(client, parent_headers):
    book_id = create_book(client, parent_headers)
    response = client.post(
        f"/api/v1/books/{book_id}/pages",
        headers=parent_headers,
        data={"upload_key": "bad-file", "order_index": 1, "is_cover": "false"},
        files={"file": ("bad.txt", b"not an image", "text/plain")},
    )
    assert response.status_code == 415

