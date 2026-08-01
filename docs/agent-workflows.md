# Agent Workflows

VoxFlow has two related agent workflows: composing prompts for AI tools and dispatching spoken instructions to local coding-agent sessions.

## Agent Compose

Agent Compose reads visible text and optional OCR context from the current window, combines it with your spoken intent, and produces a prompt for tools such as ChatGPT, Claude, Codex, Cursor, or other LLM workflows.

Safety boundary:

- The result is copied.
- VoxFlow does not inject the prompt into another app.
- VoxFlow does not press Enter.
- VoxFlow does not auto-submit messages.

This keeps Agent Compose close to a voice keyboard: it helps you draft a better prompt without taking control of the destination app.

## AI Coding Assistant Command Center

AI Coding Assistant is for local terminal agents. It works with registered sessions such as Codex, Claude, CodeBuddy, or other terminal-agent sessions.

Typical flow:

1. Start or register a local agent session.
2. Speak a target name and task.
3. VoxFlow resolves the target session.
4. If the target is ambiguous or new, VoxFlow asks for confirmation.
5. The instruction is dispatched to the registered session.
6. Dispatch history and traces are available in the Workbench.

## Runtime Handling

When a configured local agent runtime is available, VoxFlow can let that runtime handle the request directly. The task should be recorded as completed by the runtime, not as a normal text-output cancellation. This distinction matters for logs, task history, and future analytics.

## Safety Rules

- Dispatch only to registered sessions.
- Confirm ambiguous target names.
- Keep aliases user-confirmed before learning them.
- Treat destructive or file-modifying commands as higher risk.
- Keep command history bounded and local.

## Current Boundaries

- Agent Compose is copy-only.
- AI Coding Assistant dispatches to local sessions.
- VoxFlow does not silently execute shell commands outside the registered agent session.
- Runtime traces are stored locally unless the user enables external diagnostics.
