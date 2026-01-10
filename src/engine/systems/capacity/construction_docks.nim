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

import std/[strutils, algorithm, options, math]
import ../../types/[capacity, core, game_state, ship, production, facilities, colony,
                    combat]
import ../../state/[engine, iterators]
import ../../entities/project_ops
import ../../../common/logger

proc projectDesc*(p: ConstructionProject): string =
  ## Format project description from typed fields for logging
  if p.shipClass.isSome: return $p.shipClass.get()
  if p.facilityClass.isSome: return $p.facilityClass.get()
  if p.groundClass.isSome: return $p.groundClass.get()
  if p.industrialUnits > 0: return $p.industrialUnits & " IU"
  return "unknown"

export capacity.CapacityViolation, capacity.ViolationSeverity

type FacilityCapacity* = object ## Capacity status for a single facility
  facilityId*: string
  facilityType*: NeoriaClass
  maxDocks*: int32
  usedDocks*: int32
  isCrippled*: bool
  constructionProjects*: int32 # Active construction count
  repairProjects*: int32 # Active repair count

proc getFacilityCapacity*(neoria: Neoria): FacilityCapacity =
  ## Get capacity status for a neoria (uses pre-calculated effectiveDocks)
  let used = int32(neoria.activeConstructions.len + neoria.activeRepairs.len)
  let isCrippled = neoria.state == CombatState.Crippled

  result = FacilityCapacity(
    facilityId: $uint32(neoria.id),
    facilityType: neoria.neoriaClass,
    maxDocks: neoria.effectiveDocks,
    usedDocks: used,
    isCrippled: isCrippled,
    constructionProjects: int32(neoria.activeConstructions.len),
    repairProjects: int32(neoria.activeRepairs.len),
  )

proc analyzeColonyCapacity*(
    state: GameState, colonyId: ColonyId
): seq[FacilityCapacity] =
  ## Analyze all facility capacities for a colony
  ## Returns capacity status for each facility
  result = @[]

  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  let colony = colonyOpt.get()

  # Analyze all neorias at colony
  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome:
      result.add(getFacilityCapacity(neoriaOpt.get()))

proc checkColonyViolation*(
    state: GameState, colonyId: ColonyId
): Option[capacity.CapacityViolation] =
  ## Check if colony has any facilities exceeding capacity
  ## This should NEVER happen (hard limit at build time) but we track it

  let facilities = analyzeColonyCapacity(state, colonyId)
  var totalCurrent = 0'i32
  var totalMaximum = 0'i32
  var hasViolation = false

  for facility in facilities:
    totalCurrent += facility.usedDocks
    # Crippled facilities contribute 0 to max capacity
    if facility.isCrippled:
      totalMaximum += 0'i32
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
        current: totalCurrent,
        maximum: totalMaximum,
        excess: max(0'i32, totalCurrent - totalMaximum),
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
): seq[tuple[facilityId: string, facilityType: NeoriaClass, availableDocks: int32]] =
  ## Get list of facilities with available dock capacity at colony
  ## Returns facilities sorted by priority: shipyards first, then by available
  ## capacity (descending)
  ##
  ## For projectType=Facility and facilityClass=Shipyard/Starbase:
  ##   Returns spaceports only (shipyards/starbases built in orbit, don't
  ##   occupy docks)
  result = @[]

  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  let facilities = analyzeColonyCapacity(state, colonyId)

  # Collect available facilities
  for facility in facilities:
    # Skip crippled facilities (0 capacity)
    if facility.isCrippled:
      continue

    # Skip drydocks - they're repair-only, not for construction
    if facility.facilityType == NeoriaClass.Drydock:
      continue

    let available = facility.maxDocks - facility.usedDocks
    if available > 0'i32:
      result.add((facility.facilityId, facility.facilityType, available))

  # Sort: Shipyards first, then by available docks (descending)
  result.sort do(
    a, b: tuple[facilityId: string, facilityType: NeoriaClass, availableDocks: int32]
  ) -> int:
    # Shipyards have priority
    if a.facilityType == NeoriaClass.Shipyard and
        b.facilityType == NeoriaClass.Spaceport:
      return -1
    elif a.facilityType == NeoriaClass.Spaceport and
        b.facilityType == NeoriaClass.Shipyard:
      return 1
    else:
      # Among same type, prefer more available docks (even distribution)
      return cmp(b.availableDocks, a.availableDocks)

