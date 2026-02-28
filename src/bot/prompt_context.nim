## Prompt context generator for LLM bot decisions.

import std/[algorithm, options, strformat, strutils, tables]

import ../engine/types/[core, player_state]

proc optIntLabel(value: Option[int32], fallback: string = "?"): string =
  if value.isSome:
    return $value.get()
  fallback

proc houseLabel(state: PlayerState, houseId: HouseId): string =
  if state.houseNames.hasKey(houseId):
    return state.houseNames[houseId]
  "House " & $int(houseId)

proc sortedHouseIds(state: PlayerState): seq[int] =
  result = @[]
  for houseId in state.housePrestige.keys:
    result.add(int(houseId))
  result.sort(system.cmp[int])

proc sortedVisibleSystems(state: PlayerState): seq[VisibleSystem] =
  result = @[]
  for _, sys in state.visibleSystems.pairs:
    result.add(sys)
  result.sort(proc(a, b: VisibleSystem): int =
    cmp(int(a.systemId), int(b.systemId))
  )

proc buildTurnContext*(state: PlayerState): string =
  var lines: seq[string] = @[]

  lines.add("# EC4X Bot Turn Context")
  lines.add("")
  lines.add("## Strategic Overview")
  lines.add(&"- Turn: {state.turn}")
  lines.add(&"- Viewing House: {houseLabel(state, state.viewingHouse)}")
  lines.add(&"- Treasury: {optIntLabel(state.treasuryBalance)}")
  lines.add(&"- Net Income: {optIntLabel(state.netIncome)}")
  lines.add(&"- EBP: {optIntLabel(state.ebpPool)}")
  lines.add(&"- CIP: {optIntLabel(state.cipPool)}")
  lines.add(&"- Tax Rate: {optIntLabel(state.taxRate)}")

  lines.add("")
  lines.add("## Own Assets")
  lines.add(&"- Colonies: {state.ownColonies.len}")
  lines.add(&"- Fleets: {state.ownFleets.len}")
  lines.add(&"- Ships: {state.ownShips.len}")
  if state.ownFleets.len > 0:
    lines.add("- Fleet Summary:")
    for fleet in state.ownFleets:
      lines.add(&"  - Fleet {int(fleet.id)} at system {int(fleet.location)} " &
        &"status={fleet.status}")

  lines.add("")
  lines.add("## Visible Intel")
  lines.add(&"- Visible Systems: {state.visibleSystems.len}")
  lines.add(&"- Visible Colonies: {state.visibleColonies.len}")
  lines.add(&"- Visible Fleets: {state.visibleFleets.len}")
  let visible = sortedVisibleSystems(state)
  if visible.len > 0:
    lines.add("- Systems:")
    for sys in visible:
      lines.add(&"  - {int(sys.systemId)} {sys.name} " &
        &"visibility={sys.visibility}")

  lines.add("")
  lines.add("## Public Standings")
  let houseIds = sortedHouseIds(state)
  for houseIdInt in houseIds:
    let houseId = HouseId(houseIdInt)
    let prestige = state.housePrestige.getOrDefault(houseId, 0)
    let colonies = state.houseColonyCounts.getOrDefault(houseId, 0)
    lines.add(&"- {houseLabel(state, houseId)}: prestige={prestige}, " &
      &"colonies={colonies}")

  lines.add("")
  lines.add("## Last Turn Events")
  lines.add(&"- Event Count: {state.turnEvents.len}")

  lines.join("\n")
