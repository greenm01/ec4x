## Fleet command validation for EC4X
##
## This module provides validation logic for player commands.
## All type definitions are in @types/ modules per architecture.md.

import std/[options, tables, strformat, sequtils]
import
  ../../types/[
    core,
    game_state,
    command,
    fleet,
    production,
    diplomacy,
    colony,
    starmap,
    espionage as esp_types,
    tech as tech_types,
    facilities,
  ]
import ../capacity/[capital_squadrons, total_squadrons]
import ../../state/[engine]
import ../../../common/logger
import ../production/projects
import ../fleet/entity

# Re-export command types for convenience
export command.CommandPacket, command.ValidationResult
export command.CommandValidationContext, command.CommandCostSummary
export fleet.FleetCommandType, fleet.FleetCommand
export production.BuildCommand, production.BuildType
export diplomacy.DiplomaticCommand, diplomacy.DiplomaticActionType
export colony.TerraformCommand, colony.PopulationTransferCommand

# Command validation

proc validateFleetCommand*(
    cmd: FleetCommand, state: GameState, issuingHouse: HouseId
): ValidationResult =
  ## Validate a fleet command against current game state
  ## Checks:
  ## - Fleet exists
  ## - Fleet ownership (prevents controlling enemy fleets)
  ## - Fleet mission state (locked if OnSpyMission)
  ## - Target validity (system exists, path exists)
  ## - Required capabilities (transport, combat, scout)
  ## Creates GameEvent when commands are rejected
  result = ValidationResult(valid: true, error: "")

  # Check fleet exists
  let fleetOpt = state_helpers.getFleet(state, cmd.fleetId)
  if fleetOpt.isNone:
    logWarn(
      LogCategory.lcOrders,
      &"{issuingHouse} Fleet Validation FAILED: {cmd.fleetId} does not exist",
    )
    return ValidationResult(valid: false, error: "Fleet does not exist")

  let fleet = fleetOpt.get()

  # CRITICAL: Validate fleet ownership (prevent controlling enemy fleets)
  if fleet.houseId != issuingHouse:
    logWarn(
      LogCategory.lcOrders,
      &"SECURITY VIOLATION: {issuingHouse} attempted to control {cmd.fleetId} " &
        &"(owned by {fleet.houseId})",
    )
    return ValidationResult(
      valid: false, error: &"Fleet {cmd.fleetId} is not owned by {issuingHouse}"
    )

  # Check if fleet is locked on active spy mission
  # Scouts on active missions (OnSpyMission state) cannot accept new commands
  # Scouts traveling to mission (Traveling state) can change commands (cancel mission)
  if fleet.missionState == FleetMissionState.OnSpyMission:
    logWarn(
      LogCategory.lcOrders,
      &"{issuingHouse} Command REJECTED: {cmd.fleetId} is on active spy mission " &
        &"(cannot issue new commands while mission active)",
    )
    return ValidationResult(
      valid: false, error: "Fleet locked on active spy mission (scouts consumed)"
    )

  logDebug(
    LogCategory.lcOrders,
    &"{issuingHouse} Validating {cmd.commandType} command for {cmd.fleetId} " &
      &"at {fleet.location}",
  )

  # Validate based on command type
  case cmd.commandType
  of FleetCommandType.Hold:
    # Always valid
    discard
  of FleetCommandType.Move:
    if cmd.targetSystem.isNone:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} Move command REJECTED: {cmd.fleetId} - no target system specified",
      )
      return
        ValidationResult(valid: false, error: "Move command requires target system")

    let targetId = cmd.targetSystem.get()
    if not state.starMap.systems.hasKey(targetId):
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} Move command REJECTED: {cmd.fleetId} → {targetId} " &
          &"(target system does not exist)",
      )
      return ValidationResult(valid: false, error: "Target system does not exist")

    # Check pathfinding - can fleet reach target?
    let pathResult = state.starMap.findPath(fleet.location, targetId, fleet)
    if not pathResult.found:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} Move command REJECTED: {cmd.fleetId} → {targetId} " &
          &"(no valid path from {fleet.location})",
      )
      return ValidationResult(valid: false, error: "No valid path to target system")

    logDebug(
      LogCategory.lcOrders,
      &"{issuingHouse} Move command VALID: {cmd.fleetId} → {targetId} " &
        &"({pathResult.path.len - 1} jumps via {fleet.location})",
    )
  of FleetCommandType.Colonize:
    # Check fleet has operational ETAC (Expansion squadron)
    logDebug(
      LogCategory.lcOrders,
      &"{issuingHouse} Validating Colonize command for {cmd.fleetId} at " &
        &"{fleet.location} ({fleet.squadrons.len} squadrons)",
    )
    var hasETAC = false
    for squadronId in fleet.squadrons:
      let sq = state.squadron(squadronId).get
      if sq.squadronType == SquadronClass.Expansion:
        let flagship = state.ship(sq.flagshipId).get
        logDebug(
          LogCategory.lcOrders,
          &"  Squadron {sq.id}: class={flagship.shipClass}, " &
            &"crippled={flagship.isCrippled}, " & &"cargo={flagship.cargo}",
        )
        if flagship.shipClass == ShipClass.ETAC:
          if not flagship.isCrippled:
            hasETAC = true
            break

    if not hasETAC:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} Colonize command REJECTED: {cmd.fleetId} - " &
          &"no functional ETAC",
      )
      return ValidationResult(valid: false, error: "Colonize requires functional ETAC")

    if cmd.targetSystem.isNone:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} Colonize command REJECTED: {cmd.fleetId} - no target system specified",
      )
      return
        ValidationResult(valid: false, error: "Colonize command requires target system")

    # Check if system already colonized
    let targetId = cmd.targetSystem.get()
    let colonyOpt = state.colonyBySystem(targetId)
    if colonyOpt.isSome:
      let colony = colonyOpt.get()
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} Colonize command REJECTED: {cmd.fleetId} → {targetId} " &
          &"(already colonized by {colony.owner})",
      )
      return ValidationResult(valid: false, error: "Target system is already colonized")

    logDebug(
      LogCategory.lcOrders,
      &"{issuingHouse} Colonize command VALID: {cmd.fleetId} → {targetId}",
    )
  of FleetCommandType.Bombard, FleetCommandType.Invade, FleetCommandType.Blitz:
    # Check fleet has no Intel squadrons (Intel squadrons are intelligence-only, not combat units)
    for squadronId in fleet.squadrons:
      let sq = state.squadron(squadronId).get
      if sq.squadronType == SquadronClass.Intel:
        logWarn(
          LogCategory.lcOrders,
          &"{issuingHouse} {cmd.commandType} command REJECTED: {cmd.fleetId} - " &
            &"combat commands cannot include Intel squadrons (intelligence-only)",
        )
        return ValidationResult(
          valid: false, error: "Combat commands cannot include Intel squadrons"
        )

    # Check fleet has combat squadrons
    var hasMilitary = false
    for squadronId in fleet.squadrons:
      let sq = state.squadron(squadronId).get
      let flagship = state.ship(sq.flagshipId).get
      if flagship.stats.attackStrength > 0:
        hasMilitary = true
        break

    if not hasMilitary:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} {cmd.commandType} command REJECTED: {cmd.fleetId} - " &
          &"no combat-capable squadrons",
      )
      return ValidationResult(
        valid: false, error: "Combat command requires combat-capable squadrons"
      )

    if cmd.targetSystem.isNone:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} {cmd.commandType} command REJECTED: {cmd.fleetId} - " &
          &"no target system specified",
      )
      return
        ValidationResult(valid: false, error: "Combat command requires target system")

    logDebug(
      LogCategory.lcOrders,
      &"{issuingHouse} {cmd.commandType} command VALID: {cmd.fleetId} → " &
        &"{cmd.targetSystem.get()}",
    )
  of FleetCommandType.SpyColony, FleetCommandType.SpySystem,
      FleetCommandType.HackStarbase:
    # Spy missions require pure Intel fleets (no combat, auxiliary, or expansion squadrons)
    # Multiple Intel squadrons can merge for mesh network ELI bonuses
    if fleet.squadrons.len == 0:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} {cmd.commandType} command REJECTED: {cmd.fleetId} - " &
          &"requires at least one Intel squadron",
      )
      return ValidationResult(
        valid: false, error: "Spy missions require at least one Intel squadron"
      )

    # Check fleet is pure Intel (all squadrons must be Intel type)
    var hasIntel = false
    var hasNonIntel = false

    for squadronId in fleet.squadrons:
      let sq = state.squadron(squadronId).get
      if sq.squadronType == SquadronClass.Intel:
        hasIntel = true
      else:
        hasNonIntel = true
        logWarn(
          LogCategory.lcOrders,
          &"{issuingHouse} {cmd.commandType} command REJECTED: {cmd.fleetId} - " &
            &"spy missions require pure Intel fleet (found {sq.squadronType} squadron)",
        )

    if not hasIntel:
      return ValidationResult(
        valid: false, error: "Spy missions require at least one Intel squadron"
      )

    if hasNonIntel:
      return ValidationResult(
        valid: false,
        error: "Spy missions require pure Intel fleet (no combat/auxiliary/expansion)",
      )

    if cmd.targetSystem.isNone:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} {cmd.commandType} command REJECTED: {cmd.fleetId} - " &
          &"no target system specified",
      )
      return ValidationResult(valid: false, error: "Spy mission requires target system")

    logDebug(
      LogCategory.lcOrders,
      &"{issuingHouse} {cmd.commandType} command VALID: {cmd.fleetId} → " &
        &"{cmd.targetSystem.get()}",
    )
  of FleetCommandType.JoinFleet:
    if cmd.targetFleet.isNone:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} JoinFleet command REJECTED: {cmd.fleetId} - " &
          &"no target fleet specified",
      )
      return ValidationResult(valid: false, error: "Join command requires target fleet")

    let targetFleetId = cmd.targetFleet.get()
    let targetFleetOpt = state_helpers.getFleet(state, targetFleetId)
    if targetFleetOpt.isNone:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} JoinFleet command REJECTED: {cmd.fleetId} → {targetFleetId} " &
          &"(target fleet does not exist)",
      )
      return ValidationResult(valid: false, error: "Target fleet does not exist")

    # Check fleets are in same location
    let targetFleet = targetFleetOpt.get()
    if fleet.location != targetFleet.location:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} JoinFleet command REJECTED: {cmd.fleetId} → {targetFleetId} " &
          &"(fleets at different systems: {fleet.location} vs {targetFleet.location})",
      )
      return
        ValidationResult(valid: false, error: "Fleets must be in same system to join")

    # Check scout/combat fleet mixing
    let mergeCheck = fleet.canMergeWith(targetFleet, state.squadrons)
    if not mergeCheck.canMerge:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} JoinFleet command REJECTED: {cmd.fleetId} → {targetFleetId} - " &
          &"{mergeCheck.reason}",
      )
      return ValidationResult(valid: false, error: mergeCheck.reason)

    logDebug(
      LogCategory.lcOrders,
      &"{issuingHouse} JoinFleet command VALID: {cmd.fleetId} → {targetFleetId} " &
        &"at {fleet.location}",
    )
  of FleetCommandType.Rendezvous:
    if cmd.targetSystem.isNone:
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} Rendezvous command REJECTED: {cmd.fleetId} - " &
          &"no target system specified",
      )
      return ValidationResult(
        valid: false, error: "Rendezvous command requires target system"
      )

    let targetId = cmd.targetSystem.get()
    if not state.starMap.systems.hasKey(targetId):
      logWarn(
        LogCategory.lcOrders,
        &"{issuingHouse} Rendezvous command REJECTED: {cmd.fleetId} → {targetId} " &
          &"(target system does not exist)",
      )
      return ValidationResult(valid: false, error: "Target system does not exist")

    logDebug(
      LogCategory.lcOrders,
      &"{issuingHouse} Rendezvous command VALID: {cmd.fleetId} → {targetId}",
    )
  else:
    # Other command types - basic validation only for now
    discard

