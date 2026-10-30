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
from fastapi import FastAPI, File, Form, Request, UploadFile
from fastapi.responses import JSONResponse
from starlette.requests import ClientDisconnect

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("bugnarrator-transcription")


@contextlib.asynccontextmanager
async def _lifespan(_app: FastAPI):
    """Keep the idle-unload watchdog running for as long as the server serves."""
    watchdog = asyncio.create_task(_idle_unload_watchdog())
    try:
        yield
    finally:
        watchdog.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await watchdog


app = FastAPI(title="BugNarrator Local Transcription Server", lifespan=_lifespan)

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

# ---------------------------------------------------------------------------
# Memory lifecycle (#1229)
#
# The server's peak resident memory must not grow with the length of the
# recording, and it must come back down when a job ends. Three knobs shape
# that: the window size (how much audio is decoded at once), the memory
# ceiling (when to refuse instead of swapping the host to death), and the
# idle unload (when to give the model's memory back).
# ---------------------------------------------------------------------------

_model_lock = threading.Lock()
_activity_lock = threading.Lock()

# 0 means "no ceiling": the server never refuses a job on memory grounds.
_max_memory_bytes = 0
# 0 means "keep the model resident". That is the default because the app's
# launchd service expects a warm server and the model is a small, fixed cost
# next to a recording. `--idle-unload-seconds` trades that for a load on the
# next request.
_idle_unload_seconds = 0
_last_activity_monotonic = time.monotonic()

_idle_check_interval_seconds = 5.0
_disconnect_poll_seconds = 0.5


class TranscriptionCancelled(RuntimeError):
    """The client went away mid-job: the work is abandoned and its memory released."""


class MemoryCeilingExceeded(RuntimeError):
    """The process went above the configured memory ceiling, so the job stops there."""


def _current_rss_bytes() -> Optional[int]:
    """This process's resident set size in bytes, or None when it cannot be read.

    The stdlib exposes no cross-platform RSS call, so each platform is read
    through its own tool. A read that fails returns None instead of raising: a
    measurement problem must never turn into a failed transcription.
    """
    try:
        if sys.platform == "darwin":
            completed = subprocess.run(
                ["ps", "-o", "rss=", "-p", str(os.getpid())],
                check=True,
                capture_output=True,
                text=True,
            )
            kilobytes = completed.stdout.strip()
            return int(kilobytes) * 1024 if kilobytes else None
        if sys.platform.startswith("linux"):
            with open("/proc/self/statm", "r", encoding="ascii") as handle:
                fields = handle.read().split()
            return int(fields[1]) * os.sysconf("SC_PAGE_SIZE")
        if sys.platform == "win32":
            return _windows_working_set_bytes()
    except Exception:
        logger.debug("Could not read the resident set size", exc_info=True)
    return None


def _windows_working_set_bytes() -> Optional[int]:
    """The Windows working set of this process, read through psapi."""
    import ctypes
    from ctypes import wintypes

    class _ProcessMemoryCounters(ctypes.Structure):
        _fields_ = [
            ("cb", wintypes.DWORD),
            ("PageFaultCount", wintypes.DWORD),
            ("PeakWorkingSetSize", ctypes.c_size_t),
            ("WorkingSetSize", ctypes.c_size_t),
            ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
            ("QuotaPagedPoolUsage", ctypes.c_size_t),
            ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
            ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
            ("PagefileUsage", ctypes.c_size_t),
            ("PeakPagefileUsage", ctypes.c_size_t),
        ]

    counters = _ProcessMemoryCounters()
    counters.cb = ctypes.sizeof(counters)
    handle = ctypes.windll.kernel32.GetCurrentProcess()
    ok = ctypes.windll.psapi.GetProcessMemoryInfo(
        handle, ctypes.byref(counters), counters.cb
    )
    return int(counters.WorkingSetSize) if ok else None


def _note_activity():
    """Record that the server was busy, so the idle clock restarts."""
    global _last_activity_monotonic
    with _activity_lock:
        _last_activity_monotonic = time.monotonic()


def _seconds_since_last_activity() -> float:
    with _activity_lock:
        return time.monotonic() - _last_activity_monotonic


def _check_cancelled(cancel_event: Optional[threading.Event]):
    """Abandon the job when the client has gone away (#1229).

    The app closes the connection when the user cancels a transcription; without
    this check the server would keep decoding and transcribing a recording
    nobody is waiting for, holding its memory for the rest of the job.
    """
    if cancel_event is not None and cancel_event.is_set():
        raise TranscriptionCancelled("the client disconnected before the job finished")


