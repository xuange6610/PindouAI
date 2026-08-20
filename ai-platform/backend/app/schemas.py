from datetime import datetime
from decimal import Decimal
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from .models import UserRole


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(default="用户", min_length=1, max_length=80)
    phone: str | None = Field(default=None, max_length=32)


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    email: EmailStr
    phone: str | None
    display_name: str
    avatar_url: str | None
    role: UserRole
    is_active: bool
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserRead


class ModelCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    provider: str = Field(min_length=1, max_length=40)
    api_base: str = Field(min_length=8, max_length=1000)
    api_key: str = Field(min_length=1, max_length=4000)
    model_id: str = Field(min_length=1, max_length=255)
    model_type: str = Field(default="chat", max_length=30)
    max_tokens: int = Field(default=8192, ge=1, le=10_000_000)
    input_price: Decimal = Field(default=0, ge=0)
    output_price: Decimal = Field(default=0, ge=0)
    capabilities: dict[str, Any] = Field(default_factory=dict)
    shared: bool = False


class ModelRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    name: str
    model_id: str
    provider: str
    model_type: str
    status: str
    max_tokens: int
    input_price: Decimal
    output_price: Decimal
    capabilities: dict[str, Any]
    owner_id: str | None


class ChatCreate(BaseModel):
    title: str = Field(default="新聊天", max_length=160)
    model_id: str
    system_prompt: str | None = Field(default=None, max_length=20_000)


class ChatUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=160)
    model_id: str | None = None


class ChatRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    title: str
    model_id: str | None
    created_at: datetime
    updated_at: datetime


class MessageRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    role: str
    content: str
    attachments: list[dict[str, Any]]
    created_at: datetime


class ChatDetail(ChatRead):
    messages: list[MessageRead]


class SendMessage(BaseModel):
    content: str = Field(min_length=1, max_length=100_000)
    file_ids: list[str] = Field(default_factory=list, max_length=10)


class FileRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    original_name: str
    mime_type: str
    size_bytes: int
    status: str
    created_at: datetime


class AgentCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    prompt: str = Field(min_length=1, max_length=100_000)
    model_id: str
    knowledge_id: str | None = None
    tool_permissions: list[str] = Field(default_factory=list)


class HealthResponse(BaseModel):
    status: Literal["ok"]
    service: str