proc validateCommandPacket*(packet: CommandPacket, state: GameState): ValidationResult =
  ## Validate entire command packet for a house
  ## Performs comprehensive validation including:
  ## - Fleet ownership (prevents controlling enemy fleets)
  ## - Target validity (systems exist, paths exist)
  ## - Colony ownership (prevents building at enemy colonies)
  ## Creates GameEvents for rejected commands
  result = ValidationResult(valid: true, error: "")

  # Check house exists
  if packet.houseId notin state.houses:
    logWarn(
      LogCategory.lcOrders, &"Command packet REJECTED: {packet.houseId} does not exist"
    )
    return ValidationResult(valid: false, error: "House does not exist")

  # Check turn number matches
  if packet.turn != state.turn:
    logWarn(
      LogCategory.lcOrders,
      &"{packet.houseId} Command packet REJECTED: wrong turn " &
        &"(packet={packet.turn}, current={state.turn})",
    )
    return ValidationResult(valid: false, error: "Command packet for wrong turn")

  logInfo(
    LogCategory.lcOrders,
    &"{packet.houseId} Validating command packet: {packet.fleetCommands.len} fleet commands, " &
      &"{packet.buildCommands.len} build commands",
  )

  # Validate each fleet command with ownership check
  var validFleetCommands = 0
  for cmd in packet.fleetCommands:
    let cmdResult = validateFleetCommand(cmd, state, packet.houseId)
    if not cmdResult.valid:
      return cmdResult
    validFleetCommands += 1

  if packet.fleetCommands.len > 0:
    logInfo(
      LogCategory.lcOrders,
      &"{packet.houseId} Fleet commands: {validFleetCommands}/{packet.fleetCommands.len} valid",
    )

  # Validate build commands (check colony ownership, production capacity)
  var validBuildCommands = 0
  for cmd in packet.buildCommands:
    # Check colony exists and is owned by house
    let colonyOpt = state.colony(cmd.colonyId)
    if colonyOpt.isNone:
      logWarn(
        LogCategory.lcOrders,
        &"{packet.houseId} Build command REJECTED: colony at {cmd.colonyId} " &
          &"does not exist",
      )
      return ValidationResult(
        valid: false, error: "Build command: Colony does not exist at " & $cmd.colonyId
      )

    let colony = colonyOpt.get()
    if colony.owner != packet.houseId:
      logWarn(
        LogCategory.lcOrders,
        &"SECURITY VIOLATION: {packet.houseId} attempted to build at {cmd.colonyId} " &
          &"(owned by {colony.owner})",
      )
      return ValidationResult(
        valid: false,
        error: "Build command: House does not own colony at " & $cmd.colonyId,
      )

    # Check CST tech requirement for ships (economy.md:4.5)
    if cmd.buildType == BuildType.Ship and cmd.shipClass.isSome:
      let shipClass = cmd.shipClass.get()
      let required_cst = getShipCSTRequirement(shipClass)

      # Get house's CST level
      if packet.houseId in state.houses:
        let house = state.houses[packet.houseId]
        let house_cst = house.techTree.levels.constructionTech

        if house_cst < required_cst:
          logWarn(
            LogCategory.lcOrders,
            &"{packet.houseId} Build command REJECTED: {shipClass} requires CST{required_cst}, " &
              &"house has CST{house_cst}",
          )
          return ValidationResult(
            valid: false,
            error:
              &"Build command: {shipClass} requires CST{required_cst}, house has CST{house_cst}",
          )

    # Check CST tech requirement and prerequisites for buildings (assets.md:2.4.4)
    if cmd.buildType == BuildType.Facility and cmd.buildingType.isSome:
      let buildingType = cmd.buildingType.get()

      # Check CST requirement (e.g., Starbase requires CST3)
      let required_cst = getBuildingCSTRequirement(buildingType)
      if required_cst > 0 and packet.houseId in state.houses:
        let house = state.houses[packet.houseId]
        let house_cst = house.techTree.levels.constructionTech

        if house_cst < required_cst:
          logWarn(
            LogCategory.lcOrders,
            &"{packet.houseId} Build command REJECTED: {buildingType} requires CST{required_cst}, " &
              &"house has CST{house_cst}",
          )
          return ValidationResult(
            valid: false,
            error:
              &"Build command: {buildingType} requires CST{required_cst}, house has CST{house_cst}",
          )

      # Check shipyard prerequisite (e.g., Starbase requires shipyard)
      if requiresShipyard(buildingType):
        if not hasOperationalShipyard(colony):
          logWarn(
            LogCategory.lcOrders,
            &"{packet.houseId} Build command REJECTED: {buildingType} requires operational shipyard at {cmd.colonyId}",
          )
          return ValidationResult(
            valid: false,
            error: &"Build command: {buildingType} requires operational shipyard",
          )

    # NOTE: Multiple build commands per colony per turn are supported (queue system)
    # Dock capacity is validated during resolution (production_resolution.nim)
    # Commands beyond capacity remain queued for future turns
    # This allows unlimited PP spending per turn (limited by treasury + dock capacity)

    validBuildCommands += 1
    logDebug(
      LogCategory.lcOrders,
      &"{packet.houseId} Build command VALID: {cmd.buildType} at {cmd.colonyId}",
    )

  if packet.buildCommands.len > 0:
    logInfo(
      LogCategory.lcOrders,
      &"{packet.houseId} Build commands: {validBuildCommands}/{packet.buildCommands.len} valid",
    )

  # Validate research allocation (check total points available)
  # Note: Actual PP availability check happens during resolution (after income phase)
  # Here we just validate structure - allocation can't be negative
  if packet.researchAllocation.economic < 0 or packet.researchAllocation.science < 0:
    return ValidationResult(
      valid: false, error: "Research allocation: Cannot allocate negative PP"
    )

  # Validate technology allocations (per-field)
  for field, amount in packet.researchAllocation.technology:
    if amount < 0:
      return ValidationResult(
        valid: false,
        error: "Research allocation: Cannot allocate negative PP to " & $field,
      )

  # Validate diplomatic actions (check diplomatic state and constraints)
  for action in packet.diplomaticCommand:
    # Check target house exists
    if action.targetHouse notin state.houses:
      return ValidationResult(
        valid: false, error: "Diplomatic action: Target house does not exist"
      )

    # Can't take diplomatic actions against eliminated houses
    if state.houses[action.targetHouse].eliminated:
      return ValidationResult(
        valid: false, error: "Diplomatic action: Target house is eliminated"
      )

    # Can't target self
    if action.targetHouse == packet.houseId:
      return ValidationResult(
        valid: false, error: "Diplomatic action: Cannot target own house"
      )

  # Validate colony management commands
  for cmd in packet.colonyManagement:
    # Check colony exists
    let colonyOpt = state.colony(cmd.colonyId)
    if colonyOpt.isNone:
      return ValidationResult(
        valid: false,
        error: "Colony management: Colony does not exist at " & $cmd.colonyId,
      )

    # Check ownership
    let colony = colonyOpt.get()
    if colony.owner != packet.houseId:
      return ValidationResult(
        valid: false,
        error: "Colony management: House does not own colony at " & $cmd.colonyId,
      )

    # Validate parameters
    if cmd.taxRate.isSome:
      let rate = cmd.taxRate.get()
      if rate < 0 or rate > 100:
        return ValidationResult(
          valid: false, error: "Colony management: Tax rate must be 0-100"
        )

  # All validations passed
  logInfo(
    LogCategory.lcOrders,
    &"{packet.houseId} Command packet VALIDATED: All commands valid and authorized",
  )
  result = ValidationResult(valid: true, error: "")

