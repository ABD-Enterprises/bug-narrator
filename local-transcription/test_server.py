import asyncio
import inspect
import hashlib
import hmac
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
        # A custom id is accepted when it is the one this server was told to
        # load. An id a request invents is refused - see the unknown-id test.
        server.configure_default_model("mlx-community/custom-parakeet")
        self.assertEqual(
            server._resolve_model_id("mlx-community/custom-parakeet"),
            "mlx-community/custom-parakeet",
        )

    def test_the_canonical_id_resolves_to_the_configured_default(self):
        # The operator configured a different model, so a request that names
        # the canonical id must not pull the upstream repository instead: the
        # server loads the model it was configured to load, and only that.
        server.configure_default_model("/Users/operator/models/parakeet")

        self.assertEqual(
            server._resolve_model_id("mlx-community/parakeet-tdt-0.6b-v3"),
            "/Users/operator/models/parakeet",
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
            "Local transcription failed. The details are in the local transcription server's output.",
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

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg is required")
    def test_decoder_rejects_playlists_that_reference_other_local_audio(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sibling = root / "private.mp3"
            subprocess.run(
                ["ffmpeg", "-nostdin", "-loglevel", "error", "-f", "lavfi",
                 "-i", "sine=frequency=440:duration=1", "-y", str(sibling)],
                check=True, capture_output=True,
            )
            uploads = root / "uploads"
            uploads.mkdir()
            playlist = uploads / "upload.m3u8"
            playlist.write_text(
                "#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\n"
                + sibling.as_uri() + "\n#EXT-X-ENDLIST\n"
            )
            with self.assertRaises(RuntimeError):
                server._decode_audio_window(str(playlist), 0)
            # The same decoder still accepts the self-contained audio upload.
            decoded = server._decode_audio_window(str(sibling), 0)
            self.addCleanup(server._unlink_quietly, decoded)
            self.assertIsNotNone(decoded)

    def test_decoder_error_does_not_inject_log_control_text(self):
        failure = subprocess.CalledProcessError(
            1, "ffmpeg", stderr=b"invalid media\nFORGED\x1b[2J"
        )
        with patch.object(server.subprocess, "run", side_effect=failure):
            with self.assertRaises(RuntimeError) as caught:
                server._decode_audio_window("/tmp/synthetic.audio", 0)
        self.assertNotIn("\n", str(caught.exception))
        self.assertNotIn("\x1b", str(caught.exception))

    def test_hostile_wav_rate_cannot_expand_one_read_beyond_the_byte_budget(self):
        import io

        declared_size = 80 * 1024 * 1024
        header = (
            b"RIFF" + struct.pack("<I", declared_size + 36) + b"WAVEfmt "
            + struct.pack("<IHHIIHH", 16, 1, 2, 1_000_000_000, 4_000_000_000, 4, 16)
            + b"data" + struct.pack("<I", declared_size)
        )

        class VirtualWav(io.BytesIO):
            def __init__(self):
                super().__init__(header + bytes(4096))
                self.requests = []

            def seek(self, offset, whence=0):
                if whence == os.SEEK_END:
                    return super().seek(declared_size + 44 + offset)
                return super().seek(offset, whence)

            def read(self, count=-1):
                self.requests.append(count)
                return super().read(min(count, 4096))

        handle = VirtualWav()
        with patch.object(server, "open", return_value=handle, create=True):
            windows = server._wav_windows("/synthetic.wav", 120)
            _, rate, _ = next(windows)
            windows.close()
        self.assertEqual(rate, 1_000_000_000)
        self.assertLessEqual(max(handle.requests), server._pcm_window_byte_limit)
        self.assertEqual(max(handle.requests) % 4, 0)

    def test_byte_limited_windows_preserve_samples_and_offsets(self):
        import numpy as np

        path = self._write_wav(8000, 5)
        original = np.arange(40000, dtype="<i2")
        with wave.open(path, "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(8000)
            handle.writeframes(original.tobytes())
        # An odd byte budget must round down to a complete PCM frame.
        with patch.object(server, "_pcm_window_byte_limit", 32001):
            windows = list(server._wav_windows(path, 120))
        self.assertEqual([len(samples) for samples, _, _ in windows], [16000, 16000, 8000])
        self.assertEqual([offset for _, _, offset in windows], [0, 2, 4])
        self.assertTrue(all(rate == 8000 for _, rate, _ in windows))
        np.testing.assert_array_equal(
            np.concatenate([samples for samples, _, _ in windows]),
            original.astype(np.float32) / 32768.0,
        )

    def test_invalid_wav_encoding_is_refused_before_reading_sample_data(self):
        import io

        header = (
            b"RIFF" + struct.pack("<I", 40) + b"WAVEfmt "
            + struct.pack("<IHHIIHH", 16, 1, 2, 48000, 192000, 4, 65535)
            + b"data" + struct.pack("<I", 4) + bytes(4)
        )
        handle = io.BytesIO(header)
        with self.assertRaises(server.UnsupportedAudioError):
            server._parse_wav(handle)
        self.assertLessEqual(handle.tell(), 44)

    def test_a_wedged_ffmpeg_is_stopped_instead_of_blocking_the_inference_worker(self):
        # ffmpeg is given one window, so it cannot legitimately take longer
        # than the window is long. Without a timeout a wedged ffmpeg holds the
        # single inference worker for ever and takes the local provider down
        # with it.
        # The window is a length of media, not of wall clock, so the timeout
        # carries headroom over it.
        self.assertGreaterEqual(server._ffmpeg_timeout_seconds, 2 * server._chunk_duration_seconds)
        created = []
        real_named_temp_file = server.tempfile.NamedTemporaryFile

        def recording_named_temp_file(*args, **kwargs):
            handle = real_named_temp_file(*args, **kwargs)
            created.append(handle.name)
            return handle

        with patch.object(
            server.subprocess,
            "run",
            side_effect=subprocess.TimeoutExpired("ffmpeg", 120),
        ) as run, patch.object(
            server.tempfile,
            "NamedTemporaryFile",
            side_effect=recording_named_temp_file,
        ):
            with self.assertRaises(RuntimeError) as caught:
                server._decode_audio_window("/nonexistent/recording.wav", 0)

        self.assertIn("did not finish", str(caught.exception))
        # The timeout is the mechanism that bounds a wedged ffmpeg: without the
        # kwarg the child is never killed, and the handler above would still
        # pass this test.
        self.assertEqual(run.call_args.kwargs.get("timeout"), server._ffmpeg_timeout_seconds)
        # The half-decoded window must not be left behind on disk.
        self.assertTrue(created)
        self.assertFalse(server.os.path.exists(created[-1]))

    def test_the_health_answer_carries_no_local_path(self):
        # The health route answers the client's challenge without a token, so
        # every local account on the machine can read that answer. The full
        # detail stays in the server's own log.
        #
        # The failure has to go through the server's own path: setting
        # _model_load_error by hand would only prove the helper works, and
        # the server could stop calling it without any test noticing.
        server._model_load_state = "not_loaded"
        server._model_load_error = None
        self.addCleanup(setattr, server, "_model_load_state", "not_loaded")
        self.addCleanup(setattr, server, "_model_load_error", None)

        failure = (
            "No such file or directory: '/Users/victim/Library/Application Support/"
            "BugNarrator/LocalTranscription/Models/parakeet/config.json'"
        )
        with patch.object(server, "get_model", side_effect=RuntimeError(failure)):
            server._load_model_in_background("a-model")
            deadline = time.time() + 5
            while server._model_load_state != "failed" and time.time() < deadline:
                # Bounded polling waits for a test server, not production work.
                # nosemgrep: security.semgrep.python.lang.best-practice.sleep.arbitrary-sleep
                time.sleep(0.02)

        self.assertEqual(server._model_load_state, "failed")
        health = asyncio.run(server.health())

        self.assertNotIn("/Users/victim", health["model_error"])
        self.assertNotIn("Application Support", health["model_error"])
        self.assertNotIn("config.json", health["model_error"])
        # The published answer is one of the server's own fixed messages, so
        # no part of the loader's text can reach a caller that only knows
        # the port.
        self.assertIn(
            health["model_error"],
            (server._PUBLIC_MODEL_ERROR_MISSING, server._PUBLIC_MODEL_ERROR_FAILED),
        )

    def test_a_url_in_the_model_error_is_not_mistaken_for_a_local_path(self):
        message = "could not fetch https://huggingface.co/parakeet/config.json"

        # The published answer carries one of the server's own fixed
        # messages, so neither the URL nor anything else from the loader's
        # text can reach the token-free health route.
        published = server._public_model_error(message)

        self.assertEqual(published, server._PUBLIC_MODEL_ERROR_FAILED)
        self.assertNotIn("huggingface.co", published)

    def test_a_windows_profile_path_never_reaches_the_health_answer(self):
        # The same server ships on Windows, where the managed model
        # directory sits under %LocalAppData% and the loader's error text
        # carries a backslash path with the account name in it.
        server._model_load_state = "not_loaded"
        server._model_load_error = None
        self.addCleanup(setattr, server, "_model_load_state", "not_loaded")
        self.addCleanup(setattr, server, "_model_load_error", None)

        failure = (
            "Could not open C:\\Users\\Bob\\AppData\\Local\\BugNarrator\\"
            "LocalTranscription\\Models\\parakeet\\config.json"
        )
        with patch.object(server, "get_model", side_effect=RuntimeError(failure)):
            server._load_model_in_background("a-model")
            deadline = time.time() + 5
            while server._model_load_state != "failed" and time.time() < deadline:
                # Bounded polling waits for a test server, not production work.
                # nosemgrep: security.semgrep.python.lang.best-practice.sleep.arbitrary-sleep
                time.sleep(0.02)

        health = asyncio.run(server.health())

        self.assertNotIn("Bob", health["model_error"])
        self.assertNotIn("AppData", health["model_error"])
        self.assertNotIn("\\", health["model_error"])
        self.assertEqual(health["model_error"], server._PUBLIC_MODEL_ERROR_FAILED)

    def test_the_health_answer_does_not_publish_a_local_path_as_the_model_name(self):
        # An operator may point the server at a model in a local directory.
        # That path names the user's account and cache layout, and it may be
        # absolute, drive-qualified, tilde-relative, relative or wrapped in
        # a file:// URL, so only a bare model id is published.
        server._model_name = None
        self.addCleanup(setattr, server, "_model_name", None)

        for name in (
            "/Users/operator/models/parakeet",
            "C:\\Users\\operator\\models\\parakeet",
            "file:///Users/operator/models/parakeet",
            "~/models/parakeet",
            "./models/parakeet",
            # A relative path is shaped like an "owner/name" repository id, so
            # only the ids this server knows are published.
            "models/parakeet",
            "parakeet-local",
        ):
            server._model_name = name
            health = asyncio.run(server.health())

            self.assertEqual(health["model_name"], "custom", f"the path was published: {name}")

        # A model id is published as it is. No client reads it back - the
        # app shows the model from its own settings - but a caller that
        # already answered the challenge may read it.
        server._model_name = "mlx-community/parakeet-tdt-0.6b-v3"
        health = asyncio.run(server.health())

        self.assertEqual(health["model_name"], "mlx-community/parakeet-tdt-0.6b-v3")

        # Every id the server knows is published, not just the canonical one.
        server._model_name = "nvidia/parakeet-tdt-0.6b-v3"
        health = asyncio.run(server.health())

        self.assertEqual(health["model_name"], "nvidia/parakeet-tdt-0.6b-v3")

    def test_an_http_error_is_rendered_in_the_envelope_the_clients_read(self):
        # FastAPI's own body for an HTTP error is {"detail": ...}. Both
        # shipped clients read {"error": {"message": ...}} and fall back to
        # the bare status text when they cannot find one, so the actionable
        # message - "the upload exceeds the limit" - would be lost.
        limit = server._max_upload_bytes
        response = asyncio.run(server._error_envelope(
            None,
            server.HTTPException(
                status_code=413,
                detail=f"The upload exceeds the {limit} byte limit",
            ),
        ))

        self.assertEqual(response.status_code, 413)
        payload = json.loads(response.body)
        self.assertEqual(
            payload["error"]["message"],
            f"The upload exceeds the {limit} byte limit",
        )
        self.assertEqual(payload["error"]["type"], "invalid_request_error")

    def test_transcription_route_keeps_http_event_loop_async(self):
        self.assertTrue(inspect.iscoroutinefunction(server.transcribe))

    def test_a_failed_preload_reports_the_failure_to_the_health_check(self):
        # The loader runs in a thread, and the state it sets has to reach the
        # module. A local assignment in the loader would leave the server
        # reporting "loading" for ever after a failure, so the app would wait
        # for a model that is never going to arrive.
        server._model_load_state = "not_loaded"
        server._model_load_error = None
        self.addCleanup(setattr, server, "_model_load_state", "not_loaded")
        self.addCleanup(setattr, server, "_model_load_error", None)

        with patch.object(server, "get_model", side_effect=RuntimeError("the model is missing")):
            server._load_model_in_background("a-model")
            deadline = time.time() + 5
            while server._model_load_state != "failed" and time.time() < deadline:
                # Bounded polling waits for a test server, not production work.
                # nosemgrep: security.semgrep.python.lang.best-practice.sleep.arbitrary-sleep
                time.sleep(0.02)

        self.assertEqual(server._model_load_state, "failed")
        # The published error is one of the server's own fixed messages; the
        # loader's own text stays in the log, which only the user reads.
        self.assertEqual(server._model_load_error, server._PUBLIC_MODEL_ERROR_MISSING)
        self.assertNotIn("the model is missing", server._model_load_error)

        health = asyncio.run(server.health())
        self.assertEqual(health["status"], "degraded")
        self.assertEqual(health["model_error"], server._PUBLIC_MODEL_ERROR_MISSING)

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
        # Fixed test interpreter and fixture script; no user input or shell.
        # nosemgrep: security.semgrep.python.lang.security.audit.dangerous-subprocess-use-audit.dangerous-subprocess-use-audit
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
                    # Bounded polling waits for a test server, not production work.
                    # nosemgrep: security.semgrep.python.lang.best-practice.sleep.arbitrary-sleep
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

        upload = UploadFile(io.BytesIO(b"\x00\x00\x00\x18ftypM4A "), filename="fixture\nFORGED\x1b[2J.m4a")
        with self.assertLogs(server.logger, level="INFO") as captured, patch.object(server, "get_model", return_value=NeverCalled()):
            response = asyncio.run(server.transcribe(file=upload, model="parakeet-tdt-0.6b-v3"))

        self.assertNotIn("FORGED", "\n".join(captured.output))
        self.assertNotIn("\x1b", "\n".join(captured.output))
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
            seen["path"] = path
            return server._Transcription("ok", [])

        upload = UploadFile(io.BytesIO(payload), filename="clip.m4a\nFORGED\x1b[2J")
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
        self.assertEqual(Path(seen["path"]).suffix, ".audio")
        self.assertNotIn("FORGED", seen["path"])
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

    def test_model_identifiers_reject_log_control_text_and_excessive_length(self):
        for value in ["repo/model\nFORGED", "repo/model\n", "\n", "repo/model\x1b[2J", "repo/\u202emodel", "x" * 4097, " " * 4097]:
            with self.subTest(value=value[:20]):
                with self.assertRaises(server.HTTPException) as caught:
                    server._resolve_model_id(value)
                self.assertEqual(caught.exception.status_code, 400)
                self.assertNotIn(value, caught.exception.detail)

    def test_a_model_id_the_server_was_not_configured_for_is_refused(self):
        # The id reaches the model loader as a repo id or a local directory,
        # and the loader turns any hub error into a local path. An
        # unrestricted value therefore lets a caller read local files
        # (config.json, model.safetensors) and load weights from a repo it
        # chooses, at a revision that is not pinned to a digest.
        for value in [
            "owner/model",
            "/synthetic/model directory",
            "../../../../Users/victim/model",
            "attacker/evil-repo",
        ]:
            with self.subTest(value=value):
                with self.assertRaises(server.HTTPException) as caught:
                    server._resolve_model_id(value)
                self.assertEqual(caught.exception.status_code, 400)

    def test_invalid_multipart_model_never_reaches_logs_or_inference(self):
        async def request(value):
            body = (
                "--fixture-boundary\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n"
                + value + "\r\n--fixture-boundary\r\n"
                + "Content-Disposition: form-data; name=\"file\"; filename=\"fixture.wav\"\r\n"
                + "Content-Type: audio/wav\r\n\r\nsynthetic\r\n--fixture-boundary--\r\n"
            ).encode()
            scope = {
                "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1",
                "method": "POST", "scheme": "http", "path": "/v1/audio/transcriptions",
                "raw_path": b"/v1/audio/transcriptions", "query_string": b"",
                "server": ("127.0.0.1", 8422), "client": ("127.0.0.1", 12345),
                "headers": [
                    (b"host", b"127.0.0.1:8422"),
                    (b"authorization", b"Bearer fixture-token"),
                    (b"content-type", b"multipart/form-data; boundary=fixture-boundary"),
                    (b"content-length", str(len(body)).encode()),
                ],
            }
            sent = False
            messages = []

            async def receive():
                nonlocal sent
                if sent:
                    return {"type": "http.disconnect"}
                sent = True
                return {"type": "http.request", "body": body, "more_body": False}

            async def send(message):
                messages.append(message)

            await server.app(scope, receive, send)
            return messages

        for value in ["repo/model\nFORGED", "repo/model\n", "\n", " " * 4097]:
            with self.subTest(value=value[:20]), patch.object(server, "_auth_token", "fixture-token"):
                with patch.object(server.logger, "info") as info, patch.object(server, "_run_inference") as inference:
                    messages = asyncio.run(request(value))
                status = next(message["status"] for message in messages if message["type"] == "http.response.start")
                self.assertEqual(status, 400)
                info.assert_not_called()
                inference.assert_not_called()
                # The refusal uses the error envelope the clients know how to
                # read, not a bare "detail" they cannot parse.
                body = b"".join(
                    message.get("body", b"")
                    for message in messages
                    if message["type"] == "http.response.body"
                )
                payload = json.loads(body)
                self.assertIn("error", payload)
                self.assertNotIn("detail", payload)
                self.assertNotIn(value, json.dumps(payload))

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
    """Every route refuses a request that does not carry the server's token
    (#1270); the health check's proof challenge is the one exception.

    Without the token any process on the machine could drive the model and
    receive the user's microphone audio, and a rogue listener that grabbed the
    port first looked like a healthy server.
    """

    def setUp(self):
        self._previous_token = server._auth_token
        self._previous_max_upload_bytes = server._max_upload_bytes
        self.addCleanup(setattr, server, "_auth_token", self._previous_token)
        self.addCleanup(setattr, server, "_max_upload_bytes", self._previous_max_upload_bytes)

    def _request(self, url, token=None, data=None, method=None, headers=None):
        import http.client
        from urllib.parse import urlsplit

        parts = urlsplit(url)
        path = parts.path or "/"
        if parts.query:
            path = f"{path}?{parts.query}"
        headers = dict(headers or {})
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        connection = http.client.HTTPConnection(parts.hostname, parts.port, timeout=30)
        try:
            connection.request(method or "GET", path, body=data, headers=headers)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def test_the_health_check_answers_a_challenge_with_a_proof(self):
        """The server has to prove that it is the server (#1270).

        A listener that answers on the port is not the server, and the app
        must not learn the token from the first request it sends. So the
        challenge carries a nonce and no token, and the answer carries an
        HMAC of the nonce and bound authority that only a peer knowing the
        token can produce.
        """
        import http.client
        from urllib.parse import urlsplit

        token = "s3cret-token-value"
        port = 8477
        token_file = Path(self.enterContext(tempfile.TemporaryDirectory())) / "token"
        self._serve(token, port, token_file)
        base = f"http://127.0.0.1:{port}"
        parts = urlsplit(base)

        connection = http.client.HTTPConnection(parts.hostname, parts.port, timeout=30)
        try:
            connection.request(
                "GET",
                "/health",
                headers={server.CHALLENGE_HEADER: "the-nonce"},
            )
            response = connection.getresponse()
            body = response.read()
            proof = response.getheader(server.PROOF_HEADER)
        finally:
            connection.close()

        self.assertEqual(response.status, 200)
        self.assertIsNotNone(proof)
        # Bind the proof to the configured endpoint, not the request Host header.
        self.assertEqual(
            proof,
            hmac.new(token.encode(), f"the-nonce\n127.0.0.1:{port}".encode(), hashlib.sha256).hexdigest(),
        )
        self.assertIn("model_loaded", json.loads(body))

    def test_health_proof_is_bound_to_the_server_and_cannot_be_relayed(self):
        import http.client
        from http.server import BaseHTTPRequestHandler, HTTPServer

        token = "s3cret-token-value"
        nonce = "relay-test-nonce"
        ports = []
        for _ in range(2):
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                ports.append(listener.getsockname()[1])
            token_file = Path(self.enterContext(tempfile.TemporaryDirectory())) / "token"
            self._serve(token, ports[-1], token_file)

        def challenge(port):
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
            try:
                # A forged Host must not change the server's bound authority.
                connection.request("GET", "/health", headers={
                    server.CHALLENGE_HEADER: nonce, "Host": "relay.invalid:9999",
                })
                response = connection.getresponse()
                body = response.read()
                self.assertEqual(response.status, 200)
                return body, response.getheader(server.PROOF_HEADER)
            finally:
                connection.close()

        proofs = [challenge(port)[1] for port in ports]
        self.assertNotEqual(*proofs)
        for port, proof in zip(ports, proofs):
            expected = hmac.new(
                token.encode(), f"{nonce}\n127.0.0.1:{port}".encode(), hashlib.sha256,
            ).hexdigest()
            self.assertEqual(proof, expected)

        class Relay(BaseHTTPRequestHandler):
            def do_GET(self):
                connection = http.client.HTTPConnection("127.0.0.1", ports[0], timeout=30)
                try:
                    connection.request("GET", self.path, headers={
                        server.CHALLENGE_HEADER: self.headers[server.CHALLENGE_HEADER],
                    })
                    upstream = connection.getresponse()
                    body = upstream.read()
                    self.send_response(upstream.status)
                    self.send_header(server.PROOF_HEADER, upstream.getheader(server.PROOF_HEADER))
                    self.end_headers()
                    self.wfile.write(body)
                finally:
                    connection.close()

            def log_message(self, *_args):
                pass

        relay = HTTPServer(("127.0.0.1", 0), Relay)
        thread = threading.Thread(target=relay.serve_forever, daemon=True)
        thread.start()
        try:
            relay_port = relay.server_address[1]
            _, relayed_proof = challenge(relay_port)
            self.assertEqual(relayed_proof, proofs[0])
            expected_for_relay = hmac.new(
                token.encode(), f"{nonce}\n127.0.0.1:{relay_port}".encode(), hashlib.sha256,
            ).hexdigest()
            self.assertNotEqual(relayed_proof, expected_for_relay)
        finally:
            relay.shutdown()
            relay.server_close()
            thread.join()

    def test_a_health_request_without_a_token_or_a_challenge_is_refused(self):
        port = 8478
        token_file = Path(self.enterContext(tempfile.TemporaryDirectory())) / "token"
        self._serve("s3cret-token-value", port, token_file)

        status, _ = self._request(f"http://127.0.0.1:{port}/health")

        self.assertEqual(status, 401)

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
        # Fixed test interpreter and fixture script; no user input or shell.
        # nosemgrep: security.semgrep.python.lang.security.audit.dangerous-subprocess-use-audit.dangerous-subprocess-use-audit
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
                # Bounded polling waits for a test server, not production work.
                # nosemgrep: security.semgrep.python.lang.best-practice.sleep.arbitrary-sleep
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

    def test_proof_differs_for_each_configured_bind_authority(self):
        self.addCleanup(setattr, server, "_auth_token", server._auth_token)
        self.addCleanup(setattr, server, "_auth_authority", server._auth_authority)
        proofs = []
        for authority in ["127.0.0.1:8422", "127.0.0.1:8423", "localhost:8422", "[::1]:8422"]:
            server.configure_auth("token", authority=authority)
            proof = server.proof_for_nonce("nonce")
            self.assertEqual(proof, hmac.new(
                b"token", f"nonce\n{authority}".encode(), hashlib.sha256,
            ).hexdigest())
            proofs.append(proof)
        self.assertEqual(len(set(proofs)), len(proofs))
        server.configure_auth("token", authority="LOCALHOST:8422")
        self.assertEqual(server.proof_for_nonce("nonce"), proofs[2])

    def test_the_token_path_matches_the_shared_contract_fixture(self):
        fixture = json.loads(
            (Path(__file__).parent.parent / "contract-fixtures" / "local-server-token.json").read_text()
        )
        self.assertEqual(server.TOKEN_FILE_NAME, fixture["tokenFileName"])
        self.assertEqual(
            server.TOKEN_ENVIRONMENT_VARIABLE,
            fixture["environmentVariable"],
        )
        self.assertEqual(server.CHALLENGE_HEADER, fixture["challengeHeader"])
        self.assertEqual(server.PROOF_HEADER, fixture["proofHeader"])
        # The three ports have to compute the same proof from the same inputs,
        # or the app and the server would never agree on it.
        vector = fixture["proofVector"]
        previous_token = server._auth_token
        self.addCleanup(setattr, server, "_auth_token", previous_token)
        self.addCleanup(setattr, server, "_auth_authority", server._auth_authority)
        server.configure_auth(vector["token"], authority=vector["authority"])
        self.assertEqual(
            server.proof_for_nonce(vector["nonce"]),
            vector["proof"],
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


class ServerErrorEnvelopeTests(unittest.TestCase):
    """Every refusal the server sends has to carry the envelope the clients read.

    Both shipped clients read {"error": {"message": ...}} and fall back to a
    status-derived message when they cannot find one, so a refusal in
    FastAPI's own {"detail": ...} shape loses the actionable message - "the
    upload exceeds the limit", "missing authorization header".

    These tests drive the ASGI app itself, so they fail when a refusal stops
    carrying the envelope - whether it is refused by the admission middleware
    before the router sees the request, or by the handler that renders an
    HTTPError raised inside a route.
    """

    def setUp(self):
        self._previous_token = server._auth_token
        self._previous_limit = server._max_upload_bytes
        self.addCleanup(setattr, server, "_auth_token", self._previous_token)
        self.addCleanup(setattr, server, "_max_upload_bytes", self._previous_limit)
        server.configure_auth("s3cret-token-value", max_upload_bytes=1024)

    async def _answer(self, scope, body=b""):
        delivered = False
        messages = []

        async def receive():
            nonlocal delivered
            if delivered:
                return {"type": "http.disconnect"}
            delivered = True
            return {"type": "http.request", "body": body, "more_body": False}

        async def send(message):
            messages.append(message)

        await server.app(scope, receive, send)
        status = next(
            message["status"] for message in messages if message["type"] == "http.response.start"
        )
        payload = b"".join(
            message.get("body", b"")
            for message in messages
            if message["type"] == "http.response.body"
        )
        return status, json.loads(payload)

    def _scope(self, path, method="GET", headers=(), content_length=None):
        all_headers = [(b"host", b"127.0.0.1:8422"), *headers]
        if content_length is not None:
            all_headers.append((b"content-length", str(content_length).encode()))
        return {
            "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1",
            "method": method, "scheme": "http", "path": path,
            "raw_path": path.encode(), "query_string": b"",
            "server": ("127.0.0.1", 8422), "client": ("127.0.0.1", 12345),
            "headers": all_headers,
        }

    def _assert_envelope(self, payload, message):
        self.assertIn("error", payload)
        self.assertNotIn("detail", payload)
        self.assertEqual(payload["error"]["message"], message)
        self.assertEqual(payload["error"]["type"], "invalid_request_error")

    def test_a_refused_request_is_answered_in_the_envelope_the_clients_read(self):
        # The middleware refuses this before the router sees it, so the
        # envelope has to be rendered by the refusal itself.
        status, payload = asyncio.run(self._answer(self._scope("/v1/models")))

        self.assertEqual(status, 401)
        self._assert_envelope(payload, "Missing Authorization header")

    def test_a_declared_oversized_upload_is_answered_in_the_envelope(self):
        # Same path: the admission middleware refuses the declared length
        # before the body is read, so its own answer has to carry the
        # envelope rather than a bare "detail".
        scope = self._scope(
            "/v1/audio/transcriptions",
            method="POST",
            headers=[
                (b"authorization", b"Bearer s3cret-token-value"),
                (b"content-type", b"multipart/form-data; boundary=boundary"),
            ],
            content_length=64 * 1024 * 1024,
        )
        status, payload = asyncio.run(self._answer(scope))

        self.assertEqual(status, 413)
        self._assert_envelope(payload, "The upload exceeds the 1024 byte limit")

    def test_an_oversized_body_is_answered_in_the_envelope(self):
        # No declared length here, so the refusal comes from the route that
        # reads the body, and the handler that renders an HTTPError is the one
        # that has to carry the envelope.
        body = (
            b"--boundary\r\n"
            b'Content-Disposition: form-data; name="file"; filename="clip.wav"\r\n'
            b"Content-Type: audio/wav\r\n\r\n"
            + b"x" * 4096
            + b"\r\n--boundary--\r\n"
        )
        scope = self._scope(
            "/v1/audio/transcriptions",
            method="POST",
            headers=[
                (b"authorization", b"Bearer s3cret-token-value"),
                (b"content-type", b"multipart/form-data; boundary=boundary"),
            ],
        )
        status, payload = asyncio.run(self._answer(scope, body))

        self.assertEqual(status, 413)
        self._assert_envelope(payload, "The upload exceeds the 1024 byte limit")

    def test_an_unknown_route_is_answered_in_the_envelope(self):
        # Starlette raises its own HTTPException for a route that does not
        # exist, not FastAPI's, so this refusal is rendered by the framework
        # default unless the envelope is registered for the base class too.
        scope = self._scope("/v1/no-such-route", headers=[(b"authorization", b"Bearer s3cret-token-value")])
        status, payload = asyncio.run(self._answer(scope))

        self.assertEqual(status, 404)
        self._assert_envelope(payload, "Not Found")

    def test_a_wrong_method_is_answered_in_the_envelope(self):
        scope = self._scope(
            "/v1/models",
            method="POST",
            headers=[(b"authorization", b"Bearer s3cret-token-value")],
        )
        status, payload = asyncio.run(self._answer(scope))

        self.assertEqual(status, 405)
        self._assert_envelope(payload, "Method Not Allowed")

    def test_a_request_that_is_not_the_expected_upload_is_answered_in_the_envelope(self):
        # A body the server cannot read as its upload fails validation, and
        # FastAPI answers that with {"detail": [...]} unless it is given its
        # own handler.
        scope = self._scope(
            "/v1/audio/transcriptions",
            method="POST",
            headers=[
                (b"authorization", b"Bearer s3cret-token-value"),
                (b"content-type", b"multipart/form-data; boundary=boundary"),
            ],
        )
        body = (
            b"--boundary\r\n"
            b'Content-Disposition: form-data; name="model"\r\n\r\n'
            b"parakeet-tdt-0.6b-v3\r\n"
            b"--boundary--\r\n"
        )
        status, payload = asyncio.run(self._answer(scope, body))

        self.assertEqual(status, 422)
        self._assert_envelope(payload, "The request is not a valid upload.")


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
        # Fixed test interpreter and fixture script; no user input or shell.
        # nosemgrep: security.semgrep.python.lang.security.audit.dangerous-subprocess-use-audit.dangerous-subprocess-use-audit
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
                # Bounded polling waits for a test server, not production work.
                # nosemgrep: security.semgrep.python.lang.best-practice.sleep.arbitrary-sleep
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
    def test_the_token_file_is_replaced_with_one_only_its_owner_can_read(self):
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
                # set: os.chmod only toggles the read-only attribute and the
                # file's access is decided by the access control list it
                # inherits from its directory. What can be checked there is
                # that the file was not left read-only, which would keep the
                # server from rewriting it.
                self.assertTrue(token_file.stat().st_mode & stat.S_IWRITE)

    def test_the_token_is_written_into_a_file_only_its_owner_can_read(self):
        # The token must not sit in a file that everyone can read, not even for
        # the moment between the write and the file taking its place.
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / server.TOKEN_FILE_NAME

            modes = []
            real_replace = os.replace

            def recording_replace(source, destination):
                modes.append(os.stat(source).st_mode & 0o777)
                return real_replace(source, destination)

            with patch.object(server.os, "replace", recording_replace):
                server.write_token_file(token_file, "s3cret-token-value")

            self.assertEqual(
                len(modes), 1, "the token file was not replaced in one step"
            )
            if os.name != "nt":
                self.assertEqual(
                    modes[0], 0o600, "the token was written into a file anyone else can read"
                )
            else:
                self.assertTrue(
                    modes[0] & stat.S_IWRITE, "the token file was left read-only"
                )

    def test_the_token_file_is_never_left_empty_by_a_failed_write(self):
        # A failure while the token is written must not empty the file the
        # token was in: a client that reads an empty file mints a new token,
        # and the server keeps the old one.
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / server.TOKEN_FILE_NAME
            server.write_token_file(token_file, "s3cret-token-value")

            with patch.object(server.os, "replace", side_effect=OSError("no space left")):
                with self.assertRaises(OSError):
                    server.write_token_file(token_file, "another-token")

            self.assertEqual(
                token_file.read_text(encoding="utf-8"), "s3cret-token-value"
            )

    def test_a_token_that_cannot_be_stored_stops_the_server(self):
        # A token no client can find is a server nobody can talk to, so the
        # server refuses to start rather than run with one.
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / server.TOKEN_FILE_NAME

            with patch.object(server.tempfile, "mkstemp", side_effect=OSError("read-only")):
                with self.assertRaises(OSError):
                    server.resolve_auth_token(token_file=token_file)

    @unittest.skipUnless(sys.platform == "darwin", "macOS sharing-permission fixture")
    def test_token_writer_removes_inherited_macos_sharing_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            # Fixed native command, disposable fixture path, and no shell.
            # nosemgrep: security.semgrep.python.lang.security.audit.dangerous-subprocess-use-audit.dangerous-subprocess-use-audit
            subprocess.run(
                ["/bin/chmod", "+a", "everyone allow read,file_inherit,directory_inherit", directory],
                check=True, capture_output=True,
            )
            token_file = Path(directory) / server.TOKEN_FILE_NAME
            server.write_token_file(token_file, "synthetic-token-fixture")
            # Read-only native command inspecting this disposable fixture only.
            # nosemgrep: security.semgrep.python.lang.security.audit.dangerous-subprocess-use-audit.dangerous-subprocess-use-audit
            listing = subprocess.run(
                ["/bin/ls", "-le", str(token_file)], check=True, capture_output=True, text=True,
            ).stdout
            self.assertNotIn("everyone allow", listing)
            self.assertEqual(token_file.read_text(), "synthetic-token-fixture")
            self.assertEqual(stat.S_IMODE(token_file.stat().st_mode), 0o600)

    def test_macos_sharing_is_cleared_before_writing_and_child_gets_no_token(self):
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / server.TOKEN_FILE_NAME

            def secure_empty(command, **kwargs):
                self.assertEqual(command[:2], ["/bin/chmod", "-N"])
                self.assertTrue(Path(command[2]).is_dir())
                self.assertEqual(list(Path(command[2]).iterdir()), [])
                self.assertNotIn(server.TOKEN_ENVIRONMENT_VARIABLE, kwargs["env"])
                return None

            with patch.object(server.sys, "platform", "darwin"), patch.dict(
                os.environ, {server.TOKEN_ENVIRONMENT_VARIABLE: "synthetic-environment-token"}
            ), patch.object(server.subprocess, "run", side_effect=secure_empty):
                server.write_token_file(token_file, "synthetic-token-fixture")
            self.assertEqual(token_file.read_text(), "synthetic-token-fixture")

    def test_failed_macos_permission_cleanup_preserves_the_existing_token(self):
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / server.TOKEN_FILE_NAME
            token_file.write_text("synthetic-existing-token")
            with patch.object(server.sys, "platform", "darwin"), patch.object(
                server.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "chmod")
            ), self.assertRaises(OSError):
                server.write_token_file(token_file, "synthetic-new-token")
            self.assertEqual(token_file.read_text(), "synthetic-existing-token")
            self.assertEqual(list(Path(directory).iterdir()), [token_file])

    def test_the_authorization_scheme_is_case_insensitive(self):
        # RFC 7235: the scheme is case-insensitive, so `bearer` is as good as
        # `Bearer`. The token itself is compared as it was given.
        server.configure_auth("s3cret-token-value")

        for accepted in ("Bearer s3cret-token-value", "bearer s3cret-token-value"):
            self.assertIsNone(
                server._authorization_failure(accepted),
                f"expected {accepted!r} to be accepted",
            )

        for refused in ("Basic s3cret-token-value", "Bearer wrong-token", "Bearer"):
            self.assertIsNotNone(
                server._authorization_failure(refused),
                f"expected {refused!r} to be refused",
            )

    def test_the_token_is_not_handed_to_a_child_process(self):
        environment = dict(os.environ)
        environment[server.TOKEN_ENVIRONMENT_VARIABLE] = "s3cret-token-value"
        with patch.dict(os.environ, environment, clear=True):
            child_environment = server._child_environment()

        self.assertNotIn(server.TOKEN_ENVIRONMENT_VARIABLE, child_environment)


if __name__ == "__main__":
    unittest.main()
