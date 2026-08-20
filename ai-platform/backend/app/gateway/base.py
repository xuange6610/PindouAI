from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class GatewayMessage:
    role: str
    content: str
    attachments: list[dict[str, Any]]


class ModelAdapter(ABC):
    def __init__(self, *, api_base: str, api_key: str, model_id: str, headers: dict[str, str] | None = None):
        self.api_base = api_base.rstrip("/")
        self.api_key = api_key
        self.model_id = model_id
        self.headers = headers or {}

    @abstractmethod
    async def stream_chat(self, messages: list[GatewayMessage]) -> AsyncIterator[str]:
        raise NotImplementedError
