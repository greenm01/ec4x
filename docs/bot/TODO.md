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
  - Evidence: trace file shows 20+ sequential submitted turns.
- [ ] Bot emits valid `CommandPacket` in common scenarios.
  - Evidence: integration smoke + live playtest traces.
- [x] Retry loop recovers from malformed LLM output within attempt budget.
  - Evidence: `tests/unit/test_bot_runner_retry.nim`.
- [ ] Human-vs-LLM games are reproducible with per-turn logs.
  - Evidence: `session_start` + per-turn records in JSONL traces.
- [x] Prompt generation is fog-of-war compliant.
  - Evidence: `src/bot/prompt_context.nim` uses PlayerState view data only.

## Phase 8 - Full Command Surface Enablement

- [x] Implement `zeroTurnCommands` compilation and validation.
  - Map supported zero-turn variants into `CommandPacket`.
  - Enforce per-command required fields and value bounds.
  - Add unit tests for valid, invalid, and ambiguous payloads.
- [x] Implement `espionageActions` compilation and validation.
  - Enforce operation-specific target requirements.
  - Enforce per-turn action limits and budget constraints.
  - Add unit tests for each supported espionage operation.
- [x] Implement `diplomaticCommand` compilation and validation.
  - Support relation changes, proposals, and proposal responses.
  - Validate proposal ids and required target fields.
  - Add unit tests for accepted, rejected, and invalid flows.
- [x] Extend correction-loop handling for new categories.
  - Feed parser, compile, and preflight errors back to the model.
  - Add retry tests that recover from malformed full-feature drafts.

## Phase 9 - Full-Feature Playtest Harness and Coverage Gates

- [x] Add multi-bot orchestration script.
  - Local launcher added: `scripts/run_multi_bot_playtest.sh`.
  - Session template added: `scripts/bot/multi_session.env.example`.
  - Launch relay, daemon, and N bot processes.
  - Support per-bot env files, keypairs, and model settings.
  - Persist run metadata (seed, game id, model list, config hash).
- [x] Add feature-coverage telemetry.
  - Emit per-turn feature-family usage tags in trace logs.
  - Add a coverage summary tool for hit/miss by command family.
- [x] Add scenario matrix for forced feature exercise.
  - Added `scripts/bot/scenario_matrix.example.json` template.
  - Added `scripts/bot/run_trace_matrix.py` automated pass/fail evaluator.
  - Define setups that trigger each command family path.
  - Run matrix automatically and emit pass/fail report.
- [x] Add stability and reproducibility gates.
  - Added `scripts/bot/evaluate_trace_quality.py` gate evaluator.
  - Added `scripts/bot/run_acceptance_gates.sh` all-in-one gate runner.
  - 20+ consecutive turns without manual correction.
  - Retry recovery rate above threshold.
  - Re-run reproducibility from env + metadata + traces.

## Full-Feature Playtest Readiness Criteria

- [x] All command families enabled in runtime compiler.
- [ ] All command families executed at least once across matrix runs.
- [ ] 20+ turn stability met in target proportion of runs.
- [x] Trace logs contain session metadata and per-turn feature tags.
- [ ] Failed runs reproducible from saved run artifacts.

## Execution Order (Recommended)

1. `zeroTurnCommands` support.
2. `espionageActions` support.
3. `diplomaticCommand` support.
4. Correction-loop and test expansion.
5. Multi-bot orchestration.
6. Coverage telemetry and reporting.
7. Scenario matrix and acceptance gating.
