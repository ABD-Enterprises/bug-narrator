import asyncio
import inspect
import json
from pathlib import Path
import signal
import socket
import subprocess
import sys
import threading
import time
import unittest
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

        script = f"""
import signal
import time
import server

signal.signal(signal.SIGTERM, server._shutdown_handler)
server._inference_executor.submit(time.sleep, 30)
server._serve("127.0.0.1", {port})
"""
        process = subprocess.Popen(
            [sys.executable, "-c", script],
            cwd=Path(__file__).parent,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
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

            process.terminate()
            process.wait(timeout=2)
            self.assertEqual(process.returncode, -signal.SIGTERM)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

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


if __name__ == "__main__":
    unittest.main()
