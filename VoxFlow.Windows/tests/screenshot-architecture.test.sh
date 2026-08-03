#!/usr/bin/env bash

set -euo pipefail

windows_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository_root="$(cd "${windows_root}/.." && pwd)"
source_root="${windows_root}/src"
platform_root="${source_root}/VoxFlow.Windows.Platform"
platform_project="${platform_root}/VoxFlow.Windows.Platform.csproj"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

test -f "${platform_project}" || fail 'Missing Windows Platform project.'
git -C "${repository_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  fail 'Screenshot architecture validation requires a Git worktree.'

screen_capture_project_files=()
for project in "${source_root}"/*/*.csproj "${windows_root}"/tests/*/*.csproj; do
  [[ "${project}" != *_wpftmp.csproj ]] || continue
  screen_capture_project_files+=("${project}")
done
screen_capture_projects="$(
  grep -El '<PackageReference[^>]+Include="ScreenCapture[.]NET([.]DX11)?"' \
    "${screen_capture_project_files[@]}" \
    || true
)"

screen_capture_project_count="$(
  printf '%s\n' "${screen_capture_projects}" | sed '/^$/d' | wc -l | tr -d '[:space:]'
)"
[[ "${screen_capture_project_count}" -eq 1 ]] ||
  fail 'Platform must be the single production owner of ScreenCapture.NET.DX11.'
[[ "${screen_capture_projects}" == "${platform_project}" ]] ||
  fail "ScreenCapture.NET packages must be owned only by Platform: ${screen_capture_projects#"${windows_root}/"}"

screen_capture_pattern='ScreenCapture[.]NET'
core_boundary_pattern='(^|[^[:alnum:]_])System[.]Windows([.;]|$)|Presentation(Core|Framework)|WindowsBase|VoxFlow[.]Windows[.](App|Platform)[.]Screenshot'
architecture_hits="$(
  git -C "${repository_root}" grep \
    --untracked \
    -n \
    -E \
    "${screen_capture_pattern}|${core_boundary_pattern}" \
    -- \
    ':(glob)VoxFlow.Windows/src/**/*.cs' \
    ':(glob)VoxFlow.Windows/src/**/*.xaml' \
    || true
)"

core_projects=(
  VoxFlow.Windows.Domain
  VoxFlow.Windows.Application
  VoxFlow.Windows.Infrastructure
  VoxFlow.Windows.Providers.Cloud
  VoxFlow.Windows.Providers.Qwen
)

core_project_files=()
for project_name in "${core_projects[@]}"; do
  project_root="${source_root}/${project_name}"
  project_file="${project_root}/${project_name}.csproj"
  test -f "${project_file}" || fail "Missing core project: ${project_name}."
  core_project_files+=("${project_file}")
done

core_project_violation="$(
  grep -El '<UseWPF([[:space:]>])|<UseWindowsForms([[:space:]>])|Presentation(Core|Framework)|WindowsBase' \
    "${core_project_files[@]}" \
    | head -n 1 \
    || true
)"
[[ -z "${core_project_violation}" ]] ||
  fail "Core project must not reference desktop UI frameworks: ${core_project_violation#"${windows_root}/"}"

xaml_violation="$(
  git -C "${repository_root}" ls-files \
    -c \
    -o \
    --exclude-standard \
    -- \
    ':(glob)VoxFlow.Windows/src/VoxFlow.Windows.Domain/**/*.xaml' \
    ':(glob)VoxFlow.Windows/src/VoxFlow.Windows.Application/**/*.xaml' \
    ':(glob)VoxFlow.Windows/src/VoxFlow.Windows.Infrastructure/**/*.xaml' \
    ':(glob)VoxFlow.Windows/src/VoxFlow.Windows.Providers.Cloud/**/*.xaml' \
    ':(glob)VoxFlow.Windows/src/VoxFlow.Windows.Providers.Qwen/**/*.xaml' \
    | head -n 1 \
    || true
)"
[[ -z "${xaml_violation}" ]] ||
  fail "Core project must not contain WPF XAML: ${xaml_violation}"

while IFS=: read -r relative_source line_number source_line; do
  [[ -n "${relative_source}" ]] || continue

  if [[ "${source_line}" =~ ${screen_capture_pattern} ]]; then
    case "${relative_source}" in
      VoxFlow.Windows/src/VoxFlow.Windows.Platform/Screenshot/*.cs) ;;
      *)
        fail "ScreenCapture.NET APIs must remain behind Platform/Screenshot: ${relative_source}:${line_number}"
        ;;
    esac
  fi

  case "${relative_source}" in
    VoxFlow.Windows/src/VoxFlow.Windows.Domain/* | \
      VoxFlow.Windows/src/VoxFlow.Windows.Application/* | \
      VoxFlow.Windows/src/VoxFlow.Windows.Infrastructure/* | \
      VoxFlow.Windows/src/VoxFlow.Windows.Providers.Cloud/* | \
      VoxFlow.Windows/src/VoxFlow.Windows.Providers.Qwen/*)
      if [[ "${source_line}" =~ ${core_boundary_pattern} ]]; then
        fail "Core screenshot layers must stay UI- and adapter-free: ${relative_source}:${line_number}"
      fi
      ;;
  esac
done <<< "${architecture_hits}"

printf '%s\n' 'PASS: screenshot capture dependencies and desktop UI concerns stay behind their Windows adapter boundaries.'
