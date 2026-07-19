from __future__ import annotations

import asyncio

from .config import get_settings
from .database import db
from .jobs import worker_loop


def main() -> None:
    settings = get_settings()
    db.create_all()
    asyncio.run(worker_loop(db.session_factory, settings))


if __name__ == "__main__":
    main()

