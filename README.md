# Local-First Planning Assistant

This repository houses the non-Apple stack for the semester-long scheduling assistant. It covers the local Node.js API, static web client, and shared scheduling/analytics logic. The Swift project inside `cal/` remains untouched per request.

## Workspace Layout

- `apps/server` – lightweight HTTP API for tasks, goals, routines, scheduling, analytics, notifications.
- `apps/web` – static SPA that calls the API for day-to-day usage.
- `packages/shared` – shared domain models, scheduling heuristics, analytics, notification logic, and JSON persistence helpers.
- `docs` – requirements checklist and supporting docs.

## Prerequisites

- Node.js 20 or newer (already installed in the provided environment).
- No external dependencies beyond the standard Node toolchain; everything runs offline.

Install workspace links (creates local symlinks for the packages):

```bash
npm install
```

## Running the Stack

Start the API (port 4000 by default):

```bash
npm run dev:server
```

Start the static web dev server (port 5173 by default):

```bash
npm run dev:web
```

Open `http://localhost:5173` to interact with the app. The web client talks to the API at `http://localhost:4000`.

## Features Delivered

- CRUD for tasks, goals, and routines backed by a JSON store (`data/server-db.json`).
- Greedy scheduling engine that respects priorities, deadlines, travel buffers, and routine blocks.
- Analytics summaries plus weekly reports via shared helpers.
- Notification and escalation heuristics exposed through dedicated endpoints.
- Assistant chat wired to a local LLM provider with graceful fallback messaging.
- Calendar-first web UI that mirrors the mobile prototype with tab navigation for Tasks, Routines, and Chat.
- Node test suites for shared logic, server handlers, and web state management.

### Local Model Integration

- Configure the model path and llama.cpp binary in `config/local-llm.json`. By default it points to `Mistral-7B-Instruct-v0.3.Q4_K_M.gguf` and expects a runnable binary at `./bin/llama-cli`.
- When the binary or model is missing, the assistant falls back to lightweight heuristic responses so the UI continues working.
- The server exposes `POST /api/assistant` which accepts `{ "message": string, "history": Array<{ role, content }> }` and returns `{ "reply": string }`.
- Update the config or pass `assistantOptions` into `createApp` to fine-tune temperature, token limits, or system prompt.

## Testing

Run every package test suite with one command:

```bash
npm run test
```

This executes tests for `packages/shared`, `apps/server`, and `apps/web`.

## Next Steps

- Attach the assistant UI to the eventual local LLM/ChatGPT bridge.
- Expand scheduling constraints (energy profiles, richer travel estimates, collaboration hooks).
- Replace the JSON store with encrypted persistence and design the P2P sync layer.
- Harden notification delivery (desktop, email/SMS hooks) and surface device pairing UX.

Refer to `docs/project_todo.md` for the full roadmap and remaining tasks.
