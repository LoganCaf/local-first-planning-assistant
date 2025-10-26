## Product Vision & Success
- [ ] Validate production-ready definition (stability, performance, offline criteria)
- [ ] Set semester milestones and demo timeline (Week 2 PRD, Week 4 architecture, Week 8 engine, Week 11 freeze, Week 13 hardening, Week 15 release)
- [ ] Align team members to roles (Product, Web, iOS, AI/ML, QA/Docs)
- [ ] Confirm individual availability and sprint cadence

## Personas & User Research
- [ ] Document primary personas (student, busy individual)
- [ ] Capture top user pain points and desired outcomes
- [ ] Outline MVP vs stretch scenarios for each persona

## Core Features
- [ ] Finalize task hierarchy (project → task → subtask) and metadata schema
- [ ] Define goal tracking behaviors (time targets, recurrence, progress logging)
- [ ] Specify calendar views (daily/weekly/semester, list, Kanban, goals dashboard)
- [ ] Design import/export flows (ICS, CSV, JSON) including Canvas integration
- [ ] Detail manual split/merge interactions and overrides for recurrences
- [ ] Decide attachment support strategy and file handling limits

## Scheduling Engine
- [ ] Author constraint list (hard vs soft) and scheduling weights
- [ ] Prototype OR-Tools + heuristic fallback approach
- [ ] Implement planning horizon (rolling 4 weeks, semester outline)
- [ ] Define conflict messaging and resolution workflows
- [ ] Implement plan generation with alternate option requests
- [ ] Capture AI learning loop requirements (timer feedback, preference updates)

## AI Assistant
- [ ] Select baseline local model (e.g., Llama 3 8B q4_0) and benchmark hardware
- [ ] Implement model-agnostic serving via llama.cpp bridge
- [ ] Specify OpenAI fallback behavior and user controls
- [ ] Define assistant tone, guardrails, and supported intents
- [ ] Build chat UI with quick actions and explanation modals
- [ ] Plan optional voice input/output toggles

## Learning & Personalization
- [ ] Design preference profile schema (energy curves, weightings, notification settings)
- [ ] Implement feedback capture (accept/modify/reject, timer variances)
- [ ] Define retention policies (default 12-month window) and user controls

## Analytics & Reporting
- [ ] Choose key metrics (time by category, completion rates, focus scores, streaks)
- [ ] Design weekly AI-generated insights workflow
- [ ] Implement visualization components (Recharts) and export formats (CSV/JSON/PDF)

## Notifications & Automations
- [ ] Configure desktop notifications (service worker)
- [ ] Implement iOS local notifications and background fetch
- [ ] Provide email/SMS hooks for user-supplied providers
- [ ] Define escalation logic for repeatedly skipped tasks
- [ ] Add quiet hours and notification rule settings

## P2P Sync & Offline
- [ ] Design P2P architecture (WebRTC, Multipeer Connectivity, CRDT layer)
- [ ] Implement pairing flows (QR code, 6-digit code)
- [ ] Define conflict resolution rules and merge UI
- [ ] Ensure offline-first behavior with sync queue and diagnostics panel

## Data & Storage
- [ ] Finalize SQLite/Prisma schema for web services
- [ ] Integrate Realm schema for iOS with sync adapters
- [ ] Implement encryption at rest (AES-256) and key management
- [ ] Provide data export/delete capabilities
- [ ] Plan backup/restore (manual exports, optional scheduled local backups)

## Security & Authentication
- [ ] Implement local account creation with per-user keypair
- [ ] Store credentials in secure storage (Keychain, OS keyring)
- [ ] Support biometric unlock on iOS
- [ ] Document pairing security (Diffie-Hellman handshake)
- [ ] Establish session auto-lock policies

## UI/UX Design
- [ ] Produce design system (Tailwind theme, colorblind-safe palette, typography)
- [ ] Build responsive layout (dashboard, calendar, goals, assistant, insights, settings)
- [ ] Ensure WCAG 2.1 AA compliance (keyboard nav, screen reader labels)
- [ ] Create onboarding wizard (5-step setup)
- [ ] Implement drag-and-drop calendar interactions and travel buffers
- [ ] Add assistant side panel with history and quick commands

## iOS App
- [ ] Confirm SwiftUI architecture (MVVM + Combine)
- [ ] Mirror core features from web (task CRUD, scheduling view, assistant)
- [ ] Implement background tasks for sync/notifications
- [ ] Support share sheet imports and attachment handling
- [ ] Integrate pairing and P2P sync modules

## Testing & QA
- [ ] Configure linting/formatting (ESLint, Prettier, SwiftLint)
- [ ] Reach ≥70% coverage on core logic (Jest, XCTest)
- [ ] Build Playwright end-to-end suites (task flow, scheduling, sync)
- [ ] Create AI prompt regression tests
- [ ] Run performance benchmarks (1,000 task dataset)
- [ ] Define browser/device test matrix (Brave, Chrome, Firefox, Safari; iPhone 13+)

## DevOps & Tooling
- [ ] Set up pnpm workspace and project scaffolding (Next.js, NestJS, Prisma)
- [ ] Configure GitHub Actions pipeline (lint, test, build, package)
- [ ] Provide local deployment scripts (Docker optional)
- [ ] Implement secrets management (.env encryption, rotation CLI)
- [ ] Package web app for local install (optional Tauri/Electron)
- [ ] Prepare TestFlight distribution for iOS builds

## Documentation & Release
- [ ] Maintain `docs/requirements.md` with updates
- [ ] Draft architecture diagrams (C4, sequence) by Week 4
- [ ] Document APIs (scheduling, sync, AI interfaces)
- [ ] Write user guide (onboarding, daily usage, troubleshooting)
- [ ] Create deployment manual (web + iOS build steps, pairing instructions)
- [ ] Prepare open-source assets (README, license, contribution guide, changelog, privacy statement)

## Risk Management
- [ ] Benchmark local LLM performance and set thresholds
- [ ] Prototype connectivity diagnostics for P2P issues
- [ ] Provide manual override tools for scheduling conflicts
- [ ] Track stretch goals separately with feature flags
