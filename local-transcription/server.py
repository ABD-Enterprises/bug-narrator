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
import platform
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
        # Stream the upload to disk in bounded pieces: a long recording must not be
        # held in memory as one buffer (#1229).
        written = 0
        while True:
            piece = await file.read(_upload_piece_bytes)
            if not piece:
                break
            tmp.write(piece)
            written += len(piece)
        tmp.flush()
        tmp.close()

        file_size_mb = written / (1024 * 1024)
        model_id = _resolve_model_id(model)

        logger.info(
            f"Transcribing {_log_safe(file.filename, 'audio')} ({file_size_mb:.1f} MB) "
            f"with model {_log_safe(model_id, 'unknown')} in {_chunk_duration_seconds}s chunks"
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
    except Exception:
        logger.exception("Transcription failed")
        return _transcription_failure_response()
    finally:
        with contextlib.suppress(OSError):
            tmp.close()
        with contextlib.suppress(OSError):
            os.unlink(tmp.name)


def _log_safe(value: Optional[str], fallback: str = "") -> str:
    """A value safe to write into a log line.

    The filename and the model name both come from the request, so either can
    carry newlines and other control characters that would forge log lines.
    Only printable characters are kept, and the result is short: a log line is
    not a place for an unbounded string.
    """
    if value is None:
        return fallback
    cleaned = "".join(character for character in value if character.isprintable()).strip()
    if not cleaned:
        return fallback
    return cleaned[:120]


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
        subprocess.run(command, check=True, capture_output=True)
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
