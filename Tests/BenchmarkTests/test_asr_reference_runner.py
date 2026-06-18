import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


def load_reference_runner_module():
    root = Path(__file__).resolve().parents[2]
    module_path = root / "scripts" / "asr_reference_runner.py"
    spec = importlib.util.spec_from_file_location("asr_reference_runner", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


asr_reference_runner = load_reference_runner_module()


class ASRReferenceRunnerTests(unittest.TestCase):
    def test_all_formal_providers_are_registered_with_runtime_env_keys(self):
        providers = asr_reference_runner.registered_providers()

        self.assertEqual(
            [provider["id"] for provider in providers],
            [
                "apple_speech",
                "qwen3",
                "funasr_nano",
                "sensevoice",
                "whisper",
            ],
        )
        for provider in providers:
            provider_id = provider["id"]
            self.assertEqual(provider["runtime_env_key"], f"VOXFLOW_REFERENCE_{provider_id.upper()}_RUNTIME")
            self.assertTrue(provider["display_name"])
            self.assertTrue(provider["adapter"])

    def test_each_provider_can_be_enabled_by_runtime_environment(self):
        root = Path(__file__).resolve().parents[2]
        corpus_path = root / "TestResources" / "GoldenCorpus" / "manifest.json"

        for provider in asr_reference_runner.registered_providers():
            provider_id = provider["id"]
            env = {provider["runtime_env_key"]: f"/tmp/{provider_id}-reference-runtime"}
            with self.subTest(provider=provider_id):
                result = asr_reference_runner.run_reference(
                    corpus_path=corpus_path,
                    provider_id=provider_id,
                    runtime_path=None,
                    env=env,
                )

                self.assertEqual(result["provider"], provider_id)
                self.assertEqual(result["runtime"]["configured"], True)
                self.assertEqual(result["runtime"]["path"], env[provider["runtime_env_key"]])
                self.assertEqual(result["summary"]["item_count"], 2)
                self.assertEqual(result["summary"]["skipped_count"], 2)
                self.assertEqual(
                    {item["skip_reason"] for item in result["items"]},
                    {"reference_runtime_adapter_not_implemented"},
                )

    def test_cli_lists_registered_providers_as_json(self):
        root = Path(__file__).resolve().parents[2]
        script_path = root / "scripts" / "asr_reference_runner.py"

        completed = subprocess.run(
            ["python3", str(script_path), "--list-providers"],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(len(payload["providers"]), 5)
        self.assertEqual(payload["providers"][0]["id"], "apple_speech")
        self.assertNotIn("paraformer", {provider["id"] for provider in payload["providers"]})

    def test_unconfigured_provider_emits_unified_skipped_schema(self):
        root = Path(__file__).resolve().parents[2]
        corpus_path = root / "TestResources" / "GoldenCorpus" / "manifest.json"

        result = asr_reference_runner.run_reference(
            corpus_path=corpus_path,
            provider_id="qwen3",
            runtime_path=None,
            env={},
        )

        self.assertEqual(result["schema_version"], 1)
        self.assertEqual(result["provider"], "qwen3")
        self.assertEqual(result["runtime"]["configured"], False)
        self.assertEqual(result["summary"]["item_count"], 2)
        self.assertEqual(result["summary"]["skipped_count"], 2)
        self.assertEqual(result["summary"]["completed_count"], 0)
        self.assertEqual(result["summary"]["failed_count"], 0)
        self.assertEqual(len(result["items"]), 2)
        for item in result["items"]:
            self.assertEqual(item["provider"], "qwen3")
            self.assertIn(item["language"], {"zh-Hans-CN", "en-US"})
            self.assertEqual(item["status"], "skipped")
            self.assertEqual(item["skip_reason"], "reference_runtime_not_configured")
            self.assertIsNone(item["text"])
            self.assertEqual(item["partials"], [])
            self.assertIn("cer", item["metrics"])
            self.assertIn("word_error_rate", item["metrics"])
            self.assertIn("stable_prefix_ratio", item["metrics"])
            self.assertIn("real_time_factor", item["metrics"])
            self.assertIn("peak_rss_mb", item["metrics"])

    def test_qwen_reference_json_exposes_minimal_benchmark_fields_for_two_samples(self):
        root = Path(__file__).resolve().parents[2]
        corpus_path = root / "TestResources" / "GoldenCorpus" / "manifest.json"

        result = asr_reference_runner.run_reference(
            corpus_path=corpus_path,
            provider_id="qwen3",
            runtime_path=None,
            env={},
        )

        self.assertEqual(result["provider"], "qwen3")
        self.assertEqual([item["id"] for item in result["items"]], ["zh-minimal-001", "en-minimal-001"])
        self.assertEqual([item["language"] for item in result["items"]], ["zh-Hans-CN", "en-US"])
        for item in result["items"]:
            self.assertIn("final_text", item)
            self.assertIn("latency_ms", item)
            self.assertIn("rtf", item)
            self.assertIn("skip_reason", item)
            self.assertIsNone(item["final_text"])
            self.assertIsNone(item["latency_ms"])
            self.assertIsNone(item["rtf"])
            self.assertEqual(item["status"], "skipped")
            self.assertEqual(item["skip_reason"], "reference_runtime_not_configured")

    def test_completed_reference_items_missing_text_or_timing_are_failed(self):
        root = Path(__file__).resolve().parents[2]
        corpus_path = root / "TestResources" / "GoldenCorpus" / "manifest.json"

        class IncompleteCompletedAdapter:
            configured = True
            runtime_path = Path("/tmp/qwen-runtime")
            configuration_hint = "--runtime-path"

            def transcribe(self, entry, _root):
                return {
                    "id": str(entry["id"]),
                    "provider": "qwen3",
                    "language": entry.get("bcp47"),
                    "status": "completed",
                    "final_text": None,
                    "latency_ms": None,
                    "rtf": None,
                    "text": None,
                    "partials": [],
                    "timings": {
                        "final_latency_ms": None,
                    },
                    "metrics": {
                        "real_time_factor": None,
                    },
                }

        original_make_adapter = asr_reference_runner.make_adapter
        try:
            asr_reference_runner.make_adapter = lambda *_args, **_kwargs: IncompleteCompletedAdapter()
            result = asr_reference_runner.run_reference(
                corpus_path=corpus_path,
                provider_id="qwen3",
                runtime_path=Path("/tmp/qwen-runtime"),
                env={},
            )
        finally:
            asr_reference_runner.make_adapter = original_make_adapter

        self.assertEqual(result["summary"]["completed_count"], 0)
        self.assertEqual(result["summary"]["failed_count"], 2)
        for item in result["items"]:
            self.assertEqual(item["status"], "failed")
            self.assertEqual(item["error_reason"], "completed_result_missing_required_fields")
            self.assertEqual(
                set(item["missing_fields"]),
                {"final_text", "latency_ms", "rtf"},
            )

    def test_cli_writes_reference_json_for_same_corpus(self):
        root = Path(__file__).resolve().parents[2]
        script_path = root / "scripts" / "asr_reference_runner.py"
        corpus_path = root / "TestResources" / "GoldenCorpus" / "manifest.json"
        with tempfile.TemporaryDirectory() as tmpdir:
            output_path = Path(tmpdir) / "reference.json"

            completed = subprocess.run(
                [
                    "python3",
                    str(script_path),
                    "--provider",
                    "whisper",
                    "--corpus",
                    str(corpus_path),
                    "--output",
                    str(output_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            payload = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["provider"], "whisper")
            self.assertEqual(payload["summary"]["item_count"], 2)
            self.assertEqual(payload["summary"]["skipped_count"], 2)


if __name__ == "__main__":
    unittest.main()
