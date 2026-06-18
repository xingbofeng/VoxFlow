#!/usr/bin/env python3
"""Compare VoxFlow ASR benchmark output with an official reference output."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
METRICS = (
    ("cer", "cer"),
    ("word_error_rate", "wer"),
    ("partial_rewrite_rate", "partial_rewrite_rate"),
    ("stable_prefix_ratio", "stable_prefix_ratio"),
    ("real_time_factor", "real_time_factor"),
    ("peak_rss_mb", "peak_rss_mb"),
)


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def item_map(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(item["id"]): item for item in payload.get("items", [])}


def reference_metric(item: dict[str, Any], metric_name: str) -> float | None:
    value = item.get("metrics", {}).get(metric_name)
    if value is None:
        return None
    return float(value)


def voxflow_metric(item: dict[str, Any], metric_name: str) -> float | None:
    value = item.get(metric_name)
    if value is None:
        return None
    return float(value)


def metric_deltas(voxflow_item: dict[str, Any], reference_item: dict[str, Any]) -> dict[str, float]:
    deltas: dict[str, float] = {}
    for report_metric, voxflow_key in METRICS:
        left = voxflow_metric(voxflow_item, voxflow_key)
        right = reference_metric(reference_item, report_metric)
        if left is None or right is None:
            continue
        deltas[report_metric] = left - right
    return deltas


def audio_path(item: dict[str, Any]) -> str | None:
    value = item.get("audio_path")
    return str(value) if value else None


def paired_audio_paths(voxflow_item: dict[str, Any], reference_item: dict[str, Any]) -> dict[str, str | None]:
    return {
        "voxflow": audio_path(voxflow_item),
        "reference": audio_path(reference_item),
    }


def average_deltas(items: list[dict[str, Any]]) -> dict[str, float | None]:
    result: dict[str, float | None] = {}
    for metric, _ in METRICS:
        values = [item["deltas"][metric] for item in items if metric in item["deltas"]]
        result[metric] = sum(values) / len(values) if values else None
    return result


def build_report(voxflow: dict[str, Any], reference: dict[str, Any]) -> dict[str, Any]:
    voxflow_items = item_map(voxflow)
    reference_items = item_map(reference)
    matched_ids = sorted(set(voxflow_items).intersection(reference_items))
    items: list[dict[str, Any]] = []
    for item_id in matched_ids:
        audio_paths = paired_audio_paths(voxflow_items[item_id], reference_items[item_id])
        same_audio_path = (
            audio_paths["voxflow"] is not None
            and audio_paths["voxflow"] == audio_paths["reference"]
        )
        item: dict[str, Any] = {
            "id": item_id,
            "audio_path": audio_paths["voxflow"] if same_audio_path else None,
            "audio_paths": audio_paths,
            "same_audio_path": same_audio_path,
            "voxflow": {
                metric: voxflow_metric(voxflow_items[item_id], voxflow_key)
                for metric, voxflow_key in METRICS
                if voxflow_metric(voxflow_items[item_id], voxflow_key) is not None
            },
            "reference": {
                metric: reference_metric(reference_items[item_id], metric)
                for metric, _ in METRICS
                if reference_metric(reference_items[item_id], metric) is not None
            },
            "deltas": metric_deltas(voxflow_items[item_id], reference_items[item_id]),
        }
        items.append(item)
    missing_in_reference = sorted(set(voxflow_items).difference(reference_items))
    missing_in_voxflow = sorted(set(reference_items).difference(voxflow_items))
    audio_path_mismatches = [item["id"] for item in items if not item["same_audio_path"]]
    return {
        "schema_version": SCHEMA_VERSION,
        "reference_provider": reference.get("provider"),
        "summary": {
            "matched_count": len(matched_ids),
            "missing_in_reference_count": len(missing_in_reference),
            "missing_in_voxflow_count": len(missing_in_voxflow),
            "same_audio_path_count": sum(1 for item in items if item["same_audio_path"]),
            "audio_path_mismatch_count": len(audio_path_mismatches),
            "average_deltas": average_deltas(items),
        },
        "items": items,
        "audio_path_mismatches": audio_path_mismatches,
        "missing_in_reference": missing_in_reference,
        "missing_in_voxflow": missing_in_voxflow,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare VoxFlow and official ASR reference JSON outputs.")
    parser.add_argument("--voxflow", required=True, type=Path, help="VoxFlow benchmark JSON path.")
    parser.add_argument("--reference", required=True, type=Path, help="Official reference JSON path.")
    parser.add_argument("--output", type=Path, help="Optional output JSON path.")
    args = parser.parse_args()

    result = build_report(load_json(args.voxflow), load_json(args.reference))
    payload = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload + "\n", encoding="utf-8")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
