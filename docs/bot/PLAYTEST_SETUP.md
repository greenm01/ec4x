# EC4X Playtest Setup Guide (OpenCode Primary)

**Last Updated:** 2026-03-02

Primary workflow is now **Human vs OpenCode** turn-by-turn for bug
reproduction and balance iteration. Bot workflows remain available as
legacy soak/stress options.

---

## Prerequisites

### System services (already managed via systemd on this machine)

Both services must be running before any playtest:

```fish
systemctl --user status ec4x-daemon.service
systemctl --user status nostr-relay.service
```

If either is stopped:

```fish
systemctl --user start ec4x-daemon.service
systemctl --user start nostr-relay.service
```

See [daemon setup (user)](../guides/daemon-setup-user.md) if either
service is not installed. For turn resolution options (manual, scheduled,
hybrid), see the
[Turn Resolution Operations runbook](../guides/turn-resolution-operations.md).

### Binaries

```bash
nimble buildAll   # produces bin/ec4x, bin/ec4x-daemon, bin/tui
```

All three must exist. Run `ls bin/` to confirm.

## Scenarios

| File | Players | Map | Use case |
|---|---|---|---|
| `scenarios/standard-4-player.kdl` | 4 | 4 rings (61 systems) | Standard game |
| `scenarios/standard-2-player.kdl` | 2 | 3 rings (37 systems) | Quick 1v1 |

---

## Option A (Primary): Human vs OpenCode (1v1)

Recommended for iterative balancing and bug hunting.

### Fresh Reset After Engine/Daemon/TUI Changes

Use this whenever command formats, turn resolution, player-state sync, or
daemon behavior changed. It avoids stale binaries, stale game DB rows, and
mixed human/LLM wallet state.

```bash
# 1. Rebuild and redeploy the user daemon
./scripts/deploy_daemon_user.sh --logs

# 2. Clear the LLM wallet/cache root used by OpenCode
rm -rf "$HOME/.local/share/ec4x-llm"

# 3. Create a fresh 2-player game and clear normal player cache/data
./scripts/start_opencode_playtest.sh
```

What this does:
- `deploy_daemon_user.sh` rebuilds `bin/ec4x-daemon`, installs it to the user
  bin dir, and restarts `ec4x-daemon`
- `start_opencode_playtest.sh` in default `full` mode runs
  `nim r tools/clean_dev.nim --clean --logs`, then creates a fresh
  `standard-2-player` game and prints invite codes
- the normal player cache under `~/.local/share/ec4x/` is cleared while
  preserving `daemon_identity.kdl`
- the LLM cache is **not** cleared by that script; delete
  `~/.local/share/ec4x-llm` separately

Quick validation after reset:

```bash
./scripts/status_daemon_user.sh
```

Confirm:
- `ec4x-daemon` is active
- `nostr-relay.service` is active
- only the new game slug exists under `data/games/`

### Setup

```bash
# Standard setup (cleans cache/data/logs, creates game, prints invites)
./scripts/start_opencode_playtest.sh

# Join one seat in TUI as the human player
./bin/tui
```

Manual equivalent:

```bash
nim r tools/clean_dev.nim --clean --logs
./bin/ec4x new --scenario=scenarios/standard-2-player.kdl
./bin/ec4x invite <game-slug>
./bin/tui
```

If you need to preserve existing cache/identity for a quick rerun:

```bash
./scripts/start_opencode_playtest.sh --clean-mode none
```

### Turn Loop

1. You play and submit your turn in TUI.
2. Tell OpenCode: `play house <N> for <game-slug> turn <T>`.
3. OpenCode uses `tools/dump_state.nim` plus the LLM toolchain in
   [LLM_PLAYTEST_QUICKREF.md](LLM_PLAYTEST_QUICKREF.md) to inspect,
   claim, and submit through Nostr.
4. For auto-resolve testing, ensure all seats are claimed and all
   players submit through Nostr.
5. Resolve turn manually only when you explicitly want deterministic
   debug control:

```bash
./bin/ec4x-daemon resolve --gameId=<game-slug>
```

6. Analyze outcomes together and repeat.

### Recommended Reset + Join Loop

For the fastest reproducible human-vs-OpenCode cycle:

1. Run the three reset commands in `Fresh Reset After Engine/Daemon/TUI Changes`.
2. Human joins one invite in `./bin/tui`.
3. Human submits turn 1 normally through the TUI.
4. OpenCode claims the other invite with the separate LLM wallet root.
5. OpenCode inspects state with `tools/dump_state.nim`.
6. OpenCode submits through real KDL-over-Nostr, not by DB injection.
7. Verify auto-resolve in daemon logs before trusting the next-turn UI/state.

Claiming notes:
- Use the bare invite token when calling `claim_invite`, not the display
  form with `@localhost:8080`.
- Always pass `--game <slug-or-uuid>` to `claim_invite`.
- Confirm the slot flips to `CLAIMED` in `./bin/ec4x invite <slug>`
  before submitting the LLM turn.

### Notes

- For this workflow, set daemon to manual-only mode to avoid accidental
  auto-advance while only one seat is claimed.
