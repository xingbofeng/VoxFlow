# Windows Built-in Agent build evidence

This record covers the minimal Rust `voxflow-agent.exe` sidecar only. It is
not installer acceptance evidence and does not replace the release manifest
or clean-VM checks.

## 2026-07-12 MSVC host result

The build ran on the Windows/MSVC Rust toolchain installed for this workspace.

```text
cargo test --all-targets
  builtin_agent_tests: 11 passed

cargo build --release --target x86_64-pc-windows-msvc \
  --no-default-features --features builtin-agent --bin voxflow-agent

voxflow-agent.exe --version
  voxflow-agent 0.1.0
```

The resulting file was a 2,441,216-byte PE32+ x86-64 console executable:

```text
SHA-256: b0c25efe0a832ad6b4ea5b49bcf26ed9b76ccdba656f2761ddc3ca800eebfb25
```

`objdump -p` reported Windows system DLLs plus `VCRUNTIME140.dll` and the
`api-ms-win-crt-*` runtime DLLs. The current build therefore **does require a
VC runtime strategy in the installer**; it must not yet be represented as a
self-contained release artifact.

## Scope isolation

`voxflow-agent` is built with `--no-default-features --features builtin-agent`.
The full `voxflow` command and its Router, session, PTY, MCP and Unix-socket
modules are `cfg(unix)`, so they do not compile into the Windows sidecar.
Windows `cargo test --all-targets` compiles the sidecar and its protocol tests
without compiling Unix-only integration test bodies. Unix continues to build
the existing full command under the `full-cli` feature; its macOS regression
run remains a separate acceptance task.
