You are a senior systems architect and integration engineer working in Cursor.

Goal:
Create a full, comprehensive installation, configuration, and integration plan for running three self-hosted systems together:

1. Hermes Agent
2. Paperclip
3. Honcho persistent memory layer

Local repos to inspect:

- Hermes Agent repo: /home/hammer/Documents/repos/hermaper/hermes-agent
- Paperclip repo: /home/hammer/Documents/repos/hermaper/paperclip
- Honcho repo: /home/hammer/Documents/repos/hermaper/honcho

Also inspect the full Archon MCP knowledge base, especially these known sources:

- Hermes Agent source_id: b7825e7ddcd4ddca
- Paperclip Documentation source_id: ba6bf5bb4ff81909

If Honcho exists in Archon knowledge sources, inspect that too. Otherwise, use the local Honcho repo README and code as the source of truth.

Important Architecture Requirement:
Hermes Agent, Paperclip, and Honcho must be treated as separate systems with separate responsibilities.

- Hermes Agent must remain independently runnable as a self-hosted agent.
- Paperclip must remain the company/control-plane system for managing AI companies, agents, roles, tasks, goals, budgets, and adapters.
- Honcho must be the persistent memory layer. It should not be embedded inside Hermes or Paperclip as an internal module.
- Honcho may share the same physical Postgres server/database cluster with Paperclip if practical, but its memory domain, schema, credentials, workspaces, peers, sessions, collections, and operational lifecycle must remain logically separated.
- Prefer separate databases or schemas for Honcho and Paperclip unless the codebase clearly supports a safe shared-database strategy.
- Memory ownership and boundaries must be explicit.

Product Relationship:

1. Hermes -> Paperclip:
   Hermes should be able to direct, inspect, and operate a Paperclip company through the Paperclip API. It should be able to create/update tasks, inspect company state, monitor agents, and trigger workflows through authenticated API calls.

2. Paperclip -> Hermes:
   Paperclip should be able to use one or more Hermes Agent instances as agent runtimes for company roles. Hermes should be available as a CLI-backed/local adapter or runtime, so a Paperclip company can assign work to “Hermes agents” just like it might assign work to Claude, Codex, Gemini, process, HTTP, or other adapters.

3. Hermes/Paperclip -> Honcho:
   Honcho should provide persistent memory and long-term context for humans, Hermes agents, Paperclip roles, Paperclip companies, projects, tasks, and sessions where appropriate.

4. Honcho Separation:
   Honcho must not become the task manager or control plane. Paperclip owns company/task orchestration. Hermes owns autonomous agent execution. Honcho owns memory, context, peer/session representations, summaries, search, and insights.

Research Requirements:
First confirm Archon MCP is reachable with its health check. Then inspect the Archon knowledge base systematically.

Use Archon tools to:
- List all available RAG sources.
- Identify and fully inspect Hermes Agent, Paperclip, and Honcho-related documentation sources.
- Search with concise queries:
  - paperclip adapters
  - paperclip API
  - paperclip authentication
  - paperclip deployment
  - hermes cli
  - hermes setup
  - hermes gateway
  - hermes skills
  - hermes mcp
  - hermes automation
  - honcho memory
  - honcho peers sessions
  - honcho context endpoint
  - honcho self hosted
  - honcho postgres pgvector
- Read full pages for the most relevant results.
- Search code examples where available.
- Query Archon projects, tasks, and documents for “paperclip”, “Hermes agent”, “Honcho”, “memory”, “adapter”, “API”, and “CLI”.

Then inspect all three local repos:
- Read READMEs, install docs, architecture docs, package manifests, config examples, environment examples, CLI entrypoints, adapter code, API routes, auth code, Docker/systemd/quadlet files, migrations, and tests.
- Do not assume docs are current. Cross-check docs against live code.
- Do not modify files. This task is research and planning only.

Known Honcho Concepts To Validate:
From the Honcho README, Honcho is an open-source memory library/service for stateful agents. It provides:

- FastAPI server/API
- Python and TypeScript SDKs
- Workspaces
- Peers representing users, agents, groups, or other entities
- Sessions containing interactions between peers
- Messages labeled by source peer
- Collections and Documents for vector/RAG data
- Context endpoint for long-running conversations
- Search endpoints at workspace/session/peer level
- Chat endpoint for asking questions about a peer
- Representation endpoint for low-latency peer insights
- Background deriver worker for summaries, representations, peer cards, and dreaming tasks
- Postgres with pgvector
- Optional Redis/cache, metrics, telemetry, auth, and multiple LLM providers

