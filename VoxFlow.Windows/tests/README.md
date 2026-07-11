# Windows test conventions

Shared deterministic test utilities live in `VoxFlow.Windows.Testing` and are
referenced by every xUnit project.

- Name behavior-simulating test doubles `Fake*`.
- Name test doubles whose purpose is recording inputs or calls `Capturing*`.
- Do not introduce a generic `Mock*` prefix; the name must reveal the double's
  behavior.
- Use `TemporaryDirectory`, `ControlledTimeProvider`, and
  `CancellableTestTask` instead of process-global paths, wall-clock delays, or
  uncancellable waits.
- Run WPF-specific assertions through `StaWpfTestHost` so tests have an STA
  thread and dispatcher without relying on the test runner's apartment state.
