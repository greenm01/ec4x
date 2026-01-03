## Construction Dock Capacity System (Per-Facility Tracking)
##
## Implements per-facility construction dock capacity management.
##
## **Per-Facility Model:**
## - Each Spaceport: 5 docks (construction only, ship builds at 2x cost)
## - Each Shipyard: 10 docks (construction + repair)
## - Shipyard/Starbase construction does NOT occupy dock space (requires spaceport assist)
##
## **Capacity Formula:**
## - Spaceport: max projects = docks (5)
## - Shipyard: max projects = docks (10), shared between construction and repair
## - Active projects consume 1 dock each (FIFO priority)
##
## **Key Mechanics:**
## 1. Facility Assignment: Prioritize shipyards, distribute evenly by available capacity
## 2. Priority: FIFO (first queued, first processed) - construction and repair treated equally
## 3. Spaceport Penalty: Ships built at spaceports cost 2x PP (except Shipyard/Starbase buildings)
## 4. Shipyard/Starbase Special: Built in orbit, don't occupy docks, spaceports assist
##
## Data-oriented design: Calculate violations (pure), report status (no enforcement needed - hard limit)

import std/[tables, strutils, algorithm, options, math]
import ../../types/[capacity, core, game_state, ship, production, facilities, colony]
import ../../state/[game_state as gs_helpers, iterators]
import ../../../common/logger

export capacity.CapacityViolation, capacity.ViolationSeverity

type FacilityCapacity* = object ## Capacity status for a single facility
  facilityId*: string
  facilityType*: FacilityClass
  maxDocks*: int
  usedDocks*: int
  isCrippled*: bool
  constructionProjects*: int # Active construction count
  repairProjects*: int # Active repair count

proc getFacilityCapacity*(spaceport: Spaceport): FacilityCapacity =
  ## Get capacity status for a spaceport (uses pre-calculated effectiveDocks)
  let used = spaceport.activeConstructions.len

  result = FacilityCapacity(
    facilityId: $uint32(spaceport.id),
    facilityType: FacilityClass.Spaceport,
    maxDocks: spaceport.effectiveDocks,
    usedDocks: used,
    isCrippled: false, # Spaceports don't get crippled
    constructionProjects: used,
    repairProjects: 0, # Spaceports don't repair
  )

proc getFacilityCapacity*(shipyard: Shipyard): FacilityCapacity =
  ## Get capacity status for a shipyard (uses pre-calculated effectiveDocks)
  let used = shipyard.activeConstructions.len

  result = FacilityCapacity(
    facilityId: $uint32(shipyard.id),
    facilityType: FacilityClass.Shipyard,
    maxDocks: shipyard.effectiveDocks,
    usedDocks: used,
    isCrippled: shipyard.isCrippled,
    constructionProjects: used,
    repairProjects: 0, # Shipyards don't repair (drydocks handle repairs)
  )

proc getFacilityCapacity*(drydock: Drydock): FacilityCapacity =
  ## Get capacity status for a drydock (uses pre-calculated effectiveDocks)
  let used = drydock.activeRepairs.len

  result = FacilityCapacity(
    facilityId: $uint32(drydock.id),
    facilityType: FacilityClass.Drydock,
    maxDocks: drydock.effectiveDocks,
    usedDocks: used,
    isCrippled: drydock.isCrippled,
    constructionProjects: 0, # Drydocks cannot construct
    repairProjects: drydock.activeRepairs.len,
  )

proc analyzeColonyCapacity*(
    state: GameState, colonyId: ColonyId
): seq[FacilityCapacity] =
  ## Analyze all facility capacities for a colony
  ## Returns capacity status for each facility
  result = @[]

  let colonyOpt = gs_helpers.getColony(state, colonyId)
  if colonyOpt.isNone:
    return

  let colony = colonyOpt.get()

  # Analyze spaceports
  for spaceportId in colony.spaceportIds:
    let spaceportOpt = gs_helpers.getSpaceport(state, spaceportId)
    if spaceportOpt.isSome:
      result.add(getFacilityCapacity(spaceportOpt.get()))

  # Analyze shipyards
  for shipyardId in colony.shipyardIds:
    let shipyardOpt = gs_helpers.getShipyard(state, shipyardId)
    if shipyardOpt.isSome:
      result.add(getFacilityCapacity(shipyardOpt.get()))

  # Analyze drydocks
  for drydockId in colony.drydockIds:
    let drydockOpt = gs_helpers.getDrydock(state, drydockId)
    if drydockOpt.isSome:
      result.add(getFacilityCapacity(drydockOpt.get()))

