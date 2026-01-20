## TUI state synchronization helpers
##
## Converts engine state and player state into SAM model data.

import std/[options, tables, algorithm]

import ../../engine/types/[core, colony, fleet, player_state as ps_types,
  diplomacy]
import ../../engine/state/[engine, iterators]
import ../../engine/systems/capacity/c2_pool
import ../sam/sam_pkg
import ../tui/adapters
import ../tui/widget/overview

proc syncGameStateToModel*(
    model: var TuiModel,
    state: GameState,
    viewingHouse: HouseId
) =
  ## Sync game state into the SAM TuiModel
  let house = state.house(viewingHouse).get()

  model.turn = state.turn
  model.viewingHouse = int(viewingHouse)
  model.houseName = house.name
  model.treasury = house.treasury.int
  model.prestige = house.prestige.int
  model.alertCount = 0
  model.unreadReports = 0
  model.unreadMessages = 0

  # Production (from last income report if available)
  if house.latestIncomeReport.isSome:
    model.production = house.latestIncomeReport.get().totalNet.int
  else:
    model.production = 0

  # Command capacity (C2 pool)
  let c2Analysis = analyzeC2Capacity(state, viewingHouse)
  model.commandUsed = c2Analysis.totalFleetCC.int
  model.commandMax = c2Analysis.c2Pool.int

  # Prestige rank and total houses
  var prestigeList: seq[tuple[id: HouseId, prestige: int32]] = @[]
  for otherHouse in state.allHouses():
    prestigeList.add((id: otherHouse.id, prestige: otherHouse.prestige))
  prestigeList.sort(
    proc(a, b: tuple[id: HouseId, prestige: int32]): int =
      result = cmp(b.prestige, a.prestige)
      if result == 0:
        result = cmp(int(a.id), int(b.id))
  )
  model.totalHouses = prestigeList.len
  model.prestigeRank = 0
  for i, entry in prestigeList:
    if entry.id == viewingHouse:
      model.prestigeRank = i + 1
      break

  # Build systems table from fog-of-war map data
  let mapData = toFogOfWarMapData(state, viewingHouse)
  model.systems.clear()
  model.maxRing = mapData.maxRing

  for coord, sysInfo in mapData.systems.pairs:
    let samSys = sam_pkg.SystemInfo(
      id: sysInfo.id,
      name: sysInfo.name,
      coords: (coord.q, coord.r),
      ring: sysInfo.ring,
      planetClass: sysInfo.planetClass,
      resourceRating: sysInfo.resourceRating,
      owner: sysInfo.owner,
      isHomeworld: sysInfo.isHomeworld,
      isHub: sysInfo.isHub,
      fleetCount: sysInfo.fleetCount,
    )
    model.systems[(coord.q, coord.r)] = samSys

    # Track homeworld
    if sysInfo.isHomeworld and sysInfo.owner.isSome and
        sysInfo.owner.get == int(viewingHouse):
      model.homeworld = some((coord.q, coord.r))

  # Build colonies list
  model.colonies = @[]
  for colony in state.coloniesOwned(viewingHouse):
    let sysOpt = state.system(colony.systemId)
    let sysName =
      if sysOpt.isSome:
        sysOpt.get().name
      else:
        "???"
    model.colonies.add(
      sam_pkg.ColonyInfo(
        systemId: int(colony.systemId),
        systemName: sysName,
        population: colony.population.int,
        production: colony.production.int,
        owner: int(viewingHouse),
      )
    )

  # Build fleets list
  model.fleets = @[]
  for fleet in state.fleetsOwned(viewingHouse):
    let sysOpt = state.system(fleet.location)
    let locName =
      if sysOpt.isSome:
        sysOpt.get().name
      else:
        "???"
    let cmdType = int(fleet.command.commandType)
    model.fleets.add(
      sam_pkg.FleetInfo(
        id: int(fleet.id),
        location: int(fleet.location),
        locationName: locName,
        shipCount: fleet.ships.len,
        owner: int(viewingHouse),
        command: cmdType,
        commandLabel: sam_pkg.commandLabel(cmdType),
        isIdle: fleet.command.commandType == FleetCommandType.Hold,
      )
    )

