import asyncio
import inspect
import json
from pathlib import Path
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import wave
from unittest.mock import patch

import server


class ServerModelConfigurationTests(unittest.TestCase):
    def tearDown(self):
        server._model = None
        server._model_name = None
        server.configure_default_model("mlx-community/parakeet-tdt-0.6b-v3")

    def test_configured_default_model_is_used_for_lazy_requests(self):
        server.configure_default_model("mlx-community/custom-parakeet")

        self.assertEqual(
            server._resolve_model_id(None),
            "mlx-community/custom-parakeet",
        )
        self.assertEqual(
            server._resolve_model_id("  "),
            "mlx-community/custom-parakeet",
        )

    def test_model_aliases_and_custom_ids_are_normalized(self):
        self.assertEqual(
            server._resolve_model_id("parakeet-tdt-0.6b-v3"),
            "mlx-community/parakeet-tdt-0.6b-v3",
        )
        self.assertEqual(
            server._resolve_model_id(" parakeet "),
            "mlx-community/parakeet-tdt-0.6b-v3",
        )
        self.assertEqual(
            server._resolve_model_id("mlx-community/custom-parakeet"),
            "mlx-community/custom-parakeet",
        )

    def test_model_aliases_resolve_to_configured_default(self):
        server.configure_default_model("mlx-community/custom-parakeet")

        self.assertEqual(
            server._resolve_model_id("parakeet-tdt-0.6b-v3"),
            "mlx-community/custom-parakeet",
        )
        self.assertEqual(
            server._resolve_model_id("whisper-1"),
            "mlx-community/custom-parakeet",
        )

    def test_configured_alias_resets_to_canonical_default(self):
        server.configure_default_model("mlx-community/custom-parakeet")
        server.configure_default_model("parakeet")

        self.assertEqual(
            server._resolve_model_id(None),
            "mlx-community/parakeet-tdt-0.6b-v3",
        )

    def test_models_endpoint_reports_configured_default_before_lazy_load(self):
        server.configure_default_model("mlx-community/custom-parakeet")

        response = asyncio.run(server.list_models())

        self.assertEqual(
            response["data"][0]["id"],
            "mlx-community/custom-parakeet",
        )

    def test_models_endpoint_reports_loaded_model_after_lazy_load(self):
        server.configure_default_model("mlx-community/custom-parakeet")
        server._model_name = "mlx-community/loaded-parakeet"

        response = asyncio.run(server.list_models())

        self.assertEqual(
            response["data"][0]["id"],
            "mlx-community/loaded-parakeet",
        )

    def test_transcription_failure_response_hides_exception_details(self):
        response = server._transcription_failure_response()
        body = json.loads(response.body)

        self.assertEqual(response.status_code, 500)
        self.assertEqual(body["error"]["type"], "server_error")
        self.assertEqual(
            body["error"]["message"],
            "Local transcription failed. Check the local transcription server logs for details.",
        )
        self.assertNotIn("Traceback", body["error"]["message"])
        self.assertNotIn("Exception", body["error"]["message"])

    def test_transcription_uses_supported_bounded_chunking_argument(self):
        class RecordingModel:
            def __init__(self):
                self.calls = []

            def transcribe(self, path, **kwargs):
                self.calls.append((path, kwargs))
                return "result"

        model = RecordingModel()

        result = server._transcribe_audio(model, "/tmp/fixture.m4a")

        self.assertEqual(result, "result")
        self.assertEqual(
            model.calls,
            [("/tmp/fixture.m4a", {"chunk_duration": 120})],
        )

    def test_transcription_route_keeps_http_event_loop_async(self):
        self.assertTrue(inspect.iscoroutinefunction(server.transcribe))

    def test_model_load_and_transcription_share_the_inference_thread(self):
        class RecordingModel:
            def transcribe(self, path, **kwargs):
                return (threading.get_ident(), path, kwargs)

        model = RecordingModel()

        def load_model(_model_id):
            return model

        with patch.object(server, "get_model", side_effect=load_model):
            first = server._inference_executor.submit(
                server._run_inference,
                "model",
                "/tmp/first.m4a",
            ).result()
            second = server._inference_executor.submit(
                server._run_inference,
                "model",
                "/tmp/second.m4a",
            ).result()

        self.assertEqual(first[0], second[0])
        self.assertEqual(first[2], {"chunk_duration": 120})
        self.assertEqual(second[2], {"chunk_duration": 120})

    def test_shutdown_terminates_process_even_during_active_inference(self):
        with (
            patch.object(server.os, "getpid", return_value=2468),
            patch.object(server.os, "kill") as kill,
            patch.object(server.signal, "signal") as restore_signal,
        ):
            server._shutdown_handler(server.signal.SIGTERM, None)

        restore_signal.assert_called_once_with(
            server.signal.SIGTERM,
            server.signal.SIG_DFL,
        )
        kill.assert_called_once_with(2468, server.signal.SIGTERM)

    def test_uvicorn_does_not_replace_process_signal_handlers(self):
        uvicorn_server = server._SignalPreservingServer(
            server.uvicorn.Config(server.app)
        )

        with patch.object(server.signal, "signal") as install_signal:
            with uvicorn_server.capture_signals():
                pass

        install_signal.assert_not_called()

    def test_serve_uses_signal_preserving_uvicorn_server(self):
        config = object()
        with (
            patch.object(server.uvicorn, "Config", return_value=config) as make_config,
            patch.object(server, "_SignalPreservingServer") as server_type,
        ):
            server._serve("127.0.0.1", 8422)

        make_config.assert_called_once_with(
            server.app,
            host="127.0.0.1",
            port=8422,
            log_level="info",
        )
        server_type.assert_called_once_with(config)
        server_type.return_value.run.assert_called_once_with()

    def test_sigterm_exits_while_inference_worker_is_active(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]

        # POSIX: SIGTERM. Windows has no SIGTERM delivery; Ctrl+Break to the process group is the
        # supervisor's stop signal, handled by the same _shutdown_handler.
        stop_signal = "SIGBREAK" if sys.platform == "win32" else "SIGTERM"
        script = f"""
import signal
import time
import server

signal.signal(signal.{stop_signal}, server._shutdown_handler)
server._inference_executor.submit(time.sleep, 30)
server._serve("127.0.0.1", {port})
"""
        creation_flags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        process = subprocess.Popen(
            [sys.executable, "-c", script],
            cwd=Path(__file__).parent,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=creation_flags,
        )
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    self.fail("transcription server exited before accepting connections")
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                        break
                except OSError:
                    time.sleep(0.05)
            else:
                self.fail("transcription server did not start within 10 seconds")

            if sys.platform == "win32":
                process.send_signal(signal.CTRL_BREAK_EVENT)
                process.wait(timeout=2)
                # The handler re-raises with the default disposition; on Windows that is
                # TerminateProcess with the signal number as the exit code.
                self.assertEqual(process.returncode, signal.SIGBREAK)
            else:
                process.terminate()
                process.wait(timeout=2)
                self.assertEqual(process.returncode, -signal.SIGTERM)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    # ---- ONNX backend (every platform but macOS) ----

    def test_onnx_model_mapping_keeps_the_request_facing_ids_and_passes_unknowns_through(self):
        self.assertEqual(
            server._onnx_model_for("mlx-community/parakeet-tdt-0.6b-v3"),
            "nemo-parakeet-tdt-0.6b-v3",
        )
        self.assertEqual(server._onnx_model_for("nvidia/parakeet-tdt-0.6b-v3"), "nemo-parakeet-tdt-0.6b-v3")
        self.assertEqual(server._onnx_model_for("C:/models/custom"), "C:/models/custom")
        # The alias table the client relies on is unchanged by the backend split.
        self.assertEqual(server._resolve_model_id("whisper-1"), server._default_model_name)

    def test_onnx_transcription_chunks_at_the_shared_bound_and_offsets_timestamps(self):
        class Result:
            def __init__(self, text, tokens, timestamps):
                self.text, self.tokens, self.timestamps = text, tokens, timestamps

        class RecordingOnnxModel:
            def __init__(self):
                self.calls = []

            def recognize(self, waveform, *, sample_rate):
                self.calls.append((len(waveform), sample_rate))
                index = len(self.calls)
                return Result(f"chunk {index}.", [f"chunk {index}", "."], [0.5, 1.0])

        rate = 16000
        seconds = server._chunk_duration_seconds * 2 + 5  # two full chunks and a tail
        path = self._write_wav(rate, seconds)
        model = RecordingOnnxModel()

        result = server._transcribe_audio(model, path)

        self.assertEqual(
            [c[0] for c in model.calls],
            [server._chunk_duration_seconds * rate, server._chunk_duration_seconds * rate, 5 * rate],
        )
        self.assertTrue(all(c[1] == rate for c in model.calls))
        self.assertEqual(result.text, "chunk 1. chunk 2. chunk 3.")
        self.assertEqual([round(s.start, 1) for s in result.sentences], [0.5, 120.5, 240.5])
        self.assertEqual([round(s.end, 1) for s in result.sentences], [1.0, 121.0, 241.0])
        self.assertEqual([s.text for s in result.sentences], ["chunk 1.", "chunk 2.", "chunk 3."])

    def test_onnx_sentences_group_tokens_on_terminal_punctuation(self):
        sentences = server._group_sentences(
            ["Hello", " there", ".", " Second", " one", "?", " trailing"],
            [0.0, 0.2, 0.4, 1.0, 1.2, 1.4, 2.0],
            offset=10.0,
        )

        self.assertEqual([s.text for s in sentences], ["Hello there.", "Second one?", "trailing"])
        self.assertEqual([(s.start, s.end) for s in sentences], [(10.0, 10.4), (11.0, 11.4), (12.0, 12.0)])
        self.assertEqual(server._group_sentences(None, None, 0.0), [])

    def test_onnx_reads_stereo_and_8_bit_wav(self):
        stereo = self._write_wav(8000, 1, channels=2)
        samples, rate = server._read_wav(stereo)
        self.assertEqual(rate, 8000)
        self.assertEqual(len(samples), 8000)

        eight_bit = self._write_wav(16000, 1, width=1)
        samples, _ = server._read_wav(eight_bit)
        self.assertEqual(len(samples), 16000)
        self.assertTrue(float(abs(samples).max()) <= 1.0)

    def test_transcription_route_reads_the_onnx_result_shape(self):
        # The route reads .text and .sentences (start/end/text) — the MLX result shape — so the
        # ONNX result must expose the same attributes.
        result = server._Transcription("hi.", [server._Sentence(0.0, 0.5, "hi.")])
        self.assertTrue(hasattr(result, "text") and hasattr(result, "sentences"))
        self.assertEqual(result.sentences[0].end, 0.5)

    def _write_wav(self, rate, seconds, channels=1, width=2):
        path = tempfile.NamedTemporaryFile(delete=False, suffix=".wav").name
        self.addCleanup(lambda: Path(path).unlink(missing_ok=True))
        with wave.open(path, "wb") as handle:
            handle.setnchannels(channels)
            handle.setsampwidth(width)
            handle.setframerate(rate)
            frames = rate * seconds * channels
            if width == 2:
                handle.writeframes(struct.pack(f"<{frames}h", *([0] * frames)))
            else:
                handle.writeframes(bytes([128] * frames))
        return path

    def test_runtime_dependencies_are_exactly_pinned(self):
        requirements = (
            Path(__file__).with_name("requirements.txt").read_text().splitlines()
        )
        packages = [line for line in requirements if line and not line.startswith("#")]

        self.assertTrue(packages)
        self.assertTrue(all("==" in package for package in packages))

    def test_standalone_dependencies_are_hash_locked(self):
        lockfile = Path(__file__).with_name("requirements-standalone.lock")
        contents = lockfile.read_text()
        packages = [
            line
            for line in contents.splitlines()
            if line and not line.startswith(("#", " ", "--"))
        ]

        self.assertTrue(packages)
        self.assertTrue(all("==" in package for package in packages))
        self.assertGreaterEqual(contents.count("--hash=sha256:"), len(packages))

    def test_windows_dependencies_are_hash_locked_and_free_of_apple_only_packages(self):
        lockfile = Path(__file__).with_name("requirements-windows.lock")
        contents = lockfile.read_text()
        packages = [
            line
            for line in contents.splitlines()
            if line and not line.startswith(("#", " ", "--"))
        ]

        self.assertTrue(packages)
        self.assertTrue(all("==" in package for package in packages))
        self.assertGreaterEqual(contents.count("--hash=sha256:"), len(packages))
        names = {package.split("==")[0].lower() for package in packages}
        self.assertIn("onnx-asr", names)
        self.assertIn("onnxruntime", names)
        self.assertIn("pyinstaller", names)
        self.assertNotIn("parakeet-mlx", names)
        self.assertNotIn("mlx", names)
        # The two runtimes pin the same web stack so the protocol cannot drift by dependency.
        runtime = Path(__file__).with_name("requirements.txt").read_text().splitlines()
        for pin in ("fastapi==", "uvicorn", "python-multipart=="):
            shared = next(line for line in runtime if line.startswith(pin))
            version = shared.split("==")[1]
            self.assertIn(f"{pin.split('[')[0].rstrip('=')}=={version}", contents)


if __name__ == "__main__":
    unittest.main()
