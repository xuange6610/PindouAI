from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_session
from ..models import Chat, Message, ModelConfig, UsageLog, User
from ..security import admin_user


router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/stats")
async def stats(
    _: User = Depends(admin_user), session: AsyncSession = Depends(get_session)
) -> dict[str, int]:
    async def count(model):
        return int((await session.scalar(select(func.count()).select_from(model))) or 0)

    return {
        "users": await count(User),
        "models": await count(ModelConfig),
        "chats": await count(Chat),
        "messages": await count(Message),
        "usage_logs": await count(UsageLog),
    }
