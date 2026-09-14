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
import logging
import os
import signal
import sys
import tempfile
import time
import wave
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import uvicorn
from fastapi import FastAPI, File, Form, UploadFile
from fastapi.responses import JSONResponse

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("bugnarrator-transcription")

app = FastAPI(title="BugNarrator Local Transcription Server")

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
_backend = "mlx" if sys.platform == "darwin" else "onnx"
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
_transcription_failure_message = (
    "Local transcription failed. Check the local transcription server logs for details."
)


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
    global _model, _model_name
    resolved_model_name = _resolve_model_id(model_name)
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
    elapsed = time.time() - start
    logger.info(f"Model loaded in {elapsed:.1f}s")
    return _model


@app.get("/health")
async def health():
    """Health check endpoint for BugNarrator to verify the server is running."""
    return {
        "status": "ok",
        "model_loaded": _model is not None,
        "model_name": _model_name,
    }


@app.get("/v1/models")
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


@app.post("/v1/audio/transcriptions")
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
        contents = await file.read()
        tmp.write(contents)
        tmp.flush()
        tmp.close()

        file_size_mb = len(contents) / (1024 * 1024)
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

    except Exception:
        logger.exception("Transcription failed")
        return _transcription_failure_response()
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


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


def _read_wav(audio_path: str):
    """PCM WAV → (float32 mono samples, sample rate). BugNarrator's Windows recorder writes
    16 kHz 16-bit mono WAV; other PCM widths are converted, anything else is rejected."""
    import numpy as np

    with wave.open(audio_path, "rb") as handle:
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        rate = handle.getframerate()
        frames = handle.readframes(handle.getnframes())

    if width == 2:
        samples = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
    elif width == 1:
        samples = (np.frombuffer(frames, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    elif width == 4:
        samples = np.frombuffer(frames, dtype=np.int32).astype(np.float32) / 2147483648.0
    else:
        raise ValueError(f"unsupported WAV sample width: {width}")

    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)

    return samples, rate


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
    """Chunk at the same 120 s bound as the MLX path and stitch the results back together."""
    samples, rate = _read_wav(audio_path)
    chunk = _chunk_duration_seconds * rate
    texts = []
    sentences = []
    for start in range(0, max(len(samples), 1), chunk):
        piece = samples[start : start + chunk]
        if len(piece) == 0:
            break

        result = model.recognize(piece, sample_rate=rate)
        offset = start / rate
        if result.text.strip():
            texts.append(result.text.strip())
        sentences.extend(
            _group_sentences(
                getattr(result, "tokens", None), getattr(result, "timestamps", None), offset
            )
        )

    return _Transcription(" ".join(texts), sentences)


def _transcribe_audio(parakeet, audio_path: str):
    """Bound inference so long recordings do not degrade or exhaust Metal buffers.

    Dispatches on the model object rather than the platform so a test double with
    a transcribe method exercises the MLX contract on any OS."""
    if hasattr(parakeet, "transcribe"):
        return parakeet.transcribe(
            audio_path,
            chunk_duration=_chunk_duration_seconds,
        )

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


def _shutdown_handler(signum, frame):
    logger.info("Stopping transcription server...")
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
    _SignalPreservingServer(config).run()


def main():
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
        help="Load the model at startup instead of on first request",
    )
    args = parser.parse_args()
    configure_default_model(args.model)

    signal.signal(signal.SIGTERM, _shutdown_handler)
    signal.signal(signal.SIGINT, _shutdown_handler)
    if hasattr(signal, "SIGBREAK"):
        # Windows: Ctrl+Break is what a supervisor can send to a process group.
        signal.signal(signal.SIGBREAK, _shutdown_handler)

    if args.preload:
        _inference_executor.submit(get_model, args.model).result()

    logger.info(
        f"Starting BugNarrator transcription server on {args.host}:{args.port}"
    )
    _serve(args.host, args.port)


if __name__ == "__main__":
    main()
