## Facility Query Helpers
##
## Shared read-only queries for checking whether operational facilities exist
## at a colony. Used by build validation, commissioning safety nets, and
## repair prerequisites.
##
## **Design:**
## - Pure read-only: never mutates state or touches any queue
## - Config-driven: prerequisite relationships come from facilities.kdl
## - Does NOT interact with Neoria dock queues (activeConstructions,
##   constructionQueue, repairQueue) — those belong to queue_advancement.nim
##
## **Operational Definition:**
## A facility is "operational" when it is NOT CombatState.Crippled (or Destroyed).
## This matches the definition used throughout commands.nim and the spec.

import std/options
import ../../types/[core, game_state, facilities, combat]
import ../../state/engine
import ../../globals

proc hasOperationalFacility*(
    state: GameState, colonyId: ColonyId, target: NeoriaClass
): bool =
  ## Return true if colony has at least one non-crippled Neoria of the given class.
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return false
  let colony = colonyOpt.get()
  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome:
      let neoria = neoriaOpt.get()
      if neoria.neoriaClass == target and
          neoria.state notin {CombatState.Crippled, CombatState.Destroyed}:
        return true
  return false

proc hasOperationalSpaceport*(state: GameState, colonyId: ColonyId): bool =
  ## Return true if colony has at least one operational (non-crippled) Spaceport.
  state.hasOperationalFacility(colonyId, NeoriaClass.Spaceport)

proc hasOperationalShipyard*(state: GameState, colonyId: ColonyId): bool =
  ## Return true if colony has at least one operational (non-crippled) Shipyard.
  state.hasOperationalFacility(colonyId, NeoriaClass.Shipyard)

proc facilityPrerequisiteMet*(
    state: GameState, colonyId: ColonyId, facilityClass: FacilityClass
): bool =
  ## Config-driven prerequisite check for facility construction.
  ## Reads the `prerequisite` string from facilities.kdl.
  ## Returns true if the prerequisite is satisfied (or if there is none).
  let prereq = gameConfig.facilities.facilities[facilityClass].prerequisite
  if prereq.len == 0:
    return true
  case prereq
  of "Spaceport":
    return state.hasOperationalSpaceport(colonyId)
  of "Shipyard":
    return state.hasOperationalShipyard(colonyId)
  else:
    # Unknown prerequisite - fail safe (deny)
    return false