Package management constraint:
For Python/Hermes/Honcho work, use Astral UV only. Do not recommend pip, pipx, conda, poetry, or python -m venv. Use uv venv, uv sync, uv add, uv run, and uv lock as appropriate. If docs mention pip or poetry, translate those commands into UV-based equivalents.

Deliverable:
Produce a comprehensive implementation plan, not code.

The plan must include:

1. Current-State Findings
   - What Hermes Agent currently supports.
   - What Paperclip currently supports.
   - What Honcho currently supports.
   - Existing CLI, API, adapter, auth, deployment, config, database, and memory surfaces.
   - Any gaps or mismatches between docs and code.

2. Target Architecture
   - Explain the three-system architecture.
   - Show Hermes as an independent agent.
   - Show Paperclip as the company control plane.
   - Show Honcho as the separate persistent memory service.
   - Show Hermes controlling Paperclip through API.
   - Show Paperclip invoking Hermes through a Hermes CLI/local adapter.
   - Show Hermes and/or Paperclip using Honcho for memory without collapsing service boundaries.
   - Define ownership boundaries between orchestration, execution, and memory.

3. Memory Architecture
   - Define how Honcho workspaces map to Paperclip companies, Hermes instances, users, and roles.
   - Define how Honcho peers map to humans, Hermes agents, Paperclip agents, Paperclip roles, and company entities.
   - Define how sessions map to tasks, conversations, workflows, and agent runs.
   - Define what should be stored as messages, documents, collections, summaries, and representations.
   - Define what should not be stored in Honcho.
   - Define retention, isolation, access control, and memory reset/export strategies.

4. Database Plan
   - Identify each system’s database needs.
   - Recommend whether to use separate Postgres databases, separate schemas, or a shared database.
   - Include pgvector requirements for Honcho.
   - Include migration order.
   - Include backup/restore strategy.
   - Include credentials and least-privilege access boundaries.
   - Make clear that shared infrastructure is acceptable, but shared memory ownership is not.

5. Installation Plan
   - Prerequisites.
   - Honcho installation and launch.
   - Hermes installation and launch.
   - Paperclip installation and launch.
   - Database/services setup.
   - Environment variables.
   - Auth/token setup.
   - Local development mode.
   - Production/self-hosted mode.

6. Configuration Plan
   - Hermes config needed for Paperclip API access.
   - Hermes config needed for Honcho memory access.
   - Paperclip config needed for Hermes runtime/adapter access.
   - Paperclip config needed for Honcho memory access if Paperclip directly writes memory.
   - Honcho config for DB_CONNECTION_URI, LLM provider keys, auth, deriver, vector store, metrics, and telemetry.
   - Example environment variable names and config shapes.
   - Secrets management guidance.
   - Role-to-Hermes-instance mapping strategy.

7. Integration Design
   - Hermes-to-Paperclip API client plan.
   - Paperclip Hermes adapter plan.
   - Hermes-to-Honcho memory client plan.
   - Optional Paperclip-to-Honcho memory client plan.
   - CLI invocation contract.
   - API contracts.
   - Input/output schemas between Paperclip and Hermes.
   - Memory write/read schemas between Hermes/Paperclip and Honcho.
   - Error handling, retries, timeouts, logs, and status reporting.
   - Identity model across Paperclip agents, Hermes instances, and Honcho peers.

8. Security Model
   - API authentication.
   - Least privilege tokens.
   - Honcho workspace isolation.
   - Honcho peer/session access control.
   - Local CLI execution risks.
   - Sandbox/container options.
   - Audit logging.
   - Secret storage.
   - Memory privacy and deletion requirements.

9. Verification Plan
   - Smoke tests.
   - Unit tests.
   - Integration tests.
   - End-to-end workflow:
     - Start Honcho independently.
     - Start Hermes independently.
     - Start Paperclip.
     - Hermes stores and retrieves memory through Honcho.
     - Hermes creates/updates Paperclip tasks via API.
     - Paperclip assigns a role task to a Hermes-backed agent.
     - Hermes uses Honcho context during execution.
     - Hermes completes work and reports structured output back to Paperclip.
     - Paperclip records task status while Honcho records memory/context separately.

10. Implementation Phases
   - Break into small, ordered phases.
   - Include dependencies, risks, acceptance criteria, and rollback notes.
   - Separate:
     - minimum viable local integration
     - durable self-hosted deployment
     - production-ready security and observability
     - advanced memory features

11. Open Questions
   - List decisions requiring user confirmation.
   - Clearly separate unknowns from assumptions.
   - Call out any code/doc drift found during inspection.

Output Format:
Use concise Markdown with clear sections. Include file paths and code symbols discovered during repo inspection. Cite important repo files by path. Do not write or edit code unless explicitly asked later.