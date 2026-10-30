"""
BugNarrator Local Transcription Server

OpenAI-compatible /v1/audio/transcriptions endpoint powered by parakeet-mlx on
macOS and by onnx-asr (ONNX Runtime, CPU) everywhere else. Designed to be a
drop-in replacement for api.openai.com when BugNarrator is configured with the
Local (Parakeet) provider. The HTTP protocol, model aliases, chunking, and the
failure message are identical on every platform; only the inference backend
differs (docs/architecture/windows-local-transcription.md).

Usage:
    python server.py [--port 8422] [--model mlx-community/parakeet-tdt-0.6b-v3]

The server loads the model lazily on first request and keeps it warm for
subsequent transcriptions.
"""

import argparse
import asyncio
import contextlib
from concurrent.futures import ThreadPoolExecutor
import hmac
import logging
import os
import platform
import secrets
import signal
import subprocess
import sys
import tempfile
import struct
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import uvicorn
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("bugnarrator-transcription")

app = FastAPI(
    title="BugNarrator Local Transcription Server",
    # FastAPI registers the interactive documentation and the schema it
    # renders as plain routes that no dependency covers, so they answer
    # without the bearer token. Nothing a client of this server needs lives
    # in them, so they are switched off rather than left open.
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)

_model = None
_model_name = None
_canonical_model_name = "mlx-community/parakeet-tdt-0.6b-v3"
_model_aliases = {
    "parakeet-tdt-0.6b-v3",
    "parakeet",
    "whisper-1",
}
_default_model_name = _canonical_model_name

# Inference backend: MLX exists only on Apple Silicon; the same NVIDIA weights run through
# ONNX Runtime elsewhere. The request-facing model id stays the MLX name on every platform
# so aliases and settings never differ; the ONNX backend maps it at load time.
def _select_backend() -> str:
    # Intel Macs have no MLX and take the ONNX path like Windows.
    return "mlx" if sys.platform == "darwin" and platform.machine() == "arm64" else "onnx"


_backend = _select_backend()
_onnx_canonical_model_name = "nemo-parakeet-tdt-0.6b-v3"
_onnx_model_names = {
    _canonical_model_name: _onnx_canonical_model_name,
    "nvidia/parakeet-tdt-0.6b-v3": _onnx_canonical_model_name,
    "parakeet-tdt-0.6b-v3": _onnx_canonical_model_name,
}
_onnx_quantization = os.environ.get("BUGNARRATOR_ONNX_QUANTIZATION") or None
_inference_executor = ThreadPoolExecutor(
    max_workers=1,
    thread_name_prefix="bugnarrator-parakeet",
)
_chunk_duration_seconds = 120
_upload_piece_bytes = 1024 * 1024
_transcription_failure_message = (
    "Local transcription failed. Check the local transcription server logs for details."
)

# The server is reachable by every process on the machine, so every route
# requires a bearer token that only the desktop app knows (#1270). The token
# lives in a per-user file so an app that started the server and an app that
# found one already running agree on it.
TOKEN_FILE_NAME = "bugnarrator-transcription.token"
TOKEN_ENVIRONMENT_VARIABLE = "BUGNARRATOR_TRANSCRIPTION_TOKEN"
DEFAULT_MAX_UPLOAD_BYTES = 512 * 1024 * 1024

_auth_token: Optional[str] = None
_max_upload_bytes = DEFAULT_MAX_UPLOAD_BYTES
# not_loaded | loading | loaded | failed. The health check reports it, so a
# client can tell "the server is still starting" from "the server cannot
# load its model".
_model_load_state = "not_loaded"
_model_load_error: Optional[str] = None
_model_lock = threading.Lock()


def default_token_file() -> Path:
    """The per-user file that carries the token between the server and the app.

    The path follows the same convention as the managed server install, so the
    token sits next to the executable it belongs to on both platforms. The
    contract fixture pins it; the desktop ports compute the same path.
    """
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
        return Path(base) / "BugNarrator" / "LocalTranscription" / TOKEN_FILE_NAME
    return (
        Path.home()
        / "Library"
        / "Application Support"
        / "BugNarrator"
        / "LocalTranscription"
        / TOKEN_FILE_NAME
    )