- Runbook: [Turn Resolution Operations](../guides/turn-resolution-operations.md)
- Tool reference: [Dev Tools Reference](../tools/ec4x-play.md)

### Fast Bug Repro Checklist

Use this after each resolved turn when testing engine or TUI fixes:

- `nim r tools/dump_state.nim <game-slug> --house 1`
- `nim r tools/dump_state.nim <game-slug> --house 2`
- `journalctl --user -u ec4x-daemon -n 120 --no-pager`

Check for:
- turn advanced for both houses
- one-hop moves that arrived now show `Hold` and `Mission: None`
- colonize orders do not both succeed and later reject
- commissioned ships join fleets actually at the commissioning colony
- research deposits/purchases appear in the next-turn tech state
- enemy command events are not leaking unexpectedly into player turn events
- a left-open TUI refreshes to the new turn after daemon publish

### Operator Discipline

For OpenCode-vs-human sessions, trust this order of evidence:

1. `./bin/ec4x invite <slug>` for seat claim state
2. `journalctl --user -u ec4x-daemon` for command receipt and resolution
3. `nim r tools/dump_state.nim <slug> --house <N>` for authoritative player state
4. TUI display last

Do not trust:
- `claim_invite` stdout by itself
- `submit_turn_nostr` stdout by itself
- a stale TUI header that has not repainted yet

If logs, DB-facing CLI, and TUI disagree, trust daemon logs plus
`dump_state` and rebuild/redeploy before continuing.

---

## Option B (Legacy): Human vs 3 Bots (4-player)

Standard game with you as one house and 3 LLM-controlled houses.

```bash
# 1. Bootstrap: claims 3 bot seats, reserves 1 for you
python3 scripts/bot/bootstrap_multi_playtest.py \
  --bots 3 \
  --reserve 1 \
  --clean-mode none \
  --scenario scenarios/standard-4-player.kdl \
  --model gpt-4o-mini
```

```bash
# 2. Start all 3 bots
scripts/run_multi_bot_playtest.sh &

# 3. Join as human
./bin/tui
# Paste the invite code from scripts/bot/human_invites.txt
```

---

## Option C (Legacy): Human vs 2 Bots (3-player from 4-player scenario)

Fill 3 of the 4 seats: you + 2 bots. The 4th slot stays empty.
Note: the daemon now requires **all slots claimed** and **all players
submitted** before auto-resolution. With one slot intentionally left
unclaimed, advance turns manually.

```bash
python3 scripts/bot/bootstrap_multi_playtest.py \
  --bots 2 \
  --reserve 1 \
  --clean-mode none \
  --scenario scenarios/standard-4-player.kdl \
  --model gpt-4o-mini

scripts/run_multi_bot_playtest.sh &
./bin/tui
```

---

## Option D (Legacy): Bot-only (automated playtesting, no human)

All seats filled by bots. Useful for stability testing and training
data generation.

```bash
# 4-bot fully automated run
python3 scripts/bot/bootstrap_multi_playtest.py \
  --bots 4 \
  --reserve 0 \
  --scenario scenarios/standard-4-player.kdl \
  --model gpt-4o-mini

scripts/run_multi_bot_playtest.sh
```

For a timed run that automatically stops:

```bash
python3 scripts/bot/bootstrap_multi_playtest.py \
  --bots 4 \
  --reserve 0 \
  --run-seconds 600
# Runs for 10 minutes then stops
```

---

## Clean Behaviour and When to Skip It

This section applies to legacy bootstrap bot workflows (Options B-D).

By default bootstrap runs `tools/clean_dev.nim --clean --logs`, which
wipes:

- `~/.local/share/ec4x/` -- player state (wallet, **TUI identity**,
  cached game state), except `daemon_identity.kdl`
- `data/games/` and `data/players/` -- all game data
- `data/logs/*.log` -- log files

Bootstrap cleanup controls:

- `--clean-mode full` (default): `clean_dev.nim --clean --logs`
- `--clean-mode cache`: clear only `~/.local/share/ec4x/`
- `--clean-mode data`: clear only `data/games`, `data/players` (plus logs)
- `--clean-mode none`: skip cleanup
- `--no-clean-logs`: keep logs when using `full` or `data`

**This destroys your TUI identity.** For human playtests where you need
to preserve identity or cache state, use `--clean-mode none` (legacy
`--no-clean` is still accepted):

```bash
python3 scripts/bot/bootstrap_multi_playtest.py \
  --bots 3 \
  --reserve 1 \
  --clean-mode none \
  --scenario scenarios/standard-4-player.kdl
```

Use default clean mode (`full`) when you want a completely fresh slate (e.g.,
automated bot-only runs where no human TUI identity needs to survive).
If you do want to manually wipe game data without touching player state,
use `tools/clean_dev.nim` directly:

```bash
nim r tools/clean_dev.nim --data        # wipe game data only
nim r tools/clean_dev.nim --cache       # wipe player state only
nim r tools/clean_dev.nim --dry-run     # preview what would be deleted
```

---

## Legacy Bot Prerequisite: LLM API Key

Bot bootstrap/runner reads `BOT_API_KEY` from environment. On this
machine it is defined in your Fish secrets file:

