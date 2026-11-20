"""ASGI entry point for the data service."""

import logging
import time
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import FastAPI, Request
from starlette.middleware.base import RequestResponseEndpoint
from starlette.responses import Response

from data.api.routers import health, items, service
from data.core.config import get_settings
from data.core.errors import install_exception_handlers
from data.core.logging import configure_logging

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_application: FastAPI) -> AsyncGenerator[None, None]:
    """Prepare shared resources before serving and release them afterwards."""
    settings = get_settings()
    configure_logging(settings.log_level)
    logger.info(
        "service_starting",
        extra={
            "service": settings.service_name,
            "version": settings.app_version,
            "environment": settings.environment,
        },
    )
    yield
    logger.info("service_stopping", extra={"service": settings.service_name})


def create_app() -> FastAPI:
    """Build the FastAPI application."""
    settings = get_settings()
    application = FastAPI(
        title=f"Bituach Yashir {settings.service_name}",
        version=settings.app_version,
        lifespan=lifespan,
    )
    install_exception_handlers(application)
    application.include_router(service.router)
    application.include_router(items.router)
    application.include_router(health.router)

    @application.middleware("http")
    async def request_context(request: Request, call_next: RequestResponseEndpoint) -> Response:
        """Attach a correlation id and log one line per request."""
        request_id = request.headers.get("x-request-id") or uuid4().hex
        request.state.request_id = request_id
        started = time.perf_counter()
        response = await call_next(request)
        response.headers["x-request-id"] = request_id
        logger.info(
            "request_completed",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "status_code": response.status_code,
                "duration_ms": round((time.perf_counter() - started) * 1000, 2),
            },
        )
        return response

    return application


app = create_app()
