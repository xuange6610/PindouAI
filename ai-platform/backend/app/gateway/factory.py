from .anthropic import AnthropicAdapter
from .base import ModelAdapter
from .ollama import OllamaAdapter
from .openai_compatible import OpenAICompatibleAdapter
from .gemini import GeminiAdapter


OPENAI_COMPATIBLE_PROVIDERS = {
    "openai",
    "qwen",
    "glm",
    "kimi",
    "deepseek",
    "vllm",
    "llama",
    "local",
    "openrouter",
}


def build_adapter(
    provider: str,
    *,
    api_base: str,
    api_key: str,
    model_id: str,
    headers: dict[str, str] | None = None,
) -> ModelAdapter:
    normalized = provider.strip().lower()
    adapter_type: type[ModelAdapter]
    if normalized in OPENAI_COMPATIBLE_PROVIDERS:
        adapter_type = OpenAICompatibleAdapter
    elif normalized in {"anthropic", "claude"}:
        adapter_type = AnthropicAdapter
    elif normalized == "ollama":
        adapter_type = OllamaAdapter
    elif normalized in {"google", "gemini"}:
        adapter_type = GeminiAdapter
    else:
        raise ValueError(f"Unsupported provider protocol: {provider}")
    return adapter_type(api_base=api_base, api_key=api_key, model_id=model_id, headers=headers)
