import base64
import json
import time
from datetime import datetime
from decimal import Decimal
from pathlib import Path

import httpx
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..database import SessionLocal, get_session
from ..gateway import build_adapter
from ..gateway.base import GatewayMessage
from ..models import Chat, FileAsset, Message, ModelConfig, UsageLog, User
from ..schemas import ChatCreate, ChatDetail, ChatRead, ChatUpdate, SendMessage
from ..security import current_user, decrypt_secret


router = APIRouter(prefix="/chats", tags=["chats"])


async def _owned_chat(session: AsyncSession, chat_id: str, user_id: str) -> Chat:
    chat = (
        await session.execute(
            select(Chat)
            .where(Chat.id == chat_id, Chat.user_id == user_id)
            .options(selectinload(Chat.messages))
        )
    ).scalar_one_or_none()
    if chat is None:
        raise HTTPException(status_code=404, detail="聊天不存在")
    chat.messages.sort(key=lambda message: message.created_at)
    return chat


async def _usable_model(session: AsyncSession, model_id: str, user_id: str) -> ModelConfig:
    model = (
        await session.execute(
            select(ModelConfig).where(
                ModelConfig.id == model_id,
                ModelConfig.status == "active",
                or_(ModelConfig.owner_id.is_(None), ModelConfig.owner_id == user_id),
            )
        )
    ).scalar_one_or_none()
    if model is None:
        raise HTTPException(status_code=404, detail="模型不可用")
    return model


@router.get("", response_model=list[ChatRead])
async def list_chats(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[Chat]:
    return list(
        (
            await session.scalars(
                select(Chat).where(Chat.user_id == user.id).order_by(Chat.updated_at.desc())
            )
        ).all()
    )


@router.post("", response_model=ChatRead, status_code=201)
async def create_chat(
    payload: ChatCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Chat:
    await _usable_model(session, payload.model_id, user.id)
    chat = Chat(
        user_id=user.id,
        model_id=payload.model_id,
        title=payload.title,
        system_prompt=payload.system_prompt,
    )
    session.add(chat)
    await session.commit()
    await session.refresh(chat)
    return chat


@router.get("/{chat_id}", response_model=ChatDetail)
async def get_chat(
    chat_id: str,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Chat:
    return await _owned_chat(session, chat_id, user.id)


@router.patch("/{chat_id}", response_model=ChatRead)
async def update_chat(
    chat_id: str,
    payload: ChatUpdate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Chat:
    chat = await _owned_chat(session, chat_id, user.id)
    if payload.model_id is not None:
        await _usable_model(session, payload.model_id, user.id)
        chat.model_id = payload.model_id
    if payload.title is not None:
        chat.title = payload.title
    chat.updated_at = datetime.utcnow()
    await session.commit()
    return chat


@router.delete("/{chat_id}", status_code=204)
async def delete_chat(
    chat_id: str,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    chat = await _owned_chat(session, chat_id, user.id)
    await session.delete(chat)
    await session.commit()


@router.post("/{chat_id}/messages/stream")
async def stream_message(
    chat_id: str,
    payload: SendMessage,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> StreamingResponse:
    chat = await _owned_chat(session, chat_id, user.id)
    if chat.model_id is None:
        raise HTTPException(status_code=409, detail="请先选择模型")
    model = await _usable_model(session, chat.model_id, user.id)
    attachments: list[dict[str, object]] = []
    if payload.file_ids:
        assets = list(
            (
                await session.scalars(
                    select(FileAsset).where(
                        FileAsset.id.in_(payload.file_ids), FileAsset.user_id == user.id
                    )
                )
            ).all()
        )
        if len(assets) != len(set(payload.file_ids)):
            raise HTTPException(status_code=404, detail="部分附件不存在")
        for asset in assets:
            content = Path(asset.storage_path).read_bytes()
            attachments.append(
                {
                    "id": asset.id,
                    "name": asset.original_name,
                    "mime_type": asset.mime_type,
                    "data_url": f"data:{asset.mime_type};base64,{base64.b64encode(content).decode('ascii')}",
                }
            )
    user_message = Message(
        chat_id=chat.id,
        role="user",
        content=payload.content,
        attachments=[{key: value for key, value in item.items() if key != "data_url"} for item in attachments],
    )
    session.add(user_message)
    chat.updated_at = datetime.utcnow()
    await session.commit()
    message_history = [
        GatewayMessage(role=message.role, content=message.content, attachments=message.attachments)
        for message in chat.messages
    ]
    if chat.system_prompt:
        message_history.insert(0, GatewayMessage(role="system", content=chat.system_prompt, attachments=[]))
    message_history.append(GatewayMessage(role="user", content=payload.content, attachments=attachments))
    api_key = decrypt_secret(model.api_config.encrypted_api_key)
    adapter = build_adapter(
        model.provider,
        api_base=model.api_config.api_base,
        api_key=api_key,
        model_id=model.model_id,
        headers={str(key): str(value) for key, value in model.api_config.extra_headers.items()},
    )

    async def events():
        chunks: list[str] = []
        started = time.perf_counter()
        try:
            yield f"event: meta\ndata: {json.dumps({'model': model.name}, ensure_ascii=False)}\n\n"
            async for chunk in adapter.stream_chat(message_history):
                chunks.append(chunk)
                yield f"event: delta\ndata: {json.dumps({'content': chunk}, ensure_ascii=False)}\n\n"
            content = "".join(chunks)
            latency_ms = int((time.perf_counter() - started) * 1000)
            async with SessionLocal() as write_session:
                write_session.add(Message(chat_id=chat.id, role="assistant", content=content))
                write_session.add(
                    UsageLog(
                        user_id=user.id,
                        model_id=model.id,
                        chat_id=chat.id,
                        output_tokens=max(1, len(content) // 4),
                        latency_ms=latency_ms,
                        cost=Decimal("0"),
                    )
                )
                stored_chat = await write_session.get(Chat, chat.id)
                if stored_chat is not None:
                    stored_chat.updated_at = datetime.utcnow()
                await write_session.commit()
            yield f"event: done\ndata: {json.dumps({'content': content}, ensure_ascii=False)}\n\n"
        except (httpx.HTTPError, ValueError) as error:
            yield f"event: error\ndata: {json.dumps({'detail': str(error)}, ensure_ascii=False)}\n\n"

    return StreamingResponse(
        events(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
