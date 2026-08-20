import json
from collections.abc import AsyncIterator

import httpx

from .base import GatewayMessage, ModelAdapter


class OpenAICompatibleAdapter(ModelAdapter):
    async def stream_chat(self, messages: list[GatewayMessage]) -> AsyncIterator[str]:
        if any(
            attachment
            for message in messages
            for attachment in message.attachments
            if not str(attachment.get("mime_type", "")).startswith("image/")
        ):
            async for chunk in self._stream_responses(messages):
                yield chunk
            return
        payload_messages = []
        for message in messages:
            content: str | list[dict[str, object]] = message.content
            images = [item for item in message.attachments if str(item.get("mime_type", "")).startswith("image/")]
            if images:
                content = [{"type": "text", "text": message.content}]
                content.extend(
                    {"type": "image_url", "image_url": {"url": image["data_url"]}}
                    for image in images
                    if image.get("data_url")
                )
            payload_messages.append({"role": message.role, "content": content})
        headers = {"Authorization": f"Bearer {self.api_key}", **self.headers}
        payload = {"model": self.model_id, "messages": payload_messages, "stream": True}
        async with httpx.AsyncClient(timeout=180.0) as client:
            async with client.stream(
                "POST",
                f"{self.api_base}/chat/completions",
                headers=headers,
                json=payload,
            ) as response:
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        body = json.loads(data)
                        delta = body.get("choices", [{}])[0].get("delta", {}).get("content", "")
                    except (ValueError, IndexError, AttributeError):
                        continue
                    if isinstance(delta, str) and delta:
                        yield delta

    async def _stream_responses(self, messages: list[GatewayMessage]) -> AsyncIterator[str]:
        input_messages = []
        for message in messages:
            parts: list[dict[str, object]] = [
                {
                    "type": "output_text" if message.role == "assistant" else "input_text",
                    "text": message.content,
                }
            ]
            if message.role != "assistant":
                for attachment in message.attachments:
                    data_url = attachment.get("data_url")
                    if not data_url:
                        continue
                    if str(attachment.get("mime_type", "")).startswith("image/"):
                        parts.append({"type": "input_image", "image_url": data_url})
                    else:
                        parts.append(
                            {
                                "type": "input_file",
                                "filename": attachment.get("name", "file"),
                                "file_data": data_url,
                            }
                        )
            input_messages.append({"role": message.role, "content": parts})
        headers = {"Authorization": f"Bearer {self.api_key}", **self.headers}
        payload = {"model": self.model_id, "input": input_messages, "stream": True}
        async with httpx.AsyncClient(timeout=180.0) as client:
            async with client.stream(
                "POST", f"{self.api_base}/responses", headers=headers, json=payload
            ) as response:
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        body = json.loads(data)
                    except ValueError:
                        continue
                    if body.get("type") == "response.output_text.delta":
                        delta = body.get("delta", "")
                        if isinstance(delta, str) and delta:
                            yield delta
