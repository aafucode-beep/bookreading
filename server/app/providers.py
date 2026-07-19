from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import math
import struct
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

import httpx

from .config import Settings


class ProviderError(RuntimeError):
    pass


@dataclass(slots=True)
class ProviderResult:
    data: dict[str, Any]
    provider: str
    model: str
    request_id: str = ""


@dataclass(slots=True)
class AudioResult:
    content: bytes
    mime_type: str
    provider: str
    model: str
    request_id: str = ""


class AIProvider(Protocol):
    name: str

    async def analyze_page(self, image_path: Path, page_number: int) -> ProviderResult: ...
    async def synthesize_book(self, pages: list[dict[str, Any]]) -> ProviderResult: ...
    async def synthesize_speech(self, text: str, language: str) -> AudioResult: ...


class MockProvider:
    name = "mock"

    async def analyze_page(self, image_path: Path, page_number: int) -> ProviderResult:
        language = "zh" if page_number % 2 else "en"
        original = f"第{page_number}页：小雪狐沿着极光寻找勇气。" if language == "zh" else f"Page {page_number}: The little snow fox follows the aurora."
        return ProviderResult(
            data={
                "language": language,
                "original_blocks": [{"language": language, "text": original}],
                "original_text": original,
                "zh_text": f"第{page_number}页：小雪狐沿着极光寻找勇气。",
                "en_text": f"Page {page_number}: The little snow fox follows the aurora.",
                "explanation": "勇气不是不害怕，而是害怕时也愿意向前一步。",
                "question": "如果你是小雪狐，你会带什么去冒险？",
            },
            provider=self.name,
            model="deterministic-fixture",
        )

    async def synthesize_book(self, pages: list[dict[str, Any]]) -> ProviderResult:
        issues = [] if pages else ["没有可分析的正文页"]
        return ProviderResult(
            data={
                "title": "极光下的勇气",
                "summary": "一只小雪狐踏上寻找极光的旅程，在朋友的陪伴中学会面对害怕。",
                "completeness_status": "likely_complete" if pages else "unknown",
                "issues": issues,
            },
            provider=self.name,
            model="deterministic-fixture",
        )

    async def synthesize_speech(self, text: str, language: str) -> AudioResult:
        sample_rate = 16_000
        duration = min(2.0, max(0.35, len(text) * 0.035))
        frames = int(sample_rate * duration)
        frequency = 440 if language == "zh" else 523
        buffer = __import__("io").BytesIO()
        with wave.open(buffer, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(sample_rate)
            samples = bytearray()
            for index in range(frames):
                envelope = min(1.0, index / 800, (frames - index) / 800)
                value = int(2500 * envelope * math.sin(2 * math.pi * frequency * index / sample_rate))
                samples.extend(struct.pack("<h", value))
            wav.writeframes(bytes(samples))
        return AudioResult(buffer.getvalue(), "audio/wav", self.name, "fixture-tone")


def _json_object(text: str) -> dict[str, Any]:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1].rsplit("```", 1)[0]
    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ProviderError("模型未返回有效 JSON") from exc
    if not isinstance(value, dict):
        raise ProviderError("模型返回结构不是对象")
    return value


PAGE_PROMPT = """你是4岁儿童绘本分析助手。识别图片中的中英文文字并理解画面，只输出 JSON：
{"language":"zh|en|bilingual|unknown","original_blocks":[{"language":"zh|en","text":""}],"original_text":"","zh_text":"","en_text":"","explanation":"一句儿童化简释","question":"一个简单开放问题"}。
忠实保留原文；翻译自然、简短；不要添加图片中没有的情节。"""


BOOK_PROMPT = """根据逐页结构化内容判断故事连续性。只输出 JSON：
{"title":"","summary":"不超过120字","completeness_status":"likely_complete|needs_review|unknown","issues":["具体证据"]}。
完整性只是辅助判断；页码缺失时根据叙事连续性判断，不得声称绝对完整。输入："""


