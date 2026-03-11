# LLM Playtest Quick Reference

Token-efficient operator guide for local Human vs LLM EC4X playtests.

Use this when an LLM needs to:
- create or inspect its local wallet
- claim an invite
- inspect state
- submit a real turn over Nostr
- rely on daemon auto-resolve

For full environment setup, see [PLAYTEST_SETUP.md](PLAYTEST_SETUP.md).

---

## Rules That Matter

- Use a dedicated wallet root for the LLM.
- Claim the invite before trying to submit turns.
- Submit turns through `submit_turn_nostr`, not `submit_orders`.
- Auto-resolve triggers only after:
  - all seats are claimed
  - all claimed players submit through the real Nostr path

If you write commands directly into the DB, you are bypassing the player
flow and may not trigger auto-resolve.

---

## Recommended Wallet Root

```bash
export XDG_DATA_HOME="$HOME/.local/share/ec4x-llm"
```

This keeps the LLM identity separate from the human player's wallet.

---

## One-Time Setup

Create the wallet if needed:

```bash
XDG_DATA_HOME="$HOME/.local/share/ec4x-llm" \
  ./tools/player_wallet init
```

Show the active identity:

```bash
XDG_DATA_HOME="$HOME/.local/share/ec4x-llm" \
  ./tools/player_wallet show-active
```

---

## Join a Game

Before claiming, get the canonical game ID and bare invite code:

```bash
./bin/ec4x invite <game-slug>
```

Use:
- the game UUID shown in logs or `data/games/<slug>/ec4x.db`
- the bare invite token, not the display form with `@localhost:8080`

Claim the invite with the LLM wallet:

```bash
XDG_DATA_HOME="$HOME/.local/share/ec4x-llm" \
  ./tools/claim_invite ws://localhost:8080 <invite-code> --game <game-id>
```

Example:

```bash
XDG_DATA_HOME="$HOME/.local/share/ec4x-llm" \
  ./tools/claim_invite ws://localhost:8080 pinched-square \
  --game 442e007c-5e92-4d10-a87e-b9a1229e3c34
```

Notes:
- Use `ws://localhost:8080`, not bare `localhost:8080`.
- Prefer the bare code like `pinched-square`, not
  `pinched-square@localhost:8080`.
- Always pass `--game`. The tool now resolves slug/name/UUID tokens to
  the canonical game UUID before publishing the slot claim.
- Verify the seat flips to `CLAIMED` with `./bin/ec4x invite <slug>`
  before assuming turn submission will count.

---

## Inspect State

Read the current fog-of-war state for your house:

```bash
nim r tools/dump_state.nim <game-slug> --house <N>
```

Example:

```bash
nim r tools/dump_state.nim phase-sapling-awful --house 1
```

Use this as the main planning input for the LLM.

Map-awareness note:
- Player state intentionally includes the full starmap topology from turn 1:
  all system names and jump lanes are public information.
- Fog-of-war still hides current contents, ownership changes, fleet presence,
  and detailed intel until observed.

---

## Submit a Turn

Create a KDL orders file, then submit it through Nostr:

```bash
XDG_DATA_HOME="$HOME/.local/share/ec4x-llm" \
  ./tools/submit_turn_nostr \
  ws://localhost:8080 \
  <game-slug> \
  /tmp/orders.kdl
```

Optional house override:

```bash
XDG_DATA_HOME="$HOME/.local/share/ec4x-llm" \
  ./tools/submit_turn_nostr \
  ws://localhost:8080 \
  <game-slug> \
  /tmp/orders.kdl \
  --house <N>
```

Requirements:
- the house in the orders file must match the claimed invite slot
- the turn in the KDL header must match the current turn

---

## Minimal Turn Loop

1. Claim seat.
2. Inspect state with `dump_state`.
3. Write KDL orders.
4. Submit with `submit_turn_nostr`.
5. Wait for auto-resolve after all players submit.
6. Re-read state for the next turn.

For a full fresh restart after engine/daemon changes, see the
`Fresh Reset After Engine/Daemon/TUI Changes` section in
[PLAYTEST_SETUP.md](PLAYTEST_SETUP.md).

---

## KDL Skeleton

```kdl
orders turn=2 house=(HouseId)1 {
  fleet (FleetId)1 {
    move to=(SystemId)10
  }
}
```

Use actual fleet and system IDs from `dump_state`.

## KDL Syntax Notes

Use the canonical parser syntax, not guessed variants.

