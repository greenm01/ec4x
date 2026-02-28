# Bot Playtest Prompts

Use these prompts with an automation LLM (or coding agent) to run repeatable
EC4X bot playtests.

## Prompt 1: General Bot Playtest

```text
You are running a local EC4X bot playtest.

Goal:
- Start a bot session against an existing EC4X game.
- Let it run long enough to evaluate stability (target 20+ turns if possible).
- Produce a concise report with evidence from trace logs.

Constraints:
- Do not modify engine/game logic.
- Do not commit anything.
- Do not print secrets.
- Use existing bot runner and env conventions only.

Steps:
1) Prepare bot env file:
   - Copy `scripts/bot/session.env.example` to `scripts/bot/session.env`.
   - Fill required vars:
     - BOT_RELAYS
     - BOT_GAME_ID
     - BOT_DAEMON_PUBHEX
     - BOT_PLAYER_PRIV_HEX
     - BOT_PLAYER_PUB_HEX
     - BOT_MODEL
     - BOT_API_KEY
   - Optional orchestration:
     - BOT_START_RELAY=1 and BOT_START_DAEMON=1 for local infra launch.
     - Otherwise keep both 0 and use already-running relay/daemon.
   - Keep BOT_LOG_DIR set (default `logs/bot`).

2) Start playtest:
   - Run: `scripts/run_bot_playtest.sh`
   - Let it run until sufficient turns are processed (target 20+ if feasible).

3) Validate output:
   - Confirm trace file exists:
     - `logs/bot/bot_trace_<gameId>.jsonl` (or BOT_LOG_DIR equivalent).
   - Confirm there is a `session_start` record.
   - Confirm per-turn entries are being appended.
   - Count successful submitted turns and identify failures by `errorClass`.
   - Run `scripts/bot/summarize_trace_coverage.py` on trace output to
     measure feature-family coverage.

4) Report:
   - Number of turns attempted/submitted.
   - Number of retries and most common failure stage
     (`llm_request`, `schema_parse`, `compile`, `submit`).
   - Whether 20+ consecutive turns without manual correction was achieved.
   - Top 3 issues and recommended next fixes.

Important:
- If the bot exits due to connection issues, restart and continue.
- Use trace logs as source of truth for conclusions.
```

## Prompt 2: Human-vs-LLM Playtest

```text
You are running a Human-vs-LLM EC4X playtest using the bot runtime.

Goal:
- Run a reproducible game where at least one house is bot-controlled.
- Gather operational quality data from bot traces.
- Produce a short QA summary with pass/fail acceptance notes.

Constraints:
- Do not modify engine or daemon logic.
- Do not commit code.
- Do not print API keys or private keys.

Setup:
1) Prepare `scripts/bot/session.env` from
   `scripts/bot/session.env.example`.
2) Fill required values for relay/game/daemon/bot identity/model.
3) Ensure bot has a valid house identity and is in the target game.

Execution:
1) Start the bot with `scripts/run_bot_playtest.sh`.
2) Let human and bot turns progress naturally.
3) Keep run alive until at least 20 bot decision opportunities,
   or document why not achievable.

Evidence collection:
1) Use `BOT_LOG_DIR` trace JSONL as source of truth.
2) Extract:
   - total decision attempts
   - successful submissions
   - retries per turn
   - failures by `errorClass`
3) Note any repeated malformed output loops or submit rejections.

Acceptance checklist:
- 20+ consecutive bot turns without manual correction (pass/fail).
- Valid `CommandPacket` submissions in common scenarios (pass/fail).
- Retry loop recovers from malformed responses within budget (pass/fail).
- Reproducible logs with session metadata + per-turn traces (pass/fail).

Output format:
- Brief run summary
- Acceptance checklist with pass/fail
- Top issues and next actions
```

## Prompt 3: Multi-Bot Stress Playtest

```text
You are running a multi-bot EC4X stress playtest.

Goal:
- Launch multiple bot identities in the same game.
- Observe stability, retries, and feature usage over extended turns.

Constraints:
- Do not modify engine/daemon logic.
- Do not commit code.
- Do not print secrets.

Steps:
1) Copy `scripts/bot/multi_session.env.example` to
   `scripts/bot/multi_session.env`.
2) Fill relay/game/daemon/API settings and per-bot keypairs.
3) Set `BOT_COUNT` and optional per-bot models (`BOT_i_MODEL`).
4) Run: `scripts/run_multi_bot_playtest.sh`.
5) Let bots run for 20+ decision opportunities.

Evidence:
- Per-bot stdout: `logs/bot/multi/bot<N>.stdout.log`.
- Per-bot trace JSONL: `logs/bot/multi/bot<N>/bot_trace_<gameId>.jsonl`.

Report:
- Number of bots launched and models used.
- Turn throughput and failures by `errorClass`.
- Most common retry stages and top recurring errors.
- Recommended next fixes.
```
