import asyncio
import base64
import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from fastapi import HTTPException

from backend.app.routes.ai import (
    AiChatMessageRequest,
    AiChatRequest,
    AiGenerateRequest,
    AiImageRequest,
    AiVideoRequest,
    chat,
    generate,
    generate_image,
    generate_video,
    list_models,
)


class _ProviderHandler(BaseHTTPRequestHandler):
    request_paths: list[str] = []
    request_bodies: list[bytes] = []

    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer test-provider-key":
            self.send_response(401)
            self.end_headers()
            return
        response = json.dumps(
            {"data": [{"id": "gpt-test"}, {"id": "qwen-test"}]}
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def do_POST(self):
        self.__class__.request_paths.append(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(length)
        self.__class__.request_bodies.append(raw_body)
        if self.headers.get("Authorization") != "Bearer test-provider-key":
            self.send_response(401)
            self.end_headers()
            return
        if self.path.endswith("/images/edits"):
            response_payload = {
                "model": "mock-edit-model",
                "data": [
                    {
                        "b64_json": base64.b64encode(
                            b"\x89PNG\r\n\x1a\nmock-edit"
                        ).decode()
                    }
                ],
            }
            response = json.dumps(response_payload).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)
            return
        payload = json.loads(raw_body)
        if self.path.endswith("/images/generations"):
            response_payload = {
                "model": payload["model"],
                "data": [
                    {
                        "b64_json": base64.b64encode(
                            b"\x89PNG\r\n\x1a\nmock-image"
                        ).decode()
                    }
                ],
            }
        elif self.path.endswith("/videos/generations"):
            response_payload = {
                "model": payload["model"],
                "data": [
                    {
                        "b64_video": base64.b64encode(
                            b"\x00\x00\x00\x14ftyp"
                        ).decode()
                    }
                ],
            }
        else:
            response_payload = {
                "model": payload["model"],
                "choices": [{"message": {"content": "连接成功"}}],
            }
        response = json.dumps(response_payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, format, *args):
        return


class AiRouteTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), _ProviderHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def setUp(self):
        _ProviderHandler.request_paths.clear()
        _ProviderHandler.request_bodies.clear()

    def test_custom_provider_key_and_url_are_forwarded(self):
        result = asyncio.run(
            generate(
                AiGenerateRequest(prompt="ping"),
                f"http://127.0.0.1:{self.server.server_port}/v1",
                "test-provider-key",
            )
        )
        self.assertEqual(result.content, "连接成功")
        self.assertEqual(result.model, "gpt-5.6-sol")

    def test_custom_provider_url_cannot_receive_backend_default_key(self):
        with self.assertRaises(HTTPException) as caught:
            asyncio.run(
                generate(
                    AiGenerateRequest(prompt="ping"),
                    "https://untrusted.example/v1",
                    None,
                )
            )
        self.assertEqual(caught.exception.status_code, 400)

    def test_image_generation_forwards_custom_provider_and_returns_base64(self):
        result = asyncio.run(
            generate_image(
                AiImageRequest(prompt="pixel art", model="mock-image-model"),
                f"http://127.0.0.1:{self.server.server_port}/v1",
                "test-provider-key",
            )
        )
        self.assertEqual(result.model, "mock-image-model")
        self.assertTrue(result.image_data_url.startswith("data:image/png;base64,"))

    def test_image_edit_multipart_omits_string_n_field(self):
        result = asyncio.run(
            generate_image(
                AiImageRequest(
                    prompt="remove background",
                    model="mock-edit-model",
                    image_data_url="data:image/png;base64,"
                    + base64.b64encode(b"source-image").decode(),
                ),
                f"http://127.0.0.1:{self.server.server_port}/v1",
                "test-provider-key",
            )
        )
        self.assertEqual(result.model, "mock-edit-model")
        multipart = _ProviderHandler.request_bodies[-1]
        self.assertIn(b'name="model"', multipart)
        self.assertNotIn(b'name="n"', multipart)

    def test_model_list_is_forwarded_without_exposing_key(self):
        result = asyncio.run(
            list_models(
                f"http://127.0.0.1:{self.server.server_port}/v1",
                "test-provider-key",
            )
        )
        self.assertEqual([item["id"] for item in result["data"]], ["gpt-test", "qwen-test"])

    def test_video_generation_forwards_any_selected_model(self):
        result = asyncio.run(
            generate_video(
                AiVideoRequest(prompt="pixel animation", model="glm-5.2"),
                f"http://127.0.0.1:{self.server.server_port}/v1",
                "test-provider-key",
            )
        )
        self.assertEqual(result.model, "glm-5.2")
        self.assertTrue(result.video_data_url.startswith("data:video/mp4;base64,"))
        self.assertEqual(
            _ProviderHandler.request_paths,
            ["/v1/videos", "/v1/videos/generations"],
        )

    def test_multi_turn_chat_falls_back_to_chat_completions(self):
        result = asyncio.run(
            chat(
                AiChatRequest(
                    model="gpt-test",
                    messages=[
                        AiChatMessageRequest(role="user", content="第一问"),
                        AiChatMessageRequest(role="assistant", content="第一答"),
                        AiChatMessageRequest(role="user", content="继续"),
                    ],
                ),
                f"http://127.0.0.1:{self.server.server_port}/v1",
                "test-provider-key",
            )
        )
        self.assertEqual(result.content, "连接成功")
        self.assertEqual(result.model, "gpt-test")

    def test_non_openai_model_uses_chat_completions_without_responses_probe(self):
        result = asyncio.run(
            chat(
                AiChatRequest(
                    model="qwen-max",
                    messages=[AiChatMessageRequest(role="user", content="模型检查")],
                ),
                f"http://127.0.0.1:{self.server.server_port}/v1",
                "test-provider-key",
            )
        )
        self.assertEqual(result.model, "qwen-max")
        self.assertEqual(_ProviderHandler.request_paths, ["/v1/chat/completions"])


if __name__ == "__main__":
    unittest.main()
