import asyncio
import inspect
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import wave
from unittest.mock import call, patch

import server


class ServerModelConfigurationTests(unittest.TestCase):
    def tearDown(self):
        server._model = None
        server._model_name = None
        server._server = None
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

    def test_mlx_transcription_decodes_bounded_windows_and_offsets_sentences(self):
        # The model must never receive the full recording: each window is decoded on its
        # own and its timestamps are shifted back into the recording's timeline (#1229).
        class Sentence:
            def __init__(self, start, end, text):
                self.start, self.end, self.text = start, end, text

        class Result:
            text = "hello."
            sentences = [Sentence(0.5, 1.0, "hello.")]

        class RecordingModel:
            def __init__(self):
                self.calls = []

            def transcribe(self, path, **kwargs):
                self.calls.append((path, kwargs))
                return Result()

        model = RecordingModel()
        windows = ["/tmp/window-0.wav", "/tmp/window-120.wav"]

        with (
            patch.object(
                server,
                "_decode_audio_window",
                side_effect=[*windows, None],
            ) as decode,
            patch.object(server, "_release_accelerator_cache") as release,
        ):
            result = server._transcribe_audio(model, "/tmp/fixture.m4a")

        self.assertEqual(
            decode.call_args_list,
            [
                call("/tmp/fixture.m4a", 0),
                call("/tmp/fixture.m4a", 120),
                call("/tmp/fixture.m4a", 240),
            ],
        )
        self.assertEqual(
            model.calls,
            [
                (windows[0], {"chunk_duration": 120}),
                (windows[1], {"chunk_duration": 120}),
            ],
        )
        self.assertEqual(result.text, "hello. hello.")
        self.assertEqual(
            [(s.start, s.end, s.text) for s in result.sentences],
            [(0.5, 1.0, "hello."), (120.5, 121.0, "hello.")],
        )
        # Released after each window and once more when leaving the loop.
        self.assertGreaterEqual(release.call_count, 3)

    def test_mlx_failure_releases_the_accelerator_cache_and_propagates(self):
        class FailingModel:
            def transcribe(self, path, **kwargs):
                raise ValueError("bad window")

        with (
            patch.object(server, "_decode_audio_window", return_value="/tmp/window.wav"),
            patch.object(server, "_release_accelerator_cache") as release,
        ):
            with self.assertRaises(ValueError):
                server._transcribe_audio(FailingModel(), "/tmp/fixture.m4a")

        # The inner finally releases the failed window; the outer finally guarantees it.
        self.assertGreaterEqual(release.call_count, 2)

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg is required to decode windows")
    def test_audio_windows_decode_bounded_slices_and_stop_past_the_end(self):
        rate = 8000
        seconds = server._chunk_duration_seconds + 5  # one full window and a tail
        source = self._write_wav(rate, seconds)

        first = server._decode_audio_window(source, 0)
        self.addCleanup(server._unlink_quietly, first)
        tail = server._decode_audio_window(source, server._chunk_duration_seconds)
        self.addCleanup(server._unlink_quietly, tail)
        past_end = server._decode_audio_window(source, 2 * server._chunk_duration_seconds)

        self.assertIsNone(past_end)
        for window in (first, tail):
            with wave.open(window, "rb") as handle:
                self.assertEqual(handle.getframerate(), 16000)  # parakeet's rate
                self.assertEqual(handle.getnchannels(), 1)
        with wave.open(first, "rb") as handle:
            self.assertAlmostEqual(
                handle.getnframes() / handle.getframerate(),
                server._chunk_duration_seconds,
                places=1,
            )
        with wave.open(tail, "rb") as handle:
            self.assertAlmostEqual(handle.getnframes() / handle.getframerate(), 5, places=1)

    def test_transcription_route_keeps_http_event_loop_async(self):
        self.assertTrue(inspect.iscoroutinefunction(server.transcribe))

    def test_model_load_and_transcription_share_the_inference_thread(self):
        class RecordingModel:
            def __init__(self):
                self.threads = []
                self.calls = []

            def transcribe(self, path, **kwargs):
                self.threads.append(threading.get_ident())
                self.calls.append((path, kwargs))

        model = RecordingModel()
        load_threads = []

        def load_model(_model_id):
            load_threads.append(threading.get_ident())
            return model

        def one_window(_audio_path, start):
            return "/tmp/window.wav" if start == 0 else None

        with (
            patch.object(server, "get_model", side_effect=load_model),
            patch.object(server, "_decode_audio_window", side_effect=one_window),
            patch.object(server, "_release_accelerator_cache"),
        ):
            server._inference_executor.submit(
                server._run_inference,
                "model",
                "/tmp/first.m4a",
            ).result()
            server._inference_executor.submit(
                server._run_inference,
                "model",
                "/tmp/second.m4a",
            ).result()

        self.assertEqual(len(model.threads), 2)
        self.assertEqual(model.threads, load_threads)
        self.assertEqual(model.threads[0], model.threads[1])
        self.assertTrue(all(kwargs == {"chunk_duration": 120} for _, kwargs in model.calls))

    def test_shutdown_terminates_process_even_during_active_inference(self):
        # The MLX contract: no drain, re-raise the signal with the default disposition.
        with (
            patch.object(server, "_backend", "mlx"),
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

    def test_onnx_shutdown_lets_uvicorn_drain_then_hard_exits_within_the_grace(self):
        class FakeServer:
            should_exit = False

        fake = FakeServer()
        with (
            patch.object(server, "_backend", "onnx"),
            patch.object(server, "_server", fake),
            patch.object(server.threading, "Timer") as timer,
            patch.object(server.os, "kill") as kill,
        ):
            server._shutdown_handler(server.signal.SIGTERM, None)

        self.assertTrue(fake.should_exit)
        kill.assert_not_called()
        timer.assert_called_once_with(server._drain_grace_seconds, server.os._exit, args=(0,))
        timer.return_value.start.assert_called_once_with()
        self.assertLess(server._drain_grace_seconds, 2.0)  # inside LocalServerProcess's grace

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
            deadline = time.monotonic() + 90
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

            started = time.monotonic()
            if sys.platform == "win32":
                process.send_signal(signal.CTRL_BREAK_EVENT)
            else:
                process.terminate()
            process.wait(timeout=2)
            self.assertLess(time.monotonic() - started, 2)
            if server._backend == "onnx":
                # ONNX (Windows, Linux, Intel macOS): uvicorn drains, then a bounded hard exit
                # inside the app's 2 s grace even though the inference worker is still busy.
                self.assertEqual(process.returncode, 0)
            else:
                # MLX: the signal is re-raised with the default disposition.
                self.assertEqual(process.returncode, -signal.SIGTERM)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    # ---- ONNX backend (every platform but macOS) ----

    def test_backend_is_mlx_only_on_apple_silicon(self):
        with patch.object(server.sys, "platform", "darwin"), patch.object(server.platform, "machine", return_value="arm64"):
            self.assertEqual(server._select_backend(), "mlx")
        with patch.object(server.sys, "platform", "darwin"), patch.object(server.platform, "machine", return_value="x86_64"):
            self.assertEqual(server._select_backend(), "onnx")
        with patch.object(server.sys, "platform", "win32"), patch.object(server.platform, "machine", return_value="AMD64"):
            self.assertEqual(server._select_backend(), "onnx")

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

    def test_onnx_refuses_non_wav_uploads_before_inference(self):
        path = tempfile.NamedTemporaryFile(delete=False, suffix=".m4a").name
        self.addCleanup(lambda: Path(path).unlink(missing_ok=True))
        Path(path).write_bytes(b"\x00\x00\x00\x18ftypM4A ")

        class NeverCalled:
            def recognize(self, *args, **kwargs):
                raise AssertionError("inference must not run on undecodable audio")

        with self.assertRaises(server.UnsupportedAudioError):
            server._transcribe_audio(NeverCalled(), path)

    def test_transcription_route_maps_unsupported_audio_to_a_400(self):
        import io

        from fastapi import UploadFile

        class NeverCalled:
            def recognize(self, *args, **kwargs):
                raise AssertionError("inference must not run on undecodable audio")

        upload = UploadFile(io.BytesIO(b"\x00\x00\x00\x18ftypM4A "), filename="clip.m4a")
        with patch.object(server, "get_model", return_value=NeverCalled()):
            response = asyncio.run(server.transcribe(file=upload, model="parakeet-tdt-0.6b-v3"))

        body = json.loads(response.body)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(body["error"]["type"], "invalid_request_error")
        self.assertIn("PCM WAV", body["error"]["message"])

    def test_transcription_route_streams_the_upload_to_disk_in_bounded_pieces(self):
        import io

        from fastapi import UploadFile

        payload = b"\x00" * (3 * server._upload_piece_bytes + 17)
        seen = {}

        def fake_run_inference(_model_id, path):
            seen["bytes"] = Path(path).read_bytes()
            return server._Transcription("ok", [])

        upload = UploadFile(io.BytesIO(payload), filename="clip.m4a")
        original_read = upload.read
        read_sizes = []

        async def guarded_read(size=-1):
            read_sizes.append(size)
            return await original_read(size)

        upload.read = guarded_read

        with patch.object(server, "_run_inference", side_effect=fake_run_inference):
            response = asyncio.run(
                server.transcribe(file=upload, model="parakeet-tdt-0.6b-v3")
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(seen.get("bytes"), payload)
        # Every read is a bounded piece; the whole upload is never read at once (#1229).
        self.assertTrue(read_sizes)
        self.assertEqual(max(read_sizes), server._upload_piece_bytes)

    def test_onnx_reads_stereo_and_8_bit_wav(self):
        stereo = self._write_wav(8000, 1, channels=2)
        samples, rate = server._read_wav(stereo)
        self.assertEqual(rate, 8000)
        self.assertEqual(len(samples), 8000)

        eight_bit = self._write_wav(16000, 1, width=1)
        samples, _ = server._read_wav(eight_bit)
        self.assertEqual(len(samples), 16000)
        self.assertTrue(float(abs(samples).max()) <= 1.0)

    def test_onnx_reads_the_loopback_recorders_float_wav(self):
        # WASAPI loopback capture (System Audio mode) is 32-bit IEEE float, usually wrapped in
        # WAVE_FORMAT_EXTENSIBLE; Python's wave module refuses it, this reader must not.
        for extensible in (False, True):
            with self.subTest(extensible=extensible):
                path = self._write_float_wav(48000, 2, seconds=1, extensible=extensible)
                samples, rate = server._read_wav(path)
                self.assertEqual(rate, 48000)
                self.assertEqual(len(samples), 48000)
                self.assertAlmostEqual(float(samples[0]), 0.25, places=5)

    def test_onnx_refuses_unknown_wav_encodings(self):
        path = tempfile.NamedTemporaryFile(delete=False, suffix=".wav").name
        self.addCleanup(lambda: Path(path).unlink(missing_ok=True))
        Path(path).write_bytes(self._riff(fmt_tag=0x0055, channels=1, rate=16000, bits=0, frames=b""))  # MP3-in-WAV

        with self.assertRaises(server.UnsupportedAudioError):
            server._read_wav(path)

    def _riff(self, fmt_tag, channels, rate, bits, frames, extensible=False):
        block_align = max(1, channels * bits // 8)
        fmt = struct.pack("<HHIIHH", 0xFFFE if extensible else fmt_tag, channels, rate, rate * block_align, block_align, bits)
        if extensible:
            fmt += struct.pack("<HHI", 22, bits, 0) + struct.pack("<H", fmt_tag) + b"\x00\x00\x00\x00\x10\x00\x80\x00\x00\xaa\x00\x38\x9b\x71"
        body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(frames)) + frames
        return b"RIFF" + struct.pack("<I", len(body)) + body

    def _write_float_wav(self, rate, channels, seconds, extensible):
        path = tempfile.NamedTemporaryFile(delete=False, suffix=".wav").name
        self.addCleanup(lambda: Path(path).unlink(missing_ok=True))
        frames = struct.pack(f"<{rate * seconds * channels}f", *([0.25] * (rate * seconds * channels)))
        Path(path).write_bytes(self._riff(fmt_tag=3, channels=channels, rate=rate, bits=32, frames=frames, extensible=extensible))
        return path

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
        for name in ("requirements-windows.lock", "requirements-windows-arm64.lock"):
            with self.subTest(lock=name):
                self._assert_windows_lock(Path(__file__).with_name(name))

    def test_hash_locks_carry_every_pin_from_their_inputs(self):
        # Dependabot bumps the .in/.txt pins but not these uv-compiled locks (#1221), and
        # the packaged runtimes install only from the locks, so a stale lock ships the old
        # version while the pins claim the new one.
        here = Path(__file__).parent
        for source, locks in (
            ("requirements-standalone.in", ("requirements-standalone.lock",)),
            (
                "requirements-windows.in",
                ("requirements-windows.lock", "requirements-windows-arm64.lock"),
            ),
        ):
            pins = self._exact_pins(here / source)
            self.assertTrue(pins)
            for name in locks:
                locked = self._exact_pins(here / name)
                for package, version in pins.items():
                    with self.subTest(lock=name, package=package):
                        self.assertEqual(
                            locked.get(package),
                            version,
                            f"{name} does not lock {package}=={version}; "
                            "run local-transcription/relock.sh",
                        )

    def _exact_pins(self, path):
        pins = {}
        for raw in path.read_text().splitlines():
            line = raw.split("#")[0].strip().rstrip("\\").strip()
            if line.startswith("-r "):
                pins.update(self._exact_pins(path.parent / line[3:].strip()))
            elif "==" in line and not line.startswith("-"):
                requirement, version = line.split("==", 1)
                package = requirement.split("[")[0].strip().lower().replace("_", "-")
                pins[package] = version.strip()
        return pins

    def _assert_windows_lock(self, lockfile):
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


class ServerAuthenticationTests(unittest.TestCase):
    """Every route refuses a request that does not carry the server's token (#1270).

    Without the token any process on the machine could drive the model and
    receive the user's microphone audio, and a rogue listener that grabbed the
    port first looked like a healthy server.
    """

    def setUp(self):
        self._previous_token = server._auth_token
        self._previous_max_upload_bytes = server._max_upload_bytes
        self.addCleanup(setattr, server, "_auth_token", self._previous_token)
        self.addCleanup(setattr, server, "_max_upload_bytes", self._previous_max_upload_bytes)

    def _request(self, url, token=None, data=None, method=None):
        import http.client
        from urllib.parse import urlsplit

        parts = urlsplit(url)
        path = parts.path or "/"
        if parts.query:
            path = f"{path}?{parts.query}"
        headers = {}
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        connection = http.client.HTTPConnection(parts.hostname, parts.port, timeout=30)
        try:
            connection.request(method or "GET", path, body=data, headers=headers)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def _serve(self, token, port, token_file, max_upload_mb=None):
        # `--lazy` keeps the test server from loading a real model: the tests
        # are about the transport, not about inference.
        extra = "" if max_upload_mb is None else f', "--max-upload-mb", "{max_upload_mb}"'
        script = f"""
import sys
sys.argv = ["server", "--host", "127.0.0.1", "--port", "{port}", "--token-file", r"{token_file}", "--lazy"{extra}]
import server
server.main()
"""
        environment = dict(os.environ)
        environment[server.TOKEN_ENVIRONMENT_VARIABLE] = token
        environment["PYTHONUNBUFFERED"] = "1"
        creation_flags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        process = subprocess.Popen(
            [sys.executable, "-c", script],
            cwd=Path(__file__).parent,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=environment,
            creationflags=creation_flags,
        )
        self.addCleanup(self._stop, process)
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            if process.poll() is not None:
                self.fail("the transcription server exited before accepting connections")
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                    return process
            except OSError:
                time.sleep(0.05)
        self.fail("the transcription server did not start within 20 seconds")

    @staticmethod
    def _stop(process):
        if process.poll() is None:
            process.kill()
            process.wait()

    def test_every_route_refuses_a_request_without_the_token(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        with tempfile.TemporaryDirectory() as directory:
            token_file = str(Path(directory) / server.TOKEN_FILE_NAME)
            self._serve("s3cret-token-value", port, token_file)
            base = f"http://127.0.0.1:{port}"

            status, _ = self._request(f"{base}/health")
            self.assertEqual(status, 401)

            status, _ = self._request(f"{base}/v1/models")
            self.assertEqual(status, 401)

            status, _ = self._request(
                f"{base}/v1/audio/transcriptions",
                data=b"--x\r\n\r\n",
                method="POST",
            )
            self.assertEqual(status, 401)

    def test_a_wrong_token_is_refused(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        with tempfile.TemporaryDirectory() as directory:
            token_file = str(Path(directory) / server.TOKEN_FILE_NAME)
            self._serve("s3cret-token-value", port, token_file)

            status, _ = self._request(
                f"http://127.0.0.1:{port}/health",
                token="not-the-token",
            )
            self.assertEqual(status, 401)

    def test_the_right_token_is_accepted(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        with tempfile.TemporaryDirectory() as directory:
            token_file = str(Path(directory) / server.TOKEN_FILE_NAME)
            self._serve("s3cret-token-value", port, token_file)
            base = f"http://127.0.0.1:{port}"

            status, body = self._request(f"{base}/health", token="s3cret-token-value")
            self.assertEqual(status, 200)
            health = json.loads(body)
            # The token was accepted. The server reports that it has not
            # loaded its model, because this test server runs with --lazy.
            self.assertIn(health["status"], ("not_loaded", "loading", "ok"))
            self.assertIn("model_loaded", health)

            status, body = self._request(f"{base}/v1/models", token="s3cret-token-value")
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(body)["data"][0]["owned_by"], "local")

    def test_a_token_without_the_bearer_prefix_is_refused(self):
        server.configure_auth("s3cret-token-value")
        with self.assertRaises(server.HTTPException) as raised:
            server.require_bearer_token(authorization="s3cret-token-value")
        self.assertEqual(raised.exception.status_code, 401)

    def test_an_empty_token_is_refused(self):
        server.configure_auth("s3cret-token-value")
        with self.assertRaises(server.HTTPException) as raised:
            server.require_bearer_token(authorization="")
        self.assertEqual(raised.exception.status_code, 401)

    def test_the_token_is_stored_for_its_owner_only(self):
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / server.TOKEN_FILE_NAME
            server.write_token_file(token_file, "s3cret-token-value")

            self.assertEqual(token_file.read_text(encoding="utf-8"), "s3cret-token-value")
            if os.name != "nt":
                self.assertEqual(token_file.stat().st_mode & 0o777, 0o600)

    def test_the_environment_token_wins_over_the_token_on_disk(self):
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / server.TOKEN_FILE_NAME
            server.write_token_file(token_file, "the-old-token")

            resolved = server.resolve_auth_token(
                token_file=token_file,
                environment_token="the-new-token",
            )

            self.assertEqual(resolved, "the-new-token")
            # The file keeps the effective token so a client that only reads the
            # file agrees with the server.
            self.assertEqual(server.read_token_file(token_file), "the-new-token")

    def test_a_token_on_disk_is_reused(self):
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / server.TOKEN_FILE_NAME
            server.write_token_file(token_file, "the-token-on-disk")

            resolved = server.resolve_auth_token(token_file=token_file)

            self.assertEqual(resolved, "the-token-on-disk")

    def test_a_missing_token_yields_a_fresh_random_one(self):
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / server.TOKEN_FILE_NAME

            resolved = server.resolve_auth_token(token_file=token_file)

            self.assertTrue(resolved)
            self.assertGreaterEqual(len(resolved), 32)
            self.assertNotEqual(resolved, server.resolve_auth_token(token_file=Path(directory) / "other"))
            self.assertEqual(server.read_token_file(token_file), resolved)

    def test_the_default_token_file_follows_the_platform_convention(self):
        with patch.object(server.sys, "platform", "win32"), patch.dict(
            os.environ, {"LOCALAPPDATA": "/tmp/localappdata"}
        ):
            self.assertEqual(
                server.default_token_file(),
                Path("/tmp/localappdata/BugNarrator/LocalTranscription") / server.TOKEN_FILE_NAME,
            )
        with patch.object(server.sys, "platform", "darwin"):
            self.assertEqual(
                server.default_token_file(),
                Path.home()
                / "Library"
                / "Application Support"
                / "BugNarrator"
                / "LocalTranscription"
                / server.TOKEN_FILE_NAME,
            )

    def test_the_token_path_matches_the_shared_contract_fixture(self):
        fixture = json.loads(
            (Path(__file__).parent.parent / "contract-fixtures" / "local-server-token.json").read_text()
        )
        self.assertEqual(server.TOKEN_FILE_NAME, fixture["tokenFileName"])
        self.assertEqual(
            server.TOKEN_ENVIRONMENT_VARIABLE,
            fixture["environmentVariable"],
        )

        with patch.object(server.sys, "platform", "darwin"):
            self.assertEqual(
                server.default_token_file(),
                Path.home()
                / fixture["macos"]["directoryRelativeToHome"]
                / fixture["tokenFileName"],
            )

        with patch.object(server.sys, "platform", "win32"), patch.dict(
            os.environ, {"LOCALAPPDATA": "/tmp/localappdata"}
        ):
            self.assertEqual(
                server.default_token_file(),
                Path("/tmp/localappdata")
                / fixture["windows"]["directoryRelativeToLocalAppData"]
                / fixture["tokenFileName"],
            )

    def test_an_oversized_upload_is_refused_before_it_is_written(self):
        class FakeRequest:
            def __init__(self, headers):
                self.headers = headers

        server.configure_auth("s3cret-token-value", max_upload_bytes=1024)

        with self.assertRaises(server.HTTPException) as raised:
            server._reject_oversized_upload(FakeRequest({"content-length": "2048"}))
        self.assertEqual(raised.exception.status_code, 413)

        # A body that declares less than the limit is not refused on its word.
        server._reject_oversized_upload(FakeRequest({"content-length": "512"}))
        server._reject_oversized_upload(FakeRequest({}))

    def test_the_streaming_loop_enforces_the_upload_cap(self):
        import io

        from fastapi import UploadFile

        payload = b"\x00" * (2 * server._upload_piece_bytes + 17)
        upload = UploadFile(io.BytesIO(payload), filename="clip.m4a")
        server.configure_auth("s3cret-token-value", max_upload_bytes=1024)

        with self.assertRaises(server.HTTPException) as raised:
            asyncio.run(server.transcribe(file=upload, model="parakeet-tdt-0.6b-v3"))
        self.assertEqual(raised.exception.status_code, 413)


class ServerTransportAdmissionTests(unittest.TestCase):
    """The request has to be refused before its body reaches the disk.

    FastAPI parses a multipart body before it solves the route's
    dependencies, so a check that lives in a dependency runs only after the
    body has been spooled to disk. These tests send the headers of a request
    and read the answer without sending the body at all: the server has to
    answer from the headers alone.
    """

    def _free_port(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            return listener.getsockname()[1]

    def _serve(self, token, port, token_file, max_upload_mb=None):
        extra = "" if max_upload_mb is None else f', "--max-upload-mb", "{max_upload_mb}"'
        script = f"""
import sys
sys.argv = ["server", "--host", "127.0.0.1", "--port", "{port}", "--token-file", r"{token_file}", "--lazy"{extra}]
import server
server.main()
"""
        environment = dict(os.environ)
        environment[server.TOKEN_ENVIRONMENT_VARIABLE] = token
        environment["PYTHONUNBUFFERED"] = "1"
        process = subprocess.Popen(
            [sys.executable, "-c", script],
            cwd=Path(__file__).parent,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=environment,
        )
        self.addCleanup(self._stop, process)
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            if process.poll() is not None:
                self.fail("the transcription server exited before accepting connections")
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                    return process
            except OSError:
                time.sleep(0.05)
        self.fail("the transcription server did not start within 20 seconds")

    def _stop(self, process):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()

    def _headers_only(self, port, request_line, headers, timeout=60.0):
        """Send a request's headers and read the status line, sending no body."""
        request = request_line + "\r\n"
        request += "".join(f"{name}: {value}\r\n" for name, value in headers)
        request += "\r\n"
        with socket.create_connection(("127.0.0.1", port), timeout=timeout) as connection:
            connection.settimeout(timeout)
            connection.sendall(request.encode("latin-1"))
            data = b""
            try:
                while b"\r\n" not in data:
                    chunk = connection.recv(4096)
                    if not chunk:
                        break
                    data += chunk
            except socket.timeout:
                self.fail(
                    "the server waited for the request body before answering; "
                    "the body would have been spooled to disk first"
                )
            return data.decode("latin-1", "replace")

    def test_an_unauthenticated_upload_is_refused_before_the_body_is_read(self):
        port = self._free_port()
        with tempfile.TemporaryDirectory() as directory:
            self._serve("s3cret-token-value", port, str(Path(directory) / server.TOKEN_FILE_NAME))

            response = self._headers_only(
                port,
                "POST /v1/audio/transcriptions HTTP/1.1",
                [
                    ("Host", f"127.0.0.1:{port}"),
                    ("Content-Type", "multipart/form-data; boundary=boundary"),
                    ("Content-Length", str(512 * 1024 * 1024)),
                ],
            )
        self.assertIn("401", response.split("\r\n")[0])

    def test_an_oversized_declared_upload_is_refused_before_the_body_is_read(self):
        port = self._free_port()
        with tempfile.TemporaryDirectory() as directory:
            self._serve(
                "s3cret-token-value",
                port,
                str(Path(directory) / server.TOKEN_FILE_NAME),
                max_upload_mb=1,
            )

            response = self._headers_only(
                port,
                "POST /v1/audio/transcriptions HTTP/1.1",
                [
                    ("Host", f"127.0.0.1:{port}"),
                    ("Authorization", "Bearer s3cret-token-value"),
                    ("Content-Type", "multipart/form-data; boundary=boundary"),
                    ("Content-Length", str(64 * 1024 * 1024)),
                ],
            )
        self.assertIn("413", response.split("\r\n")[0])

    def test_a_chunked_upload_over_the_cap_is_refused(self):
        port = self._free_port()
        with tempfile.TemporaryDirectory() as directory:
            self._serve(
                "s3cret-token-value",
                port,
                str(Path(directory) / server.TOKEN_FILE_NAME),
                max_upload_mb=1,
            )

            request = (
                "POST /v1/audio/transcriptions HTTP/1.1\r\n"
                f"Host: 127.0.0.1:{port}\r\n"
                "Authorization: Bearer s3cret-token-value\r\n"
                "Content-Type: multipart/form-data; boundary=boundary\r\n"
                "Transfer-Encoding: chunked\r\n\r\n"
            )
            # A well-formed multipart body, so the request fails on the size
            # ceiling rather than on the parser.
            body = (
                b"--boundary\r\n"
                b'Content-Disposition: form-data; name="file"; filename="clip.m4a"\r\n'
                b"Content-Type: application/octet-stream\r\n\r\n"
                + b"x" * (3 * 1024 * 1024)
                + b"\r\n--boundary--\r\n"
            )
            with socket.create_connection(("127.0.0.1", port), timeout=60) as connection:
                connection.settimeout(60)
                connection.sendall(request.encode("latin-1"))
                sent = 0
                try:
                    while sent < len(body):
                        chunk = body[sent : sent + 65536]
                        sent += len(chunk)
                        connection.sendall(f"{len(chunk):x}\r\n".encode("latin-1") + chunk + b"\r\n")
                except (BrokenPipeError, ConnectionResetError):
                    pass
                try:
                    connection.sendall(b"0\r\n\r\n")
                except (BrokenPipeError, ConnectionResetError):
                    pass
                data = b""
                try:
                    while b"\r\n" not in data:
                        chunk = connection.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                except socket.timeout:
                    self.fail("the server did not answer the oversized chunked upload")
        self.assertIn("413", data.decode("latin-1", "replace").split("\r\n")[0])

    def test_a_non_ascii_token_is_refused_with_401(self):
        port = self._free_port()
        with tempfile.TemporaryDirectory() as directory:
            self._serve("s3cret-token-value", port, str(Path(directory) / server.TOKEN_FILE_NAME))

            status, _ = self._request(
                f"http://127.0.0.1:{port}/health",
                token="ééé",
            )
        self.assertEqual(status, 401)

    def test_the_documentation_routes_are_not_served(self):
        port = self._free_port()
        with tempfile.TemporaryDirectory() as directory:
            self._serve("s3cret-token-value", port, str(Path(directory) / server.TOKEN_FILE_NAME))
            base = f"http://127.0.0.1:{port}"

            for path in ("/docs", "/redoc", "/openapi.json"):
                status, _ = self._request(f"{base}{path}")
                self.assertNotEqual(status, 200, f"{path} is served without the token")
                status, _ = self._request(f"{base}{path}", token="s3cret-token-value")
                self.assertEqual(status, 404, f"{path} is served")

    def _request(self, url, token=None, data=None, method=None):
        import http.client
        from urllib.parse import urlsplit

        parts = urlsplit(url)
        path = parts.path or "/"
        headers = {}
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        connection = http.client.HTTPConnection(parts.hostname, parts.port, timeout=30)
        try:
            connection.request(method or "GET", path, body=data, headers=headers)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()


class ServerTokenFileAndChildProcessTests(unittest.TestCase):
    def test_the_token_file_mode_is_repaired_when_it_is_rewritten(self):
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / server.TOKEN_FILE_NAME
            token_file.write_text("an-old-token", encoding="utf-8")
            os.chmod(token_file, 0o644)

            server.write_token_file(token_file, "s3cret-token-value")

            self.assertEqual(token_file.read_text(encoding="utf-8"), "s3cret-token-value")
            if os.name != "nt":
                self.assertEqual(stat.S_IMODE(token_file.stat().st_mode), 0o600)
            else:
                # Windows has no POSIX permission bits, so there is no mode to
                # repair: os.chmod only toggles the read-only attribute and
                # the file's access is decided by the access control list it
                # inherits from its directory. What the repair can be checked
                # for there is that the file was not left read-only, which
                # would keep the server from rewriting it.
                self.assertTrue(token_file.stat().st_mode & stat.S_IWRITE)

    def test_the_mode_is_repaired_before_the_token_is_written(self):
        # The token must never sit in a file that everyone can read, not even
        # for the moment between the write and the repair.
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / server.TOKEN_FILE_NAME
            token_file.write_text("an-old-token", encoding="utf-8")
            os.chmod(token_file, 0o644)

            token_visible_when_repaired = []
            real_chmod = os.chmod

            def recording_chmod(path, mode, *args, **kwargs):
                if os.fspath(path) == os.fspath(token_file):
                    token_visible_when_repaired.append(
                        "s3cret-token-value" in token_file.read_text(encoding="utf-8")
                    )
                return real_chmod(path, mode, *args, **kwargs)

            with patch.object(server.os, "chmod", recording_chmod):
                server.write_token_file(token_file, "s3cret-token-value")

            self.assertTrue(token_visible_when_repaired, "the mode was never repaired")
            self.assertEqual(
                token_visible_when_repaired[0],
                False,
                "the mode must be repaired before the token is written",
            )

    def test_the_token_is_not_handed_to_a_child_process(self):
        environment = dict(os.environ)
        environment[server.TOKEN_ENVIRONMENT_VARIABLE] = "s3cret-token-value"
        with patch.dict(os.environ, environment, clear=True):
            child_environment = server._child_environment()

        self.assertNotIn(server.TOKEN_ENVIRONMENT_VARIABLE, child_environment)


if __name__ == "__main__":
    unittest.main()