def read_token_file(path: Path) -> Optional[str]:
    """The token stored in `path`, or None when there is no usable token."""
    try:
        value = path.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    return value or None


def write_token_file(path: Path, token: str) -> None:
    """Store `token` in `path`, readable by its owner only.

    The file is created with owner-only permissions before the token is
    written, so it is never briefly world-readable. The mode is set again
    after the write: `O_CREAT` only applies the mode when it creates the
    file, so a token file left at 0644 by an older build, a restored backup
    or a copy would otherwise stay readable by everyone.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(token)
    os.chmod(path, 0o600)


def resolve_auth_token(
    token_file: Optional[Path] = None,
    explicit_token: Optional[str] = None,
    environment_token: Optional[str] = None,
) -> str:
    """Work out the token this server runs with, and record it.

    The explicit token wins, then the environment, then a token already on
    disk, and only then a fresh random one. The result is always written back
    to the token file so a client that reads the file and a client that was
    handed the token directly agree.
    """
    path = token_file or default_token_file()
    candidates = (explicit_token, environment_token, read_token_file(path))
    token = next((value.strip() for value in candidates if value and value.strip()), None)
    if token is None:
        token = secrets.token_urlsafe(32)
    try:
        write_token_file(path, token)
    except OSError:
        # An unwritable token file must not stop the server: it still refuses
        # every request that does not carry the token.
        logger.warning(f"Could not write the server token to {path}")
    return token


def _authorization_failure(authorization: Optional[str]) -> Optional[tuple]:
    """Why an Authorization header is not acceptable, or None when it is.

    The comparison is constant-time. It compares bytes rather than `str`
    values: `hmac.compare_digest` refuses to compare two strings that carry
    non-ASCII characters, and the header is attacker-controlled, so a
    non-ASCII token has to be refused with a 401 rather than crash the
    request with a 500.
    """
    if not _auth_token:
        return (503, "The server token is not configured")
    if not authorization:
        return (401, "Missing Authorization header")
    prefix = "Bearer "
    if not authorization.startswith(prefix):
        return (401, "Invalid Authorization header")
    presented = authorization[len(prefix):].encode("utf-8")
    if not hmac.compare_digest(presented, _auth_token.encode("utf-8")):
        return (401, "Invalid bearer token")
    return None


def require_bearer_token(authorization: Optional[str] = Header(None)) -> None:
    """Reject every request that does not carry the server's bearer token.

    Without this, any process on the machine could drive the model or, worse,
    receive the user's microphone audio.
    """
    failure = _authorization_failure(authorization)
    if failure is not None:
        raise HTTPException(status_code=failure[0], detail=failure[1])


def configure_auth(token: str, max_upload_bytes: int = DEFAULT_MAX_UPLOAD_BYTES) -> None:
    """Install the token the routes check, and the upload ceiling."""
    global _auth_token, _max_upload_bytes
    _auth_token = token
    _max_upload_bytes = max_upload_bytes


def _reject_oversized_upload(request: Request) -> None:
    """Refuse an upload whose declared length is already over the limit.

    The length is a hint, not a promise, so the streaming loop enforces the
    same ceiling. This check exists to reject an oversized upload before any
    of it is written to disk.
    """
    declared = request.headers.get("content-length")
    if declared is None:
        return
    try:
        declared_bytes = int(declared)
    except ValueError:
        return
    if declared_bytes > _max_upload_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"The upload exceeds the {_max_upload_bytes} byte limit",
        )


def _upload_too_large_detail(limit: int) -> str:
    return f"The upload exceeds the {limit} byte limit"


def _scope_header(scope, name: bytes) -> Optional[str]:
    """Read one header out of an ASGI scope."""
    for key, value in scope.get("headers", []):
        if key.lower() == name:
            return value.decode("latin-1")
    return None


def _capped_receive(receive, limit: int):
    """A receive channel that refuses to deliver more than `limit` bytes.

    A request that declares no length is still bounded: the body is refused
    as soon as it exceeds the ceiling, so it never reaches the spooled
    temporary file the multipart parser writes to.
    """
    delivered = 0

    async def capped():
        nonlocal delivered
        message = await receive()
        if message["type"] == "http.request":
            delivered += len(message.get("body", b""))
            if delivered > limit:
                raise HTTPException(status_code=413, detail=_upload_too_large_detail(limit))
        return message

    return capped


class _BearerTokenMiddleware:
    """Refuse a request before its body is read.

    FastAPI parses a multipart body before it solves the route's
    dependencies, so a check that lives in a dependency runs only after the
    body has been spooled to disk. An unauthenticated caller could therefore
    make the server write an unbounded amount of data to its temporary
    directory before it was refused — and a web page the user visits could
    make that call cross-origin, because `multipart/form-data` is a
    CORS-safelisted content type.

    This middleware sits in front of the router. It reads the headers, so
    the body is never touched when the request is refused, and it caps how
    many bytes the body may deliver when the request is accepted.
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        failure = _authorization_failure(_scope_header(scope, b"authorization"))
        if failure is not None:
            await self._respond(scope, receive, send, failure[0], failure[1])
            return

        limit = _max_upload_bytes
        declared = _scope_header(scope, b"content-length")
        if declared is not None:
            try:
                declared_bytes = int(declared)
            except ValueError:
                declared_bytes = None
            if declared_bytes is not None and declared_bytes > limit:
                await self._respond(scope, receive, send, 413, _upload_too_large_detail(limit))
                return

        await self.app(scope, _capped_receive(receive, limit), send)

    @staticmethod
    async def _respond(scope, receive, send, status: int, detail: str) -> None:
        response = JSONResponse({"detail": detail}, status_code=status)
        await response(scope, receive, send)


