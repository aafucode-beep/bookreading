from __future__ import annotations

import time
from collections import defaultdict, deque

from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Small single-instance limiter for the one-family deployment profile."""

    def __init__(self, app):
        super().__init__(app)
        self._events: dict[tuple[str, str], deque[float]] = defaultdict(deque)

    async def dispatch(self, request, call_next):
        path = request.url.path
        if request.method == "POST" and path.endswith("/auth/login"):
            bucket, limit, window = "login", 5, 60
        elif request.method == "POST" and path.endswith("/pages"):
            bucket, limit, window = "upload", 120, 3600
        else:
            return await call_next(request)

        forwarded = request.headers.get("x-forwarded-for", "")
        client_ip = forwarded.split(",", 1)[0].strip() or (request.client.host if request.client else "unknown")
        key = (bucket, client_ip)
        now = time.monotonic()
        events = self._events[key]
        while events and events[0] <= now - window:
            events.popleft()
        if len(events) >= limit:
            return JSONResponse(
                {"detail": "请求过于频繁，请稍后再试"},
                status_code=429,
                headers={"Retry-After": str(max(1, int(window - (now - events[0]))))},
            )
        events.append(now)
        return await call_next(request)

