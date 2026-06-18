#!/usr/bin/env python3
"""Official ASR reference runner skeleton for VoxFlow.

The runner emits one unified JSON shape for VoxFlow and external reference
runtime outputs. Until a provider runtime is explicitly configured, entries are
reported as skipped so they cannot be counted as passing live model validation.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Mapping


SCHEMA_VERSION = 1
PROVIDERS = (
    {
        "id": "apple_speech",
        "display_name": "Apple Speech",
        "adapter": "AppleSpeechReferenceAdapter",
    },
    {
        "id": "qwen3",
        "display_name": "Qwen3-ASR",
        "adapter": "Qwen3ReferenceAdapter",
    },
    {
        "id": "funasr_nano",
        "display_name": "FunASR Nano",
        "adapter": "FunASRNanoReferenceAdapter",
    },
    {
        "id": "sensevoice",
        "display_name": "SenseVoice",
        "adapter": "SenseVoiceReferenceAdapter",
    },
    {
        "id": "whisper",
        "display_name": "Whisper",
        "adapter": "WhisperReferenceAdapter",
    },
)
PROVIDER_IDS = tuple(provider["id"] for provider in PROVIDERS)


def read_corpus(corpus_path: Path) -> tuple[dict[str, Any], Path]:
    corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
    root = corpus_path.parent.parent.parent
    return corpus, root


def corpus_entries(corpus: dict[str, Any]) -> list[dict[str, Any]]:
    if "entries" in corpus:
        return list(corpus.get("entries", []))
    if "samples" in corpus:
        return list(corpus.get("samples", []))
    return []


def read_reference_text(root: Path, entry: dict[str, Any]) -> str:
    if "transcript" in entry:
        return str(entry["transcript"])
    transcript_path = entry.get("transcript_path")
    if not transcript_path:
        return ""
    return (root / transcript_path).read_text(encoding="utf-8").strip()


def runtime_env_key(provider_id: str) -> str:
    normalized = provider_id.upper().replace("-", "_")
    return f"VOXFLOW_REFERENCE_{normalized}_RUNTIME"


def registered_providers() -> list[dict[str, str]]:
    return [
        {
            **provider,
            "runtime_env_key": runtime_env_key(provider["id"]),
        }
        for provider in PROVIDERS
    ]


class ReferenceAdapter:
    provider_id: str

    def __init__(
        self,
        provider_id: str,
        runtime_path: Path | None,
        env: Mapping[str, str],
    ) -> None:
        self.provider_id = provider_id
        self.runtime_path = runtime_path
        self.env = env

    @property
    def configured(self) -> bool:
        return self.runtime_path is not None

    @property
    def configuration_hint(self) -> str:
        return f"--runtime-path or {runtime_env_key(self.provider_id)}"

    def transcribe(self, entry: dict[str, Any], root: Path) -> dict[str, Any]:
        reference = read_reference_text(root, entry)
        language = entry.get("bcp47") or entry.get("language")
        base = {
            "id": str(entry["id"]),
            "provider": self.provider_id,
            "language": language,
            "audio_path": entry.get("audio_path"),
            "transcript_path": entry.get("transcript_path"),
            "reference_text": reference,
            "final_text": None,
            "latency_ms": None,
            "rtf": None,
            "text": None,
            "partials": [],
            "timings": {
                "first_partial_latency_ms": None,
                "partial_update_interval_ms": None,
                "final_latency_ms": None,
            },
            "metrics": {
                "cer": None,
                "word_error_rate": None,
                "partial_rewrite_rate": None,
                "stable_prefix_ratio": None,
                "real_time_factor": None,
                "peak_rss_mb": None,
            },
        }
        if not self.configured:
            return {
                **base,
                "status": "skipped",
                "skip_reason": "reference_runtime_not_configured",
            }

        return {
            **base,
            "status": "skipped",
            "skip_reason": "reference_runtime_adapter_not_implemented",
        }


class VoxFlowSmokeReferenceAdapter(ReferenceAdapter):
    provider_env: dict[str, tuple[str, str]] = {
        "qwen3": ("qwen3", "VOICEINPUT_TEST_QWEN3_MODEL_PATH"),
        "funasr_nano": ("funasr", "VOICEINPUT_TEST_FUNASR_MODEL_PATH"),
        "sensevoice": ("sensevoice", "VOICEINPUT_TEST_SENSEVOICE_MODEL_PATH"),
        "whisper": ("whisper", "VOICEINPUT_TEST_WHISPERKIT_MODEL_PATH"),
    }

    def run_smoke(self, root: Path) -> dict[str, dict[str, Any]]:
        if self.provider_id not in self.provider_env or self.runtime_path is None:
            return {}
        smoke_provider, model_env_key = self.provider_env[self.provider_id]
        with tempfile.TemporaryDirectory() as tmpdir:
            output_path = Path(tmpdir) / "asr-smoke-results.json"
            env = dict(os.environ)
            env.update({
                "VOICEINPUT_TEST_ASR_SMOKE_PROVIDER": smoke_provider,
                model_env_key: str(self.runtime_path),
                "VOICEINPUT_TEST_ASR_SMOKE_OUTPUT": str(output_path),
            })
            if self.provider_id == "funasr_nano":
                env.setdefault("VOICEINPUT_TEST_FUNASR_VARIANT", "int8")
            completed = subprocess.run(
                [
                    "swift",
                    "test",
                    "--filter",
                    "ASRProviderLiveSmokeTests/testConfiguredProviderRunsMinimalSmokeCorpus",
                ],
                cwd=root,
                env=env,
                check=False,
                capture_output=True,
                text=True,
            )
            if completed.returncode != 0:
                raise RuntimeError(
                    "VoxFlow smoke runner failed:\n"
                    + completed.stdout
                    + completed.stderr
                )
            items = json.loads(output_path.read_text(encoding="utf-8"))
        return {str(item["id"]): item for item in items}

    def transcribe_many(self, entries: list[dict[str, Any]], root: Path) -> list[dict[str, Any]]:
        smoke_items = self.run_smoke(root)
        return [self.item_from_smoke(entry, smoke_items.get(str(entry["id"])), root) for entry in entries]

    def item_from_smoke(
        self,
        entry: dict[str, Any],
        smoke_item: dict[str, Any] | None,
        root: Path,
    ) -> dict[str, Any]:
        base = super().transcribe(entry, root)
        if smoke_item is None:
            return {
                **base,
                "status": "skipped",
                "skip_reason": "reference_smoke_item_not_found",
            }
        reference_text = str(base.get("reference_text") or "").strip()
        if entry.get("expects_speech") is False and not reference_text:
            return {
                **base,
                "status": "skipped",
                "skip_reason": "non_speech_reference_sample",
            }
        status = "completed" if smoke_item.get("status") == "completed" else "failed"
        final_text = str(smoke_item.get("finalText") or "")
        latency_ms = smoke_item.get("latencyMs")
        rtf = smoke_item.get("rtf")
        return {
            **base,
            "status": status,
            "final_text": final_text,
            "latency_ms": latency_ms,
            "rtf": rtf,
            "text": final_text,
            "skip_reason": None,
            "error_reason": ",".join(smoke_item.get("issues") or []) if status == "failed" else None,
            "timings": {
                **base["timings"],
                "final_latency_ms": latency_ms,
            },
            "metrics": {
                **base["metrics"],
                "real_time_factor": rtf,
            },
        }


def completed_result_missing_fields(item: dict[str, Any]) -> list[str]:
    missing: list[str] = []
    if not str(item.get("final_text") or "").strip():
        missing.append("final_text")
    if item.get("latency_ms") is None:
        timings = item.get("timings")
        if not isinstance(timings, dict) or timings.get("final_latency_ms") is None:
            missing.append("latency_ms")
    if item.get("rtf") is None:
        metrics = item.get("metrics")
        if not isinstance(metrics, dict) or metrics.get("real_time_factor") is None:
            missing.append("rtf")
    return missing


def validate_reference_item(item: dict[str, Any]) -> dict[str, Any]:
    if item.get("status") != "completed":
        return item
    missing_fields = completed_result_missing_fields(item)
    if not missing_fields:
        return item
    return {
        **item,
        "status": "failed",
        "error_reason": "completed_result_missing_required_fields",
        "missing_fields": missing_fields,
    }


def make_adapter(
    provider_id: str,
    runtime_path: Path | None,
    env: Mapping[str, str],
) -> ReferenceAdapter:
    if provider_id not in PROVIDER_IDS:
        raise ValueError(f"Unknown provider id: {provider_id}")

    resolved_runtime_path = runtime_path
    if resolved_runtime_path is None:
        env_value = env.get(runtime_env_key(provider_id))
        if env_value:
            resolved_runtime_path = Path(env_value)
    adapter_type = ReferenceAdapter
    if (
        provider_id in VoxFlowSmokeReferenceAdapter.provider_env
        and resolved_runtime_path is not None
        and resolved_runtime_path.exists()
    ):
        adapter_type = VoxFlowSmokeReferenceAdapter
    return adapter_type(
        provider_id=provider_id,
        runtime_path=resolved_runtime_path,
        env=env,
    )


def run_reference(
    corpus_path: Path,
    provider_id: str,
    runtime_path: Path | None = None,
    env: Mapping[str, str] | None = None,
) -> dict[str, Any]:
    active_env = os.environ if env is None else env
    corpus, root = read_corpus(corpus_path)
    adapter = make_adapter(provider_id, runtime_path, active_env)
    entries = corpus_entries(corpus)
    if isinstance(adapter, VoxFlowSmokeReferenceAdapter):
        raw_items = adapter.transcribe_many(entries, root)
    else:
        raw_items = [adapter.transcribe(entry, root) for entry in entries]
    items = [validate_reference_item(item) for item in raw_items]
    summary = {
        "item_count": len(items),
        "completed_count": sum(1 for item in items if item["status"] == "completed"),
        "skipped_count": sum(1 for item in items if item["status"] == "skipped"),
        "failed_count": sum(1 for item in items if item["status"] == "failed"),
    }
    return {
        "schema_version": SCHEMA_VERSION,
        "provider": provider_id,
        "corpus_status": corpus.get("status"),
        "runtime": {
            "configured": adapter.configured,
            "path": str(adapter.runtime_path) if adapter.runtime_path else None,
            "configuration_hint": adapter.configuration_hint,
        },
        "summary": summary,
        "items": items,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run an official ASR reference adapter.")
    parser.add_argument("--list-providers", action="store_true", help="Print provider registry JSON and exit.")
    parser.add_argument("--provider", choices=PROVIDER_IDS)
    parser.add_argument("--corpus", type=Path, help="Path to Golden Corpus manifest JSON.")
    parser.add_argument("--runtime-path", type=Path, help="Optional official runtime path.")
    parser.add_argument("--output", type=Path, help="Optional output JSON path.")
    args = parser.parse_args()

    if args.list_providers:
        print(json.dumps(
            {
                "schema_version": SCHEMA_VERSION,
                "providers": registered_providers(),
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ))
        return 0

    if args.provider is None or args.corpus is None:
        parser.error("--provider and --corpus are required unless --list-providers is used.")

    result = run_reference(
        corpus_path=args.corpus,
        provider_id=args.provider,
        runtime_path=args.runtime_path,
    )
    payload = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload + "\n", encoding="utf-8")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
