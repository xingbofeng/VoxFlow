import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


def load_benchmark_module():
    root = Path(__file__).resolve().parents[2]
    module_path = root / "scripts" / "asr_benchmark.py"
    spec = importlib.util.spec_from_file_location("asr_benchmark", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


asr_benchmark = load_benchmark_module()


class ASRBenchmarkTests(unittest.TestCase):
    def test_repository_manifest_contains_minimal_chinese_and_english_entries(self):
        root = Path(__file__).resolve().parents[2]
        manifest_path = root / "TestResources" / "GoldenCorpus" / "manifest.json"

        result = asr_benchmark.benchmark(manifest_path, None)

        minimal_items = {
            item["id"]: item
            for item in result["items"]
            if item["id"] in {"zh-minimal-001", "en-minimal-001"}
        }
        self.assertEqual(set(minimal_items), {"zh-minimal-001", "en-minimal-001"})
        self.assertEqual(result["summary"]["entry_count"], 2)
        self.assertEqual(result["summary"]["language_counts"], {"en-US": 1, "zh-Hans-CN": 1})
        self.assertEqual(result["summary"]["audio_pending_count"], 2)
        for item in minimal_items.values():
            self.assertEqual(item["status"], "audio_pending")
            self.assertIsNotNone(item["audio_path"])
            self.assertGreater(item["reference_character_count"], 0)
            self.assertGreater(item["reference_word_count"], 0)
            self.assertIn("授权", item["authorization_source"])
            self.assertTrue(item["scenario"])

    def test_summary_reports_empty_result_tail_loss_and_technical_recall(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            corpus_dir = root / "TestResources" / "GoldenCorpus"
            transcript_dir = root / "TestResources" / "Transcripts"
            corpus_dir.mkdir(parents=True)
            transcript_dir.mkdir(parents=True)
            (transcript_dir / "short.txt").write_text("打开设置", encoding="utf-8")
            (transcript_dir / "tech.txt").write_text(
                "运行 swift test --filter Qwen3ASRProviderTests 成功",
                encoding="utf-8",
            )
            corpus = {
                "status": "skeleton",
                "entries": [
                    {
                        "id": "short",
                        "status": "audio_ready",
                        "voice_activity": True,
                        "transcript_path": "TestResources/Transcripts/short.txt",
                    },
                    {
                        "id": "tech",
                        "status": "audio_ready",
                        "voice_activity": True,
                        "category": "code_terms",
                        "technical_terms": ["swift", "test", "--filter", "Qwen3ASRProviderTests"],
                        "transcript_path": "TestResources/Transcripts/tech.txt",
                    },
                ],
            }
            predictions = {
                "short": {"text": ""},
                "tech": {"text": "运行 swift test Qwen3ASRProviderTests"},
            }
            corpus_path = corpus_dir / "manifest.json"
            predictions_path = root / "predictions.json"
            corpus_path.write_text(json.dumps(corpus), encoding="utf-8")
            predictions_path.write_text(json.dumps(predictions), encoding="utf-8")

            result = asr_benchmark.benchmark(corpus_path, predictions_path)

        self.assertEqual(result["summary"]["effective_speech_count"], 2)
        self.assertEqual(result["summary"]["empty_result_count"], 1)
        self.assertEqual(result["summary"]["effective_speech_empty_result_rate"], 0.5)
        self.assertEqual(result["summary"]["tail_loss_count"], 1)
        self.assertEqual(result["summary"]["tail_loss_rate"], 0.5)
        self.assertEqual(result["summary"]["technical_term_recall"], 0.75)
        tech_item = next(item for item in result["items"] if item["id"] == "tech")
        self.assertEqual(tech_item["technical_term_recall"], 0.75)

    def test_benchmark_consumes_reference_runner_final_text_and_ignores_skipped_items(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            corpus_dir = root / "TestResources" / "GoldenCorpus"
            transcript_dir = root / "TestResources" / "Transcripts"
            corpus_dir.mkdir(parents=True)
            transcript_dir.mkdir(parents=True)
            (transcript_dir / "zh.txt").write_text("打开设置页面", encoding="utf-8")
            (transcript_dir / "en.txt").write_text("Open the settings page", encoding="utf-8")
            corpus = {
                "status": "minimal",
                "entries": [
                    {
                        "id": "zh-minimal-001",
                        "status": "audio_ready",
                        "bcp47": "zh-Hans-CN",
                        "voice_activity": True,
                        "transcript_path": "TestResources/Transcripts/zh.txt",
                    },
                    {
                        "id": "en-minimal-001",
                        "status": "audio_ready",
                        "bcp47": "en-US",
                        "voice_activity": True,
                        "transcript_path": "TestResources/Transcripts/en.txt",
                    },
                ],
            }
            predictions = {
                "items": [
                    {
                        "id": "zh-minimal-001",
                        "status": "completed",
                        "final_text": "打开设置页面",
                        "latency_ms": 321,
                        "rtf": 0.42,
                    },
                    {
                        "id": "en-minimal-001",
                        "status": "skipped",
                        "skip_reason": "reference_runtime_not_configured",
                        "final_text": None,
                        "latency_ms": None,
                        "rtf": None,
                    },
                ]
            }
            corpus_path = corpus_dir / "manifest.json"
            predictions_path = root / "reference.json"
            corpus_path.write_text(json.dumps(corpus), encoding="utf-8")
            predictions_path.write_text(json.dumps(predictions), encoding="utf-8")

            result = asr_benchmark.benchmark(corpus_path, predictions_path)

        self.assertEqual(result["summary"]["prediction_count"], 1)
        zh_item = next(item for item in result["items"] if item["id"] == "zh-minimal-001")
        en_item = next(item for item in result["items"] if item["id"] == "en-minimal-001")
        self.assertTrue(zh_item["has_prediction"])
        self.assertEqual(zh_item["cer"], 0)
        self.assertEqual(zh_item["final_latency_ms"], 321)
        self.assertEqual(zh_item["real_time_factor"], 0.42)
        self.assertFalse(en_item["has_prediction"])
        self.assertIsNone(en_item["cer"])


if __name__ == "__main__":
    unittest.main()
