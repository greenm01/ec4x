## Blockade System Engine
## Implements blockade mechanics from operations.md Section 6.2.6

import std/[tables, options]
import ../../types/[core, fleet, colony, squadron, ship]
import ../../types/game_state as game_state_types
import ../../state/[entity_manager, iterators]
import ../../state/game_state
# import ../intelligence/blockade_intel  # TODO: Module doesn't exist yet

# =============================================================================
# Blockade Detection
# =============================================================================

proc isSystemBlockaded*(
    state: GameState, systemId: SystemId, colonyOwner: HouseId
): (bool, seq[HouseId]) =
  ## Check if a system is currently blockaded by hostile forces
  ## Returns (isBlockaded, blockadingHouses)
  ## (O(1) lookup via fleetsByLocation index)
  ##
  ## Per operations.md:6.2.6:
  ## "Fleets are ordered to blockade an enemy planet and do not engage
  ##  in Space Combat unless confronted by enemy ships under order 05"
  ##
  ## Multiple empires can blockade the same planet if all are hostile
  ## to the colony owner. Blockade effects stack (still 60% reduction,
  ## but multiple houses contribute to the blockade).

  var blockadingHouses: seq[HouseId] = @[]

  # Use iterator for O(1) indexed lookup
  for fleet in state.fleetsInSystem(systemId):
    if fleet.houseId != colonyOwner:
      # Check diplomatic status - only Enemy status can blockade
      # TODO: Add diplomatic status check when diplomacy system integrated
      # For now, any non-owner fleet with combat capability can blockade

      # Check if fleet has combat ships
      var hasCombatShips = false
      for sqId in fleet.squadrons:
        let sqOpt = state.squadrons.entities.entity(sqId)
        if sqOpt.isSome:
          let squadron = sqOpt.get()
          # Check if squadron has combat capability
          for shipId in squadron.ships:
            let shipOpt = state.ships.entities.entity(shipId)
            if shipOpt.isSome:
              let ship = shipOpt.get()
              if ship.stats.attackStrength > 0:
                hasCombatShips = true
                break
          if hasCombatShips:
            break

      if hasCombatShips and fleet.houseId notin blockadingHouses:
        blockadingHouses.add(fleet.houseId)

  return (blockadingHouses.len > 0, blockadingHouses)

# =============================================================================
# Blockade Application
# =============================================================================

proc applyBlockades*(state: var GameState) =
  ## Apply blockade status to all colonies
  ## Called at start of Income Phase
  ## Per operations.md:6.2.6: "Blockades established during the Conflict Phase
  ## reduce GCO for that same turn's Income Phase calculation"

  for (systemId, colony) in state.allColoniesWithId():
    let (isBlockaded, blockaders) = isSystemBlockaded(state, systemId, colony.owner)
    var updatedColony = colony

    var needsUpdate = false

    if isBlockaded:
      if not colony.blockaded:
        # Blockade just established - generate intelligence reports
        updatedColony.blockaded = true
        updatedColony.blockadedBy = blockaders
        updatedColony.blockadeTurns = 1
        needsUpdate = true

        # TODO: Generate intelligence reports when blockade_intel module exists
        # blockade_intel.generateBlockadeEstablishedIntel(
        #   state,
        #   systemId,
        #   colony.owner,
        #   blockaders,
        #   state.turn
        # )
      else:
        # Blockade continues (update blockading houses list)
        updatedColony.blockadedBy = blockaders
        updatedColony.blockadeTurns += 1
        needsUpdate = true
    else:
      if colony.blockaded:
        # Blockade lifted - generate intelligence reports
        updatedColony.blockaded = false
        updatedColony.blockadedBy = @[]
        updatedColony.blockadeTurns = 0
        needsUpdate = true

        # TODO: Generate intelligence reports when blockade_intel module exists
        # let previousBlockaders = colony.blockadedBy
        # blockade_intel.generateBlockadeLiftedIntel(
        #   state,
        #   systemId,
        #   colony.owner,
        #   previousBlockaders,
        #   state.turn
        # )

    # Write back if changed
    if needsUpdate:
      state.colonies.entities.updateEntity(ColonyId(systemId), updatedColony)

