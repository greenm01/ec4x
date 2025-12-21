import std/[tables, sets]
import ../types/[all_types, player_view]

proc calculateVisibility*(state: GameState, viewerId: HouseId): Table[SystemId, VisibilityLevel] =
  result = initTable[SystemId, VisibilityLevel]()
  
  # 1. Start with systems containing viewer's assets
  # Owned Colonies provide 'Owned' visibility
  for id, colony in state.colonies.entities:
    if colony.owner == viewerId:
      result[colony.systemId] = VisibilityLevel.Owned [cite: 12]

  # 2. Fleets provide 'Occupied' visibility in their current system
  for id, fleet in state.fleets.entities:
    if fleet.owner == viewerId:
      let sysId = fleet.location
      # Don't overwrite 'Owned' with 'Occupied'
      if not result.contains(sysId) or result[sysId] < VisibilityLevel.Occupied:
        result[sysId] = VisibilityLevel.Occupied [cite: 12]
      
      # 3. Handle Sensor Range (Adjacency)
      # In many 4X games, a fleet "sees" into neighboring systems
      #for neighborId in state.starMap.getNeighbors(sysId):
      #  if not result.contains(neighborId):
      #    result[neighborId] = VisibilityLevel.Adjacent [cite: 12]

  # 4. Fallback: Historical Knowledge
  # If a system was once visited but is no longer in sensor range, it is 'Scouted'
  let intelDb = state.intelligence.getOrDefault(viewerId) [cite: 19]
  for sysId in intelDb.systemReports.keys:
    if not result.contains(sysId):
      result[sysId] = VisibilityLevel.Scouted [cite: 12]
