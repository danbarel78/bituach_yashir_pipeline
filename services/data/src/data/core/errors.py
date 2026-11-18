"""Consistent error responses for every failure path."""

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger(__name__)


class ErrorResponse(BaseModel):
    """Error payload returned by every failure path."""

    error: str = Field(description="Machine-readable error code.")
    detail: str = Field(description="Human-readable explanation.")
    request_id: str | None = Field(default=None, description="Correlation identifier for the request.")


def _request_id(request: Request) -> str | None:
    """Return the correlation id attached by the request middleware, if any."""
    value: str | None = getattr(request.state, "request_id", None)
    return value


def install_exception_handlers(app: FastAPI) -> None:
    """Register handlers so clients always receive the same error shape."""

    @app.exception_handler(StarletteHTTPException)
    async def handle_http_exception(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        body = ErrorResponse(
            error=f"http_{exc.status_code}",
            detail=str(exc.detail),
            request_id=_request_id(request),
        )
        return JSONResponse(status_code=exc.status_code, content=body.model_dump())

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
        logger.info("request_validation_failed", extra={"path": request.url.path, "errors": exc.errors()})
        body = ErrorResponse(
            error="validation_error",
            detail="Request validation failed.",
            request_id=_request_id(request),
        )
        return JSONResponse(status_code=422, content=body.model_dump())

    @app.exception_handler(Exception)
    async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
        logger.exception(
            "unhandled_exception",
            extra={
                "path": request.url.path,
                "request_id": _request_id(request),
                "error_type": type(exc).__name__,
            },
        )
        body = ErrorResponse(
            error="internal_error",
            detail="Internal server error.",
            request_id=_request_id(request),
        )
        return JSONResponse(status_code=500, content=body.model_dump())