```kdl
orders turn=1 house=(HouseId)2 {
  fleet (FleetId)5 hold
  fleet (FleetId)6 {
    move to=(SystemId)32 roe=6
  }
  fleet (FleetId)7 {
    colonize system=(SystemId)36
  }

  build (ColonyId)2 {
    ship destroyer
    ship scout quantity=2
    ship etac
    facility shipyard
    ground army quantity=2
    ground marine quantity=2
    ground ground-battery
  }

  research {
    erp 50
    srp 50
    mrp 60
    purchase economic
    purchase science
    purchase military
    purchase cst
  }
}
```

Rules:
- Root header should be `orders turn=<N> house=(HouseId)<H>`.
- Fleet orders use `fleet (FleetId)<id> ...`.
- `move` uses `to=(SystemId)<id>`.
- `colonize`, `scout-system`, `scout-colony`, `blockade`, `bombard`,
  `invade`, and similar targeted mission orders use
  `system=(SystemId)<id>`.
- Builds use `build (ColonyId)<id> { ... }`.
- Ship names are lowercase KDL tokens such as `destroyer`, `scout`,
  `light-cruiser`, `etac`, `troop-transport`.
- Ground names are `army`, `marine`, `ground-battery`,
  `planetary-shield`.
- Research deposits and purchases belong inside a `research { ... }`
  block.
- On turn 1, empty orders are legal, but for bug-hunting prefer active
  submissions that touch fleet movement, colonization, production, and
  research in the same packet.

## Turn 1 Active Opening Template

For a fresh 2-player start with one home colony, 4 starting fleets, and
2 ETAC fleets:

1. Send both ETAC fleets to adjacent colonizable systems.
2. Send the non-ETAC combat fleets outward instead of leaving all
   combat power stacked at home.
3. Queue at least one ship build and one ground-unit build.
4. Deposit PP into ERP/SRP/MRP and queue early purchases so next-turn
   state exercises research advancement too.

Example opening pattern for House 2 from `dizzy-vane-prying` turn 1:

```kdl
orders turn=1 house=(HouseId)2 {
  fleet (FleetId)5 {
    colonize system=(SystemId)36
  }
  fleet (FleetId)6 {
    colonize system=(SystemId)33
  }
  fleet (FleetId)7 {
    move to=(SystemId)32 roe=6
  }
  fleet (FleetId)8 {
    move to=(SystemId)36 roe=6
  }

  build (ColonyId)2 {
    ship destroyer
    ship scout
    ship etac
    ground army quantity=2
    ground marine quantity=2
    ground ground-battery
  }

  research {
    erp 50
    srp 50
    mrp 60
    purchase economic
    purchase science
    purchase military
    purchase cst
  }
}
```

This is a good default bug-hunt opener because it exercises:
- fleet move validation
- colonize resolution
- production queue creation across ship and ground projects
- research deposit conversion
- same-turn EL/SL/ML/branch purchase sequencing

## Fresh Runtime Checklist

Use this exact flow after engine, daemon, parser, or msgpack changes:

1. `./scripts/deploy_daemon_user.sh --logs`
2. `rm -rf "$HOME/.local/share/ec4x-llm"`
3. `./scripts/start_opencode_playtest.sh`
4. Human joins in `./bin/tui` and submits turn 1.
5. Run `./bin/ec4x invite <slug>` and copy the bare invite token for the
   LLM seat.
6. `XDG_DATA_HOME=/tmp/ec4x-llm ./tools/player_wallet init`
7. `XDG_DATA_HOME=/tmp/ec4x-llm ./tools/claim_invite ws://localhost:8080 <bare-code> --game <slug-or-uuid>`
8. Re-run `./bin/ec4x invite <slug>` and confirm both seats are
   `CLAIMED`.
9. Submit the LLM turn through `submit_turn_nostr`.
10. Check `journalctl --user -u ec4x-daemon -n 120 --no-pager`.

## Verification Gate After Every Step

Do not assume success from tool stdout alone. Verify each state change:

After claim:
- `./bin/ec4x invite <slug>`
- Expect both seats to show `CLAIMED`

After submit:
- `journalctl --user -u ec4x-daemon -n 120 --no-pager`
- Expect `Received and saved commands`
- Expect `All players submitted! Auto-triggering resolution`
- Expect `Saved full game state (msgpack) | turn= <N+1>`

