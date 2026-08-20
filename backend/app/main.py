from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .routes import colors
from .routes import ai
from .routes import collection
from .schemas import HealthResponse

settings = get_settings()


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Database schema changes are handled outside the process by migrations.
    yield


app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    description="拼豆颜色库与云作品 API。版权所有 © 2026 xuan。",
    lifespan=lifespan,
)
if settings.cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST"],
        allow_headers=[
            "Authorization",
            "Content-Type",
            "X-AI-Provider-Base-Url",
            "X-AI-Provider-Key",
        ],
    )

app.include_router(colors.router, prefix="/v1")
app.include_router(ai.router, prefix="/v1")
app.include_router(collection.router, prefix="/v1")


@app.get("/health", response_model=HealthResponse, tags=["system"])
async def health() -> HealthResponse:
    return HealthResponse(
        status="ok",
        service=settings.app_name,
        copyright="xuan",
    )