class OpenAIProvider:
    name = "openai"

    def __init__(self, settings: Settings):
        self.settings = settings
        if not settings.openai_api_key or not settings.openai_vision_model:
            raise ProviderError("OpenAI API key 或视觉模型未配置")

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.settings.openai_api_key}", "Content-Type": "application/json"}

    async def _responses(self, content: list[dict[str, Any]]) -> tuple[dict, str]:
        payload = {
            "model": self.settings.openai_vision_model,
            "input": [{"role": "user", "content": content}],
        }
        async with httpx.AsyncClient(timeout=self.settings.provider_timeout_seconds) as client:
            response = await client.post(f"{self.settings.openai_base_url.rstrip('/')}/responses", headers=self.headers, json=payload)
        if response.status_code >= 400:
            raise ProviderError(f"OpenAI {response.status_code}: {response.text[:300]}")
        body = response.json()
        text = body.get("output_text")
        if not text:
            parts = []
            for item in body.get("output", []):
                for part in item.get("content", []):
                    if part.get("type") == "output_text":
                        parts.append(part.get("text", ""))
            text = "".join(parts)
        return _json_object(text or ""), response.headers.get("x-request-id", "")

    async def analyze_page(self, image_path: Path, page_number: int) -> ProviderResult:
        mime = "image/webp" if image_path.suffix.lower() == ".webp" else "image/jpeg"
        encoded = base64.b64encode(image_path.read_bytes()).decode()
        data, request_id = await self._responses([
            {"type": "input_text", "text": f"{PAGE_PROMPT}\n这是第 {page_number} 页。"},
            {"type": "input_image", "image_url": f"data:{mime};base64,{encoded}"},
        ])
        return ProviderResult(data, self.name, self.settings.openai_vision_model, request_id)

    async def synthesize_book(self, pages: list[dict[str, Any]]) -> ProviderResult:
        data, request_id = await self._responses([
            {"type": "input_text", "text": BOOK_PROMPT + json.dumps(pages, ensure_ascii=False)}
        ])
        return ProviderResult(data, self.name, self.settings.openai_vision_model, request_id)

    async def synthesize_speech(self, text: str, language: str) -> AudioResult:
        payload = {
            "model": self.settings.openai_tts_model,
            "voice": self.settings.openai_voice,
            "input": text,
            "response_format": "mp3",
            "instructions": "Speak warmly, clearly, and gently for a four-year-old child.",
        }
        async with httpx.AsyncClient(timeout=self.settings.provider_timeout_seconds) as client:
            response = await client.post(f"{self.settings.openai_base_url.rstrip('/')}/audio/speech", headers=self.headers, json=payload)
        if response.status_code >= 400:
            raise ProviderError(f"OpenAI TTS {response.status_code}: {response.text[:300]}")
        return AudioResult(response.content, "audio/mpeg", self.name, self.settings.openai_tts_model, response.headers.get("x-request-id", ""))


