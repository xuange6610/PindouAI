import json
from collections.abc import AsyncIterator

import httpx

from .base import GatewayMessage, ModelAdapter


class OllamaAdapter(ModelAdapter):
    async def stream_chat(self, messages: list[GatewayMessage]) -> AsyncIterator[str]:
        payload = {
            "model": self.model_id,
            "messages": [{"role": item.role, "content": item.content} for item in messages],
            "stream": True,
        }
        async with httpx.AsyncClient(timeout=180.0) as client:
            async with client.stream("POST", f"{self.api_base}/api/chat", json=payload) as response:
                response.raise_for_status()
                async for line in response.aiter_lines():
                    try:
                        body = json.loads(line)
                    except ValueError:
                        continue
                    content = body.get("message", {}).get("content", "")
                    if content:
                        yield content
