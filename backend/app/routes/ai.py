import asyncio
import base64
import json
from typing import Any, Literal

import httpx
from fastapi import APIRouter, Header, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from ..config import get_settings

router = APIRouter(prefix="/ai", tags=["ai"])


class AiGenerateRequest(BaseModel):
    prompt: str = Field(min_length=1, max_length=8000)
    model: str | None = None
    image_data_url: str | None = None
    temperature: float = Field(default=0.7, ge=0, le=2)


class AiGenerateResponse(BaseModel):
    model: str
    content: str
    raw: dict[str, Any] | None = None


class AiImageRequest(BaseModel):
    prompt: str = Field(min_length=1, max_length=8000)
    model: str | None = None
    size: str = Field(default="1024x1024", pattern=r"^(256|512|1024|1536)x(256|512|1024|1536)$")
    image_data_url: str | None = None


class AiImageResponse(BaseModel):
    model: str
    image_data_url: str
    raw: dict[str, Any] | None = None


class AiAttachmentRequest(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    mime_type: str = Field(min_length=1, max_length=120)
    data_url: str = Field(min_length=1, max_length=30_000_000)


class AiChatMessageRequest(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str = Field(max_length=100_000)
    attachment: AiAttachmentRequest | None = None


class AiChatRequest(BaseModel):
    model: str = Field(min_length=1, max_length=255)
    messages: list[AiChatMessageRequest] = Field(min_length=1, max_length=100)


class AiVideoRequest(BaseModel):
    prompt: str = Field(min_length=1, max_length=8000)
    model: str | None = None
    size: str = "1280x720"
    duration_seconds: int = Field(default=5, ge=1, le=60)
    image_data_url: str | None = None


class AiVideoResponse(BaseModel):
    model: str
    video_data_url: str
    raw: dict[str, Any] | None = None


def _prefer_responses_api(model: str) -> bool:
    normalized = model.strip().lower()
    return normalized.startswith(("gpt-", "o1", "o3", "o4")) or "openai" in normalized


def _provider_config(
    custom_base_url: str | None,
    custom_key: str | None,
) -> tuple[str, str]:
    settings = get_settings()
    if custom_base_url and not custom_key:
        raise HTTPException(
            status_code=400,
            detail="A custom AI provider URL requires its matching API key",
        )
    api_key = (custom_key or settings.ai_proxy_api_key).strip()
    provider_base_url = (custom_base_url or settings.ai_proxy_base_url).strip()
    if not api_key:
        raise HTTPException(status_code=503, detail="AI proxy is not configured")
    if not provider_base_url.startswith(("https://", "http://")):
        raise HTTPException(status_code=400, detail="AI provider URL is invalid")
    return provider_base_url.rstrip("/"), api_key


def _provider_error(error: httpx.HTTPStatusError) -> HTTPException:
    detail = error.response.text[:500]
    return HTTPException(
        status_code=502,
        detail=f"AI provider returned HTTP {error.response.status_code}: {detail}",
    )


@router.get("/models")
async def list_models(
    x_ai_provider_base_url: str | None = Header(default=None),
    x_ai_provider_key: str | None = Header(default=None),
) -> dict[str, Any]:
    provider_base_url, api_key = _provider_config(
        x_ai_provider_base_url,
        x_ai_provider_key,
    )
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                provider_base_url + "/models",
                headers={"Authorization": f"Bearer {api_key}"},
            )
            response.raise_for_status()
            body = response.json()
    except httpx.HTTPStatusError as error:
        raise _provider_error(error) from error
    except (httpx.HTTPError, ValueError) as error:
        raise HTTPException(status_code=504, detail="Unable to read AI model list") from error
    values = body.get("data", body.get("models", [])) if isinstance(body, dict) else body
    if not isinstance(values, list):
        raise HTTPException(status_code=502, detail="AI provider model list is invalid")
    active_model = None
    if isinstance(body, dict):
        active_model = (
            body.get("active_model")
            or body.get("current_model")
            or body.get("default_model")
        )
    if not active_model:
        active_model = get_settings().ai_proxy_model
    return {"data": values, "active_model": active_model}


@router.get("/balance")
async def get_balance(
    x_ai_provider_base_url: str | None = Header(default=None),
    x_ai_provider_key: str | None = Header(default=None),
) -> dict[str, Any]:
    """Proxy common relay balance endpoints without inventing a balance.

    Balance APIs are not standardized. A 404 tells the client that this
    provider simply does not expose one, while authentication/quota errors are
    preserved as useful diagnostics.
    """
    provider_base_url, api_key = _provider_config(
        x_ai_provider_base_url,
        x_ai_provider_key,
    )
    roots = [provider_base_url]
    if provider_base_url.endswith("/v1"):
        roots.append(provider_base_url[:-3].rstrip("/"))
    paths = (
        "/dashboard/billing/credit_grants",
        "/v1/dashboard/billing/credit_grants",
        "/balance",
        "/v1/balance",
        "/user/balance",
    )
    headers = {"Authorization": f"Bearer {api_key}"}
    async with httpx.AsyncClient(timeout=20.0) as client:
        for root in dict.fromkeys(roots):
            for path in paths:
                try:
                    response = await client.get(root + path, headers=headers)
                except httpx.HTTPError:
                    continue
                if response.status_code == 404:
                    continue
                if response.status_code in (401, 402, 403, 429):
                    raise HTTPException(
                        status_code=response.status_code,
                        detail=response.text[:500],
                    )
                if not response.is_success:
                    continue
                try:
                    body = response.json()
                except ValueError:
                    continue
                if isinstance(body, dict):
                    return body
    raise HTTPException(status_code=404, detail="Provider does not expose a balance API")


@router.post("/chat", response_model=AiGenerateResponse)
async def chat(
    request: AiChatRequest,
    x_ai_provider_base_url: str | None = Header(default=None),
    x_ai_provider_key: str | None = Header(default=None),
) -> AiGenerateResponse:
    provider_base_url, api_key = _provider_config(
        x_ai_provider_base_url,
        x_ai_provider_key,
    )
    headers = {"Authorization": f"Bearer {api_key}"}
    responses_input: list[dict[str, Any]] = []
    for message in request.messages:
        content: list[dict[str, Any]] = [
            {
                "type": "output_text" if message.role == "assistant" else "input_text",
                "text": message.content,
            }
        ]
        if message.attachment and message.role != "assistant":
            attachment = message.attachment
            if attachment.mime_type.startswith("image/"):
                content.append({"type": "input_image", "image_url": attachment.data_url})
            else:
                content.append(
                    {
                        "type": "input_file",
                        "filename": attachment.name,
                        "file_data": attachment.data_url,
                    }
                )
        responses_input.append({"role": message.role, "content": content})

    responses_payload = {"model": request.model, "input": responses_input}
    last_response: httpx.Response | None = None
    try:
        async with httpx.AsyncClient(timeout=get_settings().ai_proxy_timeout_seconds) as client:
            if _prefer_responses_api(request.model):
                response = await client.post(
                    provider_base_url + "/responses",
                    json=responses_payload,
                    headers=headers,
                )
                last_response = response
                if response.is_success:
                    body = response.json()
                    content = _responses_output_text(body)
                    if content:
                        return AiGenerateResponse(
                            model=body.get("model", request.model),
                            content=content,
                            raw=body,
                        )

            completion_messages: list[dict[str, Any]] = []
            for message in request.messages:
                attachment = message.attachment
                if not attachment or message.role == "assistant":
                    completion_messages.append(
                        {"role": message.role, "content": message.content}
                    )
                    continue
                if attachment.mime_type.startswith("image/"):
                    completion_messages.append(
                        {
                            "role": message.role,
                            "content": [
                                {"type": "text", "text": message.content},
                                {
                                    "type": "image_url",
                                    "image_url": {"url": attachment.data_url},
                                },
                            ],
                        }
                    )
                    continue
                if attachment.mime_type.startswith("text/") or attachment.mime_type == "application/json":
                    try:
                        _, encoded = attachment.data_url.split(",", 1)
                        attachment_text = base64.b64decode(encoded, validate=True).decode("utf-8")
                    except (ValueError, UnicodeDecodeError, base64.binascii.Error) as error:
                        raise HTTPException(status_code=400, detail="Text attachment data is invalid") from error
                    completion_messages.append(
                        {
                            "role": message.role,
                            "content": f"{message.content}\n\nAttachment {attachment.name}:\n{attachment_text}",
                        }
                    )
                    continue
                raise HTTPException(
                    status_code=422,
                    detail=(
                        f"Model gateway does not support {attachment.name} through Chat Completions; "
                        "select a model with Responses file input"
                    ),
                )
            completion_response = await client.post(
                provider_base_url + "/chat/completions",
                json={"model": request.model, "messages": completion_messages},
                headers=headers,
            )
            last_response = completion_response
            completion_response.raise_for_status()
            body = completion_response.json()
    except HTTPException:
        raise
    except httpx.HTTPStatusError as error:
        raise _provider_error(error) from error
    except (httpx.HTTPError, ValueError) as error:
        raise HTTPException(status_code=504, detail="AI provider request failed") from error
    choices = body.get("choices") or []
    message = choices[0].get("message", {}) if choices else {}
    content_value = message.get("content", "")
    if isinstance(content_value, list):
        content_value = "".join(
            item.get("text", "") for item in content_value if isinstance(item, dict)
        )
    if not content_value:
        status = last_response.status_code if last_response is not None else 502
        raise HTTPException(status_code=502, detail=f"AI provider returned no text (HTTP {status})")
    return AiGenerateResponse(
        model=body.get("model", request.model),
        content=str(content_value),
        raw=body,
    )


@router.post("/chat/stream")
async def chat_stream(
    request: AiChatRequest,
    x_ai_provider_base_url: str | None = Header(default=None),
    x_ai_provider_key: str | None = Header(default=None),
) -> StreamingResponse:
    """Pass through provider SSE while preserving the requested model name."""
    provider_base_url, api_key = _provider_config(
        x_ai_provider_base_url,
        x_ai_provider_key,
    )
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "text/event-stream",
    }
    responses_input: list[dict[str, Any]] = []
    completion_messages: list[dict[str, Any]] = []
    for message in request.messages:
        response_content: list[dict[str, Any]] = [
            {
                "type": "output_text" if message.role == "assistant" else "input_text",
                "text": message.content,
            }
        ]
        completion_content: Any = message.content
        if message.attachment and message.role != "assistant":
            attachment = message.attachment
            if attachment.mime_type.startswith("image/"):
                response_content.append(
                    {"type": "input_image", "image_url": attachment.data_url}
                )
                completion_content = [
                    {"type": "text", "text": message.content},
                    {
                        "type": "image_url",
                        "image_url": {"url": attachment.data_url},
                    },
                ]
            else:
                response_content.append(
                    {
                        "type": "input_file",
                        "filename": attachment.name,
                        "file_data": attachment.data_url,
                    }
                )
                try:
                    _, encoded = attachment.data_url.split(",", 1)
                    extracted = base64.b64decode(encoded, validate=True).decode("utf-8")
                    completion_content = (
                        f"{message.content}\n\nAttachment {attachment.name}:\n{extracted}"
                    )
                except (ValueError, UnicodeDecodeError, base64.binascii.Error):
                    completion_content = message.content
        responses_input.append({"role": message.role, "content": response_content})
        completion_messages.append(
            {"role": message.role, "content": completion_content}
        )

    candidates: list[tuple[str, dict[str, Any]]] = []
    if _prefer_responses_api(request.model):
        candidates.append(
            (
                provider_base_url + "/responses",
                {"model": request.model, "input": responses_input, "stream": True},
            )
        )
    candidates.append(
        (
            provider_base_url + "/chat/completions",
            {
                "model": request.model,
                "messages": completion_messages,
                "stream": True,
            },
        )
    )

    async def events():
        last_error = "AI provider streaming request failed"
        async with httpx.AsyncClient(
            timeout=get_settings().ai_proxy_timeout_seconds
        ) as client:
            for url, payload in candidates:
                try:
                    async with client.stream(
                        "POST", url, json=payload, headers=headers
                    ) as response:
                        if not response.is_success:
                            detail = (await response.aread()).decode(
                                "utf-8", errors="replace"
                            )[:500]
                            last_error = (
                                f"Provider returned HTTP {response.status_code}: {detail}"
                            )
                            continue
                        content_type = response.headers.get("content-type", "")
                        if "text/event-stream" in content_type:
                            async for chunk in response.aiter_bytes():
                                yield chunk
                            return
                        raw = await response.aread()
                        body = json.loads(raw)
                        text = _responses_output_text(body)
                        if not text:
                            choices = body.get("choices") or []
                            value = (
                                choices[0].get("message", {}).get("content", "")
                                if choices
                                else ""
                            )
                            text = str(value)
                        if text:
                            event = {
                                "model": body.get("model", request.model),
                                "delta": text,
                                "usage": body.get("usage", {}),
                            }
                            yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n".encode()
                            yield b"data: [DONE]\n\n"
                            return
                except (httpx.HTTPError, ValueError) as error:
                    last_error = str(error)
        yield (
            "data: "
            + json.dumps({"error": {"message": last_error}}, ensure_ascii=False)
            + "\n\n"
        ).encode()

    return StreamingResponse(
        events(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


def _responses_output_text(body: dict[str, Any]) -> str:
    direct = body.get("output_text")
    if isinstance(direct, str) and direct:
        return direct
    values: list[str] = []
    for output in body.get("output") or []:
        if not isinstance(output, dict):
            continue
        for item in output.get("content") or []:
            if isinstance(item, dict) and isinstance(item.get("text"), str):
                values.append(item["text"])
    return "".join(values)


@router.post("/generate", response_model=AiGenerateResponse)
async def generate(
    request: AiGenerateRequest,
    x_ai_provider_base_url: str | None = Header(default=None),
    x_ai_provider_key: str | None = Header(default=None),
) -> AiGenerateResponse:
    settings = get_settings()
    if x_ai_provider_base_url and not x_ai_provider_key:
        raise HTTPException(
            status_code=400,
            detail="A custom AI provider URL requires its matching API key",
        )
    api_key = (x_ai_provider_key or settings.ai_proxy_api_key).strip()
    provider_base_url = (x_ai_provider_base_url or settings.ai_proxy_base_url).strip()
    if not api_key:
        raise HTTPException(status_code=503, detail="AI proxy is not configured")
    if not provider_base_url.startswith(("https://", "http://")):
        raise HTTPException(status_code=400, detail="AI provider URL is invalid")
    content: list[dict[str, Any]] = [{"type": "text", "text": request.prompt}]
    if request.image_data_url:
        content.append({"type": "image_url", "image_url": {"url": request.image_data_url}})
    payload = {
        "model": request.model or settings.ai_proxy_model,
        "messages": [{"role": "user", "content": content}],
    }
    if not payload["model"].startswith("gpt-5"):
        payload["temperature"] = request.temperature
    else:
        payload["reasoning_effort"] = "none"
    url = provider_base_url.rstrip("/") + "/chat/completions"
    headers = {"Authorization": f"Bearer {api_key}"}
    try:
        async with httpx.AsyncClient(timeout=settings.ai_proxy_timeout_seconds) as client:
            response = await client.post(url, json=payload, headers=headers)
            response.raise_for_status()
            body = response.json()
    except httpx.HTTPStatusError as error:
        provider_detail = error.response.text[:500]
        raise HTTPException(
            status_code=502,
            detail=f"AI provider returned HTTP {error.response.status_code}: {provider_detail}",
        ) from error
    except httpx.HTTPError as error:
        raise HTTPException(status_code=504, detail="AI provider timeout") from error
    choices = body.get("choices") or []
    message = choices[0].get("message", {}) if choices else {}
    content_value = message.get("content", "")
    if isinstance(content_value, list):
        content_value = "".join(
            item.get("text", "") for item in content_value if isinstance(item, dict)
        )
    return AiGenerateResponse(
        model=body.get("model", payload["model"]),
        content=str(content_value),
        raw=body,
    )


@router.post("/image", response_model=AiImageResponse)
async def generate_image(
    request: AiImageRequest,
    x_ai_provider_base_url: str | None = Header(default=None),
    x_ai_provider_key: str | None = Header(default=None),
) -> AiImageResponse:
    settings = get_settings()
    if x_ai_provider_base_url and not x_ai_provider_key:
        raise HTTPException(
            status_code=400,
            detail="A custom AI provider URL requires its matching API key",
        )
    api_key = (x_ai_provider_key or settings.ai_proxy_api_key).strip()
    provider_base_url = (x_ai_provider_base_url or settings.ai_proxy_base_url).strip()
    if not api_key:
        raise HTTPException(status_code=503, detail="AI proxy is not configured")
    if not provider_base_url.startswith(("https://", "http://")):
        raise HTTPException(status_code=400, detail="AI provider URL is invalid")
    payload = {
        "model": request.model or settings.ai_proxy_image_model,
        "prompt": request.prompt,
        "size": request.size,
        "n": 1,
    }
    url = provider_base_url.rstrip("/") + (
        "/images/edits" if request.image_data_url else "/images/generations"
    )
    headers = {"Authorization": f"Bearer {api_key}"}
    body: dict[str, Any] = {}
    image_error = "图片模型没有返回图片数据"
    try:
        async with httpx.AsyncClient(timeout=settings.ai_proxy_timeout_seconds) as client:
            if request.image_data_url:
                try:
                    _, encoded = request.image_data_url.split(",", 1)
                    image_bytes = base64.b64decode(encoded, validate=True)
                except (ValueError, base64.binascii.Error) as error:
                    raise HTTPException(status_code=400, detail="参考图数据格式无效") from error
                response = await client.post(
                    url,
                    # Multipart form values are encoded as strings. Several
                    # strict Images relays reject `n="1"`; omitting it keeps
                    # the provider default of one edited image.
                    data={key: value for key, value in payload.items() if key != "n"},
                    files={"image": ("reference.png", image_bytes, "image/png")},
                    headers=headers,
                )
            else:
                response = await client.post(url, json=payload, headers=headers)
            response.raise_for_status()
            body = response.json()
    except httpx.HTTPStatusError as error:
        provider_detail = error.response.text[:500]
        image_error = (
            f"Images API HTTP {error.response.status_code}: {provider_detail}"
        )
    except httpx.HTTPError as error:
        image_error = f"Images API 调用失败：{error}"
    images = body.get("data") or []
    first = images[0] if images else {}
    if not isinstance(first, dict):
        raise HTTPException(status_code=502, detail="图片模型返回格式无效")
    encoded = first.get("b64_json")
    if isinstance(encoded, str) and encoded:
        return AiImageResponse(
            model=body.get("model", payload["model"]),
            image_data_url=f"data:image/png;base64,{encoded}",
            raw=body,
        )
    image_url = first.get("url")
    if isinstance(image_url, str) and image_url.startswith(("https://", "http://")):
        try:
            async with httpx.AsyncClient(timeout=settings.ai_proxy_timeout_seconds) as client:
                image_response = await client.get(image_url)
                image_response.raise_for_status()
                encoded = base64.b64encode(image_response.content).decode("ascii")
        except httpx.HTTPError as error:
            raise HTTPException(status_code=502, detail="无法下载图片模型返回的图片") from error
        return AiImageResponse(
            model=body.get("model", payload["model"]),
            image_data_url=f"data:image/png;base64,{encoded}",
            raw=body,
        )
    responses_payload = {
        "model": payload["model"],
        "input": [
            {
                "role": "user",
                "content": [
                    {"type": "input_text", "text": request.prompt},
                    *(
                        [
                            {
                                "type": "input_image",
                                "image_url": request.image_data_url,
                            }
                        ]
                        if request.image_data_url
                        else []
                    ),
                ],
            }
        ],
        "tools": [
            {
                "type": "image_generation",
                "size": request.size,
            }
        ],
    }
    try:
        async with httpx.AsyncClient(timeout=settings.ai_proxy_timeout_seconds) as client:
            response = await client.post(
                provider_base_url.rstrip("/") + "/responses",
                json=responses_payload,
                headers=headers,
            )
            response.raise_for_status()
            responses_body = response.json()
        for item in responses_body.get("output") or []:
            if not isinstance(item, dict) or item.get("type") != "image_generation_call":
                continue
            encoded = item.get("result")
            if isinstance(encoded, str) and encoded:
                return AiImageResponse(
                    model=responses_body.get("model", payload["model"]),
                    image_data_url=f"data:image/png;base64,{encoded}",
                    raw=responses_body,
                )
    except (httpx.HTTPError, ValueError) as error:
        image_error += f"；Responses 生图失败：{error}"
    raise HTTPException(
        status_code=502,
        detail=(
            f"图片模型无法生成图片：{image_error}。"
            "已尝试 Images API 和 Responses image_generation，请检查中转的模型媒体路由。"
        ),
    )


@router.post("/video", response_model=AiVideoResponse)
async def generate_video(
    request: AiVideoRequest,
    x_ai_provider_base_url: str | None = Header(default=None),
    x_ai_provider_key: str | None = Header(default=None),
) -> AiVideoResponse:
    provider_base_url, api_key = _provider_config(
        x_ai_provider_base_url,
        x_ai_provider_key,
    )
    selected_model = request.model or get_settings().ai_proxy_model
    legacy_payload = {
        "model": selected_model,
        "prompt": request.prompt,
        "size": request.size,
        "duration": request.duration_seconds,
        "duration_seconds": request.duration_seconds,
        "seconds": str(request.duration_seconds),
    }
    if request.image_data_url:
        legacy_payload["image_data_url"] = request.image_data_url
    openai_payload = {
        "model": selected_model,
        "prompt": request.prompt,
        "size": request.size,
        "seconds": str(request.duration_seconds),
    }
    headers = {"Authorization": f"Bearer {api_key}"}
    last_error = "no compatible video endpoint"

    def candidate_from(body: dict[str, Any]) -> dict[str, Any]:
        candidate = body
        for _ in range(5):
            nested: Any = None
            for key in ("data", "output", "result", "video"):
                value = candidate.get(key)
                if isinstance(value, list) and value and isinstance(value[0], dict):
                    nested = value[0]
                    break
                if isinstance(value, dict):
                    nested = value
                    break
            if not isinstance(nested, dict):
                break
            candidate = nested
        return candidate

    def job_id_from(body: dict[str, Any]) -> str | None:
        for candidate in (
            body,
            body.get("data"),
            body.get("output"),
            body.get("result"),
        ):
            if not isinstance(candidate, dict):
                continue
            for key in ("id", "task_id", "taskId", "request_id"):
                value = candidate.get(key)
                if value:
                    return str(value)
        return None

    async with httpx.AsyncClient(
        timeout=max(get_settings().ai_proxy_timeout_seconds, 300)
    ) as client:
        async def parse_video(
            body: dict[str, Any],
        ) -> AiVideoResponse | None:
            candidate = candidate_from(body)
            encoded = (
                candidate.get("b64_video")
                or candidate.get("video_base64")
                or candidate.get("b64_json")
                or candidate.get("base64")
            )
            if isinstance(encoded, str) and encoded:
                return AiVideoResponse(
                    model=body.get("model", selected_model),
                    video_data_url=f"data:video/mp4;base64,{encoded}",
                    raw=body,
                )
            data_url = candidate.get("video_data_url") or candidate.get("data_url")
            if isinstance(data_url, str) and data_url.startswith("data:video/"):
                return AiVideoResponse(
                    model=body.get("model", selected_model),
                    video_data_url=data_url,
                    raw=body,
                )
            video_url = (
                candidate.get("video_url")
                or candidate.get("url")
                or candidate.get("download_url")
                or candidate.get("content_url")
            )
            if isinstance(video_url, str) and video_url.startswith(("https://", "http://")):
                video_response = await client.get(video_url)
                video_response.raise_for_status()
                mime_type = video_response.headers.get("content-type", "video/mp4").split(";", 1)[0]
                encoded_bytes = base64.b64encode(video_response.content).decode("ascii")
                return AiVideoResponse(
                    model=body.get("model", selected_model),
                    video_data_url=f"data:{mime_type};base64,{encoded_bytes}",
                    raw=body,
                )
            return None

        async def poll_video(job_id: str) -> AiVideoResponse | None:
            status_paths = (
                f"/videos/{job_id}",
                f"/video/generations/{job_id}",
                f"/tasks/{job_id}",
            )
            content_paths = (
                f"/videos/{job_id}/content",
                f"/videos/{job_id}/download",
                f"/tasks/{job_id}/content",
            )
            for attempt in range(60):
                for status_path in status_paths:
                    status_response = await client.get(
                        provider_base_url + status_path,
                        headers=headers,
                    )
                    if not status_response.is_success:
                        continue
                    content_type = status_response.headers.get("content-type", "")
                    if content_type.startswith("video/"):
                        encoded_bytes = base64.b64encode(status_response.content).decode("ascii")
                        return AiVideoResponse(
                            model=selected_model,
                            video_data_url=f"data:{content_type.split(';', 1)[0]};base64,{encoded_bytes}",
                        )
                    status_body = status_response.json()
                    immediate = await parse_video(status_body)
                    if immediate is not None:
                        return immediate
                    status = str(status_body.get("status", "")).lower()
                    if status in {"failed", "error", "cancelled", "canceled"}:
                        raise HTTPException(
                            status_code=502,
                            detail=f"视频生成任务失败：{status_body}",
                        )
                    if status in {"completed", "succeeded", "success", "done"}:
                        for content_path in content_paths:
                            content_response = await client.get(
                                provider_base_url + content_path,
                                headers=headers,
                            )
                            if not content_response.is_success:
                                continue
                            content_type = content_response.headers.get(
                                "content-type", "video/mp4"
                            ).split(";", 1)[0]
                            if content_type.startswith("video/") or content_type == "application/octet-stream":
                                encoded_bytes = base64.b64encode(content_response.content).decode("ascii")
                                return AiVideoResponse(
                                    model=selected_model,
                                    video_data_url=f"data:{content_type if content_type.startswith('video/') else 'video/mp4'};base64,{encoded_bytes}",
                                )
                if attempt < 59:
                    await asyncio.sleep(5)
            return None

        endpoint_suffixes = (
            ("/videos/generations", "/videos", "/video/generations")
            if "ciyuan.fast" in provider_base_url.lower()
            else ("/videos", "/videos/generations", "/video/generations")
        )
        for suffix in endpoint_suffixes:
            try:
                payload = openai_payload if suffix == "/videos" else legacy_payload
                response = await client.post(
                    provider_base_url + suffix,
                    json=payload,
                    headers=headers,
                )
                if not response.is_success:
                    failure = f"{suffix}: HTTP {response.status_code} {response.text[:300]}"
                    # A relay may expose only one of the legacy paths. Keep a
                    # real model/permission error instead of replacing it with
                    # a later 404 from an unsupported fallback path.
                    prior_is_404 = "HTTP 404" in last_error
                    if response.status_code != 404 or prior_is_404 or last_error == "no compatible video endpoint":
                        last_error = failure
                    continue
                if response.headers.get("content-type", "").startswith("video/"):
                    encoded = base64.b64encode(response.content).decode("ascii")
                    mime_type = response.headers.get("content-type", "video/mp4").split(";", 1)[0]
                    return AiVideoResponse(
                        model=selected_model,
                        video_data_url=f"data:{mime_type};base64,{encoded}",
                    )
                body = response.json()
                immediate = await parse_video(body)
                if immediate is not None:
                    return immediate
                job_id = job_id_from(body)
                if job_id:
                    completed = await poll_video(job_id)
                    if completed is not None:
                        return completed
                last_error = f"{suffix}: provider returned no video data"
            except (httpx.HTTPError, ValueError) as error:
                last_error = f"{suffix}: {error}"
    raise HTTPException(
        status_code=502,
        detail=(
            f"视频模型调用失败：{last_error}. "
            f"已携带模型 {selected_model} 尝试标准视频端点，请确认中转已开放该模型的视频能力。"
        ),
    )
