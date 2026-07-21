# Local-First Planning Assistant

A team-built planning application that turns tasks, goals, routines, and imported calendar assignments into a workable daily schedule. The project combines a SwiftUI iOS client with a local Node.js service, a browser client, shared scheduling logic, and optional local-LLM assistance.

## What It Does

- Creates and manages tasks, goals, and recurring routines.
- Imports Canvas assignments from ICS calendar feeds.
- Builds schedules around priorities, deadlines, routine blocks, and travel buffers.
- Provides workload analytics and weekly summaries.
- Exposes notification and escalation recommendations through the API.
- Supports planning conversations through a configurable local `llama.cpp` model.
- Stores application data locally in JSON.

## Architecture

| Path | Purpose |
| --- | --- |
| `cal/` | SwiftUI iOS application, calendar views, notifications, location support, and ICS import |
| `apps/server/` | Node.js HTTP API for planning data, scheduling, analytics, notifications, and assistant requests |
| `apps/web/` | Browser client for tasks, routines, calendar views, and chat |
| `packages/shared/` | Shared data models, scheduling heuristics, analytics, ICS parsing, and persistence |
| `config/` | Local model configuration |

## Run the Node.js Application

Requirements: Node.js 20 or newer.

```bash
npm install
npm run dev:server
```

In another terminal:

```bash
npm run dev:web
```

Open `http://localhost:5173`. The API listens on `http://localhost:4000` by default and creates its local data file under `apps/server/data/`.

## Test

```bash
npm test
```

The test suite covers shared scheduling behavior, API handlers, and browser-state management.

## Optional Local Model

The assistant can run through a local `llama.cpp` executable and GGUF model. Set their paths in `config/local-llm.json`; model files and binaries are intentionally excluded from the repository.

## Project Team

Semester team project by Logan Caffey, Dawson Matthew, and BumSoo Kim.
