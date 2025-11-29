## Colonization Engine
##
## Colony establishment per operations.md:6.2.13
##
## Colonization rules:
## - Requires ETAC ship with PTU
## - One system can only have one colony (any house)
## - New colonies start at infrastructure level 1
## - Awards +5 prestige for establishing colony

import std/[options]
import ../../common/types/[core, planets]
import ../prestige
import ../config/[prestige_config, prestige_multiplier]
import ../economy/types as econ_types
import ../gamestate  # For unified Colony type

export core.HouseId, core.SystemId
export prestige.PrestigeEvent
# NOTE: Don't export gamestate.Colony to avoid ambiguity

type
  ColonizationAttempt* = object
    ## Attempt to colonize a planet
    houseId*: HouseId
    systemId*: SystemId
    fleetId*: FleetId
    ptuUsed*: int

  ColonizationResult* = object
    ## Result of colonization attempt
    success*: bool
    reason*: string
    newColony*: Option[Colony]  # Now uses unified Colony from gamestate
    prestigeEvent*: Option[PrestigeEvent]

## Colonization

proc canColonize*(systemId: SystemId, existingColonies: seq[Colony]): bool =
  ## Check if system can be colonized (no existing colony)
  ## Per operations.md:6.2.13
  for colony in existingColonies:
    if colony.systemId == systemId:
      return false
  return true

proc initNewColony*(systemId: SystemId, owner: HouseId,
                   planetClass: PlanetClass, resources: ResourceRating,
                   startingPTU: int): Colony =
  ## Initialize a new colony with all required fields
  ## Replaces econ_types.initColony with full gamestate Colony initialization
  result = Colony(
    systemId: systemId,
    owner: owner,

    # Population (multiple representations)
    population: startingPTU,  # Display field in millions
    souls: startingPTU * 50_000,  # Exact count (~50k per PTU)
    populationUnits: startingPTU,  # PU for economic calculations
    populationTransferUnits: startingPTU,  # PTU used for colonization

    # Infrastructure
    infrastructure: 1,  # New colonies start at Level I
    industrial: econ_types.IndustrialUnits(units: 0, investmentCost: econ_types.BASE_IU_COST),

    # Planet characteristics
    planetClass: planetClass,
    resources: resources,
    buildings: @[],

    # Economic state
    production: 0,  # Will be calculated in economy phase
    grossOutput: 0,  # Will be calculated in economy phase
    taxRate: 50,  # Default 50% tax rate
    infrastructureDamage: 0.0,

    # Construction
    underConstruction: none(econ_types.ConstructionProject),
    constructionQueue: @[],
    activeTerraforming: none(TerraformProject),

    # Military assets (all empty for new colony)
    unassignedSquadrons: @[],
    unassignedSpaceLiftShips: @[],
    fighterSquadrons: @[],
    capacityViolation: CapacityViolation(active: false, violationType: "", turnsRemaining: 0, violationTurn: 0),
    starbases: @[],

    # Facilities (none initially)
    spaceports: @[],
    shipyards: @[],

    # Ground defenses (none initially)
    planetaryShieldLevel: 0,
    groundBatteries: 0,
    armies: 0,
    marines: 0,

    # Blockade status (not blockaded)
    blockaded: false,
    blockadedBy: @[],
    blockadeTurns: 0
  )

proc establishColony*(houseId: HouseId, systemId: SystemId,
                     planetClass: PlanetClass, resources: ResourceRating,
                     startingPTU: int): ColonizationResult =
  ## Establish new colony at system
  ## Per operations.md:6.2.13: "New colonies start at Level I"

  let config = globalPrestigeConfig

  # Create new colony with full initialization
  let colony = initNewColony(
    systemId,
    houseId,
    planetClass,
    resources,
    startingPTU
  )

  # Create prestige event with dynamic scaling
  let prestigeAmount = applyMultiplier(config.economic.establish_colony)
  let prestigeEvent = createPrestigeEvent(
    PrestigeSource.ColonyEstablished,
    prestigeAmount,
    "Established colony at system " & $systemId
  )

  return ColonizationResult(
    success: true,
    reason: "Colony established successfully",
    newColony: some(colony),
    prestigeEvent: some(prestigeEvent)
  )

proc attemptColonization*(attempt: ColonizationAttempt,
                         existingColonies: seq[Colony],
                         planetClass: PlanetClass,
                         resources: ResourceRating): ColonizationResult =
  ## Attempt to colonize a system
  ## Per operations.md:6.2.13

  # Check if system is available
  if not canColonize(attempt.systemId, existingColonies):
    return ColonizationResult(
      success: false,
      reason: "System already colonized",
      newColony: none(Colony),
      prestigeEvent: none(PrestigeEvent)
    )

  # Check PTU availability
  if attempt.ptuUsed < 1:
    return ColonizationResult(
      success: false,
      reason: "Insufficient PTU (need at least 1)",
      newColony: none(Colony),
      prestigeEvent: none(PrestigeEvent)
    )

  # Establish colony
  return establishColony(
    attempt.houseId,
    attempt.systemId,
    planetClass,
    resources,
    attempt.ptuUsed
  )
