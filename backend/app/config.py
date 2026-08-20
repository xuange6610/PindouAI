from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "拼豆 AI API"
    app_env: str = "development"
    database_url: str = "postgresql+asyncpg://bead:bead_dev@localhost:5432/bead_ai"
    redis_url: str = "redis://localhost:6379/0"
    cors_origins: list[str] = []
    ai_proxy_base_url: str = "https://api.openai.com/v1"
    ai_proxy_api_key: str = ""
    ai_proxy_model: str = "gpt-5.6-sol"
    ai_proxy_image_model: str = "gpt-5.6-sol"
    ai_proxy_timeout_seconds: float = 120.0
    collection_source_dir: str = ""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
