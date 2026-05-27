"""
BugNarrator Local Transcription Server

OpenAI-compatible /v1/audio/transcriptions endpoint powered by parakeet-mlx.
Designed to be a drop-in replacement for api.openai.com when BugNarrator is
configured with the Local (Parakeet) provider.

Usage:
    python server.py [--port 8422] [--model mlx-community/parakeet-tdt-0.6b-v3]

The server loads the model lazily on first request and keeps it warm for
subsequent transcriptions.
"""

import argparse
import json
import logging
import os
import signal
import sys
import tempfile
import time
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
_transcription_failure_message = (
    "Local transcription failed. Check the local transcription server logs for details."
)


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

    logger.info(f"Loading model: {resolved_model_name}")
    start = time.time()

    from parakeet_mlx import from_pretrained

    _model = from_pretrained(resolved_model_name)
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

        model_id = _resolve_model_id(model)
        parakeet = get_model(model_id)

        file_size_mb = len(contents) / (1024 * 1024)
        logger.info(
            f"Transcribing {file.filename} ({file_size_mb:.1f} MB) "
            f"with model {model_id}"
        )
        start = time.time()

        # Parakeet-mlx has built-in chunking via chunk_duration_sec.
        # For files over 10MB (~15 min of AAC audio), enable chunking
        # to avoid Metal buffer allocation failures on long recordings.
        transcribe_kwargs = {}
        if file_size_mb > 10:
            transcribe_kwargs["chunk_duration_sec"] = 120
            logger.info(
                f"Large file detected ({file_size_mb:.1f} MB), "
                f"chunking at 120s intervals"
            )

        result = parakeet.transcribe(tmp.name, **transcribe_kwargs)
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
    logger.info("Shutting down gracefully...")
    sys.exit(0)


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
        help="Parakeet model to load (default: mlx-community/parakeet-tdt-0.6b-v3)",
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

    if args.preload:
        get_model(args.model)

    logger.info(
        f"Starting BugNarrator transcription server on {args.host}:{args.port}"
    )
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        log_level="info",
    )


if __name__ == "__main__":
    main()