```fish
source ~/.config/fish/secrets.fish
```

OpenCode-vs-human playtesting does not require this.

---

## Legacy Bot: Choosing a Model

The bot defaults to `gpt-4o-mini`. Set `--model` to any
OpenAI-compatible model name:

| Model | Cost | Notes |
|---|---|---|
| `gpt-4o-mini` | Low | Recommended for iterative testing |
| `gpt-4o` | Medium | Better strategic quality |
| `o4-mini` | Low-medium | Strong reasoning, slower |

To use a non-OpenAI provider, set `BOT_BASE_URL` in the generated
`scripts/bot/multi_session.env` to point at any OpenAI-compatible
endpoint before running the bot runner.

---

## Legacy Bot: Where Logs and Traces Are Written

| Path | Contents |
|---|---|
| `logs/bot/multi/run_metadata.json` | Seed, game id, model list, config hash |
| `logs/bot/multi/bot<N>.stdout.log` | Per-bot stdout |
| `logs/bot/multi/bot<N>/bot_trace_<gameId>.jsonl` | Per-turn decision traces |

---

## Legacy Bot: Post-Run Evaluation

```bash
# Feature-family coverage (which command types were used)
python3 scripts/bot/summarize_trace_coverage.py logs/bot/multi

# Stability gates (20+ turn streak, retry rate, success rate)
python3 scripts/bot/evaluate_trace_quality.py logs/bot/multi \
  --require-session-record

# All gates together (coverage + quality + scenario matrix)
scripts/bot/run_acceptance_gates.sh \
  logs/bot/multi \
  scripts/bot/scenario_matrix.example.json
```

---

## Legacy Bot: Env Var Reference

These live in `scripts/bot/multi_session.env` (written by bootstrap).
Edit the file directly to tune a run without re-bootstrapping.

| Variable | Default | Description |
|---|---|---|
| `BOT_RELAYS` | `ws://localhost:8080` | Nostr relay URL(s), comma-separated |
| `BOT_GAME_ID` | *(from bootstrap)* | Game slug |
| `BOT_DAEMON_PUBHEX` | *(from bootstrap)* | Daemon raw-hex pubkey |
| `BOT_COUNT` | *(from bootstrap)* | Number of bot processes |
| `BOT_API_KEY` | `${BOT_API_KEY:-}` | LLM provider API key (from env) |
| `BOT_MODEL_DEFAULT` | `gpt-4o-mini` | Model used when per-bot model not set |
| `BOT_BASE_URL` | `https://api.openai.com/v1` | LLM endpoint base URL |
| `BOT_MAX_RETRIES` | `2` | LLM/validation retries per turn |
| `BOT_REQUEST_TIMEOUT_SEC` | `45` | HTTP timeout to LLM (seconds) |
| `BOT_LOG_ROOT` | `logs/bot/multi` | Root dir for per-bot logs |
| `BOT_START_RELAY` | `0` | Set `1` to auto-start relay binary |
| `BOT_START_DAEMON` | `0` | Set `1` to auto-start daemon binary |
| `BOT_{N}_PLAYER_PRIV_HEX` | *(from bootstrap)* | Bot N private key (hex) |
| `BOT_{N}_PLAYER_PUB_HEX` | *(from bootstrap)* | Bot N public key (hex) |
| `BOT_{N}_MODEL` | *(optional)* | Per-bot model override |

---

## Legacy Bot: Troubleshooting

**Bot exits immediately / can't connect to relay**

Check the relay is up: `systemctl --user status nostr-relay.service`.
The default relay URL is `ws://localhost:8080`. If your relay binds to
a different port, pass `--relay ws://localhost:<port>` to bootstrap and
update `BOT_RELAYS` in the env file.

**`BOT_API_KEY` missing error**

Source your secrets file before running: `source ~/.config/fish/secrets.fish`.

**"Scenario only has N invite codes but M required"**

`--bots + --reserve` exceeds the scenario's `playerCount`. Either
reduce one of the counts or use a scenario with more players.

**Human invite code lost**

Re-run `bin/ec4x invite <game-slug>` to list all slots with their
current status (PENDING / CLAIMED). PENDING slots still have valid
codes. Or check `scripts/bot/human_invites.txt` which bootstrap writes
automatically.

**Bots loop retrying / high retry rate in traces**

Usually indicates the LLM is producing malformed JSON. Check
`logs/bot/multi/bot1.stdout.log` for the raw LLM output. Consider
switching to a stronger model or reducing `BOT_MAX_RETRIES` to surface
errors faster during debugging.

**TUI can't join -- slot already claimed**

Each invite code is single-use. If a bot accidentally claimed your
code, use `bin/ec4x invite <game-slug>` to find remaining PENDING
slots, or re-create the game.

---

## See Also

- [Interactive Debug Play](../guides/interactive-debug-play.md) —
  play turns directly via CLI without Nostr or TUI, useful for bug
  reproduction and agent-assisted play
- [Dev Tools Reference](../tools/ec4x-play.md) —
  `submit_orders`, `dump_state`, and `resolve` tool reference