# Command creation helpers

proc createMoveCommand*(
    fleetId: FleetId, targetSystem: SystemId, priority: int32 = 0
): FleetCommand =
  ## Create a movement command
  result = FleetCommand(
    orderType: FleetCommandType.Move,
    targetSystem: some(targetSystem),
    targetFleet: none(FleetId),
    priority: priority,
  )

proc createColonizeCommand*(
    fleetId: FleetId, targetSystem: SystemId, priority: int32 = 0
): FleetCommand =
  ## Create a colonization command
  result = FleetCommand(
    orderType: FleetCommandType.Colonize,
    targetSystem: some(targetSystem),
    targetFleet: none(FleetId),
    priority: priority,
  )

proc createAttackCommand*(
    fleetId: FleetId,
    targetSystem: SystemId,
    attackType: FleetCommandType,
    priority: int32 = 0,
): FleetCommand =
  ## Create an attack command (bombard, invade, or blitz)
  result = FleetCommand(
    orderType: attackType,
    targetSystem: some(targetSystem),
    targetFleet: none(FleetId),
    priority: priority,
  )

proc createHoldCommand*(fleetId: FleetId, priority: int32 = 0): FleetCommand =
  ## Create a hold position command
  result = FleetCommand(
    orderType: FleetCommandType.Hold,
    targetSystem: none(SystemId),
    targetFleet: none(FleetId),
    priority: priority,
  )

