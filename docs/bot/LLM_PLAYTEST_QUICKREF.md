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

Claim the invite with the LLM wallet:

```bash
XDG_DATA_HOME="$HOME/.local/share/ec4x-llm" \
  ./tools/claim_invite ws://localhost:8080 <invite-code>
```

Example:

```bash
XDG_DATA_HOME="$HOME/.local/share/ec4x-llm" \
  ./tools/claim_invite ws://localhost:8080 pinched-square
```

Notes:
- Use `ws://localhost:8080`, not bare `localhost:8080`.
- The invite code already identifies the game and house slot.

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
```
