"""Consistent error responses.

Every error returned by the API has the shape::

    {"error": {"code": "...", "message": "...", "details": ...}, "request_id": "..."}
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger("smartsight.errors")


class ApiError(Exception):
    """An error with a stable machine-readable code."""

    def __init__(self, status_code: int, code: str, message: str, details: Any = None):
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details


class InvalidImageError(ApiError):
    def __init__(self, message: str, details: Any = None):
        super().__init__(422, "invalid_image", message, details)


class PayloadTooLargeError(ApiError):
    def __init__(self, message: str):
        super().__init__(413, "payload_too_large", message)


class UnsupportedMediaTypeError(ApiError):
    def __init__(self, message: str):
        super().__init__(415, "unsupported_media_type", message)


class ServiceUnavailableError(ApiError):
    def __init__(self, message: str, details: Any = None):
        super().__init__(503, "service_unavailable", message, details)


class InferenceTimeoutError(ApiError):
    def __init__(self, message: str):
        super().__init__(504, "inference_timeout", message)


def _body(request: Request, code: str, message: str, details: Any = None) -> dict:
    return {
        "error": {"code": code, "message": message, "details": details},
        "request_id": getattr(request.state, "request_id", None),
    }


def _safe_validation_details(exc: RequestValidationError) -> list[dict]:
    # Strip the offending input values: they may be image bytes or user speech.
    return [
        {"loc": list(e.get("loc", ())), "msg": e.get("msg"), "type": e.get("type")}
        for e in exc.errors()
    ]


def _validation_message(exc: RequestValidationError) -> str:
    """The first message from our own validators, which are written to be
    shown to the user and never repeat the input. Generic text otherwise."""
    for e in exc.errors():
        loc = e.get("loc", ())
        if loc and loc[-1] == "email":
            return "Enter a valid email address."
        if e.get("type") == "value_error":
            return str(e.get("msg", "")).removeprefix("Value error, ")
    return "The request is invalid."


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(request: Request, exc: ApiError):
        return JSONResponse(
            status_code=exc.status_code,
            content=_body(request, exc.code, exc.message, exc.details),
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_error(request: Request, exc: RequestValidationError):
        return JSONResponse(
            status_code=422,
            content=_body(
                request,
                "validation_error",
                _validation_message(exc),
                _safe_validation_details(exc),
            ),
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(request: Request, exc: StarletteHTTPException):
        code = {404: "not_found", 405: "method_not_allowed"}.get(exc.status_code, "http_error")
        return JSONResponse(
            status_code=exc.status_code,
            content=_body(request, code, str(exc.detail)),
        )

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception):
        logger.exception("Unhandled error on %s", request.url.path)
        return JSONResponse(
            status_code=500,
            content=_body(request, "internal_error", "An unexpected error occurred."),
        )