app.add_middleware(_BearerTokenMiddleware)


class _SignalPreservingServer(uvicorn.Server):
    """Keep process handlers installed while pinned Uvicorn 0.47 serves."""

    @contextlib.contextmanager
    def capture_signals(self):
        yield


def configure_default_model(model_name: str):
    """Set the server-wide default model used for lazy-loaded requests."""
    global _default_model_name
    value = model_name.strip()
    _default_model_name = (
        _canonical_model_name
        if not value or value in _model_aliases
        else value
    )


def get_model(model_name: Optional[str] = None):
    """Lazy-load the Parakeet model. Keeps it warm after first load."""
    global _model, _model_name, _model_load_error, _model_load_state
    resolved_model_name = _resolve_model_id(model_name)
    if _model is not None and _model_name == resolved_model_name:
        return _model

    # The startup load and a request that arrives while it is still running
    # must not load the model twice.
    with _model_lock:
        if _model is not None and _model_name == resolved_model_name:
            return _model

        logger.info(f"Loading model: {resolved_model_name} ({_backend})")
        start = time.time()

        if _backend == "mlx":
            from parakeet_mlx import from_pretrained

            _model = from_pretrained(resolved_model_name)
        else:
            import onnx_asr

            _model = onnx_asr.load_model(
                _onnx_model_for(resolved_model_name),
                quantization=_onnx_quantization,
            ).with_timestamps()
        _model_name = resolved_model_name
        _model_load_error = None
        _model_load_state = "loaded"
        elapsed = time.time() - start
        logger.info(f"Model loaded in {elapsed:.1f}s")
        return _model


def _load_model_in_background(model_name: Optional[str]) -> None:
    """Load the model without holding up the server's startup.

    The health check reports whether the model is loaded, and the desktop app
    will not hand the server a recording until the health check passes. A
    server that only loaded its model on the first request could therefore
    never become healthy: the app waited for the model, and the model only
    arrived with a request the app was not allowed to make.

    A failure here leaves the server up and says why in the health check: the
    model may be missing or may need to be downloaded, and the user is better
    served by the server's own answer than by a refused connection.
    """
    global _model_load_state
    _model_load_state = "loading"

    def load() -> None:
        global _model_load_error
        try:
            _inference_executor.submit(get_model, model_name).result()
        except Exception as exc:  # noqa: BLE001 - the server stays up and says why
            _model_load_error = str(exc)
            _model_load_state = "failed"
            logger.error(f"Could not load the model at startup: {exc}")

    threading.Thread(target=load, name="model-preload", daemon=True).start()


