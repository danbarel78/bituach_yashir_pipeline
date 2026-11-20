"""Configuration loaded from the environment."""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings for the data service.

    Every value is deployment configuration and must arrive through the
    environment. Nothing here is a secret, and no value is hardcoded to a
    specific environment.
    """

    model_config = SettingsConfigDict(env_file=None, extra="ignore", case_sensitive=False)

    service_name: str = Field(default="data", description="Logical service name reported by the API.")
    environment: str = Field(default="dev", description="Deployment environment (dev, staging, prod).")
    app_version: str = Field(default="0.0.0", description="Immutable release version injected at build time.")
    git_sha: str = Field(default="unknown", description="Git commit injected at build time.")
    log_level: str = Field(default="INFO", description="Root logging level.")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the process-wide settings instance."""
    return Settings()
