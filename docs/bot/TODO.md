# Bot Implementation TODO (LLM Playtesting)

## Goal

Build a headless EC4X bot that can play full games against humans using
Nostr transport, PlayerState-driven context, and strict JSON output
compiled into `CommandPacket`.

## Locked Decisions

- [x] v1 output contract is strict JSON -> `CommandPacket` compiler.
- [x] v1 provider target is OpenAI-compatible chat endpoint.
- [ ] Direct KDL emission from LLM is deferred.

## Phase 1 - Runtime Skeleton and Transport

- [x] Create `src/bot/main.nim` for CLI and env configuration.
- [x] Create `src/bot/runner.nim` for turn loop orchestration.
- [x] Create `src/bot/state_store.nim` for full+delta state handling.
- [x] Reuse player-side Nostr transport from `src/player/nostr/client.nim`.
  - `src/bot/transport.nim`
- [x] Handle `30405` full state and `30403` delta events.
- [x] Add actionable-turn debounce to avoid duplicate submissions.

## Phase 2 - Prompt Context Generation

- [x] Create `src/bot/prompt_context.nim`.
- [x] Produce deterministic, token-efficient markdown context from
  PlayerState.
- [x] Include only fog-of-war-safe known data.
- [x] Add section summaries for economy, fleets, intel, and events.

## Phase 3 - LLM Client

- [x] Create `src/bot/llm_client.nim` with provider-agnostic interface.
- [x] Implement one OpenAI-compatible adapter for v1.
- [x] Add timeout, retry, and request metadata logging.

## Phase 4 - JSON Schema and Compiler

- [x] Create `src/bot/order_schema.nim` with strict parser.
- [x] Create `src/bot/order_compiler.nim` mapping JSON draft to
  `CommandPacket`.
- [x] Enforce one fleet command per fleet.
- [x] Enforce id presence/type checks and ROE bounds.
- [x] Reject ambiguous or unsupported command variants.

## Phase 5 - Validation and Correction Loop

- [x] Add preflight checks using available PlayerState data.
- [x] Submit serialized packet with bounded retry loop on failure.
- [x] Feed parser/compiler/preflight errors back to LLM for correction.
- [x] Persist per-turn correction traces.
  - `src/bot/trace_log.nim`
  - `tests/unit/test_bot_trace_log.nim`

## Phase 6 - Playtest Harness

- [x] Add a local script to run daemon + relay + bot process.
  - `scripts/run_bot_playtest.sh`
- [x] Add bot run log output directory conventions.
  - `BOT_LOG_DIR` (default `logs/bot`)
- [x] Add reproducible session config for game/model/relay/key.
  - `scripts/bot/session.env.example`

## Phase 7 - Test Coverage

- [x] Unit: schema parsing (`tests/unit/test_bot_order_schema.nim`).
- [x] Unit: compiler mapping (`tests/unit/test_bot_order_compiler.nim`).
- [x] Unit: prompt context (`tests/unit/test_bot_prompt_context.nim`).
- [x] Unit: state store (`tests/unit/test_bot_state_store.nim`).
- [x] Unit: retry loop (`tests/unit/test_bot_runner_retry.nim`).
- [x] Integration smoke: ingest state and submit one turn.
  - `tests/unit/test_bot_integration_smoke.nim`

## Acceptance Criteria

- [ ] Bot can complete 20+ consecutive turns without manual correction.
- [ ] Bot emits valid `CommandPacket` in common scenarios.
- [ ] Retry loop recovers from malformed LLM output within attempt budget.
- [ ] Human-vs-LLM games are reproducible with per-turn logs.
- [ ] Prompt generation is fog-of-war compliant.