@app.get("/health", dependencies=[Depends(require_bearer_token)])
async def health():
    """Health check endpoint for BugNarrator to verify the server is running."""
    if _model_load_state == "loaded":
        status = "ok"
    elif _model_load_state == "failed":
        status = "degraded"
    else:
        status = _model_load_state
    return {
        "status": status,
        "model_loaded": _model is not None,
        "model_name": _model_name,
        "model_error": _model_load_error,
    }


@app.get("/v1/models", dependencies=[Depends(require_bearer_token)])
async def list_models():
    """Minimal /v1/models endpoint so BugNarrator's 'Validate Connection' works."""
    return {
        "object": "list",
        "data": [
            {
                "id": _model_name or _default_model_name,
                "object": "model",
                "owned_by": "local",
            }
        ],
    }


@app.post(
    "/v1/audio/transcriptions",
    dependencies=[Depends(require_bearer_token), Depends(_reject_oversized_upload)],
)
async def transcribe(
    file: UploadFile = File(...),
    model: Optional[str] = Form(None),
    response_format: str = Form("verbose_json"),
    temperature: str = Form("0"),
    language: Optional[str] = Form(None),
    prompt: Optional[str] = Form(None),
):
    """
    OpenAI-compatible transcription endpoint.

    Accepts the same multipart form fields as api.openai.com/v1/audio/transcriptions.
    Returns verbose_json format with segments containing start, end, text,
    and no_speech_prob fields that BugNarrator expects.
    """
    suffix = Path(file.filename).suffix if file.filename else ".m4a"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    try:
        # Stream the upload to disk in bounded pieces: a long recording must not be
        # held in memory as one buffer (#1229).
        written = 0
        while True:
            piece = await file.read(_upload_piece_bytes)
            if not piece:
                break
            written += len(piece)
            if written > _max_upload_bytes:
                raise HTTPException(
                    status_code=413,
                    detail=f"The upload exceeds the {_max_upload_bytes} byte limit",
                )
            tmp.write(piece)
        tmp.flush()
        tmp.close()

        file_size_mb = written / (1024 * 1024)
        model_id = _resolve_model_id(model)

        logger.info(
            f"Transcribing {file.filename} ({file_size_mb:.1f} MB) "
            f"with model {model_id} in {_chunk_duration_seconds}s chunks"
        )
        start = time.time()
        result = await asyncio.get_running_loop().run_in_executor(
            _inference_executor,
            _run_inference,
            model_id,
            tmp.name,
        )

        elapsed = time.time() - start
        logger.info(f"Transcription completed in {elapsed:.1f}s")

        full_text = result.text if hasattr(result, "text") else str(result)

        segments = []
        if hasattr(result, "sentences"):
            for sentence in result.sentences:
                seg = {
                    "start": getattr(sentence, "start", 0.0),
                    "end": getattr(sentence, "end", 0.0),
                    "text": getattr(sentence, "text", ""),
                    "no_speech_prob": 0.0,
                }
                segments.append(seg)

        if response_format == "verbose_json":
            return JSONResponse(
                content={
                    "text": full_text,
                    "segments": segments,
                    "language": language or "en",
                    "duration": segments[-1]["end"] if segments else 0.0,
                }
            )
        elif response_format == "json":
            return JSONResponse(content={"text": full_text})
        else:
            return JSONResponse(content={"text": full_text})

    except UnsupportedAudioError as error:
        logger.warning(f"Rejected unsupported audio upload: {error}")
        return JSONResponse(
            status_code=400,
            content={
                "error": {
                    "message": _unsupported_audio_message,
                    "type": "invalid_request_error",
                }
            },
        )
    except HTTPException:
        # An upload that breaks the size limit is the client's mistake, not a
        # transcription failure: report it as such instead of a generic error.
        raise
    except Exception:
        logger.exception("Transcription failed")
        return _transcription_failure_response()
    finally:
        with contextlib.suppress(OSError):
            tmp.close()
        with contextlib.suppress(OSError):
            os.unlink(tmp.name)


