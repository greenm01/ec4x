# TUI Optimistic Updates

**Status:** Implemented  
**Relevant files:**
- `src/player/sam/tui_model.nim` — model types, pristine caches, rebuild proc
- `src/player/sam/acceptors.nim` — staging entry points, ship selector filter
- `src/player/tui/sync.nim` — pristine cache snapshot on server sync
- `src/player/tui/adapters.nim` — `colonyToDetailData` merges staged builds
- `src/player/tui/view_render.nim` — rendering; passes staged data to adapters

---

## Problem

All commands staged by the player are held locally until the turn is
submitted. The server resolves them during `resolveTurnDeterministic`
(ZTCs at CMD5, fleet commands at CMD6, production at CMD7, etc.). The
client will not receive authoritative results until the next turn delta
(Nostr kind 30403).

The TUI must therefore show the effect of staged commands immediately
rather than waiting for turn resolution. Two distinct patterns are used
depending on the domain.

---

## Two Patterns

### Pattern A — Staged-Collection Rendering

Used by: **tax rate, espionage, diplomacy, colony management toggles,
research allocation**

The UI holds a staged value alongside the server value. Renderers
read the staged value when present and fall back to the server value.
No mutation of `model.view.*` occurs and no pristine caches are needed.

| Domain | Staged field | Renderer preference |
|---|---|---|
| Tax rate | `model.ui.stagedTaxRate` | `stagedTaxRate.get(houseTaxRate)` |
| Espionage EBP/CIP invest | `model.ui.stagedEbpInvestment` / `stagedCipInvestment` | helpers `espionageEbpTotal`, `espionageEbpAvailable` |
| Espionage actions | `model.ui.stagedEspionageActions` | `espionageQueuedTotalEbp` helper |
| Diplomacy | `model.ui.stagedDiplomaticCommands` | overlaid onto `model.view.diplomaticRelations` in renderer |
| Colony mgmt toggles | `model.ui.stagedColonyManagement` | applied to `PlanetDetailData` before render |
| Research allocation | `model.ui.researchAllocation` | mutated directly; no server field used |

### Pattern B — Active View Mutation with Pristine Rebuild

Used by: **fleet commands, Zero-Turn Commands (ZTCs), colony build queue**

`model.view.*` and related UI caches are mutated immediately on
staging. A pristine snapshot (taken at server sync) allows the full
set of optimistic updates to be rebuilt deterministically whenever a
command is dropped or reordered.

---

## Pattern B — Architecture

### Three Data Layers (fleet/ZTC domain)

```
┌──────────────────────────────────────────────────────────────┐
│  PRISTINE LAYER  (set once per server sync, never mutated)   │
│  model.ui.pristineFleets                                     │
│  model.ui.pristineFleetConsoleFleetsBySystem                 │
└───────────────────────────┬──────────────────────────────────┘
                            │  reset baseline for rebuild
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  ACTIVE VIEW LAYER  (mutated by optimistic updates)          │
│  model.view.fleets                          (ListView)       │
│  model.ui.fleetConsoleFleetsBySystem        (SystemView)     │
└───────────────────────────┬──────────────────────────────────┘
                            │  rendered directly to screen
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  ENGINE DATA LAYER  (pristine, never mutated by TUI)         │
│  model.view.ownFleetsById    Table[int, Fleet]               │
│  model.view.ownShipsById     Table[int, Ship]                │
└──────────────────────────────────────────────────────────────┘
```

The **Engine Data Layer** (`ownFleetsById`, `ownShipsById`) is the
authoritative server state. It is populated by `syncPlayerStateToModel`
and is **never modified** by staging. It is used only to compute AS/DS
and composition stats for optimistic updates.

The **Pristine Layer** is a snapshot of the Active View Layer taken
immediately after a clean server sync. It is also never modified by
staging. It exists solely as a reset baseline.

The **Active View Layer** is what gets modified by staging and what
the renderer reads. It starts as a copy of the Pristine Layer and
diverges as commands are staged.

### Colony build queue

`model.ui.stagedBuildCommands` is the staged collection. Rather than
keeping a pristine cache of colony data, staged builds are merged into
`PlanetDetailData` at adapter time (in `colonyToDetailData` and
`colonyToDetailDataFromPS` in `src/player/tui/adapters.nim`). Staged
items appear in the construction panel with status `"Staged"` alongside
server-side projects.

The colony list and build/queue modals also show staged counts and
quantities via separate overlay logic that has been in place since the
build staging feature was introduced.

---

## Pattern B — Lifecycle

### 1. Server Sync (`syncPlayerStateToModel`)

At the end of `syncPlayerStateToModel` in `src/player/tui/sync.nim`:

```nim
model.ui.pristineFleets = model.view.fleets
model.ui.pristineFleetConsoleFleetsBySystem =
  model.ui.fleetConsoleFleetsBySystem
```

This is the only place pristine caches are written. After this point,
any staged commands will mutate only the Active View Layer.

If there are already staged commands at sync time (e.g. the player
opened a cached draft), `reapplyAllOptimisticUpdates` should be called
immediately after sync to re-apply them against the fresh pristine state.

### 2. Staging a Command

When the player confirms a ZTC or FleetCommand, the staging entry
points apply an optimistic update **immediately** to the Active View
Layer:

- `stageZeroTurnCommand` → calls `applyZeroTurnCommandOptimistically`
- `stageFleetCommand` → calls `updateFleetInfoFromStagedCommand`

Both update `model.view.fleets` and
`model.ui.fleetConsoleFleetsBySystem` in place. The pristine caches
are **not touched**.

