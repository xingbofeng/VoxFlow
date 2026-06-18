#!/usr/bin/env python3
"""VoxFlow ASR benchmark skeleton.

This tool consumes the Golden Corpus manifest and an optional predictions JSON
file, then emits machine-readable metrics. Phase 0 intentionally supports
metadata-only runs so the benchmark pipeline can exist before the real corpus is
collected.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def levenshtein(left: list[str], right: list[str]) -> int:
    previous = list(range(len(right) + 1))
    for i, left_item in enumerate(left, start=1):
        current = [i]
        for j, right_item in enumerate(right, start=1):
            insert = current[j - 1] + 1
            delete = previous[j] + 1
            replace = previous[j - 1] + (0 if left_item == right_item else 1)
            current.append(min(insert, delete, replace))
        previous = current
    return previous[-1]


def character_error_rate(reference: str, hypothesis: str) -> float | None:
    reference_chars = list(reference)
    if not reference_chars:
        return None
    return levenshtein(reference_chars, list(hypothesis)) / len(reference_chars)


def word_error_rate(reference: str, hypothesis: str) -> float | None:
    reference_words = reference.split()
    if not reference_words:
        return None
    return levenshtein(reference_words, hypothesis.split()) / len(reference_words)


def stable_prefix_ratio(partials: list[str]) -> float | None:
    if len(partials) < 2:
        return None
    ratios: list[float] = []
    for previous, current in zip(partials, partials[1:]):
        limit = min(len(previous), len(current))
        common = 0
        while common < limit and previous[common] == current[common]:
            common += 1
        ratios.append(common / max(len(previous), 1))
    return sum(ratios) / len(ratios)


def partial_rewrite_rate(partials: list[str]) -> float | None:
    ratio = stable_prefix_ratio(partials)
    if ratio is None:
        return None
    return 1.0 - ratio


def is_effective_speech(entry: dict[str, Any]) -> bool:
    if "voice_activity" in entry:
        return bool(entry["voice_activity"])
    return entry.get("category") not in {"silence_breath_ambient", "non_speech"}


def tail_lost(reference: str, hypothesis: str) -> bool:
    reference = reference.strip()
    hypothesis = hypothesis.strip()
    if not reference or not hypothesis:
        return False
    return not hypothesis.endswith(reference[-1])


def technical_term_recall(entry: dict[str, Any], hypothesis: str) -> float | None:
    terms = [str(term) for term in entry.get("technical_terms", []) if str(term)]
    if not terms:
        return None
    matched = sum(1 for term in terms if term in hypothesis)
    return matched / len(terms)


def read_text(root: Path, entry: dict[str, Any]) -> str:
    if "transcript" in entry:
        return str(entry["transcript"])
    transcript_path = entry.get("transcript_path")
    if not transcript_path:
        return ""
    return (root / transcript_path).read_text(encoding="utf-8").strip()


def load_predictions(path: Path | None) -> dict[str, dict[str, Any]]:
    if path is None:
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict) and "items" in data:
        data = data["items"]
    if isinstance(data, list):
        return {str(item["id"]): item for item in data}
    if isinstance(data, dict):
        return {str(key): value for key, value in data.items()}
    raise ValueError("Predictions JSON must be a list, an object map, or an object with items.")


def prediction_is_scored(prediction: dict[str, Any]) -> bool:
    if not prediction:
        return False
    return prediction.get("status", "completed") == "completed"


def prediction_text(prediction: dict[str, Any]) -> str:
    text = prediction.get("text")
    if text is None:
        text = prediction.get("final_text")
    return "" if text is None else str(text)


def prediction_final_latency_ms(prediction: dict[str, Any]) -> Any:
    if "final_latency_ms" in prediction:
        return prediction.get("final_latency_ms")
    if "latency_ms" in prediction:
        return prediction.get("latency_ms")
    timings = prediction.get("timings")
    if isinstance(timings, dict):
        return timings.get("final_latency_ms")
    return None


def prediction_real_time_factor(prediction: dict[str, Any]) -> Any:
    if "real_time_factor" in prediction:
        return prediction.get("real_time_factor")
    if "rtf" in prediction:
        return prediction.get("rtf")
    metrics = prediction.get("metrics")
    if isinstance(metrics, dict):
        return metrics.get("real_time_factor")
    return None


def benchmark(corpus_path: Path, predictions_path: Path | None) -> dict[str, Any]:
    corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
    root = corpus_path.parent.parent.parent
    predictions = load_predictions(predictions_path)
    items: list[dict[str, Any]] = []

    for entry in corpus.get("entries", []):
        entry_id = str(entry["id"])
        prediction = predictions.get(entry_id, {})
        reference = read_text(root, entry)
        is_scored_prediction = prediction_is_scored(prediction)
        hypothesis = prediction_text(prediction) if is_scored_prediction else ""
        partials = [str(value) for value in prediction.get("partials", [])]
        language = entry.get("bcp47") or entry.get("language")
        item = {
            "id": entry_id,
            "language": language,
            "status": entry.get("status"),
            "audio_path": entry.get("audio_path"),
            "scenario": entry.get("scenario") or entry.get("category"),
            "authorization_source": entry.get("authorization_source"),
            "reference_character_count": len(reference),
            "reference_word_count": len(reference.split()) if reference else 0,
            "effective_speech": is_effective_speech(entry),
            "has_prediction": is_scored_prediction,
            "cer": character_error_rate(reference, hypothesis) if is_scored_prediction else None,
            "wer": word_error_rate(reference, hypothesis) if is_scored_prediction else None,
            "stable_prefix_ratio": stable_prefix_ratio(partials),
            "partial_rewrite_rate": partial_rewrite_rate(partials),
            "first_partial_latency_ms": prediction.get("first_partial_latency_ms"),
            "partial_update_interval_ms": prediction.get("partial_update_interval_ms"),
            "final_latency_ms": prediction_final_latency_ms(prediction),
            "real_time_factor": prediction_real_time_factor(prediction),
            "peak_rss_mb": prediction.get("peak_rss_mb"),
            "finalization_delta": prediction.get("finalization_delta"),
            "dropped_audio_frames": prediction.get("dropped_audio_frames"),
            "empty_result": is_scored_prediction and not hypothesis.strip(),
            "tail_lost": is_scored_prediction and tail_lost(reference, hypothesis),
            "technical_term_recall": technical_term_recall(entry, hypothesis) if is_scored_prediction else None,
        }
        items.append(item)

    scored = [item for item in items if item["has_prediction"]]
    effective_scored = [item for item in scored if item["effective_speech"]]
    technical_recalls = [
        item["technical_term_recall"]
        for item in scored
        if item["technical_term_recall"] is not None
    ]
    language_counts: dict[str, int] = {}
    for item in items:
        language = item["language"]
        if language is None:
            continue
        language_counts[str(language)] = language_counts.get(str(language), 0) + 1
    summary = {
        "corpus_status": corpus.get("status"),
        "entry_count": len(items),
        "prediction_count": len(scored),
        "language_counts": dict(sorted(language_counts.items())),
        "audio_pending_count": sum(1 for item in items if item["status"] == "audio_pending"),
        "empty_result_count": sum(1 for item in scored if item["empty_result"]),
        "effective_speech_count": len(effective_scored),
        "effective_speech_empty_result_rate": (
            sum(1 for item in effective_scored if item["empty_result"]) / len(effective_scored)
            if effective_scored else None
        ),
        "tail_loss_count": sum(1 for item in effective_scored if item["tail_lost"]),
        "tail_loss_rate": (
            sum(1 for item in effective_scored if item["tail_lost"]) / len(effective_scored)
            if effective_scored else None
        ),
        "technical_term_recall": (
            sum(technical_recalls) / len(technical_recalls)
            if technical_recalls else None
        ),
    }
    return {"summary": summary, "items": items}


def main() -> int:
    parser = argparse.ArgumentParser(description="Run VoxFlow ASR benchmark metrics.")
    parser.add_argument("--corpus", required=True, type=Path, help="Path to Golden Corpus manifest JSON.")
    parser.add_argument("--predictions", type=Path, help="Optional predictions JSON.")
    parser.add_argument("--output", type=Path, help="Optional output JSON path.")
    args = parser.parse_args()

    result = benchmark(args.corpus, args.predictions)
    payload = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload + "\n", encoding="utf-8")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