def _resolve_model_id(model: Optional[str]) -> str:
    """
    Map model names from BugNarrator's settings to parakeet-mlx model IDs.
    Passes through any value that already looks like a HuggingFace model ID.
    """
    if model is None or not model.strip():
        return _default_model_name

    value = model.strip()
    if value in _model_aliases:
        return _default_model_name

    return value


def _onnx_model_for(model_id: str) -> str:
    """The onnx-asr model name for a request-facing id; anything unknown passes through
    (a local ONNX directory or a Hugging Face repo onnx-asr can load)."""
    return _onnx_model_names.get(model_id, model_id)


@dataclass
class _Sentence:
    start: float
    end: float
    text: str


@dataclass
class _Transcription:
    """The result shape the route reads: the same attributes parakeet-mlx returns."""

    text: str
    sentences: list = field(default_factory=list)


_sentence_terminators = (".", "?", "!")


class UnsupportedAudioError(ValueError):
    """The ONNX backend decodes PCM WAV only (what BugNarrator's Windows recorder writes);
    anything else is refused up front as a 400 rather than failing inside inference."""


_unsupported_audio_message = (
    "The local transcription server accepts PCM WAV audio on this platform. "
    "Other formats need the OpenAI or an OpenAI-compatible provider."
)


_WAVE_FORMAT_PCM = 1
_WAVE_FORMAT_IEEE_FLOAT = 3
_WAVE_FORMAT_EXTENSIBLE = 0xFFFE


def _parse_wav(handle):
    """Scan a RIFF/WAVE container → (format tag, channels, rate, bits, data offset, data size).

    Python's wave module only accepts integer PCM; BugNarrator's system-audio recorder writes
    WASAPI loopback captures as IEEE float (often wrapped in WAVE_FORMAT_EXTENSIBLE), so the
    container is parsed here and the subformat of an extensible header is honoured. The file
    is scanned with reads and seeks so a long recording is never loaded whole (#1229)."""
    header = handle.read(12)
    if len(header) < 12 or header[:4] != b"RIFF" or header[8:12] != b"WAVE":
        raise UnsupportedAudioError("not a RIFF/WAVE file")

    handle.seek(0, os.SEEK_END)
    file_size = handle.tell()
    handle.seek(12)

    fmt = None
    data_offset = None
    data_size = None
    while handle.tell() + 8 <= file_size:
        chunk_header = handle.read(8)
        if len(chunk_header) < 8:
            break
        chunk_id = chunk_header[:4]
        (size,) = struct.unpack("<I", chunk_header[4:])
        body_offset = handle.tell()
        if chunk_id == b"fmt ":
            body = handle.read(min(size, 26))
            if len(body) < 16:
                raise UnsupportedAudioError("truncated fmt chunk")
            tag, channels, rate, _, _, bits = struct.unpack_from("<HHIIHH", body, 0)
            if tag == _WAVE_FORMAT_EXTENSIBLE:
                if len(body) < 26:
                    raise UnsupportedAudioError("truncated extensible fmt chunk")
                (tag,) = struct.unpack_from("<H", body, 24)  # first bytes of the SubFormat GUID
            fmt = (tag, channels, rate, bits)
        elif chunk_id == b"data":
            # Clamp to the file like a byte-slice did, so a header that overruns the
            # actual capture still reads what exists.
            data_offset = body_offset
            data_size = min(size, file_size - body_offset)
        if fmt is not None and data_offset is not None:
            break
        handle.seek(body_offset + size + (size & 1))

    if fmt is None or data_offset is None:
        raise UnsupportedAudioError("missing fmt or data chunk")

    return (*fmt, data_offset, data_size)


