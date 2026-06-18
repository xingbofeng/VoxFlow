import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


def load_parity_report_module():
    root = Path(__file__).resolve().parents[2]
    module_path = root / "scripts" / "asr_parity_report.py"
    spec = importlib.util.spec_from_file_location("asr_parity_report", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


asr_parity_report = load_parity_report_module()


class ASRParityReportTests(unittest.TestCase):
    def test_report_compares_core_metrics_by_item_id(self):
        voxflow = {
            "items": [
                {
                    "id": "zh-minimal-001",
                    "cer": 0.12,
                    "wer": 0.25,
                    "partial_rewrite_rate": 0.4,
                    "stable_prefix_ratio": 0.6,
                    "real_time_factor": 1.2,
                    "peak_rss_mb": 512,
                }
            ]
        }
        reference = {
            "provider": "qwen3",
            "items": [
                {
                    "id": "zh-minimal-001",
                    "metrics": {
                        "cer": 0.10,
                        "word_error_rate": 0.20,
                        "partial_rewrite_rate": 0.5,
                        "stable_prefix_ratio": 0.7,
                        "real_time_factor": 1.0,
                        "peak_rss_mb": 480,
                    },
                }
            ],
        }

        result = asr_parity_report.build_report(voxflow, reference)

        self.assertEqual(result["schema_version"], 1)
        self.assertEqual(result["reference_provider"], "qwen3")
        self.assertEqual(result["summary"]["matched_count"], 1)
        self.assertEqual(result["summary"]["missing_in_reference_count"], 0)
        self.assertEqual(result["summary"]["missing_in_voxflow_count"], 0)
        self.assertAlmostEqual(result["summary"]["average_deltas"]["cer"], 0.02)
        self.assertAlmostEqual(result["summary"]["average_deltas"]["word_error_rate"], 0.05)
        item = result["items"][0]
        self.assertEqual(item["id"], "zh-minimal-001")
        self.assertAlmostEqual(item["deltas"]["cer"], 0.02)
        self.assertAlmostEqual(item["deltas"]["word_error_rate"], 0.05)
        self.assertAlmostEqual(item["deltas"]["partial_rewrite_rate"], -0.1)
        self.assertAlmostEqual(item["deltas"]["stable_prefix_ratio"], -0.1)
        self.assertAlmostEqual(item["deltas"]["real_time_factor"], 0.2)
        self.assertAlmostEqual(item["deltas"]["peak_rss_mb"], 32)

    def test_report_tracks_missing_items_without_counting_them_as_matched(self):
        voxflow = {"items": [{"id": "only-voxflow", "cer": 0.1}]}
        reference = {
            "provider": "whisper",
            "items": [{"id": "only-reference", "metrics": {"cer": 0.2}}],
        }

        result = asr_parity_report.build_report(voxflow, reference)

        self.assertEqual(result["summary"]["matched_count"], 0)
        self.assertEqual(result["summary"]["missing_in_reference_count"], 1)
        self.assertEqual(result["summary"]["missing_in_voxflow_count"], 1)
        self.assertEqual(result["missing_in_reference"], ["only-voxflow"])
        self.assertEqual(result["missing_in_voxflow"], ["only-reference"])

    def test_report_pairs_voxflow_and_reference_outputs_for_same_audio_path(self):
        voxflow = {
            "items": [
                {
                    "id": "zh-minimal-001",
                    "audio_path": "TestResources/Audio/zh-minimal-001.wav",
                    "cer": 0.12,
                },
                {
                    "id": "en-minimal-001",
                    "audio_path": "TestResources/Audio/en-minimal-001.wav",
                    "cer": 0.08,
                },
            ]
        }
        reference = {
            "provider": "qwen3",
            "items": [
                {
                    "id": "zh-minimal-001",
                    "audio_path": "TestResources/Audio/zh-minimal-001.wav",
                    "metrics": {"cer": 0.10},
                },
                {
                    "id": "en-minimal-001",
                    "audio_path": "TestResources/Audio/en-reference-001.wav",
                    "metrics": {"cer": 0.07},
                },
            ],
        }

        result = asr_parity_report.build_report(voxflow, reference)

        self.assertEqual(result["summary"]["same_audio_path_count"], 1)
        self.assertEqual(result["summary"]["audio_path_mismatch_count"], 1)
        self.assertEqual(result["audio_path_mismatches"], ["en-minimal-001"])

        en_item = result["items"][0]
        self.assertEqual(en_item["id"], "en-minimal-001")
        self.assertFalse(en_item["same_audio_path"])
        self.assertEqual(
            en_item["audio_paths"],
            {
                "voxflow": "TestResources/Audio/en-minimal-001.wav",
                "reference": "TestResources/Audio/en-reference-001.wav",
            },
        )

        zh_item = result["items"][1]
        self.assertEqual(zh_item["id"], "zh-minimal-001")
        self.assertTrue(zh_item["same_audio_path"])
        self.assertEqual(zh_item["audio_path"], "TestResources/Audio/zh-minimal-001.wav")

    def test_cli_writes_parity_report_json(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            voxflow_path = root / "voxflow.json"
            reference_path = root / "reference.json"
            output_path = root / "parity.json"
            voxflow_path.write_text(json.dumps({"items": [{"id": "a", "cer": 0.3}]}), encoding="utf-8")
            reference_path.write_text(
                json.dumps({"provider": "paraformer", "items": [{"id": "a", "metrics": {"cer": 0.1}}]}),
                encoding="utf-8",
            )

            completed = subprocess.run(
                [
                    "python3",
                    str(Path(__file__).resolve().parents[2] / "scripts" / "asr_parity_report.py"),
                    "--voxflow",
                    str(voxflow_path),
                    "--reference",
                    str(reference_path),
                    "--output",
                    str(output_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            payload = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["reference_provider"], "paraformer")
            self.assertEqual(payload["summary"]["matched_count"], 1)
            self.assertAlmostEqual(payload["items"][0]["deltas"]["cer"], 0.2)


if __name__ == "__main__":
    unittest.main()
