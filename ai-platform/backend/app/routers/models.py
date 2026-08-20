from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_session
from ..gateway import build_adapter
from ..models import ApiConfig, ModelConfig, User, UserRole
from ..schemas import ModelCreate, ModelRead
from ..security import current_user, encrypt_secret


router = APIRouter(prefix="/models", tags=["models"])


@router.get("", response_model=list[ModelRead])
async def list_models(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[ModelConfig]:
    query = select(ModelConfig).where(
        ModelConfig.status == "active",
        or_(ModelConfig.owner_id.is_(None), ModelConfig.owner_id == user.id),
    ).order_by(ModelConfig.provider, ModelConfig.name)
    return list((await session.scalars(query)).unique().all())


@router.post("", response_model=ModelRead, status_code=201)
async def create_model(
    payload: ModelCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> ModelConfig:
    if payload.shared and user.role != UserRole.admin:
        raise HTTPException(status_code=403, detail="只有管理员可以创建共享模型")
    try:
        build_adapter(
            payload.provider,
            api_base=payload.api_base,
            api_key=payload.api_key,
            model_id=payload.model_id,
        )
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    owner_id = None if payload.shared else user.id
    api_config = ApiConfig(
        owner_id=owner_id,
        name=f"{payload.name} API",
        provider=payload.provider.lower(),
        api_base=payload.api_base.rstrip("/"),
        encrypted_api_key=encrypt_secret(payload.api_key),
    )
    session.add(api_config)
    await session.flush()
    model = ModelConfig(
        owner_id=owner_id,
        api_config_id=api_config.id,
        name=payload.name,
        model_id=payload.model_id,
        provider=payload.provider.lower(),
        model_type=payload.model_type,
        max_tokens=payload.max_tokens,
        input_price=payload.input_price,
        output_price=payload.output_price,
        capabilities=payload.capabilities,
    )
    session.add(model)
    await session.commit()
    await session.refresh(model)
    return model


@router.delete("/{model_id}", status_code=204)
async def delete_model(
    model_id: str,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    model = await session.get(ModelConfig, model_id)
    if model is None:
        raise HTTPException(status_code=404, detail="模型不存在")
    if model.owner_id != user.id and user.role != UserRole.admin:
        raise HTTPException(status_code=403, detail="无权删除该模型")
    model.status = "disabled"
    await session.commit()