# Command packet creation

proc newCommandPacket*(
    houseId: HouseId, turn: int32, treasury: int32 = 0
): CommandPacket =
  ## Create empty command packet for a house
  ## treasury: Treasury at command generation time (defaults to 0 for test harnesses)
  result = CommandPacket(
    houseId: houseId,
    turn: turn,
    treasury: treasury,
    fleetCommands: @[],
    buildCommands: @[],
    researchAllocation: tech_types.initResearchAllocation(),
    diplomaticCommand: @[],
    populationTransfers: @[],
    terraformCommands: @[],
    colonyManagement: @[],
    standingCommands: initTable[FleetId, StandingCommand](),
    espionageAction: none(esp_types.EspionageAttempt),
    ebpInvestment: 0,
    cipInvestment: 0,
  )

proc addFleetCommand*(packet: var CommandPacket, cmd: FleetCommand) =
  ## Add a fleet command to packet
  packet.fleetCommands.add(cmd)

proc addBuildCommand*(packet: var CommandPacket, cmd: BuildCommand) =
  ## Add a build command to packet
  packet.buildCommands.add(cmd)

# Budget tracking and validation

proc initCommandValidationContext*(treasury: int32): CommandValidationContext =
  ## Create new validation context for command packet
  result = CommandValidationContext(
    availableTreasury: treasury, committedSpending: 0, rejectedCommands: 0
  )

