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
import ./types
import ../../gamestate
import ../types as econ_types
import ../../../common/types/core
import ../../../common/types/units
import ../../../common/logger

export types.CapacityViolation, types.ViolationSeverity

type
  FacilityCapacity* = object
    ## Capacity status for a single facility
    facilityId*: string
    facilityType*: econ_types.FacilityType
    maxDocks*: int
    usedDocks*: int
    isCrippled*: bool
    constructionProjects*: int  # Active construction count
    repairProjects*: int        # Active repair count

proc getFacilityCapacity*(spaceport: gamestate.Spaceport): FacilityCapacity =
  ## Calculate capacity status for a spaceport
  var used = 0
  if spaceport.activeConstruction.isSome:
    used += 1

  result = FacilityCapacity(
    facilityId: spaceport.id,
    facilityType: econ_types.FacilityType.Spaceport,
    maxDocks: spaceport.docks,
    usedDocks: used,
    isCrippled: false,  # Spaceports don't get crippled
    constructionProjects: used,
    repairProjects: 0  # Spaceports don't repair
  )

proc getFacilityCapacity*(shipyard: gamestate.Shipyard): FacilityCapacity =
  ## Calculate capacity status for a shipyard
  var used = 0
  if shipyard.activeConstruction.isSome:
    used += 1
  used += shipyard.activeRepairs.len

  let construction = if shipyard.activeConstruction.isSome: 1 else: 0

  result = FacilityCapacity(
    facilityId: shipyard.id,
    facilityType: econ_types.FacilityType.Shipyard,
    maxDocks: shipyard.docks,
    usedDocks: used,
    isCrippled: shipyard.isCrippled,
    constructionProjects: construction,
    repairProjects: shipyard.activeRepairs.len
  )

proc analyzeColonyCapacity*(state: GameState, colonyId: core.SystemId): seq[FacilityCapacity] =
  ## Analyze all facility capacities for a colony
  ## Returns capacity status for each facility
  result = @[]

  if not state.colonies.hasKey(colonyId):
    return

  let colony = state.colonies[colonyId]

  # Analyze spaceports
  for spaceport in colony.spaceports:
    result.add(getFacilityCapacity(spaceport))

  # Analyze shipyards
  for shipyard in colony.shipyards:
    result.add(getFacilityCapacity(shipyard))

proc checkColonyViolation*(state: GameState, colonyId: core.SystemId): Option[types.CapacityViolation] =
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
    return some(types.CapacityViolation(
      capacityType: CapacityType.ConstructionDock,
      entityId: $colonyId,
      current: totalCurrent,
      maximum: totalMaximum,
      excess: max(0, totalCurrent - totalMaximum),
      severity: ViolationSeverity.Critical,
      graceTurnsRemaining: 0,
      violationTurn: state.turn
    ))
  else:
    return none(types.CapacityViolation)

proc checkAllViolations*(state: GameState): seq[types.CapacityViolation] =
  ## Check all colonies for dock capacity violations
  ## Pure function - returns analysis without mutations
  result = @[]

  for colonyId, colony in state.colonies:
    let violation = checkColonyViolation(state, colonyId)
    if violation.isSome:
      result.add(violation.get())

proc getAvailableFacilities*(state: GameState, colonyId: core.SystemId,
                              projectType: econ_types.ConstructionType): seq[tuple[facilityId: string, facilityType: econ_types.FacilityType, availableDocks: int]] =
  ## Get list of facilities with available dock capacity at colony
  ## Returns facilities sorted by priority: shipyards first, then by available capacity (descending)
  ##
  ## For projectType=Building and itemId=Shipyard/Starbase:
  ##   Returns spaceports only (shipyards/starbases built in orbit, don't occupy docks)
  result = @[]

  if not state.colonies.hasKey(colonyId):
    return

  let colony = state.colonies[colonyId]
  let facilities = analyzeColonyCapacity(state, colonyId)

  # Collect available facilities
  for facility in facilities:
    # Skip crippled shipyards (0 capacity)
    if facility.isCrippled:
      continue

    let available = facility.maxDocks - facility.usedDocks
    if available > 0:
      result.add((facility.facilityId, facility.facilityType, available))

  # Sort: Shipyards first, then by available docks (descending)
  result.sort do (a, b: tuple[facilityId: string, facilityType: econ_types.FacilityType, availableDocks: int]) -> int:
    # Shipyards have priority
    if a.facilityType == econ_types.FacilityType.Shipyard and b.facilityType == econ_types.FacilityType.Spaceport:
      return -1
    elif a.facilityType == econ_types.FacilityType.Spaceport and b.facilityType == econ_types.FacilityType.Shipyard:
      return 1
    else:
      # Among same type, prefer more available docks (even distribution)
      return cmp(b.availableDocks, a.availableDocks)