### 3. Dropping a Command

When the player drops a staged command (e.g. `:drop 2` in expert
console), `dropStagedCommand` removes the entry from the staged list
and then calls `reapplyAllOptimisticUpdates`.

`reapplyAllOptimisticUpdates` in `src/player/sam/tui_model.nim`:

```nim
proc reapplyAllOptimisticUpdates*(model: var TuiModel) =
  model.view.fleets = model.ui.pristineFleets
  model.ui.fleetConsoleFleetsBySystem =
    model.ui.pristineFleetConsoleFleetsBySystem
  for cmd in model.ui.stagedZeroTurnCommands:
    model.applyZeroTurnCommandOptimistically(cmd)
  for _, cmd in model.ui.stagedFleetCommands.pairs:
    model.updateFleetInfoFromStagedCommand(cmd)
```

ZTCs are replayed first (matching CMD5 engine execution order), then
FleetCommands. This guarantees the UI always reflects exactly what the
engine will produce.

---

## What Each ZTC Does to the Active View Layer

| Command        | Active View Effect                                          |
|----------------|-------------------------------------------------------------|
| `Reactivate`   | `statusLabel → "Active"`, `commandLabel → "Hold"`, `command = 0`, `isIdle = true` |
| `MergeFleets`  | Add source stats to target; remove source fleet from both views |
| `TransferShips`| Move selected-ship stats src→target; remove source if empty |
| `DetachShips`  | Decrement source stats only (no new fleet entry — engine assigns real FleetId at CMD5) |
| Cargo/Fighter ops | No-op (FleetInfo has no marine/fighter count fields)     |

AS and DS values are computed by summing `ship.stats.attackStrength` /
`ship.stats.defenseStrength` from `ownShipsById` for the relevant ship
set. The 50%/0% reserve/mothball combat penalty is applied by the engine
at combat time and is **not** stored in `FleetInfo`, so `Reactivate`
requires no AS/DS recalculation.

---

## Double-Booking Prevention

The ship selector modal (`openShipSelectorForZtc`) reads from the
Engine Data Layer (`ownFleetsById`/`ownShipsById`), which is never
mutated. Without filtering, a player could select the same ship for
two consecutive `TransferShips` or `DetachShips` commands.

To prevent this, before building the selector rows, the function
collects all ship IDs already committed to leave this fleet via a
previously staged `TransferShips` or `DetachShips`:

```nim
var alreadyStagedShips = initHashSet[ShipId]()
for staged in model.ui.stagedZeroTurnCommands:
  if staged.commandType in {TransferShips, DetachShips} and
      staged.sourceFleetId.isSome and
      int(staged.sourceFleetId.get()) == sourceFleetId:
    for sid in staged.shipIds:
      alreadyStagedShips.incl(sid)
```

Any ship in this set is skipped when building the selector rows. The
engine would reject the second command anyway (the ship is no longer in
the source fleet at CMD5), but preventing selection keeps the UI
honest and avoids confusing zero-effect submits.

---

## Invariants

1. **Pristine caches are read-only after sync.** Only `syncPlayerStateToModel` may write to `pristineFleets` and `pristineFleetConsoleFleetsBySystem`.
2. **Engine data is read-only always.** `ownFleetsById` and `ownShipsById` are never modified by staging or optimistic updates.
3. **Every command drop triggers a full rebuild.** Partial reverts are not attempted — `reapplyAllOptimisticUpdates` always resets to pristine and replays the full remaining list.
4. **Replay order mirrors engine execution order.** ZTCs first (CMD5), then FleetCommands. Swapping this order would produce incorrect intermediate states.
5. **DetachShips creates no new fleet entry in the UI.** The engine assigns the real `FleetId` during CMD5 and the UI re-syncs on the next turn delta. The TUI only decrements the source fleet's stats.
6. **Pattern A domains never mutate `model.view.*`.** Tax, espionage, diplomacy, colony management, and research staged values live entirely in `model.ui.*` and are read by renderers and helpers directly.

---

## Extension Points

**When `FleetInfo` grows marine/fighter count fields:**  
Cargo and fighter ZTCs (`LoadCargo`, `UnloadCargo`, `LoadFighters`,
`UnloadFighters`, `TransferFighters`) currently hit the `else: discard`
branch in `applyZeroTurnCommandOptimistically`. Adding their optimistic
effects is straightforward once the display fields exist — no changes
to the rebuild/drop/filter plumbing are needed.

**When DetachShips needs a new fleet UI entry:**  
`applyZeroTurnCommandOptimistically` would need to construct a fake
`FleetInfo` and insert it into both Active View tables. A temporary
negative ID (e.g. a decrementing counter in `TuiUIState`) can serve as
the placeholder key until the real `FleetId` arrives in the turn delta.
The `MergeFleets` source-removal logic (`removeFleetFromViews`) is the
pattern to mirror for insertion.

**When adding a new Pattern A domain:**  
Hold the staged value in `model.ui.*`, add a helper function that
prefers the staged value over the server value, and call that helper
from the renderer. No pristine cache or rebuild proc is needed.

**When adding a new Pattern B domain (complex structural changes):**  
Add a pristine cache field to `TuiUIState`, snapshot it at the end of
`syncPlayerStateToModel`, mutate the active view on staging, and extend
`reapplyAllOptimisticUpdates` to reset and replay for that domain.

---

**See also:**
- `docs/architecture/dataflow.md` §5 — ZTC execution timing (CMD5)
- `docs/engine/zero_turn.md` — ZTC API reference
- `docs/architecture/sam-implementation.md` — SAM pattern overview