proc syncPlayerStateToOverview*(
    ps: ps_types.PlayerState,
    state: GameState
): OverviewData =
  ## Convert PlayerState to Overview widget data
  result = initOverviewData()

  # === Leaderboard (from public information) ===
  for houseId, prestige in ps.housePrestige.pairs:
    let houseOpt = state.house(houseId)
    if houseOpt.isNone:
      continue
    let house = houseOpt.get()

    # Determine diplomatic status
    var status = DiplomaticStatus.Neutral
    if houseId == ps.viewingHouse:
      status = DiplomaticStatus.Self
    elif houseId in ps.eliminatedHouses:
      status = DiplomaticStatus.Eliminated
    else:
      # Check diplomatic relations
      let key = (ps.viewingHouse, houseId)
      if ps.diplomaticRelations.hasKey(key):
        let dipState = ps.diplomaticRelations[key]
        case dipState
        of DiplomaticState.Enemy:
          status = DiplomaticStatus.Enemy
        of DiplomaticState.Hostile:
          status = DiplomaticStatus.Hostile
        of DiplomaticState.Neutral:
          status = DiplomaticStatus.Neutral

    result.leaderboard.addEntry(
      houseId = int(houseId),
      name = house.name,
      prestige = prestige.int,
      colonies = ps.houseColonyCounts.getOrDefault(houseId, 0).int,
      status = status,
      isPlayer = (houseId == ps.viewingHouse),
    )

  result.leaderboard.sortAndRank()
  result.leaderboard.totalSystems = state.systemsCount().int

  # Calculate total colonized systems
  result.leaderboard.colonizedSystems = state.coloniesCount().int

  # === Empire Status ===
  result.empireStatus.coloniesOwned = ps.ownColonies.len

  # Get house data for tax rate
  let houseOpt = state.house(ps.viewingHouse)
  if houseOpt.isSome:
    result.empireStatus.taxRate = houseOpt.get().taxPolicy.currentRate.int

  # Fleet counts by status
  for fleet in ps.ownFleets:
    case fleet.status
    of FleetStatus.Active:
      result.empireStatus.fleetsActive.inc
    of FleetStatus.Reserve:
      result.empireStatus.fleetsReserve.inc
    of FleetStatus.Mothballed:
      result.empireStatus.fleetsMothballed.inc

  # Intel - count known vs fogged systems
  for _, visSys in ps.visibleSystems.pairs:
    case visSys.visibility
    of VisibilityLevel.None:
      result.empireStatus.foggedSystems.inc
    else:
      result.empireStatus.knownSystems.inc

  # Diplomacy counts
  for (pair, dipState) in ps.diplomaticRelations.pairs:
    if pair[0] != ps.viewingHouse:
      continue
    case dipState
    of DiplomaticState.Neutral:
      result.empireStatus.neutralHouses.inc
    of DiplomaticState.Hostile:
      result.empireStatus.hostileHouses.inc
    of DiplomaticState.Enemy:
      result.empireStatus.enemyHouses.inc

  # === Action Queue - detect idle fleets ===
  var idleFleets: seq[Fleet] = @[]
  for fleet in ps.ownFleets:
    if fleet.command.commandType == FleetCommandType.Hold and
        fleet.status == FleetStatus.Active:
      idleFleets.add(fleet)
      result.actionQueue.addChecklistItem(
        description = "Fleet #" & $fleet.id.int & " awaiting orders",
        isDone = false,
        priority = ActionPriority.Warning,
      )

  if idleFleets.len > 0:
    result.actionQueue.addAction(
      description = $idleFleets.len & " fleet(s) awaiting orders",
      priority = ActionPriority.Warning,
      jumpView = 3,
      jumpLabel = "3",
    )

  # Placeholder recent events
  if result.recentEvents.len == 0:
    result.addEvent(ps.turn, "No recent events", false)
