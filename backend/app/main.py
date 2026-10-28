"""SmartSight FastAPI application.

Run:  uvicorn app.main:app --host 0.0.0.0 --port 8000
Docs: http://<host>:8000/docs (Swagger UI) and /redoc
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import __version__
from app.api.routes import accounts, colour, context, detection, health, intent, items, signs
from app.config import Settings, get_settings
from app.db import Database
from app.errors import install_error_handlers
from app.logging_config import RequestLoggingMiddleware, configure_logging
from app.services.accounts.google import GoogleTokenVerifier
from app.services.accounts.security import resolve_jwt_secret
from app.services.accounts.throttle import LoginThrottle
from app.services.registry import Services, build_services

DESCRIPTION = """
Backend for **SmartSight**, an assistive information app for blind and
partially sighted users.

* Object detection uses a **pretrained YOLOv8** checkpoint (COCO, 80 classes),
  with no custom training.
* Context reasoning and intent resolution are **deterministic rule-based
  baselines**, not trained models.
* Every result is an estimate. SmartSight does not replace a cane, guide dog or
  other mobility aid.
* Accounts are optional. Sign in with `/api/v1/auth/*` and send the access token
  as `Authorization: Bearer <token>` to the `/api/v1/me` endpoints.

All errors use the shape `{"error": {"code", "message", "details"}, "request_id"}`.
"""


def create_app(settings: Settings | None = None, services: Services | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.services = services or build_services(settings)
        yield
        app.state.db.dispose()

    app = FastAPI(
        title=settings.app_name,
        version=__version__,
        description=DESCRIPTION,
        lifespan=lifespan,
    )
    # Accounts are set up here rather than in lifespan so tests can replace
    # the Google verifier before the first request.
    app.state.settings = settings
    app.state.db = Database(settings.resolved_database_url)
    app.state.jwt_secret = resolve_jwt_secret(settings)
    app.state.google_verifier = GoogleTokenVerifier(settings.google_client_ids)
    app.state.login_throttle = LoginThrottle(settings.login_max_failures, settings.login_lockout_minutes * 60)

    app.add_middleware(RequestLoggingMiddleware)
    if settings.cors_origins:
        app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins,
                           allow_methods=["GET", "POST", "PUT", "DELETE"], allow_headers=["*"])
    install_error_handlers(app)
    for module in (health, detection, context, intent, items, colour, signs):
        app.include_router(module.router)
    app.include_router(accounts.auth_router)
    app.include_router(accounts.me_router)
    return app


app = create_app()