proc getRemainingBudget*(ctx: CommandValidationContext): int32 =
  ## Get remaining budget after committed spending
  result = ctx.availableTreasury - ctx.committedSpending

proc calculateBuildCommandCost*(
    cmd: BuildCommand,
    state: GameState,
    assignedFacilityClass: Option[FacilityClass] = none(FacilityClass),
): int32 =
  ## Calculate the PP cost of a build command
  ## Returns 0 if cost cannot be determined
  ##
  ## IMPORTANT: Spaceport Commission Penalty (economy.md:5.1, 5.3)
  ## - Ships built at spaceports (planet-side) incur 100% PC increase (double cost)
  ## - Ships built at shipyards (orbital) have no penalty (standard cost)
  ## - Fighters are EXEMPT (distributed planetary manufacturing)
  ## - Shipyard/Starbase buildings are EXEMPT (orbital construction, no penalty)
  ##
  ## If assignedFacilityClass is provided, use it to determine cost.
  ## Otherwise, fall back to legacy logic (check if colony has shipyard).
  result = 0

  case cmd.buildType
  of BuildType.Ship:
    if cmd.shipClass.isSome:
      let baseCost =
        projects.getShipConstructionCost(cmd.shipClass.get()) * cmd.quantity
      let shipClass = cmd.shipClass.get()

      # Apply spaceport commission penalty if building planet-side
      # Per economy.md:5.1 - "Ships (excluding fighter squadrons) constructed planet-side incur a 100% PC increase"
      # IMPORTANT: Fighters are EXEMPT from the penalty (planet-based manufacturing)
      if shipClass == ShipClass.Fighter:
        # Fighters never incur commission penalty (distributed planetary manufacturing)
        result = baseCost
      elif assignedFacilityClass.isSome:
        # NEW: Per-facility cost calculation
        if assignedFacilityClass.get() == FacilityClass.Spaceport:
          # Planet-side construction (spaceport) → 100% penalty (double cost)
          result = baseCost * 2
        else:
          # Orbital construction (shipyard) → no penalty
          result = baseCost
      else:
        # LEGACY: Fall back to colony-wide check (for backwards compatibility)
        let colonyOpt = state.colony(cmd.colonyId)
        if colonyOpt.isSome:
          let colony = colonyOpt.get()
          let hasShipyard = colony.shipyardIds.len > 0
          let hasSpaceport = colony.spaceportIds.len > 0

          if not hasShipyard and hasSpaceport:
            # Planet-side construction (spaceport only) → 100% penalty (double cost)
            result = baseCost * 2
          else:
            # Orbital construction (shipyard present) → no penalty
            result = baseCost
        else:
          # Colony doesn't exist (validation will catch this)
          result = baseCost
  of BuildType.Facility:
    if cmd.buildingType.isSome:
      # Buildings never have spaceport penalty (planet-side industry)
      # Shipyard/Starbase are built in orbit and don't get penalty
      result = projects.getBuildingCost(cmd.buildingType.get()) * cmd.quantity
  of BuildType.Industrial, BuildType.Infrastructure:
    # Infrastructure cost depends on colony state
    let colonyOpt = state.colony(cmd.colonyId)
    if colonyOpt.isSome:
      let colony = colonyOpt.get()
      result = projects.getIndustrialUnitCost(colony) * cmd.industrialUnits
  else:
    discard

