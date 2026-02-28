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

- [ ] Create `src/bot/main.nim` for CLI and env configuration.
- [ ] Create `src/bot/runner.nim` for turn loop orchestration.
- [ ] Create `src/bot/state_store.nim` for full+delta state handling.
- [ ] Reuse player-side Nostr transport from `src/player/nostr/client.nim`.
- [ ] Handle `30405` full state and `30403` delta events.
- [ ] Add actionable-turn debounce to avoid duplicate submissions.

## Phase 2 - Prompt Context Generation

- [ ] Create `src/bot/prompt_context.nim`.
- [ ] Produce deterministic, token-efficient markdown context from
  PlayerState.
- [ ] Include only fog-of-war-safe known data.
- [ ] Add section summaries for economy, fleets, intel, and events.

## Phase 3 - LLM Client

- [ ] Create `src/bot/llm_client.nim` with provider-agnostic interface.
- [ ] Implement one OpenAI-compatible adapter for v1.
- [ ] Add timeout, retry, and request metadata logging.

## Phase 4 - JSON Schema and Compiler

- [ ] Create `src/bot/order_schema.nim` with strict parser.
- [ ] Create `src/bot/order_compiler.nim` mapping JSON draft to
  `CommandPacket`.
- [ ] Enforce one fleet command per fleet.
- [ ] Enforce id presence/type checks and ROE bounds.
- [ ] Reject ambiguous or unsupported command variants.

## Phase 5 - Validation and Correction Loop

- [ ] Add preflight checks using available PlayerState data.
- [ ] Submit serialized packet with bounded retry loop on failure.
- [ ] Feed parser/compiler/preflight errors back to LLM for correction.
- [ ] Persist per-turn correction traces.

## Phase 6 - Playtest Harness

- [ ] Add a local script to run daemon + relay + bot process.
- [ ] Add bot run log output directory conventions.
- [ ] Add reproducible session config for game/model/relay/key.

## Phase 7 - Test Coverage

- [ ] Unit: schema parsing (`tests/unit/test_bot_order_schema.nim`).
- [ ] Unit: compiler mapping (`tests/unit/test_bot_order_compiler.nim`).
- [ ] Unit: prompt context (`tests/unit/test_bot_prompt_context.nim`).
- [ ] Unit: state store (`tests/unit/test_bot_state_store.nim`).
- [ ] Unit: retry loop (`tests/unit/test_bot_runner_retry.nim`).
- [ ] Integration smoke: ingest state and submit one turn.

## Acceptance Criteria

- [ ] Bot can complete 20+ consecutive turns without manual correction.
- [ ] Bot emits valid `CommandPacket` in common scenarios.
- [ ] Retry loop recovers from malformed LLM output within attempt budget.
- [ ] Human-vs-LLM games are reproducible with per-turn logs.
- [ ] Prompt generation is fog-of-war compliant.
