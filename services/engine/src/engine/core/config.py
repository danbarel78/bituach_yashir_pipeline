"""Configuration loaded from the environment."""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings for the engine service.

    Every value is deployment configuration and arrives through the
    environment. Nothing here is a secret, and no value is hardcoded to a
    specific environment. The internal service URLs are ClusterIP DNS names
    supplied by the Deployment manifest.
    """

    model_config = SettingsConfigDict(env_file=None, extra="ignore", case_sensitive=False)

    service_name: str = Field(default="engine", description="Logical service name reported by the API.")
    environment: str = Field(default="dev", description="Deployment environment (dev, staging, prod).")
    app_version: str = Field(default="0.0.0", description="Immutable release version injected at build time.")
    git_sha: str = Field(default="unknown", description="Git commit injected at build time.")
    log_level: str = Field(default="INFO", description="Root logging level.")
    data_service_url: str = Field(
        default="http://data:8000",
        description="Internal ClusterIP URL of the data service.",
    )
    ingest_service_url: str = Field(
        default="http://ingest:8000",
        description="Internal ClusterIP URL of the ingest service.",
    )
    downstream_timeout_seconds: float = Field(
        default=2.0,
        description="Per-request timeout applied to internal service calls.",
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the process-wide settings instance."""
    return Settings()