proc validateBuildCommandWithBudget*(
    cmd: BuildCommand,
    state: GameState,
    houseId: HouseId,
    ctx: var CommandValidationContext,
): ValidationResult =
  ## Validate build command including budget check and tech requirements
  ## Updates context with committed spending if valid

  # Basic validation first
  let colonyOpt = state.colony(cmd.colonyId)
  if colonyOpt.isNone:
    return ValidationResult(
      valid: false, error: &"Build command: Colony not found at {cmd.colonyId}"
    )

  let colony = colonyOpt.get()

  # Check CST tech requirement for ships (economy.md:4.5)
  if cmd.buildType == BuildType.Ship and cmd.shipClass.isSome:
    let shipClass = cmd.shipClass.get()
    let required_cst = getShipCSTRequirement(shipClass)

    # Get house's CST level
    if houseId in state.houses:
      let house = state.houses[houseId]
      let house_cst = house.techTree.levels.constructionTech

      if house_cst < required_cst:
        ctx.rejectedCommands += 1
        logWarn(
          LogCategory.lcEconomy,
          &"{houseId} Build command REJECTED: {shipClass} requires CST{required_cst}, " &
            &"house has CST{house_cst}",
        )
        return ValidationResult(
          valid: false,
          error:
            &"Build command: {shipClass} requires CST{required_cst}, house has CST{house_cst}",
        )

  # Check CST tech requirement and prerequisites for buildings (assets.md:2.4.4)
  if cmd.buildType == BuildType.Facility and cmd.buildingType.isSome:
    let buildingType = cmd.buildingType.get()

    # Check CST requirement (e.g., Starbase requires CST3)
    let required_cst = getBuildingCSTRequirement(buildingType)
    if required_cst > 0 and houseId in state.houses:
      let house = state.houses[houseId]
      let house_cst = house.techTree.levels.constructionTech

      if house_cst < required_cst:
        ctx.rejectedCommands += 1
        logWarn(
          LogCategory.lcEconomy,
          &"{houseId} Build command REJECTED: {buildingType} requires CST{required_cst}, " &
            &"house has CST{house_cst}",
        )
        return ValidationResult(
          valid: false,
          error:
            &"Build command: {buildingType} requires CST{required_cst}, house has CST{house_cst}",
        )

    # Check shipyard prerequisite (e.g., Starbase requires shipyard)
    if requiresShipyard(buildingType):
      if not hasOperationalShipyard(colony):
        ctx.rejectedCommands += 1
        logWarn(
          LogCategory.lcEconomy,
          &"{houseId} Build command REJECTED: {buildingType} requires operational shipyard at {cmd.colonyId}",
        )
        return ValidationResult(
          valid: false,
          error: &"Build command: {buildingType} requires operational shipyard",
        )

  # Check capacity limits for fighters and squadrons (military.toml)
  if cmd.buildType == BuildType.Ship and cmd.shipClass.isSome:
    let shipClass = cmd.shipClass.get()

    # Check fighter capacity (if building fighters)
    if shipClass == ShipClass.Fighter:
      if houseId in state.houses:
        if canCommissionFighter(state, colony) == false:
          ctx.rejectedCommands += 1
          return
            ValidationResult(valid: false, error: &"Fighter capacity limit exceeded")

    # Check capital squadron limit (if building capital ships)
    # Fighters are exempt from squadron limits (separate per-colony limits)
    if shipClass != ShipClass.Fighter:
      # First check capital squadron limit (subset of total limit)
      if capital_squadrons.isCapitalShip(shipClass):
        if not capital_squadrons.canBuildCapitalShip(state, houseId):
          let violation = capital_squadrons.analyzeCapacity(state, houseId)
          let underConstruction =
            capital_squadrons.countCapitalSquadronsUnderConstruction(state, houseId)

          ctx.rejectedCommands += 1
          logWarn(
            LogCategory.lcEconomy,
            &"{houseId} Build command REJECTED: Capital squadron limit exceeded " &
              &"(current={violation.current}, queued={underConstruction}, max={violation.maximum})",
          )
          return ValidationResult(
            valid: false,
            error:
              &"Capital squadron limit exceeded ({violation.current}+{underConstruction}/{violation.maximum})",
          )

      # Then check total squadron limit (all combat ships)
      # This prevents escort spam while allowing flexible fleet composition
      if not total_squadrons.canBuildSquadron(state, houseId, shipClass):
        let violation = total_squadrons.analyzeCapacity(state, houseId)
        let underConstruction =
          total_squadrons.countTotalSquadronsUnderConstruction(state, houseId)

        ctx.rejectedCommands += 1
        logWarn(
          LogCategory.lcEconomy,
          &"{houseId} Build command REJECTED: Total squadron limit exceeded " &
            &"(commissioned={violation.current}, queued={underConstruction}, " &
            &"max={violation.maximum}, ship={shipClass}). " &
            &"Increase Industrial Units to expand capacity.",
        )
        return ValidationResult(
          valid: false,
          error:
            &"Total squadron limit exceeded " &
            &"({violation.current}+{underConstruction}/{violation.maximum}). " &
            &"Requires more Industrial Units.",
        )

    # Check planet-breaker limit (1 per colony owned, assets.md:2.4.8)
    if shipClass == ShipClass.PlanetBreaker:
      let currentPBs = state.houses[houseId].planetBreakerCount
      let maxPBs = state_helpers.getPlanetBreakerLimit(state, houseId)

      # Count planet-breakers under construction house-wide
      var pbsUnderConstruction = 0
      for colId in state.colonies.byOwner.getOrDefault(houseId, @[]):
        let col = state.colony(colId).get
        # Count PlanetBreaker projects in queue
        for projId in col.constructionQueue:
          let proj = state.constructionProject(projId).get
          if proj.projectType == BuildType.Ship and proj.itemId == "PlanetBreaker":
            pbsUnderConstruction += 1

      if currentPBs + pbsUnderConstruction + 1 > maxPBs:
        ctx.rejectedCommands += 1
        logWarn(
          LogCategory.lcEconomy,
          &"{houseId} Build command REJECTED: Planet-breaker limit exceeded " &
            &"(current={currentPBs}, queued={pbsUnderConstruction}, max={maxPBs} [1 per colony])",
        )
        return ValidationResult(
          valid: false,
          error:
            &"Planet-breaker limit exceeded ({currentPBs}+{pbsUnderConstruction}/{maxPBs}, limited to 1 per colony)",
        )

  # Calculate cost
  let cost = calculateBuildCommandCost(cmd, state)
  if cost <= 0:
    return ValidationResult(
      valid: false, error: &"Build command: Invalid cost calculation ({cost} PP)"
    )

  # Check budget
  let remaining = ctx.getRemainingBudget()
  if cost > remaining:
    ctx.rejectedCommands += 1
    logInfo(
      LogCategory.lcEconomy,
      &"Build command rejected: need {cost} PP, have {remaining} PP remaining " &
        &"(treasury={ctx.availableTreasury}, committed={ctx.committedSpending})",
    )
    return ValidationResult(
      valid: false,
      error: &"Insufficient funds: need {cost} PP, have {remaining} PP remaining",
    )

  # Valid - commit spending
  ctx.committedSpending += cost
  logDebug(
    LogCategory.lcEconomy,
    &"Build command validated: {cost} PP committed, {ctx.getRemainingBudget()} PP remaining",
  )

  return ValidationResult(valid: true, error: "")