proc checkColonyViolation*(
    state: GameState, colonyId: ColonyId
): Option[capacity.CapacityViolation] =
  ## Check if colony has any facilities exceeding capacity
  ## This should NEVER happen (hard limit at build time) but we track it

  let facilities = analyzeColonyCapacity(state, colonyId)
  var totalCurrent = 0
  var totalMaximum = 0
  var hasViolation = false

  for facility in facilities:
    totalCurrent += facility.usedDocks
    # Crippled shipyards contribute 0 to max capacity
    if facility.isCrippled:
      totalMaximum += 0
    else:
      totalMaximum += facility.maxDocks

    if facility.usedDocks > facility.maxDocks:
      hasViolation = true

  if hasViolation:
    return some(
      capacity.CapacityViolation(
        capacityType: capacity.CapacityType.ConstructionDock,
        entity: capacity.EntityIdUnion(
          kind: capacity.CapacityType.ConstructionDock, colonyId: colonyId
        ),
        current: int32(totalCurrent),
        maximum: int32(totalMaximum),
        excess: int32(max(0, totalCurrent - totalMaximum)),
        severity: capacity.ViolationSeverity.Critical,
        graceTurnsRemaining: 0'i32,
        violationTurn: int32(state.turn),
      )
    )
  else:
    return none(capacity.CapacityViolation)

proc checkAllViolations*(state: GameState): seq[capacity.CapacityViolation] =
  ## Check all colonies for dock capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  for house in state.activeHouses():
    for colony in state.coloniesOwned(house.id):
      let violation = checkColonyViolation(state, colony.id)
      if violation.isSome:
        result.add(violation.get())

proc getAvailableFacilities*(
    state: GameState, colonyId: ColonyId, projectType: BuildType
): seq[tuple[facilityId: string, facilityType: FacilityClass, availableDocks: int]] =
  ## Get list of facilities with available dock capacity at colony
  ## Returns facilities sorted by priority: shipyards first, then by available
  ## capacity (descending)
  ##
  ## For projectType=Building and itemId=Shipyard/Starbase:
  ##   Returns spaceports only (shipyards/starbases built in orbit, don't
  ##   occupy docks)
  result = @[]

  let colonyOpt = gs_helpers.getColony(state, colonyId)
  if colonyOpt.isNone:
    return

  let facilities = analyzeColonyCapacity(state, colonyId)

  # Collect available facilities
  for facility in facilities:
    # Skip crippled shipyards/drydocks (0 capacity)
    if facility.isCrippled:
      continue

    # Skip drydocks - they're repair-only, not for construction
    if facility.facilityType == FacilityClass.Drydock:
      continue

    let available = facility.maxDocks - facility.usedDocks
    if available > 0:
      result.add((facility.facilityId, facility.facilityType, available))

  # Sort: Shipyards first, then by available docks (descending)
  result.sort do(
    a, b: tuple[facilityId: string, facilityType: FacilityClass, availableDocks: int]
  ) -> int:
    # Shipyards have priority
    if a.facilityType == FacilityClass.Shipyard and
        b.facilityType == FacilityClass.Spaceport:
      return -1
    elif a.facilityType == FacilityClass.Spaceport and
        b.facilityType == FacilityClass.Shipyard:
      return 1
    else:
      # Among same type, prefer more available docks (even distribution)
      return cmp(b.availableDocks, a.availableDocks)

proc assignFacility*(
    state: GameState, colonyId: ColonyId, projectType: BuildType, itemId: string
): Option[tuple[facilityId: uint32, facilityType: FacilityClass]] =
  ## Assign a construction project to the best available facility
  ##
  ## Assignment algorithm:
  ## 1. Prioritize shipyards over spaceports
  ## 2. Within same type, prefer facility with most available docks (even
  ##    distribution)
  ## 3. For Shipyard/Starbase buildings, only return spaceports (orbital
  ##    construction)
  ##
  ## Returns: (facilityId as uint32, facilityType) or none if no capacity

  # Special case: Shipyard construction only uses spaceports for assist
  # Shipyards are built in orbit and don't occupy dock space
  if projectType == BuildType.Facility and itemId == "Shipyard":
    # For shipyard, we need a spaceport but it doesn't consume docks
    let colonyOpt = gs_helpers.getColony(state, colonyId)
    if colonyOpt.isNone:
      return none(tuple[facilityId: uint32, facilityType: FacilityClass])

    let colony = colonyOpt.get()
    if colony.spaceportIds.len > 0:
      # Return first spaceport (assists but doesn't consume capacity)
      let spaceportId = colony.spaceportIds[0]
      return some((uint32(spaceportId), FacilityClass.Spaceport))
    else:
      return none(tuple[facilityId: uint32, facilityType: FacilityClass])

  # Normal case: find facility with available capacity
  let available = getAvailableFacilities(state, colonyId, projectType)

  if available.len == 0:
    return none(tuple[facilityId: uint32, facilityType: FacilityClass])

  # Return first (highest priority) facility
  # Convert string ID back to uint32
  return some((uint32(parseUInt(available[0].facilityId)), available[0].facilityType))