def _decode_pcm_frames(frames: bytes, tag: int, channels: int, bits: int):
    """Sample bytes → mono float32 in [-1, 1]; integer PCM (8/16/24/32-bit) and IEEE float
    (32/64-bit) are decoded — the microphone and system-audio recorders' formats — and anything
    else is refused before inference."""
    import numpy as np

    if tag == _WAVE_FORMAT_PCM and bits == 16:
        samples = np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0
    elif tag == _WAVE_FORMAT_PCM and bits == 8:
        samples = (np.frombuffer(frames, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    elif tag == _WAVE_FORMAT_PCM and bits == 24:
        raw = np.frombuffer(frames[: len(frames) - len(frames) % 3], dtype=np.uint8).reshape(-1, 3)
        as_int = (raw[:, 0].astype(np.int32) | (raw[:, 1].astype(np.int32) << 8) | (raw[:, 2].astype(np.int32) << 16))
        as_int = np.where(as_int >= 1 << 23, as_int - (1 << 24), as_int)
        samples = as_int.astype(np.float32) / float(1 << 23)
    elif tag == _WAVE_FORMAT_PCM and bits == 32:
        samples = np.frombuffer(frames, dtype="<i4").astype(np.float32) / 2147483648.0
    elif tag == _WAVE_FORMAT_IEEE_FLOAT and bits == 32:
        samples = np.frombuffer(frames, dtype="<f4").astype(np.float32)
    elif tag == _WAVE_FORMAT_IEEE_FLOAT and bits == 64:
        samples = np.frombuffer(frames, dtype="<f8").astype(np.float32)
    else:
        raise UnsupportedAudioError(f"unsupported WAV format tag {tag} with {bits} bits per sample")

    if channels > 1:
        samples = samples[: len(samples) - len(samples) % channels].reshape(-1, channels).mean(axis=1)

    return np.ascontiguousarray(samples)


def _read_wav(audio_path: str):
    """WAV → (float32 mono samples, sample rate), read in one bounded pass over the data chunk."""
    with open(audio_path, "rb") as handle:
        tag, channels, rate, bits, data_offset, data_size = _parse_wav(handle)
        if channels < 1 or rate < 1:
            raise UnsupportedAudioError("invalid WAV header")
        handle.seek(data_offset)
        frames = handle.read(data_size)

    return _decode_pcm_frames(frames, tag, channels, bits), rate


def _wav_windows(audio_path: str, window_seconds: int):
    """Yield (mono float32 samples, sample rate, start seconds) one bounded window at a time.

    Only one window's bytes are read and decoded at a time, so peak memory does not grow
    with recording length (#1229)."""
    with open(audio_path, "rb") as handle:
        tag, channels, rate, bits, data_offset, data_size = _parse_wav(handle)
        if channels < 1 or rate < 1:
            raise UnsupportedAudioError("invalid WAV header")
        block_align = max(1, channels * bits // 8)
        window_bytes = window_seconds * rate * block_align
        position = 0
        while position < data_size:
            length = min(window_bytes, data_size - position)
            handle.seek(data_offset + position)
            frames = handle.read(length)
            position += length
            samples = _decode_pcm_frames(frames, tag, channels, bits)
            if len(samples) == 0:
                continue
            yield samples, rate, (position - length) / (rate * block_align)


def _group_sentences(tokens, timestamps, offset: float):
    """Tokens → sentences on terminal punctuation, timestamps shifted by the chunk offset."""
    sentences = []
    words = []
    start = None
    for token, stamp in zip(tokens or [], timestamps or []):
        if start is None:
            start = stamp
        words.append(token)
        if token.rstrip().endswith(_sentence_terminators):
            sentences.append(_Sentence(start + offset, stamp + offset, "".join(words).strip()))
            words, start = [], None

    if words:
        last = (timestamps[-1] if timestamps else 0.0) + offset
        sentences.append(_Sentence((start or 0.0) + offset, last, "".join(words).strip()))

    return sentences


def _transcribe_onnx(model, audio_path: str) -> _Transcription:
    """Chunk at the same 120 s bound as the MLX path and stitch the results back together.

    Verified with parakeet-tdt-0.6b-v3 on onnx-asr 0.12: a 226 s recording in 120 s chunks
    came back complete (40/40 sentences, 41 timed segments) in 21 s on an ARM64 CPU.
    Windows are read one at a time, so the whole recording is never in memory (#1229)."""
    texts = []
    sentences = []
    for samples, rate, offset in _wav_windows(audio_path, _chunk_duration_seconds):
        result = model.recognize(samples, sample_rate=rate)
        if result.text.strip():
            texts.append(result.text.strip())
        sentences.extend(
            _group_sentences(
                getattr(result, "tokens", None), getattr(result, "timestamps", None), offset
            )
        )

    return _Transcription(" ".join(texts), sentences)


def _child_environment() -> dict:
    """The environment for a child process, without the server's token.

    The token is in this process's environment so that a server the app did
    not start can still find it. A child process does not need it, and
    `ps eww` prints the environment of every process the user owns, so the
    token is removed rather than handed to ffmpeg.
    """
    environment = dict(os.environ)
    environment.pop(TOKEN_ENVIRONMENT_VARIABLE, None)
    return environment


def _unlink_quietly(path: str):
    with contextlib.suppress(OSError):
        os.unlink(path)


def _release_accelerator_cache():
    """Return freed Metal/MLX buffers to the system so resident memory drops after a job.

    parakeet-mlx's batch transcribe() never clears the MLX cache, so without this the
    cache keeps the high-water mark of everything decoded so far (#1229)."""
    if _backend != "mlx":
        return
    try:
        import mlx.core as mx

        mx.clear_cache()
    except Exception:
        logger.debug("Could not clear the MLX cache", exc_info=True)


_mlx_window_sample_rate = 16000  # parakeet's preprocessor rate: windows stay tiny


def _decode_audio_window(audio_path: str, start: int) -> Optional[str]:
    """Decode one bounded window of the recording to a temp 16 kHz mono WAV, or None past
    the end. ffmpeg seeks to `start` and reads at most _chunk_duration_seconds, so only one
    window's audio exists in memory at a time instead of the whole file (#1229)."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".wav")
    destination = tmp.name
    tmp.close()
    command = [
        "ffmpeg",
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        str(start),
        "-t",
        str(_chunk_duration_seconds),
        "-i",
        audio_path,
        "-f",
        "wav",
        "-ac",
        "1",
        "-ar",
        str(_mlx_window_sample_rate),
        "-acodec",
        "pcm_s16le",
        "-y",
        destination,
    ]
    try:
        subprocess.run(command, check=True, capture_output=True, env=_child_environment())
        if _wav_data_size(destination) == 0:
            # Seek past the end decodes to nothing (ffmpeg exits 0 with an empty file):
            # the recording is fully consumed.
            _unlink_quietly(destination)
            return None
        return destination
    except subprocess.CalledProcessError as error:
        _unlink_quietly(destination)
        detail = (error.stderr or b"").decode(errors="replace").strip()
        raise RuntimeError(f"ffmpeg could not decode {audio_path}: {detail[-500:]}") from error
    except BaseException:
        _unlink_quietly(destination)
        raise


def _wav_data_size(path: str) -> int:
    with open(path, "rb") as handle:
        *_, data_size = _parse_wav(handle)
    return data_size


def _transcribe_mlx(parakeet, audio_path: str) -> _Transcription:
    """Decode and transcribe one bounded window at a time, offsetting each window's
    sentence timestamps back into the full recording's timeline.

    The MLX cache is released after every window (peak stays at one window's working set)
    and again when leaving, whether the job finished or failed (#1229)."""
    texts = []
    sentences = []
    index = 0
    try:
        while True:
            start = index * _chunk_duration_seconds
            window = _decode_audio_window(audio_path, start)
            if window is None:
                break
            try:
                result = parakeet.transcribe(
                    window,
                    chunk_duration=_chunk_duration_seconds,
                )
                text = getattr(result, "text", "") or ""
                if text.strip():
                    texts.append(text.strip())
                for sentence in getattr(result, "sentences", None) or []:
                    sentences.append(
                        _Sentence(
                            getattr(sentence, "start", 0.0) + start,
                            getattr(sentence, "end", 0.0) + start,
                            getattr(sentence, "text", ""),
                        )
                    )
            finally:
                _unlink_quietly(window)
                _release_accelerator_cache()
            index += 1
    finally:
        _release_accelerator_cache()

    return _Transcription(" ".join(texts), sentences)


def _transcribe_audio(parakeet, audio_path: str):
    """Dispatch on the model object rather than the platform so a test double with
    a transcribe method exercises the MLX contract on any OS."""
    if hasattr(parakeet, "transcribe"):
        return _transcribe_mlx(parakeet, audio_path)

    return _transcribe_onnx(parakeet, audio_path)


def _run_inference(model_id: str, audio_path: str):
    """Load and use MLX on the dedicated inference thread."""
    return _transcribe_audio(get_model(model_id), audio_path)


def _transcription_failure_response() -> JSONResponse:
    return JSONResponse(
        status_code=500,
        content={
            "error": {
                "message": _transcription_failure_message,
                "type": "server_error",
            }
        },
    )


_server = None
_drain_grace_seconds = 1.5


def _shutdown_handler(signum, frame):
    logger.info("Stopping transcription server...")
    if _backend == "onnx" and _server is not None:
        # Windows/ONNX: let uvicorn finish an in-flight request first. The supervisor
        # (LocalServerProcess) kills after its 2 s grace, and a bounded hard exit here keeps
        # a non-daemon inference thread from holding the process open past that.
        _server.should_exit = True
        threading.Timer(_drain_grace_seconds, os._exit, args=(0,)).start()
        return

    # MLX inference cannot be cancelled safely from another Python thread. Restore
    # the default handler and re-send the signal so the entire process exits.
    signal.signal(signum, signal.SIG_DFL)
    os.kill(os.getpid(), signum)


def _serve(host: str, port: int):
    config = uvicorn.Config(
        app,
        host=host,
        port=port,
        log_level="info",
    )
    global _server
    _server = _SignalPreservingServer(config)
    _server.run()


def main():
    global _model_load_state
    parser = argparse.ArgumentParser(
        description="BugNarrator Local Transcription Server"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8422,
        help="Port to listen on (default: 8422)",
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host to bind to (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--model",
        default="mlx-community/parakeet-tdt-0.6b-v3",
        help="Parakeet model to load (default: mlx-community/parakeet-tdt-0.6b-v3; "
        "mapped to nemo-parakeet-tdt-0.6b-v3 on the ONNX backend)",
    )
    parser.add_argument(
        "--preload",
        action="store_true",
        help="Load the model at startup and wait for it before serving "
        "(the default is to load it in the background)",
    )
    parser.add_argument(
        "--lazy",
        action="store_true",
        help="Do not load the model at startup at all. The desktop app waits "
        "for a loaded model before it hands over a recording, so a lazy "
        "server never becomes usable to the app.",
    )
    parser.add_argument(
        "--token-file",
        default=None,
        help="File that carries the bearer token the desktop app presents "
        "(default: the per-user token file for this platform)",
    )
    parser.add_argument(
        "--max-upload-mb",
        type=int,
        default=DEFAULT_MAX_UPLOAD_BYTES // (1024 * 1024),
        help="Largest upload the server accepts, in megabytes "
        "(default: %(default)s)",
    )
    args = parser.parse_args()
    configure_default_model(args.model)

    token_file = Path(args.token_file).expanduser() if args.token_file else default_token_file()
    token = resolve_auth_token(
        token_file=token_file,
        environment_token=os.environ.get(TOKEN_ENVIRONMENT_VARIABLE),
    )
    configure_auth(token, max_upload_bytes=max(1, args.max_upload_mb) * 1024 * 1024)

    signal.signal(signal.SIGTERM, _shutdown_handler)
    signal.signal(signal.SIGINT, _shutdown_handler)
    if hasattr(signal, "SIGBREAK"):
        # Windows: Ctrl+Break is what a supervisor can send to a process group.
        signal.signal(signal.SIGBREAK, _shutdown_handler)

    if args.preload:
        # A server that was asked to wait for its model and could not load it
        # does not start: the app that launched it reports the failure, and a
        # server that stays up without a model would only look healthy.
        _model_load_state = "loading"
        _inference_executor.submit(get_model, args.model).result()
    elif not args.lazy:
        _load_model_in_background(args.model)

    logger.info(
        f"Starting BugNarrator transcription server on {args.host}:{args.port}"
    )
    logger.info(f"The bearer token is stored in {token_file}")
    _serve(args.host, args.port)


if __name__ == "__main__":
    main()
