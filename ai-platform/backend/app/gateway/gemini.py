import json
from collections.abc import AsyncIterator
from urllib.parse import quote

import httpx

from .base import GatewayMessage, ModelAdapter


class GeminiAdapter(ModelAdapter):
    async def stream_chat(self, messages: list[GatewayMessage]) -> AsyncIterator[str]:
        contents = []
        for message in messages:
            if message.role == "system":
                continue
            contents.append(
                {
                    "role": "model" if message.role == "assistant" else "user",
                    "parts": [{"text": message.content}],
                }
            )
        system = "\n".join(message.content for message in messages if message.role == "system")
        payload = {
            "contents": contents,
            **({"system_instruction": {"parts": [{"text": system}]}} if system else {}),
        }
        url = (
            f"{self.api_base}/models/{quote(self.model_id, safe='')}:streamGenerateContent"
            f"?alt=sse&key={quote(self.api_key, safe='')}"
        )
        async with httpx.AsyncClient(timeout=180.0) as client:
            async with client.stream("POST", url, headers=self.headers, json=payload) as response:
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line.startswith("data:"):
                        continue
                    try:
                        body = json.loads(line[5:].strip())
                        parts = body.get("candidates", [])[0]["content"]["parts"]
                    except (ValueError, KeyError, IndexError, TypeError):
                        continue
                    for part in parts:
                        text = part.get("text", "") if isinstance(part, dict) else ""
                        if text:
                            yield text
