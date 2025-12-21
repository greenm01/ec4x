# Spatial/Complex Iterators
import ./game_state
import ../types/core

# src/engine/state/queries.nim
iterator fleetsInSystem*(state: GameState, sysId: SystemId): Fleet =
  if state.fleets.bySystem.contains(sysId):
    for fId in state.fleets.bySystem[sysId]:
      let fOpt = state.getFleet(fId)
      if fOpt.isSome: yield fOpt.get()

iterator squadronsInSystem*(state: GameState, sysId: SystemId): Squadron =
  for fleet in state.fleetsInSystem(sysId):
    for sqId in fleet.squadronIds:
      let sqOpt = state.getSquadron(sqId)
      if sqOpt.isSome: yield sqOpt.get()