def _check_memory_ceiling(stage: str):
    """Refuse to keep working above the configured ceiling (#1229).

    A ceiling turns a host-wide swap storm into a local, explained refusal: the
    job stops with a clear message instead of driving the whole machine into swap.
    """
    if not _max_memory_bytes:
        return
    rss = _current_rss_bytes()
    if rss is None or rss <= _max_memory_bytes:
        return
    raise MemoryCeilingExceeded(
        f"the local transcription server stopped this job at the {stage}: it is using "
        f"{rss // (1024 * 1024)} MB, above the configured ceiling of "
        f"{_max_memory_bytes // (1024 * 1024)} MB"
    )


def configure_window_seconds(seconds: int):
    """Set how much audio is decoded and transcribed at a time."""
    global _chunk_duration_seconds
    _chunk_duration_seconds = max(1, int(seconds))


def configure_memory_limits(max_memory_mb: int = 0, idle_unload_seconds: int = 0):
    """Set the memory ceiling and the idle-unload period."""
    global _max_memory_bytes, _idle_unload_seconds
    _max_memory_bytes = max(0, int(max_memory_mb)) * 1024 * 1024
    _idle_unload_seconds = max(0, int(idle_unload_seconds))


def _unload_model() -> bool:
    """Give the model's memory back to the system (#1229).

    This runs on the inference thread, so it can never race a job that is using
    the model, and it clears the accelerator cache so the freed buffers leave
    the resident set instead of sitting in a pool.
    """
    global _model, _model_name
    with _model_lock:
        if _model is None:
            return False
        _model = None
        _model_name = None
    _release_accelerator_cache()
    logger.info("Unloaded the transcription model and released its cached buffers.")
    return True


async def _idle_unload_watchdog():
    """Unload the model once the server has been idle for the configured time.

    The idle period is opt-in (`--idle-unload-seconds`): the default service
    keeps the model warm the way the app's launchd service expects, and an
    operator who wants the memory back pays the model load on the next request.
    """
    while True:
        await asyncio.sleep(_idle_check_interval_seconds)
        if _idle_unload_seconds <= 0:
            continue
        if _model is None:
            continue
        if _seconds_since_last_activity() < _idle_unload_seconds:
            continue
        unloaded = await asyncio.get_running_loop().run_in_executor(
            _inference_executor, _unload_model
        )
        if unloaded:
            logger.info(
                f"Idle for {_idle_unload_seconds}s: unloaded the model to return "
                "its memory to the system."
            )


async def _watch_for_disconnect(request: Request, cancel_event: threading.Event):
    """Cancel the job when the client goes away (#1229)."""
    while True:
        try:
            disconnected = await request.is_disconnected()
        except Exception:
            logger.debug("Could not read the connection state", exc_info=True)
            return
        if disconnected:
            cancel_event.set()
            logger.info("The client disconnected: cancelling the transcription job.")
            return
        await asyncio.sleep(_disconnect_poll_seconds)


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
    with _model_lock:
        if _model is not None and _model_name == resolved_model_name:
            return _model

    logger.info(f"Loading model: {resolved_model_name} ({_backend})")
    start = time.time()

    if _backend == "mlx":
        from parakeet_mlx import from_pretrained

        loaded = from_pretrained(resolved_model_name)
    else:
        import onnx_asr

        loaded = onnx_asr.load_model(
            _onnx_model_for(resolved_model_name),
            quantization=_onnx_quantization,
        ).with_timestamps()
    with _model_lock:
        _model = loaded
        _model_name = resolved_model_name
    elapsed = time.time() - start
    logger.info(f"Model loaded in {elapsed:.1f}s")
    return loaded


