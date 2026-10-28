from __future__ import annotations

import logging

from fastapi import APIRouter, Depends

from app.api.deps import get_services
from app.schemas.common import ErrorResponse
from app.schemas.intent import IntentRequest, IntentResponse
from app.services.registry import Services

router = APIRouter(prefix="/api/v1/intent", tags=["intent"])
logger = logging.getLogger("smartsight.intent")


@router.post("/resolve", response_model=IntentResponse, responses={422: {"model": ErrorResponse}},
             summary="Resolve a spoken or typed task intention (rule-based)")
def resolve(request: IntentRequest, services: Services = Depends(get_services)) -> IntentResponse:
    """Maps text such as "where is my phone" to a supported task.

    In-app navigation and scan control are handled by the phone and return
    ``UNSUPPORTED`` with the matched rule ``app_command``.
    """
    result = services.intent.resolve(request)
    # Log the outcome only, never the user's words.
    logger.info("intent=%s status=%s chars=%d", result.intent, result.status.value, len(request.text))
    return result