proc processCapacityReporting*(state: GameState): seq[capacity.CapacityViolation] =
  ## Main entry point - report capacity violations (should never happen)
  ## Called during Maintenance phase
  ## Returns: List of violations found (for logging/debugging)

  result = checkAllViolations(state)

  if result.len == 0:
    logger.logDebug("Economy", "All facilities within construction dock capacity")
  else:
    # This should NEVER happen - capacity enforced at build time
    for violation in result:
      logger.logWarn(
        "Economy",
        "Colony " & $violation.entity.colonyId & " OVER dock capacity (BUG!)",
        " usage=",
        $violation.current,
        "/",
        $violation.maximum,
        " excess=",
        $violation.excess,
      )

proc shipRequiresDock*(shipClass: ShipClass): bool =
  ## Check if a ship class requires dock construction capacity
  ## Fighters are built planet-side (distributed manufacturing) and don't use docks
  ## All other ships require dock space at spaceport or shipyard
  return shipClass != ShipClass.Fighter

proc getColonyTotalCapacity*(
    state: GameState, colonyId: ColonyId
): tuple[current: int, maximum: int] =
  ## Get total dock capacity for colony (sum of all facilities)
  ## Used for display/reporting purposes
  result = (current: 0, maximum: 0)

  let facilities = analyzeColonyCapacity(state, colonyId)
  for facility in facilities:
    result.current += facility.usedDocks
    if not facility.isCrippled:
      result.maximum += facility.maxDocks

proc assignAndQueueProject*(
    state: var GameState, colonyId: ColonyId, project: ConstructionProject
): bool =
  ## Assign project to best available facility and add to its queue
  ## Returns true if successful, false if no capacity
  ##
  ## This is the main entry point for adding construction projects to facility
  ## queues. Automatically assigns to best facility per assignment algorithm.

  let colonyOpt = gs_helpers.getColony(state, colonyId)
  if colonyOpt.isNone:
    return false

  # Assign facility
  let assignment = assignFacility(state, colonyId, project.projectType, project.itemId)
  if assignment.isNone:
    # No available facility capacity
    return false

  let (facilityId, facilityType) = assignment.get()

  # Create project with facility assignment
  var assignedProject = project
  assignedProject.facilityId = some(facilityId)
  assignedProject.facilityType = some(facilityType)

  # Add to facility queue
  if facilityType == FacilityClass.Spaceport:
    # Update spaceport
    let spaceportId = SpaceportId(facilityId)
    let spaceportOpt = gs_helpers.getSpaceport(state, spaceportId)
    if spaceportOpt.isNone:
      logger.logWarn("Economy", "Failed to find spaceport", " facility=", $facilityId)
      return false

    var spaceport = spaceportOpt.get()
    spaceport.constructionQueue.add(assignedProject.id)

    state.updateSpaceport(spaceportId, spaceport)

    logger.logDebug(
      "Economy",
      "Project queued to spaceport",
      " facility=",
      $facilityId,
      " project=",
      project.itemId,
    )
    return true
  else:
    # Update shipyard
    let shipyardId = ShipyardId(facilityId)
    let shipyardOpt = gs_helpers.getShipyard(state, shipyardId)
    if shipyardOpt.isNone:
      logger.logWarn("Economy", "Failed to find shipyard", " facility=", $facilityId)
      return false

    var shipyard = shipyardOpt.get()
    shipyard.constructionQueue.add(assignedProject.id)

    state.updateShipyard(shipyardId, shipyard)

    logger.logDebug(
      "Economy",
      "Project queued to shipyard",
      " facility=",
      $facilityId,
      " project=",
      project.itemId,
    )
    return true

## Design Notes:
##
## **Per-Facility Architecture:**
## Each facility independently tracks its own queues and capacity:
## - Spaceport.constructionQueue, Spaceport.activeConstruction
## - Shipyard.constructionQueue, Shipyard.activeConstruction
## - Shipyard.repairQueue, Shipyard.activeRepairs
##
## **Assignment Strategy:**
## 1. Prioritize shipyards (more capable, 10 docks)
## 2. Distribute evenly across available capacity
## 3. Spaceports as fallback (5 docks, 2x ship cost penalty)
##
## **Special Cases:**
## - Shipyard/Starbase construction: Requires spaceport assist but doesn't occupy docks
## - Crippled shipyards: 0 capacity until repaired
## - FIFO priority: Construction and repair projects treated equally in queue
##
## **Integration Points:**
## - Call assignFacility() when player submits build order
## - Call processCapacityReporting() in Maintenance phase (should find nothing)
## - Check getAvailableFacilities() to show player available capacity
##
## **Spaceport Cost Penalty:**
## Ships built at spaceports cost 2x PP (handled in construction cost calculation)
## Exception: Shipyard/Starbase buildings don't have penalty (orbital construction)
