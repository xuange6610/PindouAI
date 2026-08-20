from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "AI 多模型工作台"
    app_env: str = "development"
    database_url: str = "mysql+asyncmy://ai_platform:ai_platform@localhost:3306/ai_platform?charset=utf8mb4"
    redis_url: str = "redis://localhost:6379/0"
    qdrant_url: str = "http://localhost:6333"
    jwt_secret: str = Field(default="development-only-change-me-at-once", min_length=24)
    key_encryption_secret: str = Field(default="development-encryption-change-me", min_length=24)
    access_token_minutes: int = 1440
    cors_origins: list[str] = ["http://localhost:5173", "http://localhost:8080"]
    upload_directory: str = "/data/uploads"
    max_upload_bytes: int = 30 * 1024 * 1024

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