proc assignFacility*(
    state: GameState,
    colonyId: ColonyId,
    projectType: BuildType,
    facilityClass: Option[FacilityClass] = none(FacilityClass),
): Option[tuple[facilityId: NeoriaId, facilityType: NeoriaClass]] =
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
  if facilityClass == some(FacilityClass.Shipyard):
    # For shipyard, we need a spaceport but it doesn't consume docks
    let colonyOpt = state.colony(colonyId)
    if colonyOpt.isNone:
      return none(tuple[facilityId: NeoriaId, facilityType: NeoriaClass])

    let colony = colonyOpt.get()

    # Find first spaceport at colony
    for neoriaId in colony.neoriaIds:
      let neoriaOpt = state.neoria(neoriaId)
      if neoriaOpt.isSome:
        let neoria = neoriaOpt.get()
        if neoria.neoriaClass == NeoriaClass.Spaceport:
          # Return first spaceport (assists but doesn't consume capacity)
          return some((neoriaId, NeoriaClass.Spaceport))

    return none(tuple[facilityId: NeoriaId, facilityType: NeoriaClass])

  # Normal case: find facility with available capacity
  let available = getAvailableFacilities(state, colonyId, projectType)

  if available.len == 0:
    return none(tuple[facilityId: NeoriaId, facilityType: NeoriaClass])

  # Return first (highest priority) facility
  # Convert string ID to NeoriaId
  return some((NeoriaId(parseUInt(available[0].facilityId)), available[0].facilityType))

proc processCapacityReporting*(state: GameState): seq[capacity.CapacityViolation] =
  ## Main entry point - report capacity violations (should never happen)
  ## Called during Maintenance phase
  ## Returns: List of violations found (for logging/debugging)

  result = checkAllViolations(state)

  if result.len == 0:
    logDebug("Economy", "All facilities within construction dock capacity")
  else:
    # This should NEVER happen - capacity enforced at build time
    for violation in result:
      logWarn(
        "Economy",
        "Colony over dock capacity (BUG!)",
        " colony=",
        $violation.entity.colonyId,
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
): tuple[current: int32, maximum: int32] =
  ## Get total dock capacity for colony (sum of all facilities)
  ## Used for display/reporting purposes
  result = (current: 0'i32, maximum: 0'i32)

  let facilities = analyzeColonyCapacity(state, colonyId)
  for facility in facilities:
    result.current += facility.usedDocks
    if not facility.isCrippled:
      result.maximum += facility.maxDocks

proc assignAndQueueProject*(
    state: GameState, colonyId: ColonyId, project: ConstructionProject
): bool =
  ## Assign project to best available facility and add to its queue
  ## Returns true if successful, false if no capacity
  ##
  ## This is the main entry point for adding construction projects to facility
  ## queues. Automatically assigns to best facility per assignment algorithm.

  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return false

  # Assign facility
  let assignment = assignFacility(state, colonyId, project.projectType, project.facilityClass)
  if assignment.isNone:
    # No available facility capacity
    return false

  let (facilityId, _) = assignment.get()

  # Verify facility exists
  let neoriaId = facilityId
  let neoriaOpt = state.neoria(neoriaId)
  if neoriaOpt.isNone:
    logWarn("Economy", "Failed to find neoria", " facility=", $facilityId)
    return false

  # Create project with facility assignment and register with entity manager
  # queueConstructionProject generates ID, adds to entity manager, and adds to
  # the neoria's constructionQueue (when neoriaId is set)
  var assignedProject = project
  assignedProject.neoriaId = some(neoriaId)
  discard state.queueConstructionProject(colonyId, assignedProject)

  let neoria = neoriaOpt.get()
  logDebug(
    "Economy",
    "Project queued to facility",
    " facility=",
    $facilityId,
    " type=",
    $neoria.neoriaClass,
    " project=",
    project.projectDesc,
  )
  return true

## Design Notes:
##
## **Per-Facility Architecture:**
## Each facility independently tracks its own queues and capacity:
## - Neoria.constructionQueue, Neoria.activeConstructions
## - Neoria.repairQueue, Neoria.activeRepairs
##
## **Assignment Strategy:**
## 1. Prioritize shipyards (more capable, 10 docks)
## 2. Distribute evenly across available capacity
## 3. Spaceports as fallback (5 docks, 2x ship cost penalty)
##
## **Special Cases:**
## - Shipyard/Starbase construction: Requires spaceport assist but doesn't occupy docks
## - Crippled facilities: 0 capacity until repaired
## - FIFO priority: Construction and repair projects treated equally in queue
##
## **Integration Points:**
## - Call assignFacility() when player submits build command
## - Call processCapacityReporting() in Maintenance phase (should find nothing)
## - Check getAvailableFacilities() to show player available capacity
##
## **Spaceport Cost Penalty:**
## Ships built at spaceports cost 2x PP (handled in construction cost calculation)
## Exception: Shipyard/Starbase buildings don't have penalty (orbital construction)
##
