from __future__ import annotations

import os
import tempfile
from pathlib import Path


TEST_ROOT = Path(tempfile.mkdtemp(prefix="brave-growth-tests-"))
os.environ["DATA_DIR"] = str(TEST_ROOT)
os.environ["MEDIA_DIR"] = str(TEST_ROOT / "media")
os.environ["DATABASE_URL"] = f"sqlite:///{(TEST_ROOT / 'test.db').as_posix()}"
os.environ["SECRET_KEY"] = "test-secret-key-that-is-long-enough"
os.environ["AI_MODE"] = "mock"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.database import db  # noqa: E402
from app.main import app  # noqa: E402
from app.models import FamilySettings, User  # noqa: E402
from app.security import hash_secret  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def database():
    db.create_all()
    with db.session_factory() as session:
        if not session.get(User, 1):
            session.add(User(id=1, username="parent", password_hash=hash_secret("very-secure-password"), pin_hash=hash_secret("2468")))
        if not session.get(FamilySettings, 1):
            session.add(FamilySettings(id=1, preferred_provider="minimax"))
        session.commit()
    yield


@pytest.fixture()
def client(database):
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def auth_headers(client):
    response = client.post("/api/v1/auth/login", json={"username": "parent", "password": "very-secure-password"})
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


@pytest.fixture()
def parent_headers(auth_headers):
    return {**auth_headers, "X-Parent-Pin": "2468"}