@app.get("/health")
async def health():
    """Health check endpoint for BugNarrator to verify the server is running."""
    rss = _current_rss_bytes()
    return {
        "status": "ok",
        "model_loaded": _model is not None,
        "model_name": _model_name,
        "pid": os.getpid(),
        "rss_mb": rss // (1024 * 1024) if rss is not None else None,
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
    request: Request,
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

    The job watches for the client going away, so a cancelled transcription
    stops at the next window boundary and releases its memory instead of
    running to the end of the recording (#1229).
    """
    suffix = Path(file.filename).suffix if file.filename else ".m4a"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    cancel_event = threading.Event()
    watcher = asyncio.create_task(_watch_for_disconnect(request, cancel_event))
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
            f"Transcribing {file.filename} ({file_size_mb:.1f} MB) "
            f"with model {model_id} in {_chunk_duration_seconds}s chunks"
        )
        start = time.time()
        _check_memory_ceiling("start of the job")
        _note_activity()
        result = await asyncio.get_running_loop().run_in_executor(
            _inference_executor,
            _run_inference,
            model_id,
            tmp.name,
            cancel_event,
        )
        _note_activity()

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

    except TranscriptionCancelled:
        logger.info(
            "Transcription cancelled: the client disconnected, and the job's "
            "memory was released."
        )
        return _cancelled_response()
    except MemoryCeilingExceeded as error:
        logger.warning(f"Transcription refused on the memory ceiling: {error}")
        return _memory_ceiling_response(error)
    except ClientDisconnect:
        logger.info("The client disconnected during the upload; the job was abandoned.")
        return _cancelled_response()
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
        watcher.cancel()
        await asyncio.gather(watcher, return_exceptions=True)
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


def _transcribe_onnx(
    model,
    audio_path: str,
    cancel_event: Optional[threading.Event] = None,
) -> _Transcription:
    """Chunk at the same 120 s bound as the MLX path and stitch the results back together.

    Verified with parakeet-tdt-0.6b-v3 on onnx-asr 0.12: a 226 s recording in 120 s chunks
    came back complete (40/40 sentences, 41 timed segments) in 21 s on an ARM64 CPU.
    Windows are read one at a time, so the whole recording is never in memory (#1229).

    The job stops at a window boundary when the client has gone away or when the
    process has passed the memory ceiling (#1229)."""
    texts = []
    sentences = []
    for samples, rate, offset in _wav_windows(audio_path, _chunk_duration_seconds):
        _check_cancelled(cancel_event)
        _check_memory_ceiling("window boundary")
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


def _transcribe_mlx(
    parakeet,
    audio_path: str,
    cancel_event: Optional[threading.Event] = None,
) -> _Transcription:
    """Decode and transcribe one bounded window at a time, offsetting each window's
    sentence timestamps back into the full recording's timeline.

    The MLX cache is released after every window (peak stays at one window's working set)
    and again when leaving, whether the job finished or failed (#1229).

    The job stops at a window boundary when the client has gone away or when the
    process has passed the memory ceiling (#1229)."""
    texts = []
    sentences = []
    index = 0
    try:
        while True:
            _check_cancelled(cancel_event)
            _check_memory_ceiling("window boundary")
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


def _transcribe_audio(
    parakeet,
    audio_path: str,
    cancel_event: Optional[threading.Event] = None,
):
    """Dispatch on the model object rather than the platform so a test double with
    a transcribe method exercises the MLX contract on any OS."""
    if hasattr(parakeet, "transcribe"):
        return _transcribe_mlx(parakeet, audio_path, cancel_event)

    return _transcribe_onnx(parakeet, audio_path, cancel_event)


def _run_inference(
    model_id: str,
    audio_path: str,
    cancel_event: Optional[threading.Event] = None,
):
    """Load and use MLX on the dedicated inference thread."""
    return _transcribe_audio(get_model(model_id), audio_path, cancel_event)


def _cancelled_response() -> JSONResponse:
    return JSONResponse(
        status_code=499,
        content={
            "error": {
                "message": "The transcription was cancelled before it finished.",
                "type": "request_cancelled",
            }
        },
    )


def _memory_ceiling_response(error: MemoryCeilingExceeded) -> JSONResponse:
    return JSONResponse(
        status_code=503,
        content={
            "error": {
                "message": (
                    f"{error}. Raise --max-memory-mb, lower --window-seconds, or free "
                    "memory and retry."
                ),
                "type": "memory_limit_exceeded",
            }
        },
    )


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
    parser.add_argument(
        "--window-seconds",
        type=int,
        default=120,
        help="Seconds of audio decoded and transcribed at a time (default: 120). "
        "A smaller window lowers the memory one window needs and the delay before "
        "a cancelled job stops.",
    )
    parser.add_argument(
        "--max-memory-mb",
        type=int,
        default=0,
        help="Refuse a transcription once the server's resident memory passes this "
        "ceiling, in MB (default: 0, no ceiling).",
    )
    parser.add_argument(
        "--idle-unload-seconds",
        type=int,
        default=0,
        help="Unload the model after this many idle seconds (default: 0, the model "
        "stays resident). The next request then pays the model load again.",
    )
    args = parser.parse_args()
    configure_default_model(args.model)
    configure_window_seconds(args.window_seconds)
    configure_memory_limits(
        max_memory_mb=args.max_memory_mb,
        idle_unload_seconds=args.idle_unload_seconds,
    )

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
