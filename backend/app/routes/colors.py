from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_session
from ..models import Color
from ..schemas import ColorRead

router = APIRouter(prefix="/colors", tags=["colors"])


@router.get("", response_model=list[ColorRead])
async def list_colors(
    palette_id: UUID,
    series: str | None = Query(default=None, min_length=1, max_length=8),
    session: AsyncSession = Depends(get_session),
) -> list[Color]:
    query = select(Color).where(Color.palette_id == palette_id)
    if series:
        query = query.where(Color.series == series.upper())
    query = query.order_by(Color.series, Color.sort_order)
    return list((await session.scalars(query)).all())