# =============================================================================
# Blockade Effects
# =============================================================================

proc getBlockadePenalty*(colony: Colony): float =
  ## Get the GCO multiplier for a blockaded colony
  ## Per operations.md:6.2.6: "Colonies under blockade reduce their GCO by 60%"
  ##
  ## Returns multiplier (0.4 = 60% reduction)

  if colony.blockaded:
    return 0.4 # 60% reduction
  else:
    return 1.0 # No reduction

proc calculateBlockadePrestigePenalty*(state: GameState, houseId: HouseId): int =
  ## Calculate prestige penalty for colonies under blockade
  ## (O(1) lookup via coloniesOwned iterator)
  ## Per operations.md:6.2.6: "House Prestige is reduced by 2 points
  ## for each turn if the colony begins the income phase under blockade"
  ##
  ## Returns total prestige penalty (negative value)

  var penalty = 0

  for colony in state.coloniesOwned(houseId):
    if colony.blockaded:
      penalty -= 2 # -2 prestige per blockaded colony

  return penalty

# =============================================================================
# Blockade Queries
# =============================================================================

proc getBlockadedColonies*(state: GameState, houseId: HouseId): seq[Colony] =
  ## Get all colonies owned by a house that are currently blockaded
  ## (O(1) lookup via coloniesOwned iterator)
  result = @[]

  for colony in state.coloniesOwned(houseId):
    if colony.blockaded:
      result.add(colony)

proc getBlockadingFleets*(state: GameState, systemId: SystemId): seq[Fleet] =
  ## Get all fleets that are blockading a system
  result = @[]

  # Get colony using state helper (convert SystemId to ColonyId)
  let colonyOpt = getColony(state, ColonyId(systemId))
  if colonyOpt.isNone:
    return result

  let colony = colonyOpt.get()

  # Use iterator for fleets at system
  for fleet in state.fleetsInSystem(systemId):
    if fleet.houseId != colony.owner:
      # Check if fleet has combat capability
      var hasCombatShips = false
      for sqId in fleet.squadrons:
        let sqOpt = state.squadrons.entities.entity(sqId)
        if sqOpt.isSome:
          let squadron = sqOpt.get()
          for shipId in squadron.ships:
            let shipOpt = state.ships.entities.entity(shipId)
            if shipOpt.isSome:
              let ship = shipOpt.get()
              if ship.stats.attackStrength > 0:
                hasCombatShips = true
                break
          if hasCombatShips:
            break

      if hasCombatShips:
        result.add(fleet)

# =============================================================================
# Blockade Breaking
# =============================================================================

proc canBreakBlockade*(state: GameState, systemId: SystemId, reliefFleet: Fleet): bool =
  ## Check if a relief fleet can break a blockade
  ## Per operations.md:6.2.6: Blockading fleets engage relief forces
  ## under order 05 (Guard/Blockade)
  ##
  ## Returns true if relief fleet has sufficient strength

  let blockaders = getBlockadingFleets(state, systemId)

  if blockaders.len == 0:
    return true # No blockade to break

  # Calculate combined strength
  var blockaderStrength = 0
  for fleet in blockaders:
    for sqId in fleet.squadrons:
      let sqOpt = state.squadrons.entities.entity(sqId)
      if sqOpt.isSome:
        let squadron = sqOpt.get()
        for shipId in squadron.ships:
          let shipOpt = state.ships.entities.entity(shipId)
          if shipOpt.isSome:
            let ship = shipOpt.get()
            blockaderStrength += ship.stats.attackStrength

  var reliefStrength = 0
  for sqId in reliefFleet.squadrons:
    let sqOpt = state.squadrons.entities.entity(sqId)
    if sqOpt.isSome:
      let squadron = sqOpt.get()
      for shipId in squadron.ships:
        let shipOpt = state.ships.entities.entity(shipId)
        if shipOpt.isSome:
          let ship = shipOpt.get()
          reliefStrength += ship.stats.attackStrength

  # Simple strength comparison
  # TODO: Integrate with full combat resolution
  return reliefStrength >= blockaderStrength
