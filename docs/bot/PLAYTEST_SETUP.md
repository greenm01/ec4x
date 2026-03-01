# EC4X Bot Playtest Setup Guide

**Last Updated:** 2026-03-01

Step-by-step procedure for running playtests with LLM bots -- either
fully automated (bots only) or mixed human + bots.

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

### LLM API key

The bootstrap script and bot runner read `BOT_API_KEY` from the
environment. On this machine it is defined in your Fish secrets file.
Source it before running any playtest command:

```fish
source ~/.config/fish/secrets.fish
```

---

## Scenarios

| File | Players | Map | Use case |
|---|---|---|---|
| `scenarios/standard-4-player.kdl` | 4 | 4 rings (61 systems) | Standard game |
| `scenarios/standard-2-player.kdl` | 2 | 3 rings (37 systems) | Quick 1v1 |

---

## Option A: Human vs 1 Bot (1v1)

Uses the 2-player scenario. Fastest setup for iterative testing.

```bash
# 1. Bootstrap: creates game, generates bot key, claims 1 bot seat,
#    leaves 1 seat for you. Writes scripts/bot/multi_session.env.
#    --no-clean preserves your TUI identity (identity.kdl).
python3 scripts/bot/bootstrap_multi_playtest.py \
  --bots 1 \
  --reserve 1 \
  --no-clean \
  --scenario scenarios/standard-2-player.kdl \
  --model gpt-4o-mini

# Output will include your invite code, e.g.:
#   [bootstrap] unclaimed invite codes for human players:
#     player1: abc123@ws://localhost:8080
#   [bootstrap] invite codes saved to: scripts/bot/human_invites.txt
```

```bash
# 2. Start the bot (runs in background)
scripts/run_multi_bot_playtest.sh &

# 3. Launch TUI and join with your invite code
./bin/tui
# Paste the invite code shown above into the join dialog
```

---

## Option B: Human vs 3 Bots (4-player)

Standard game with you as one house and 3 LLM-controlled houses.

```bash
# 1. Bootstrap: claims 3 bot seats, reserves 1 for you
python3 scripts/bot/bootstrap_multi_playtest.py \
  --bots 3 \
  --reserve 1 \
  --no-clean \
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

## Option C: Human vs 2 Bots (3-player from 4-player scenario)

Fill 3 of the 4 seats: you + 2 bots. The 4th slot stays empty.
Note: the daemon resolves turns only when **all claimed slots** have
submitted -- unclaimed slots do not block resolution.

```bash
python3 scripts/bot/bootstrap_multi_playtest.py \
  --bots 2 \
  --reserve 1 \
  --no-clean \
  --scenario scenarios/standard-4-player.kdl \
  --model gpt-4o-mini

scripts/run_multi_bot_playtest.sh &
./bin/tui
```

---

## Option D: Bot-only (automated playtesting, no human)

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

By default bootstrap runs `tools/clean_dev.nim --clean --logs`, which
wipes:

- `~/.local/share/ec4x/` -- player state (wallet, **TUI identity**,
  cached game state), except `daemon_identity.kdl`
- `data/games/` and `data/players/` -- all game data
- `data/logs/*.log` -- log files

**This destroys your TUI identity.** For human playtests, always pass
`--no-clean` so your `identity.kdl` and any existing game data are
preserved:

```bash
python3 scripts/bot/bootstrap_multi_playtest.py \
  --bots 3 \
  --reserve 1 \
  --no-clean \
  --scenario scenarios/standard-4-player.kdl
```

Only omit `--no-clean` when you want a completely fresh slate (e.g.,
automated bot-only runs where no human TUI identity needs to survive).
If you do want to manually wipe game data without touching player state,
use `tools/clean_dev.nim` directly:

```bash
nim r tools/clean_dev.nim --data        # wipe game data only
nim r tools/clean_dev.nim --cache       # wipe player state only
nim r tools/clean_dev.nim --dry-run     # preview what would be deleted
```

---

## Choosing a Model

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

## Where Logs and Traces Are Written

| Path | Contents |
|---|---|
| `logs/bot/multi/run_metadata.json` | Seed, game id, model list, config hash |
| `logs/bot/multi/bot<N>.stdout.log` | Per-bot stdout |
| `logs/bot/multi/bot<N>/bot_trace_<gameId>.jsonl` | Per-turn decision traces |

---

## Post-Run Evaluation

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

## Env Var Reference

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

## Troubleshooting

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
