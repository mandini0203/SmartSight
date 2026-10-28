"""Logging setup and a privacy-aware request-logging middleware.

The middleware logs method, path, status and duration only. It never logs
request bodies, image bytes, query strings, client IP addresses or speech text.
"""

from __future__ import annotations

import logging
import time
import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request


def configure_logging(level: str) -> None:
    logging.basicConfig(
        level=level.upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    # Ultralytics prints per-image results at INFO; keep them out of our logs.
    logging.getLogger("ultralytics").setLevel(logging.WARNING)


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.logger = logging.getLogger("smartsight.request")

    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get("x-request-id") or uuid.uuid4().hex[:12]
        # Accept only short, simple client ids so headers cannot inject log content.
        if not (request_id.isalnum() and len(request_id) <= 64):
            request_id = uuid.uuid4().hex[:12]
        request.state.request_id = request_id
        start = time.perf_counter()
        response = await call_next(request)
        elapsed_ms = (time.perf_counter() - start) * 1000
        response.headers["x-request-id"] = request_id
        self.logger.info(
            "%s %s -> %d (%.1f ms) id=%s",
            request.method,
            request.url.path,
            response.status_code,
            elapsed_ms,
            request_id,
        )
        return response
