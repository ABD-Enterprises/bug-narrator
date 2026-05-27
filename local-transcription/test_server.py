import asyncio
import json
import unittest

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


if __name__ == "__main__":
    unittest.main()
