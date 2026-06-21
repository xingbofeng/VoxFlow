#!/usr/bin/env python3
# /// script
# dependencies = [
#   "jiwer==3.0.5",
# ]
# ///

import argparse
import json
import math
from pathlib import Path

import jiwer


def assert_close(name: str, expected: float, actual: float, tolerance: float) -> None:
    if not math.isclose(expected, actual, rel_tol=tolerance, abs_tol=tolerance):
        raise SystemExit(
            f"{name} mismatch: report={expected:.12f}, jiwer={actual:.12f}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Cross-check VoiceCorrection benchmark CER/WER with JiWER."
    )
    parser.add_argument("--report", required=True, help="Path to report.json")
    parser.add_argument(
        "--tolerance",
        type=float,
        default=1e-9,
        help="Allowed absolute/relative difference.",
    )
    args = parser.parse_args()

    report = json.loads(Path(args.report).read_text(encoding="utf-8"))
    results = report["results"]
    references = [item["case"]["expected"] for item in results]
    raw_hypotheses = [item["case"]["raw"] for item in results]
    actual_hypotheses = [item["actual"] for item in results]

    jiwer_cer_before = jiwer.cer(references, raw_hypotheses)
    jiwer_cer_after = jiwer.cer(references, actual_hypotheses)
    jiwer_wer_before = jiwer.wer(references, raw_hypotheses)
    jiwer_wer_after = jiwer.wer(references, actual_hypotheses)

    summary = report["summary"]
    assert_close("cerBefore", summary["cerBefore"], jiwer_cer_before, args.tolerance)
    assert_close("cerAfter", summary["cerAfter"], jiwer_cer_after, args.tolerance)
    assert_close("werBefore", summary["werBefore"], jiwer_wer_before, args.tolerance)
    assert_close("werAfter", summary["werAfter"], jiwer_wer_after, args.tolerance)

    print(
        "JiWER cross-check passed: "
        f"CER {jiwer_cer_before:.6f}->{jiwer_cer_after:.6f}, "
        f"WER {jiwer_wer_before:.6f}->{jiwer_wer_after:.6f}"
    )


if __name__ == "__main__":
    main()