proc previewCommandPacketCost*(
    packet: CommandPacket, state: GameState
): CommandCostSummary =
  ## Calculate total costs for a command packet without committing
  ## Useful for UI preview before submission
  result = CommandCostSummary(
    buildCosts: 0,
    researchCosts: 0,
    espionageCosts: 0,
    totalCost: 0,
    canAfford: false,
    errors: @[],
    warnings: @[],
  )

  # Calculate build costs
  for cmd in packet.buildCommands:
    let cost = calculateBuildCommandCost(cmd, state)
    if cost > 0:
      result.buildCosts += cost
    else:
      result.warnings.add(&"Build command at {cmd.colonyId}: cost calculation failed")

  # Calculate research costs
  result.researchCosts =
    packet.researchAllocation.economic + packet.researchAllocation.science
  for field, amount in packet.researchAllocation.technology:
    result.researchCosts += amount

  # Calculate espionage costs (40 PP per EBP/CIP)
  result.espionageCosts = (packet.ebpInvestment + packet.cipInvestment) * 40

  # Total
  result.totalCost = result.buildCosts + result.researchCosts + result.espionageCosts

  # Check affordability
  if packet.houseId in state.houses:
    let house = state.houses[packet.houseId]
    result.canAfford = house.treasury >= result.totalCost

    if not result.canAfford:
      result.errors.add(
        &"Insufficient funds: need {result.totalCost} PP, have {house.treasury} PP"
      )

    # Warnings for spending >90% of treasury
    if result.totalCost > (house.treasury * 9 div 10):
      result.warnings.add(
        &"Warning: Spending {result.totalCost}/{house.treasury} PP (>90% of treasury)"
      )
  else:
    result.errors.add(&"House {packet.houseId} not found")

  logInfo(
    "Economy",
    &"{packet.houseId} Command Cost Preview: Build={result.buildCosts}PP, " &
      &"Research={result.researchCosts}PP, Espionage={result.espionageCosts}PP, " &
      &"Total={result.totalCost}PP, CanAfford={result.canAfford}",
  )