After resolve:
- `nim r tools/dump_state.nim <slug> --house 1`
- `nim r tools/dump_state.nim <slug> --house 2`
- Expect both dumps to show `Turn: <N+1>`

If any one of those checks fails, stop and debug before playing the next turn.

## Known Failure Modes

`claim_invite` says `claimed` but seat stays `PENDING`:
- Re-check with `./bin/ec4x invite <slug>`
- Use bare invite token, not `code@localhost:8080`
- Pass `--game <slug-or-uuid>`
- If still pending, redeploy daemon with
  `./scripts/deploy_daemon_user.sh --logs`

Turn submit publishes but turn does not advance:
- Check daemon logs for `Command packet turn mismatch`
- Check both seats are actually `CLAIMED`
- Check daemon was rebuilt after transport/msgpack changes
- Confirm `dump_state` for both houses still shows the same current turn

DB/game metadata says turn advanced but `dump_state` still shows old turn:
- This indicates state blob persistence is broken or daemon is stale
- Redeploy daemon from current checkout immediately
- Do not trust the TUI header until `dump_state` agrees with DB/logs

Relay history noise after daemon restart:
- Old bad slot-claim events may replay briefly from the relay
- Ignore startup `Invite code not found in any game` spam unless it
  continues after a fresh claim attempt
- Judge the current attempt by fresh timestamps plus `ec4x invite`
  and `dump_state`, not by old relay backlog alone

---

## 4X Gameplay Heuristics

Use these as defaults unless the current state strongly contradicts them.

### Explore

- Push scouts and light fleets into adjacent unknown systems early.
- Prefer routes that reveal multiple branch points.
- Do not overstack scouts unless enemy contact is likely.
- Keep at least one mobile fleet near the core for reaction.

### Expand

- Colonize safe nearby worlds first.
- Prioritize reach, survivability, and output over perfection.
- Use ETAC fleets aggressively in the early game.
- Avoid sending colonizers naked into obvious enemy intercept lanes.

### Exploit

- Spend early PP on growth, not prestige vanity.
- Keep shipbuilding running if treasury allows.
- Use research to unlock practical near-term gains.
- Do not starve military movement just to overinvest in research.

### Exterminate

- Fight when you have local superiority or tempo advantage.
- Punish exposed ETACs, isolated scouts, and weak border colonies.
- Avoid fair fights in the early expansion phase.
- Convert intel into pressure before the opponent consolidates.

---

## Early-Game Defaults

Turns 1-3:
- scout outward
- colonize reachable safe systems
- keep treasury flexible for expansion and emergency builds
- avoid premature battles unless they kill enemy expansion

Turns 4-8:
- consolidate new colonies
- improve military mobility and construction capacity
- start contesting key lanes and forward systems

Midgame onward:
- shift from raw expansion to denial
- attack logistics, colonies, and exposed fleets
- turn economic lead into positional control

---

## Common Failure Modes

- Claimed the seat but submitted with the wrong wallet.
- Submitted with `submit_orders` instead of `submit_turn_nostr`.
- Used the wrong game slug or wrong turn in KDL.
- Submitted before all seats were claimed and expected auto-resolve.
- Used bare `localhost:8080` instead of `ws://localhost:8080`.
- Forgot that `start_opencode_playtest.sh` clears the normal player cache, but
  does not clear the separate LLM wallet root at `~/.local/share/ec4x-llm`.
- Played against a stale daemon binary after changing engine/msgpack code.

---

## Bug Hunt Pass

After each resolved turn, do a quick verification pass before continuing:

```bash
nim r tools/dump_state.nim <game-slug> --house 1
nim r tools/dump_state.nim <game-slug> --house 2
journalctl --user -u ec4x-daemon -n 120 --no-pager
```

Look for:
- `Turn: <N+1>` in both house dumps
- expected colonies/fleets/builds present in state
- one-turn completed moves now showing `Cmd: Hold` and `Mission: None`
- research deposits and purchases reflected in tech levels / RP pools
- no bogus `CommandRejected` after a successful colonize
- no hostile command-event leaks that the player should not know
- daemon log lines showing both command packets saved and turn resolution completed

If the TUI was left open during auto-resolve, also confirm it repainted to the
new turn instead of staying on the old header.

---

## Fast Checklist

```text
wallet root set?
wallet exists?
invite claimed?
right house?
right turn?
orders use real IDs?
submitted over Nostr?
all seats claimed?
daemon rebuilt/redeployed after engine changes?
llm cache cleared for fresh games?
```
