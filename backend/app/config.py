"""Application configuration loaded from environment variables.

Every setting can be overridden with an environment variable prefixed with
``SMARTSIGHT_`` (for example ``SMARTSIGHT_DETECTION_CONFIDENCE=0.4``) or via a
``.env`` file in the backend directory. See ``.env.example``.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="SMARTSIGHT_",
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
        protected_namespaces=(),
    )

    app_name: str = "SmartSight API"
    environment: Literal["development", "test", "production"] = "development"
    log_level: str = "INFO"
    cors_origins: list[str] = Field(default_factory=list)

    # --- Object detection (pretrained YOLOv8, COCO classes) ---
    detector_backend: Literal["yolov8"] = "yolov8"
    model_path: Path = BACKEND_DIR / "models" / "yolov8n.pt"
    detection_confidence: float = Field(0.35, ge=0.01, le=0.99)
    detection_iou: float = Field(0.45, ge=0.05, le=0.95)
    detection_image_size: int = Field(640, ge=160, le=1920)
    detection_max_results: int = Field(50, ge=1, le=300)
    inference_device: str = "cpu"
    inference_timeout_seconds: float = Field(20.0, gt=0)
    warmup_on_startup: bool = True

    # --- Door / exit-sign detection ---
    # "yolo_world": pretrained open-vocabulary YOLOv8-World (needs CLIP) verified
    #               by colour/geometry checks.
    # "heuristic":  OpenCV-only colour/geometry candidate finder (no model).
    door_sign_backend: Literal["yolo_world", "heuristic"] = "yolo_world"
    door_sign_model_path: Path = BACKEND_DIR / "models" / "yolov8s-worldv2.pt"
    door_sign_confidence: float = Field(0.15, ge=0.01, le=0.99)

    # --- Rule-based services (selectable for future trained models) ---
    intent_resolver: Literal["rule_based"] = "rule_based"
    context_reasoner: Literal["rule_based"] = "rule_based"
    colour_identifier: Literal["kmeans_lab"] = "kmeans_lab"

    # --- Personal-item matching ---
    # "embedding": ImageNet-pretrained MobileNetV3 embeddings + ORB keypoints.
    # "orb":       OpenCV ORB keypoints + colour histogram only (no download).
    item_matcher: Literal["embedding", "orb"] = "embedding"
    item_match_threshold: float = Field(0.80, ge=0.0, le=1.0)
    item_possible_match_threshold: float = Field(0.65, ge=0.0, le=1.0)
    item_max_references: int = Field(5, ge=1, le=10)

    # --- Distance estimation (calibrated monocular, known object sizes) ---
    distance_estimation_enabled: bool = True
    # Field of view across the LONG side of the image (typical phone main camera ~66 deg).
    camera_fov_degrees: float = Field(66.0, gt=10, lt=170)

    # --- Upload limits ---
    max_upload_bytes: int = Field(8 * 1024 * 1024, ge=1024)
    max_image_side: int = Field(6000, ge=64)
    min_image_side: int = Field(32, ge=8)

    # --- User accounts ---
    # Holds the SQLite database, the generated development JWT secret and
    # users' item photos.
    data_dir: Path = BACKEND_DIR / "data"
    # Empty = SQLite file in data_dir. Any SQLAlchemy URL works.
    database_url: str = ""
    # Required when environment=production. In development a random secret is
    # generated once and stored in data_dir/jwt_secret.
    jwt_secret: str = ""
    access_token_minutes: int = Field(30, ge=1, le=24 * 60)
    refresh_token_days: int = Field(30, ge=1, le=365)
    # OAuth "Web application" client ID(s) from Google Cloud. The Android app
    # requests ID tokens for this audience. Empty disables Google sign-in.
    google_client_ids: list[str] = Field(default_factory=list)
    login_max_failures: int = Field(5, ge=1, le=100)
    login_lockout_minutes: int = Field(15, ge=1, le=24 * 60)
    max_items_per_user: int = Field(50, ge=1, le=1000)

    @property
    def resolved_database_url(self) -> str:
        return self.database_url or f"sqlite:///{(self.data_dir / 'smartsight.db').as_posix()}"


@lru_cache
def get_settings() -> Settings:
    return Settings()