class MiniMaxProvider:
    name = "minimax"

    def __init__(self, settings: Settings):
        self.settings = settings
        if not settings.minimax_api_key or not settings.minimax_model:
            raise ProviderError("MiniMax Token Plan key 或模型未配置")

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.settings.minimax_api_key}", "Content-Type": "application/json"}

    async def _chat_json(self, prompt: str) -> tuple[dict[str, Any], str]:
        payload = {
            "model": self.settings.minimax_model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.2,
        }
        async with httpx.AsyncClient(timeout=self.settings.provider_timeout_seconds) as client:
            response = await client.post(self.settings.minimax_chat_url, headers=self.headers, json=payload)
        if response.status_code >= 400:
            raise ProviderError(f"MiniMax {response.status_code}: {response.text[:300]}")
        body = response.json()
        text = body["choices"][0]["message"]["content"]
        return _json_object(text), response.headers.get("trace-id", "")

    async def _mcp_image(self, image_path: Path, prompt: str) -> str:
        env = {**__import__("os").environ, "MINIMAX_API_KEY": self.settings.minimax_api_key, "MINIMAX_API_HOST": "https://api.minimaxi.com"}
        args = [self.settings.minimax_mcp_command, *[item for item in self.settings.minimax_mcp_args.split(",") if item]]
        process = await asyncio.create_subprocess_exec(*args, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, env=env)
        assert process.stdin and process.stdout

        async def request(identifier: int, method: str, params: dict) -> dict:
            payload = json.dumps({"jsonrpc": "2.0", "id": identifier, "method": method, "params": params}, separators=(",", ":")).encode()
            process.stdin.write(payload + b"\n")
            await process.stdin.drain()
            while True:
                line = await asyncio.wait_for(process.stdout.readline(), self.settings.provider_timeout_seconds)
                if not line:
                    raise ProviderError("MiniMax MCP 进程提前退出")
                try:
                    response = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if response.get("id") == identifier:
                    return response

        try:
            await request(1, "initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "brave-growth", "version": "0.1.0"}})
            notification = json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}, separators=(",", ":")).encode()
            process.stdin.write(notification + b"\n")
            await process.stdin.drain()
            response = await request(2, "tools/call", {"name": "understand_image", "arguments": {"prompt": prompt, "image_url": str(image_path.resolve())}})
            if "error" in response:
                raise ProviderError(str(response["error"]))
            content = response.get("result", {}).get("content", [])
            return "\n".join(item.get("text", "") for item in content if item.get("type") == "text")
        finally:
            process.terminate()
            await process.wait()

    async def analyze_page(self, image_path: Path, page_number: int) -> ProviderResult:
        raw = await self._mcp_image(image_path, f"{PAGE_PROMPT}\n这是第 {page_number} 页。")
        return ProviderResult(_json_object(raw), self.name, "token-plan-understand_image")

    async def synthesize_book(self, pages: list[dict[str, Any]]) -> ProviderResult:
        data, request_id = await self._chat_json(BOOK_PROMPT + json.dumps(pages, ensure_ascii=False))
        return ProviderResult(data, self.name, self.settings.minimax_model, request_id)

    async def synthesize_speech(self, text: str, language: str) -> AudioResult:
        payload = {"model": "speech-02-hd", "text": text, "stream": False, "voice_setting": {"voice_id": self.settings.minimax_voice_id, "speed": 0.92, "vol": 1.0, "pitch": 0}, "audio_setting": {"sample_rate": 32000, "bitrate": 128000, "format": "mp3", "channel": 1}}
        async with httpx.AsyncClient(timeout=self.settings.provider_timeout_seconds) as client:
            response = await client.post(self.settings.minimax_tts_url, headers=self.headers, json=payload)
        if response.status_code >= 400:
            raise ProviderError(f"MiniMax TTS {response.status_code}: {response.text[:300]}")
        body = response.json()
        audio_hex = body.get("data", {}).get("audio", "")
        if not audio_hex:
            raise ProviderError(f"MiniMax TTS 未返回音频: {response.text[:300]}")
        return AudioResult(bytes.fromhex(audio_hex), "audio/mpeg", self.name, payload["model"], response.headers.get("trace-id", ""))


class ProviderRouter:
    def __init__(self, settings: Settings, preferred: str | None = None):
        self.settings = settings
        self.preferred = preferred or settings.preferred_provider

    def providers(self) -> list[AIProvider]:
        if self.settings.ai_mode == "mock":
            return [MockProvider()]
        ordered = [self.preferred, "openai" if self.preferred == "minimax" else "minimax"]
        result: list[AIProvider] = []
        for name in ordered:
            try:
                result.append(MiniMaxProvider(self.settings) if name == "minimax" else OpenAIProvider(self.settings))
            except ProviderError:
                continue
        if not result:
            raise ProviderError("没有可用的 AI 供应商，请检查服务端密钥和模型配置")
        return result

    async def call(self, operation: str, *args) -> tuple[ProviderResult | AudioResult, list[tuple[str, str]]]:
        failures: list[tuple[str, str]] = []
        for provider in self.providers():
            try:
                method = getattr(provider, operation)
                result = await method(*args)
                return result, failures
            except Exception as exc:  # provider boundary deliberately catches transport/schema failures
                failures.append((provider.name, str(exc)))
        raise ProviderError("；".join(f"{name}: {error}" for name, error in failures))


def content_sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()
