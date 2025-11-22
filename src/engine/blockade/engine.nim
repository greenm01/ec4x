## Blockade System Engine
## Implements blockade mechanics from operations.md Section 6.2.6

import std/[tables, options]
import ../../common/types/core
import ../gamestate, ../fleet

# =============================================================================
# Blockade Detection
# =============================================================================

proc isSystemBlockaded*(
  state: GameState,
  systemId: SystemId,
  colonyOwner: HouseId
): (bool, Option[HouseId]) =
  ## Check if a system is currently blockaded by hostile forces
  ## Returns (isBlockaded, blockadingHouse)
  ##
  ## Per operations.md:6.2.6:
  ## "Fleets are ordered to blockade an enemy planet and do not engage
  ##  in Space Combat unless confronted by enemy ships under order 05"

  # Check if any enemy fleets are present with combat capability
  for fleet in state.fleets.values:
    if fleet.location == systemId and fleet.owner != colonyOwner:
      # Check if fleet has combat ships
      var hasCombatShips = false
      for squadron in fleet.squadrons:
        if squadron.flagship.stats.attackStrength > 0:
          hasCombatShips = true
          break

      if hasCombatShips:
        return (true, some(fleet.owner))

  return (false, none(HouseId))

# =============================================================================
# Blockade Application
# =============================================================================

proc applyBlockades*(state: var GameState) =
  ## Apply blockade status to all colonies
  ## Called at start of Income Phase
  ## Per operations.md:6.2.6: "Blockades established during the Conflict Phase
  ## reduce GCO for that same turn's Income Phase calculation"

  for systemId, colony in state.colonies.mpairs:
    let (isBlockaded, blockader) = isSystemBlockaded(state, systemId, colony.owner)

    if isBlockaded:
      if not colony.blockaded:
        # Blockade just established
        colony.blockaded = true
        colony.blockadedBy = blockader
        colony.blockadeTurns = 1
      else:
        # Blockade continues
        colony.blockadeTurns += 1
    else:
      if colony.blockaded:
        # Blockade lifted
        colony.blockaded = false
        colony.blockadedBy = none(HouseId)
        colony.blockadeTurns = 0

# =============================================================================
# Blockade Effects
# =============================================================================

proc getBlockadePenalty*(colony: Colony): float =
  ## Get the GCO multiplier for a blockaded colony
  ## Per operations.md:6.2.6: "Colonies under blockade reduce their GCO by 60%"
  ##
  ## Returns multiplier (0.4 = 60% reduction)

  if colony.blockaded:
    return 0.4  # 60% reduction
  else:
    return 1.0  # No reduction

proc calculateBlockadePrestigePenalty*(state: GameState, houseId: HouseId): int =
  ## Calculate prestige penalty for colonies under blockade
  ## Per operations.md:6.2.6: "House Prestige is reduced by 2 points
  ## for each turn if the colony begins the income phase under blockade"
  ##
  ## Returns total prestige penalty (negative value)

  var penalty = 0

  for colony in state.colonies.values:
    if colony.owner == houseId and colony.blockaded:
      penalty -= 2  # -2 prestige per blockaded colony

  return penalty

# =============================================================================
# Blockade Queries
# =============================================================================

proc getBlockadedColonies*(state: GameState, houseId: HouseId): seq[Colony] =
  ## Get all colonies owned by a house that are currently blockaded
  result = @[]

  for colony in state.colonies.values:
    if colony.owner == houseId and colony.blockaded:
      result.add(colony)

proc getBlockadingFleets*(state: GameState, systemId: SystemId): seq[Fleet] =
  ## Get all fleets that are blockading a system
  result = @[]

  if systemId notin state.colonies:
    return result

  let colony = state.colonies[systemId]

  for fleet in state.fleets.values:
    if fleet.location == systemId and fleet.owner != colony.owner:
      # Check if fleet has combat capability
      var hasCombatShips = false
      for squadron in fleet.squadrons:
        if squadron.flagship.stats.attackStrength > 0:
          hasCombatShips = true
          break

      if hasCombatShips:
        result.add(fleet)

# =============================================================================
# Blockade Breaking
# =============================================================================

proc canBreakBlockade*(
  state: GameState,
  systemId: SystemId,
  reliefFleet: Fleet
): bool =
  ## Check if a relief fleet can break a blockade
  ## Per operations.md:6.2.6: Blockading fleets engage relief forces
  ## under order 05 (Guard/Blockade)
  ##
  ## Returns true if relief fleet has sufficient strength

  let blockaders = getBlockadingFleets(state, systemId)

  if blockaders.len == 0:
    return true  # No blockade to break

  # Calculate combined strength
  var blockaderStrength = 0
  for fleet in blockaders:
    for squadron in fleet.squadrons:
      if squadron.flagship.stats.attackStrength > 0:
        blockaderStrength += squadron.flagship.stats.attackStrength

  var reliefStrength = 0
  for squadron in reliefFleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      reliefStrength += squadron.flagship.stats.attackStrength

  # Simple strength comparison
  # TODO: Integrate with full combat resolution
  return reliefStrength >= blockaderStrength
