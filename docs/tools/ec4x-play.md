# EC4X Dev Tools Reference

Tools for interactive debug play and game state inspection. All tools run
from the project root via `nim r tools/<tool>.nim`.

---

## submit_orders

Submit a KDL orders file to a game's database.

```
nim r tools/submit_orders.nim <game-slug> <orders.kdl> [--house N]
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `<game-slug>` | Game identifier — matches `data/games/<slug>/` |
| `<orders.kdl>` | Path to a KDL orders file |
| `--house N` | Override the house ID in the file (1-based) |

The `--house` flag is useful when controlling both houses in a debug session,
where you may submit orders from a single template with the house overridden.

**Examples:**

```bash
# Submit orders for house as specified in the KDL header
nim r tools/submit_orders.nim autumn-sky orders/house1.kdl

# Override to house 2 (useful when controlling both houses)
nim r tools/submit_orders.nim autumn-sky orders/house2.kdl --house 2
```

**Orders file format:**

```kdl
orders house=1 turn=3 {
  move-fleet fleet="A1" target-system=5
  build colony=2 type="Corvette"
}
```

The house and turn in the KDL header must match the current game state
unless `--house` overrides the house. Submitting orders for a turn that has
already been resolved will be ignored (the DB uses `submitted_at` ordering).

---

## dump_state

Dump fog-of-war filtered game state for a house. Output is compact,
LLM-optimized structured text suitable for analysis or debugging.

```
nim r tools/dump_state.nim <game-slug> --house N
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `<game-slug>` | Game identifier — matches `data/games/<slug>/` |
| `--house N` | House ID to view state for (1-based, required) |

**Example:**

```bash
# Print state to terminal
nim r tools/dump_state.nim autumn-sky --house 1

# Save to file for later reference or diff
nim r tools/dump_state.nim autumn-sky --house 1 > /tmp/state-t3-h1.txt

# Compare state before and after a resolve
nim r tools/dump_state.nim autumn-sky --house 1 > /tmp/before.txt
bin/ec4x-daemon resolve autumn-sky
nim r tools/dump_state.nim autumn-sky --house 1 > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt
```

**Output sections:**

| Section | Contents |
|---------|----------|
| Header | Game slug, turn number, viewing house |
| Economy | Treasury, net income, tax rate, EBP/CIP pools |
| Technology | All tech levels (EL, SL, CST, WEP, TER, ELI…) + research points |
| Colonies | Per colony: system, population, infrastructure, industry, output, facilities, queues, terraforming |
| Fleets | Per fleet: system, status, ROE, command/mission, ship counts by class |
| Ground Forces | Per-colony breakdown of armies/marines/batteries/shields, units on transports |
| Orbital Assets | Neorias (shipyard/spaceport/drydock) and Kastras (starbases) with combat stats |
| Intelligence | Visible systems count, enemy colony/fleet estimates with intel turn |
| Diplomacy | Relation table, pending proposals, eliminated houses |
| Public Standings | Prestige + colony counts for all houses, sorted |
| Act Progression | Current act and start turn |
| Turn Events | All events filtered for this house — compact one-line per event |

---

## bin/ec4x-daemon resolve

Manually trigger deterministic turn resolution for a game. Use after all
houses have submitted orders (or when forcing resolution in debug play).

```
bin/ec4x-daemon resolve <game-slug>
```

**Example:**

```bash
bin/ec4x-daemon resolve autumn-sky
```

This replicates what the daemon does automatically when all players have
submitted, but without waiting for the timer or player count threshold. Safe
to call even if not all houses have submitted — missing orders default to
`Hold` for all fleets.

---

## See Also

- [Interactive Debug Play Guide](../guides/interactive-debug-play.md) —
  step-by-step workflow using these tools
- [Turn Resolution Operations](../guides/turn-resolution-operations.md) —
  manual, scheduled, and hybrid turn advancement runbook
- [Bot Playtest Setup](../bot/PLAYTEST_SETUP.md) —
  setting up human-vs-bot games
- [Testing Auto-Resolve](../guides/testing-auto-resolve.md) —
  automated integration test reference