proc assignFacility*(state: GameState, colonyId: core.SystemId,
                     projectType: econ_types.ConstructionType,
                     itemId: string): Option[tuple[facilityId: string, facilityType: econ_types.FacilityType]] =
  ## Assign a construction project to the best available facility
  ##
  ## Assignment algorithm:
  ## 1. Prioritize shipyards over spaceports
  ## 2. Within same type, prefer facility with most available docks (even distribution)
  ## 3. For Shipyard/Starbase buildings, only return spaceports (orbital construction)
  ##
  ## Returns: (facilityId, facilityType) or none if no capacity

  # Special case: Shipyard/Starbase construction only uses spaceports for assist
  # These are built in orbit and don't occupy dock space
  if projectType == econ_types.ConstructionType.Building and
     (itemId == "Shipyard" or itemId == "Starbase"):
    # For shipyard/starbase, we need a spaceport but it doesn't consume docks
    if not state.colonies.hasKey(colonyId):
      return none(tuple[facilityId: string, facilityType: econ_types.FacilityType])

    let colony = state.colonies[colonyId]
    if colony.spaceports.len > 0:
      # Return first spaceport (assists but doesn't consume capacity)
      return some((colony.spaceports[0].id, econ_types.FacilityType.Spaceport))
    else:
      return none(tuple[facilityId: string, facilityType: econ_types.FacilityType])

  # Normal case: find facility with available capacity
  let available = getAvailableFacilities(state, colonyId, projectType)

  if available.len == 0:
    return none(tuple[facilityId: string, facilityType: econ_types.FacilityType])

  # Return first (highest priority) facility
  return some((available[0].facilityId, available[0].facilityType))

proc processCapacityReporting*(state: GameState): seq[types.CapacityViolation] =
  ## Main entry point - report capacity violations (should never happen)
  ## Called during Maintenance phase
  ## Returns: List of violations found (for logging/debugging)

  result = checkAllViolations(state)

  if result.len == 0:
    logDebug("Economy", "All facilities within construction dock capacity")
  else:
    # This should NEVER happen - capacity enforced at build time
    for violation in result:
      logWarn("Economy",
              "Colony " & violation.entityId & " OVER dock capacity (BUG!)",
              " usage=", $violation.current, "/", $violation.maximum,
              " excess=", $violation.excess)

proc shipRequiresDock*(shipClass: ShipClass): bool =
  ## Check if a ship class requires dock construction capacity
  ## Fighters are built planet-side (distributed manufacturing) and don't use docks
  ## All other ships require dock space at spaceport or shipyard
  return shipClass != ShipClass.Fighter

proc getColonyTotalCapacity*(state: GameState, colonyId: core.SystemId): tuple[current: int, maximum: int] =
  ## Get total dock capacity for colony (sum of all facilities)
  ## Used for display/reporting purposes
  result = (current: 0, maximum: 0)

  let facilities = analyzeColonyCapacity(state, colonyId)
  for facility in facilities:
    result.current += facility.usedDocks
    if not facility.isCrippled:
      result.maximum += facility.maxDocks

proc assignAndQueueProject*(state: var GameState, colonyId: core.SystemId,
                             project: econ_types.ConstructionProject): bool =
  ## Assign project to best available facility and add to its queue
  ## Returns true if successful, false if no capacity
  ##
  ## This is the main entry point for adding construction projects to facility queues.
  ## Automatically assigns to best facility per assignment algorithm.

  if not state.colonies.hasKey(colonyId):
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
  var colony = state.colonies[colonyId]
  var added = false

  if facilityType == econ_types.FacilityType.Spaceport:
    # Find and update spaceport
    for spaceport in colony.spaceports.mitems:
      if spaceport.id == facilityId:
        spaceport.constructionQueue.add(assignedProject)
        added = true
        logDebug("Economy",
                "Project queued to spaceport",
                " facility=", facilityId,
                " project=", project.itemId)
        break
  else:
    # Find and update shipyard
    for shipyard in colony.shipyards.mitems:
      if shipyard.id == facilityId:
        shipyard.constructionQueue.add(assignedProject)
        added = true
        logDebug("Economy",
                "Project queued to shipyard",
                " facility=", facilityId,
                " project=", project.itemId)
        break

  if added:
    state.colonies[colonyId] = colony
    return true
  else:
    logWarn("Economy", "Failed to find assigned facility", " facility=", facilityId)
    return false

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
