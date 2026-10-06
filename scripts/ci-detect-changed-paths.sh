#!/usr/bin/env bash
# CI 改动路径探测：判断本次改动是否需要跑 Rust / 基准 / iOS / R2T2 子包这些重检查。
#
# 非 PR（push main、workflow_dispatch）一律全量执行，作为发版前的完整门禁。
# PR 上按改动路径跳过无关检查，缩短反馈时间。
#
# 由 .github/workflows/ci.yml 的 changes job 调用，结果写入 $GITHUB_OUTPUT。
# 本地调试时未设置 GITHUB_OUTPUT 会打印到 stdout。
set -euo pipefail

emit() {
  printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

if [ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]; then
  emit rust_agent true
  emit voice_correction_benchmark true
  emit context_boost_benchmark true
  emit r2t2_core_tests true
  emit ios true
  exit 0
fi

changed_files="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ci-changed-files.txt"
git diff --name-only --diff-filter=ACMRT HEAD^1 HEAD > "$changed_files"

matches() {
  if grep -E "$1" "$changed_files" > /dev/null; then
    printf 'true'
  else
    printf 'false'
  fi
}

emit rust_agent "$(matches '^(agent-cli/|\.github/workflows/ci\.yml$|scripts/ci-detect-changed-paths\.sh$)')"
emit voice_correction_benchmark "$(matches '^(Packages/VoxFlowVoiceCorrectionKit/|Package\.(swift|resolved)$|\.github/workflows/ci\.yml$|scripts/ci-detect-changed-paths\.sh$)')"
emit context_boost_benchmark "$(matches '^(Packages/VoxFlowContextBoostKit/|Package\.(swift|resolved)$|\.github/workflows/ci\.yml$|scripts/ci-detect-changed-paths\.sh$)')"
emit r2t2_core_tests "$(matches '^(Packages/VoxFlowR2T2Core/|Sources/VoxFlowProviders/VoxFlowProviderR2T2/|Makefile$|\.github/workflows/ci\.yml$|scripts/ci-detect-changed-paths\.sh$)')"
emit ios "$(matches '^(Apps/VoxFlowiOS/|Makefile$|\.github/workflows/ci\.yml$|scripts/ci-detect-changed-paths\.sh$)')"
