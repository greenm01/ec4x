# EC4X Bot Architecture (LLM Playtesting)

**Status:** MVP Runtime Loop Active (WIP)
**Last Updated:** 2026-02-28

## Overview

To enable automated playtesting and to generate training data for the neural network AI (see `docs/ai/neural_network_training.md`), we need a mechanism where LLMs (like Claude, Gemini, or Codex) can play EC4X.

Because EC4X is now fully integrated with Nostr for multiplayer transport and state synchronization, the LLM bot must function as a headless Nostr client. It will receive state via Nostr events, generate orders using an LLM, and submit valid commands back over Nostr.

## Architecture Pipeline

The LLM bot (`ec4x-bot` or `src/bot`) acts as an automated player loop:

### 1. Headless Nostr Client
The bot uses a standard Nostr private key to authenticate. It subscribes to the game relay and listens for turn resolution events:
- **`30405`** - Full State Event
- **`30403`** - Delta State Event

When a new turn is received, the bot parses the `PlayerState`.

### 2. State Contextualization (The Prompt Generator)
Raw `PlayerState` JSON/KDL is too token-heavy and complex for an LLM to reliably parse without exhausting context limits or missing strategic nuance. The bot must distill `PlayerState` into a concise, high-signal text summary:
- **Strategic Overview:** Turn number, Prestige, Treasury, Income, Command Capacity.
- **Economy & Assets:** A concise list of colonies and their current surface/orbital infrastructure.
- **Military Posture:** A summary of own fleets, locations, compositions, and commands.
- **Intelligence (Fog of War):** Visible enemy fleets and colonies.
- **Diffs/Events:** Combat reports, espionage attempts, completed builds.

This contextualized state forms the core prompt for the LLM.

### 3. The LLM Agent Loop
The core intelligence loop executed by the runner:
1. **Generate Prompt:** Combine the state summary with the game's command schema (actions available to the player).
2. **Structured Output:** The LLM responds with a structured format (JSON matching `CommandPacket` or raw KDL).
3. **Local Validation:** Before submitting to Nostr, the generated orders are passed through the engine's validation logic (`src/engine/systems/command/validation.nim`).
4. **Auto-Correction:** If validation fails (e.g., "Insufficient funds", "Fleet does not exist"), the bot appends the validation error to the prompt and asks the LLM to correct its orders (up to a retry limit).

### 4. Order Submission
Once orders pass local validation, the bot compiles them into a `CommandPacket`, encrypts it for the daemon, and publishes it back to the Nostr relay as a `30404` event.

## CI / Batch Simulation Pipeline

Once the single-turn loop is functional, we will build a simulation script (`scripts/run_ai_sim.py`) that orchestrates multiple bots:
1. Spin up a local Nostr relay.
2. Start the `ec4x-daemon`.
3. Spawn 4 instances of `ec4x-bot` configured with different LLMs (e.g., `gemini-2.5-pro`, `claude-3-5-sonnet`) and distinct Nostr keys.
4. The daemon resolves turns as soon as all 4 bots submit.
5. At game end, the result is saved, fulfilling the data requirements for neural network training.

## Next Steps

Implementation tracker:
- `docs/bot/TODO.md`
- `docs/bot/playtest_prompts.md`

Locked v1 decisions:
- Output contract is strict JSON parsed by bot schema, then compiled to
  `CommandPacket`.
- Provider target is OpenAI-compatible chat endpoint.
- Direct KDL emission is deferred.

Immediate next steps:
1. Run reproducible human-vs-LLM sessions and capture traces.
2. Validate 20+ turn stability and update acceptance checklist.
3. Expand unsupported command categories in compiler.
4. Add trace analysis tooling for batch playtests.

## Local Playtest Runner (MVP)

Use:

1. Copy `scripts/bot/session.env.example` to `scripts/bot/session.env`
   and fill credentials/ids.
2. Run `scripts/run_bot_playtest.sh`.
3. Optional: set `BOT_START_RELAY=1` and `BOT_START_DAEMON=1`
   to have the script launch local relay/daemon processes.

Runtime traces are written under `BOT_LOG_DIR` (default `logs/bot`).
Each run appends `session_start` metadata and per-turn records to
`bot_trace_<gameId>.jsonl`.

## Runtime behavior notes

- Bot reconnects to relays indefinitely with capped backoff.
- Duplicate Nostr event IDs are ignored during state ingestion.
- Compiler currently rejects `zeroTurnCommands`, `espionageActions`, and
  `diplomaticCommand` in the runtime path.
