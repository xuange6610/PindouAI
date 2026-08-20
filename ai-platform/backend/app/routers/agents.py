from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_session
from ..models import Agent, User
from ..schemas import AgentCreate
from ..security import current_user


router = APIRouter(prefix="/agents", tags=["agents"])


@router.get("")
async def list_agents(
    user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> list[dict[str, object]]:
    values = (await session.scalars(select(Agent).where(Agent.owner_id == user.id))).all()
    return [
        {
            "id": item.id,
            "name": item.name,
            "model_id": item.model_id,
            "knowledge_id": item.knowledge_id,
            "tool_permissions": item.tool_permissions,
            "is_active": item.is_active,
        }
        for item in values
    ]


@router.post("", status_code=201)
async def create_agent(
    payload: AgentCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> dict[str, str]:
    agent = Agent(owner_id=user.id, **payload.model_dump())
    session.add(agent)
    await session.commit()
    return {"id": agent.id}
