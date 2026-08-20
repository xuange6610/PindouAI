import json
from collections.abc import AsyncIterator

import httpx

from .base import GatewayMessage, ModelAdapter


class AnthropicAdapter(ModelAdapter):
    async def stream_chat(self, messages: list[GatewayMessage]) -> AsyncIterator[str]:
        system = "\n".join(message.content for message in messages if message.role == "system")
        payload_messages = [
            {"role": message.role, "content": message.content}
            for message in messages
            if message.role in {"user", "assistant"}
        ]
        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            **self.headers,
        }
        payload = {
            "model": self.model_id,
            "messages": payload_messages,
            "max_tokens": 8192,
            "stream": True,
            **({"system": system} if system else {}),
        }
        async with httpx.AsyncClient(timeout=180.0) as client:
            async with client.stream(
                "POST", f"{self.api_base}/messages", headers=headers, json=payload
            ) as response:
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line.startswith("data:"):
                        continue
                    try:
                        body = json.loads(line[5:].strip())
                    except ValueError:
                        continue
                    delta = body.get("delta", {}).get("text", "")
                    if delta:
                        yield delta
