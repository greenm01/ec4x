import std/[tables, options]
import ../types/[all_types, player_view, intelligence]

proc generateView*(state: GameState, viewerId: HouseId): PlayerView =
  # 1. Initialize with Public Information [cite: 14, 17]
  result = PlayerView(
    viewingHouse: viewerId,
    turn: state.turn,
    actProgression: state.actProgression,
    houseColonyCounts: initTable[HouseId, int32](),
    visibleSystems: initTable[SystemId, VisibleSystem]()
  )

  # 2. Access the faction's persistent memory 
  let intelDb = state.intelligence.getOrDefault(viewerId)

  # 3. Filter Colonies based on visibility and intel 
  for id, colony in state.colonies.entities:
    var visColony = VisibleColony(
      colonyId: id,
      systemId: colony.systemId,
      owner: colony.owner
    )

    if colony.owner == viewerId:
      # FULL INTEL: Owned colony 
      visColony.population = some(colony.population)
      visColony.infrastructure = some(colony.infrastructure)
      result.ownColonyIds.add(id)
    elif intelDb.colonyReports.contains(id):
      # HISTORICAL INTEL: From intelligence reports [cite: 2, 10, 12]
      let report = intelDb.colonyReports[id]
      visColony.intelTurn = some(report.gatheredTurn)
      visColony.estimatedPopulation = some(report.population)
      visColony.estimatedIndustry = some(report.industry)
      visColony.starbaseLevel = some(report.starbaseLevel)

    result.visibleColonies.add(visColony)

  # 4. Filter Fleets (Only visible if in a scanned system) [cite: 13, 14]
  for id, fleet in state.fleets.entities:
    if fleet.owner == viewerId:
      result.ownFleetIds.add(id)
      result.visibleFleets.add(VisibleFleet(
        fleetId: id,
        owner: fleet.owner,
        location: fleet.location,
        isOwned: true
      ))
    # Note: Enemy fleets would be added here only if current sensors detect them
