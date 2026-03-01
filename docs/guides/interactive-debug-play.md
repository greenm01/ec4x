# Interactive Debug Play

A workflow for manually playing turns using CLI tools — no Nostr, no TUI.
Designed for bug reproduction, state inspection, and collaborative play with
a coding agent (e.g. Claude in OpenCode).

In this mode you control one or both houses directly:
- Inspect state with `dump_state`
- Write orders in KDL and submit with `submit_orders`
- Advance the turn with `ec4x-daemon resolve`
- Repeat

---

## Prerequisites

- Game daemon running: `systemctl --user status ec4x-daemon`
  (see [daemon setup (user)](daemon-setup-user.md) if not installed)
- Binaries built: `nimble buildAll`
- A game exists in `data/games/<slug>/` (see Setup below)
- For turn resolution options (manual, scheduled, hybrid) see the
  [Turn Resolution Operations runbook](turn-resolution-operations.md)

---

## Setup: Create a Debug Game

### Option A: From an existing playtest bootstrap

Run the bootstrap script with `--reserve 2` to leave both invite slots
unclaimed, then join both houses yourself:

```bash
python scripts/bot/bootstrap_multi_playtest.py \
  --scenario scenarios/standard-2-player.kdl \
  --bots 0 --reserve 2 --no-clean

# Prints two invite codes, also saved to scripts/bot/human_invites.txt
cat scripts/bot/human_invites.txt
```

### Option B: Manual setup via daemon CLI

```bash
# Create game
bin/ec4x-daemon new --name "debug-game" \
  --scenario scenarios/standard-2-player.kdl

# List to get the slug
bin/ec4x-daemon list

# Generate 2 invite codes
bin/ec4x-daemon invite <game-slug>
bin/ec4x-daemon invite <game-slug>
```

### Option C: Quick 2-player scenario (recommended for 1v1 debugging)

```bash
# Use the 2-player scenario (37 systems, faster games)
python scripts/bot/bootstrap_multi_playtest.py \
  --scenario scenarios/standard-2-player.kdl \
  --bots 0 --reserve 2 --no-clean
```

After setup, note your **game slug** (e.g. `autumn-sky`) — you'll use it in
every command.

---

## The Debug Play Loop

### Step 1: Inspect state

```bash
nim r tools/dump_state.nim <game-slug> --house 1
nim r tools/dump_state.nim <game-slug> --house 2
```

This shows the full fog-of-war filtered view for each house: economy,
technology, colonies, fleets, diplomacy, and all turn events.

Redirect to a file for diffing or sharing with an agent:

```bash
nim r tools/dump_state.nim autumn-sky --house 1 > /tmp/h1-turn3.txt
```

### Step 2: Write orders in KDL

Create an orders file for each house you're playing. The format:

```kdl
orders house=1 turn=3 {
  // Move fleet A1 to system 7
  move-fleet fleet="A1" target-system=7

  // Build a corvette at colony 2
  build colony=2 type="Corvette"

  // Set diplomatic state
  diplomacy target-house=2 action="DeclareHostile"
}
```

Save as e.g. `orders/h1-t3.kdl`. The `house` and `turn` values must match
the current game state.

**Reference:** See `docs/guides/tui-expert-commands.md` for the full KDL
order syntax. The `tools/submit_orders.nim` preamble also lists required
fields.

### Step 3: Submit orders

```bash
# Submit for each house
nim r tools/submit_orders.nim <game-slug> orders/h1-t3.kdl
nim r tools/submit_orders.nim <game-slug> orders/h2-t3.kdl --house 2
```

The `--house N` flag overrides the house ID in the KDL header. Useful when
you copy a template between houses.

You can submit for one house, inspect, then submit for the other. Later
submissions for the same house/turn overwrite earlier ones (last-write wins
by timestamp).

### Step 4: Resolve the turn

```bash
bin/ec4x-daemon resolve <game-slug>
```

This runs full deterministic resolution: combat, production, research,
diplomacy. Missing orders default to `Hold` for all fleets.

### Step 5: Compare state before/after

```bash
nim r tools/dump_state.nim <game-slug> --house 1 > /tmp/h1-t4.txt
diff /tmp/h1-t3.txt /tmp/h1-t4.txt
```

Or share the dump output directly with an agent for analysis.

**Repeat from Step 1.**

---

## Controlling Both Houses

When debugging a specific interaction (e.g. combat, diplomacy), you'll want
to control both houses precisely:

```bash
# Submit house 1 orders
nim r tools/submit_orders.nim autumn-sky orders/attacker.kdl --house 1

# Submit house 2 orders (use --house to override the file's header)
nim r tools/submit_orders.nim autumn-sky orders/defender.kdl --house 2

# Resolve
bin/ec4x-daemon resolve autumn-sky

# Inspect both views
nim r tools/dump_state.nim autumn-sky --house 1
nim r tools/dump_state.nim autumn-sky --house 2
```

---

## Reproducing a Bug

1. Note the game slug, turn number, and which house is affected
2. `dump_state --house N` to capture the pre-bug state
3. Write minimal orders that reproduce the issue
4. `submit_orders` + `resolve`
5. `dump_state` again to confirm the bug is visible in events/state
6. Share both dumps + the orders file with the issue report

---

## Tips

- **Save state snapshots:** `dump_state > /tmp/t<N>-h<N>.txt` before every
  resolve. Easy to diff and share.
- **Seed reproducibility:** The daemon uses the game's stored seed — resolves
  are deterministic given the same orders. Re-submitting the same orders and
  re-resolving gives the same outcome.
- **Don't use `--clean` when you care about your TUI identity:** The
  bootstrap `--no-clean` flag skips wiping `~/.local/share/ec4x/`, preserving
  your `identity.kdl`.
- **Check daemon logs:** `journalctl --user -u ec4x-daemon -f` for real-time
  daemon output.
- **Minimal orders:** If you only care about one house, submit an empty
  (hold-all) orders file for the other house:
  ```kdl
  orders house=2 turn=3 {
    // hold all — no commands needed
  }
  ```

---

## See Also

- [Dev Tools Reference](../tools/ec4x-play.md) — `submit_orders`,
  `dump_state`, and `resolve` reference
- [Bot Playtest Setup](../bot/PLAYTEST_SETUP.md) — human-vs-bot setup
- [Turn Resolution Operations](turn-resolution-operations.md) —
  manual, scheduled, and hybrid turn advancement runbook
- [Testing Auto-Resolve](testing-auto-resolve.md) — automated integration
  test workflow
