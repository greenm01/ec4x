# Spatial/Complex Iterators
import ./game_state
import ../types/core

# itterator to look through all squadrons in a system
iterator squadronsInSystem*(state: GameState, sysId: SystemId): Squadron =
  # 1. Direct lookup of only the fleets in THIS system
  if state.fleets.bySystem.contains(sysId):
    for fleetId in state.fleets.bySystem[sysId]:
      let fleet = state.getFleet(fleetId).get()
      # 2. Loop through squadrons in those specific fleets
      for squadronId in fleet.squadronIds:
        let sq = state.getSquadron(squadronId)
        if sq.isSome: yield sq.get()
