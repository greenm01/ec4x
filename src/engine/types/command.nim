## Fleet order types and validation for EC4X

import std/[options, tables, strformat, sequtils]
import ../common/types/[core, units]
import ./gamestate, ./fleet, ./starmap, ./logger
import ./types/colony
import ./types/orders as order_types  # Import and re-export fleet order types
import ./types/espionage as esp_types
import ./types/research as res_types
import ./systems/economy/projects  # For cost calculation
import ./systems/economy/config_accessors  # For CST requirement checking
import ./systems/economy/capacity/fighter # For colony fighter squadron limits
import ./systems/economy/capacity/capital_squadrons  # For capital squadron capacity enforcement
import ./systems/economy/capacity/total_squadrons  # For total squadron capacity (prevents escort spam)
import ./types/economy as econ_types  # For FacilityType in cost calculation

# Re-export order types
export order_types.FleetCommandType, order_types.FleetCommand

type
  TerraformCommand* = object
    ## Terraform a planet to the next class
    ## Per economy.md Section 4.7
    colonySystem*: SystemId
    startTurn*: int           # Turn when terraforming started
    turnsRemaining*: int      # Turns until completion (based on TER level)
    ppCost*: int              # Total PP cost for upgrade
    targetClass*: int         # Target planet class (current + 1)

  CommandPacket* = object
    houseId*: HouseId
    turn*: int
    treasury*: int                                           # Treasury at order generation time (for budget validation)
    fleetCommands*: seq[FleetCommand]
    buildCommands*: seq[BuildCommand]
    researchAllocation*: res_types.ResearchAllocation  # PP allocation to ERP/SRP/TRP
    diplomaticActions*: seq[DiplomaticAction]
    populationTransfers*: seq[PopulationTransferCommand]  # Space Guild transfers
    terraformCommands*: seq[TerraformCommand]                # Terraforming projects
    colonyManagement*: seq[ColonyManagementCommand]        # Colony-level management (tax rates, auto-repair, etc.)
    standingCommands*: Table[FleetId, StandingCommand]       # Persistent fleet behaviors (AutoColonize, DefendSystem, etc.)

    # Espionage budget allocation (diplomacy.md:8.2)
    espionageAction*: Option[esp_types.EspionageAttempt]  # Max 1 per turn
    ebpInvestment*: int      # EBP points to purchase (40 PP each)
    cipInvestment*: int      # CIP points to purchase (40 PP each)

  BuildCommand* = object
    colonySystem*: SystemId
    buildType*: BuildType
    quantity*: int
    shipClass*: Option[ShipClass]      # For Ship type
    buildingType*: Option[string]      # For Building type
    industrialUnits*: int              # For Infrastructure type

  BuildType* {.pure.} = enum
    Ship, Building, Infrastructure

  DiplomaticAction* = object
    targetHouse*: HouseId
    actionType*: DiplomaticActionType
    proposalId*: Option[string]  # For accept/reject/withdraw actions
    message*: Option[string]     # Optional diplomatic message

  DiplomaticActionType* {.pure.} = enum
    ## Diplomatic actions per diplomacy.md:8.1
    ## 3-level diplomatic system: Neutral, Hostile, Enemy
    DeclareHostile,            # Escalate to Hostile (deep space combat)
    DeclareEnemy,              # Escalate to Enemy (open war, planetary attacks)
    SetNeutral                 # De-escalate to Neutral (peace)

  PopulationTransferCommand* = object
    ## Space Guild population transfer between colonies
    ## Source: economy.md:3.7, config/population.toml
    sourceColony*: SystemId
    destColony*: SystemId
    ptuAmount*: int

  ValidationResult* = object
    valid*: bool
    error*: string

  CommandValidationContext* = object
    ## Budget tracking context for validating orders
    ## Prevents overspending by tracking running total of committed costs
    availableTreasury*: int      # Total treasury available at order submission
    committedSpending*: int      # Running total of validated order costs
    rejectedCommands*: int         # Count of orders rejected due to budget

  CommandCostSummary* = object
    ## Summary of order costs for preview/validation
    buildCosts*: int
    researchCosts*: int
    espionageCosts*: int
    totalCost*: int
    canAfford*: bool
    errors*: seq[string]
    warnings*: seq[string]

proc validateCommandPacket*(packet: CommandPacket, state: GameState): ValidationResult =
  ## Validate entire order packet for a house
  ## Performs comprehensive validation including:
  ## - Fleet ownership (prevents controlling enemy fleets)
  ## - Target validity (systems exist, paths exist)
  ## - Colony ownership (prevents building at enemy colonies)
  ## Creates GameEvents for rejected orders
  result = ValidationResult(valid: true, error: "")

  # Check house exists
  if packet.houseId notin state.houses:
    logWarn(LogCategory.lcCommands,
            &"Command packet REJECTED: {packet.houseId} does not exist")
    return ValidationResult(valid: false, error: "House does not exist")

  # Check turn number matches
  if packet.turn != state.turn:
    logWarn(LogCategory.lcCommands,
            &"{packet.houseId} Command packet REJECTED: wrong turn " &
            &"(packet={packet.turn}, current={state.turn})")
    return ValidationResult(valid: false, error: "Command packet for wrong turn")

  logInfo(LogCategory.lcCommands,
          &"{packet.houseId} Validating order packet: {packet.fleetCommands.len} fleet orders, " &
          &"{packet.buildCommands.len} build orders")

  # Validate each fleet order with ownership check
  var validFleetCommands = 0
  for order in packet.fleetCommands:
    let orderResult = validateFleetCommand(order, state, packet.houseId)
    if not orderResult.valid:
      return orderResult
    validFleetCommands += 1

  if packet.fleetCommands.len > 0:
    logInfo(LogCategory.lcCommands,
            &"{packet.houseId} Fleet orders: {validFleetCommands}/{packet.fleetCommands.len} valid")

  # Validate build orders (check colony ownership, production capacity)
  var validBuildCommands = 0
  for order in packet.buildCommands:
    # Check colony exists and is owned by house
    if order.colonySystem notin state.colonies:
      logWarn(LogCategory.lcCommands,
              &"{packet.houseId} Build order REJECTED: colony at {order.colonySystem} " &
              &"does not exist")
      return ValidationResult(valid: false, error: "Build order: Colony does not exist at system " & $order.colonySystem)

    let colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      logWarn(LogCategory.lcCommands,
              &"SECURITY VIOLATION: {packet.houseId} attempted to build at {order.colonySystem} " &
              &"(owned by {colony.owner})")
      return ValidationResult(valid: false, error: "Build order: House does not own colony at system " & $order.colonySystem)

    # Check CST tech requirement for ships (economy.md:4.5)
    if order.buildType == BuildType.Ship and order.shipClass.isSome:
      let shipClass = order.shipClass.get()
      let required_cst = getShipCSTRequirement(shipClass)

      # Get house's CST level
      if packet.houseId in state.houses:
        let house = state.houses[packet.houseId]
        let house_cst = house.techTree.levels.constructionTech

        if house_cst < required_cst:
          logWarn(LogCategory.lcCommands,
                  &"{packet.houseId} Build order REJECTED: {shipClass} requires CST{required_cst}, " &
                  &"house has CST{house_cst}")
          return ValidationResult(valid: false,
                                 error: &"Build order: {shipClass} requires CST{required_cst}, house has CST{house_cst}")

    # Check CST tech requirement and prerequisites for buildings (assets.md:2.4.4)
    if order.buildType == BuildType.Building and order.buildingType.isSome:
      let buildingType = order.buildingType.get()

      # Check CST requirement (e.g., Starbase requires CST3)
      let required_cst = getBuildingCSTRequirement(buildingType)
      if required_cst > 0 and packet.houseId in state.houses:
        let house = state.houses[packet.houseId]
        let house_cst = house.techTree.levels.constructionTech

        if house_cst < required_cst:
          logWarn(LogCategory.lcCommands,
                  &"{packet.houseId} Build order REJECTED: {buildingType} requires CST{required_cst}, " &
                  &"house has CST{house_cst}")
          return ValidationResult(valid: false,
                                 error: &"Build order: {buildingType} requires CST{required_cst}, house has CST{house_cst}")

      # Check shipyard prerequisite (e.g., Starbase requires shipyard)
      if requiresShipyard(buildingType):
        if not hasOperationalShipyard(colony):
          logWarn(LogCategory.lcCommands,
                  &"{packet.houseId} Build order REJECTED: {buildingType} requires operational shipyard at {order.colonySystem}")
          return ValidationResult(valid: false,
                                 error: &"Build order: {buildingType} requires operational shipyard")

    # NOTE: Multiple build orders per colony per turn are supported (queue system)
    # Dock capacity is validated during resolution (economy_resolution.nim:102-108)
    # Commands beyond capacity remain queued for future turns
    # This allows unlimited PP spending per turn (limited by treasury + dock capacity)

    validBuildCommands += 1
    logDebug(LogCategory.lcCommands,
             &"{packet.houseId} Build order VALID: {order.buildType} at {order.colonySystem}")

  if packet.buildCommands.len > 0:
    logInfo(LogCategory.lcCommands,
            &"{packet.houseId} Build orders: {validBuildCommands}/{packet.buildCommands.len} valid")

  # Validate research allocation (check total points available)
  # Note: Actual PP availability check happens during resolution (after income phase)
  # Here we just validate structure - allocation can't be negative
  if packet.researchAllocation.economic < 0 or packet.researchAllocation.science < 0:
    return ValidationResult(valid: false, error: "Research allocation: Cannot allocate negative PP")

  # Validate technology allocations (per-field)
  for field, amount in packet.researchAllocation.technology:
    if amount < 0:
      return ValidationResult(valid: false, error: "Research allocation: Cannot allocate negative PP to " & $field)

  # Validate diplomatic actions (check diplomatic state and constraints)
  for action in packet.diplomaticActions:
    # Check target house exists
    if action.targetHouse notin state.houses:
      return ValidationResult(valid: false, error: "Diplomatic action: Target house does not exist")

    # Can't take diplomatic actions against eliminated houses
    if state.houses[action.targetHouse].eliminated:
      return ValidationResult(valid: false, error: "Diplomatic action: Target house is eliminated")

    # Can't target self
    if action.targetHouse == packet.houseId:
      return ValidationResult(valid: false, error: "Diplomatic action: Cannot target own house")

  # Validate colony management orders
  for order in packet.colonyManagement:
    # Check colony exists
    if order.colonyId notin state.colonies:
      return ValidationResult(valid: false, error: "Colony management: Colony does not exist at " & $order.colonyId)

    # Check ownership
    let colony = state.colonies[order.colonyId]
    if colony.owner != packet.houseId:
      return ValidationResult(valid: false, error: "Colony management: House does not own colony at " & $order.colonyId)

    # Validate action-specific parameters
    case order.action
    of ColonyManagementAction.SetTaxRate:
      if order.taxRate < 0 or order.taxRate > 100:
        return ValidationResult(valid: false, error: "Colony management: Tax rate must be 0-100")
    of ColonyManagementAction.SetAutoRepair:
      # Boolean flag, no validation needed
      discard

  # All validations passed
  logInfo(LogCategory.lcCommands,
          &"{packet.houseId} Command packet VALIDATED: All orders valid and authorized")
  result = ValidationResult(valid: true, error: "")

# Command packet creation

proc newCommandPacket*(houseId: HouseId, turn: int, treasury: int = 0): CommandPacket =
  ## Create empty order packet for a house
  ## treasury: Treasury at order generation time (defaults to 0 for test harnesses)
  result = CommandPacket(
    houseId: houseId,
    turn: turn,
    treasury: treasury,
    fleetCommands: @[],
    buildCommands: @[],
    researchAllocation: res_types.initResearchAllocation(),
    diplomaticActions: @[]
  )

proc addFleetCommand*(packet: var CommandPacket, order: FleetCommand) =
  ## Add a fleet order to packet
  packet.fleetCommands.add(order)

proc addBuildCommand*(packet: var CommandPacket, order: BuildCommand) =
  ## Add a build order to packet
  packet.buildCommands.add(order)

# Budget tracking and validation

proc initCommandValidationContext*(treasury: int): CommandValidationContext =
  ## Create new validation context for order packet
  result = CommandValidationContext(
    availableTreasury: treasury,
    committedSpending: 0,
    rejectedCommands: 0
  )

proc getRemainingBudget*(ctx: CommandValidationContext): int =
  ## Get remaining budget after committed spending
  result = ctx.availableTreasury - ctx.committedSpending

proc calculateBuildCommandCost*(order: BuildCommand, state: GameState, assignedFacilityType: Option[econ_types.FacilityType] = none(econ_types.FacilityType)): int =
  ## Calculate the PP cost of a build order
  ## Returns 0 if cost cannot be determined
  ##
  ## IMPORTANT: Spaceport Commission Penalty (economy.md:5.1, 5.3)
  ## - Ships built at spaceports (planet-side) incur 100% PC increase (double cost)
  ## - Ships built at shipyards (orbital) have no penalty (standard cost)
  ## - Fighters are EXEMPT (distributed planetary manufacturing)
  ## - Shipyard/Starbase buildings are EXEMPT (orbital construction, no penalty)
  ##
  ## If assignedFacilityType is provided, use it to determine cost.
  ## Otherwise, fall back to legacy logic (check if colony has shipyard).
  result = 0

  case order.buildType
  of BuildType.Ship:
    if order.shipClass.isSome:
      let baseCost = projects.getShipConstructionCost(order.shipClass.get()) * order.quantity
      let shipClass = order.shipClass.get()

      # Apply spaceport commission penalty if building planet-side
      # Per economy.md:5.1 - "Ships (excluding fighter squadrons) constructed planet-side incur a 100% PC increase"
      # IMPORTANT: Fighters are EXEMPT from the penalty (planet-based manufacturing)
      if shipClass == ShipClass.Fighter:
        # Fighters never incur commission penalty (distributed planetary manufacturing)
        result = baseCost
      elif assignedFacilityType.isSome:
        # NEW: Per-facility cost calculation
        if assignedFacilityType.get() == econ_types.FacilityType.Spaceport:
          # Planet-side construction (spaceport) → 100% penalty (double cost)
          result = baseCost * 2
        else:
          # Orbital construction (shipyard) → no penalty
          result = baseCost
      elif order.colonySystem in state.colonies:
        # LEGACY: Fall back to colony-wide check (for backwards compatibility)
        let colony = state.colonies[order.colonySystem]
        let hasShipyard = colony.shipyards.len > 0
        let hasSpaceport = colony.spaceports.len > 0

        if not hasShipyard and hasSpaceport:
          # Planet-side construction (spaceport only) → 100% penalty (double cost)
          result = baseCost * 2
        else:
          # Orbital construction (shipyard present) → no penalty
          result = baseCost
      else:
        # Colony doesn't exist (validation will catch this)
        result = baseCost

  of BuildType.Building:
    if order.buildingType.isSome:
      # Buildings never have spaceport penalty (planet-side industry)
      # Shipyard/Starbase are built in orbit and don't get penalty
      result = projects.getBuildingCost(order.buildingType.get()) * order.quantity

  of BuildType.Infrastructure:
    # Infrastructure cost depends on colony state
    if order.colonySystem in state.colonies:
      let colony = state.colonies[order.colonySystem]
      result = projects.getIndustrialUnitCost(colony) * order.industrialUnits

proc validateBuildCommandWithBudget*(order: BuildCommand, state: GameState,
                                   houseId: HouseId,
                                   ctx: var CommandValidationContext): ValidationResult =
  ## Validate build order including budget check and tech requirements
  ## Updates context with committed spending if valid

  # Basic validation first
  if order.colonySystem notin state.colonies:
    return ValidationResult(valid: false,
                           error: &"Build order: Colony not found at system {order.colonySystem}")

  let colony = state.colonies[order.colonySystem]

  # Check CST tech requirement for ships (economy.md:4.5)
  if order.buildType == BuildType.Ship and order.shipClass.isSome:
    let shipClass = order.shipClass.get()
    let required_cst = getShipCSTRequirement(shipClass)

    # Get house's CST level
    if houseId in state.houses:
      let house = state.houses[houseId]
      let house_cst = house.techTree.levels.constructionTech

      if house_cst < required_cst:
        ctx.rejectedCommands += 1
        logWarn(LogCategory.lcEconomy,
                &"{houseId} Build order REJECTED: {shipClass} requires CST{required_cst}, " &
                &"house has CST{house_cst}")
        return ValidationResult(valid: false,
                               error: &"Build order: {shipClass} requires CST{required_cst}, house has CST{house_cst}")

  # Check CST tech requirement and prerequisites for buildings (assets.md:2.4.4)
  if order.buildType == BuildType.Building and order.buildingType.isSome:
    let buildingType = order.buildingType.get()

    # Check CST requirement (e.g., Starbase requires CST3)
    let required_cst = getBuildingCSTRequirement(buildingType)
    if required_cst > 0 and houseId in state.houses:
      let house = state.houses[houseId]
      let house_cst = house.techTree.levels.constructionTech

      if house_cst < required_cst:
        ctx.rejectedCommands += 1
        logWarn(LogCategory.lcEconomy,
                &"{houseId} Build order REJECTED: {buildingType} requires CST{required_cst}, " &
                &"house has CST{house_cst}")
        return ValidationResult(valid: false,
                               error: &"Build order: {buildingType} requires CST{required_cst}, house has CST{house_cst}")

    # Check shipyard prerequisite (e.g., Starbase requires shipyard)
    if requiresShipyard(buildingType):
      if not hasOperationalShipyard(colony):
        ctx.rejectedCommands += 1
        logWarn(LogCategory.lcEconomy,
                &"{houseId} Build order REJECTED: {buildingType} requires operational shipyard at {order.colonySystem}")
        return ValidationResult(valid: false,
                               error: &"Build order: {buildingType} requires operational shipyard")

  # Check capacity limits for fighters and squadrons (military.toml)
  if order.buildType == BuildType.Ship and order.shipClass.isSome:
    let shipClass = order.shipClass.get()

    # Check fighter capacity (if building fighters)
    if shipClass == ShipClass.Fighter:
      if houseId in state.houses:
        let house = state.houses[houseId]
        if canCommissionFighter(state, colony) == false:
          ctx.rejectedCommands += 1
          return ValidationResult(valid: false,
            error: &"Fighter capacity limit exceeded by {house.name}")

    # Check capital squadron limit (if building capital ships)
    # Fighters are exempt from squadron limits (separate per-colony limits)
    if shipClass != ShipClass.Fighter:
      # First check capital squadron limit (subset of total limit)
      if capital_squadrons.isCapitalShip(shipClass):
        if not capital_squadrons.canBuildCapitalShip(state, houseId):
          let violation = capital_squadrons.analyzeCapacity(state, houseId)
          let underConstruction = capital_squadrons.countCapitalSquadronsUnderConstruction(state, houseId)

          ctx.rejectedCommands += 1
          logWarn(LogCategory.lcEconomy,
                  &"{houseId} Build order REJECTED: Capital squadron limit exceeded " &
                  &"(current={violation.current}, queued={underConstruction}, max={violation.maximum})")
          return ValidationResult(valid: false,
                                 error: &"Capital squadron limit exceeded ({violation.current}+{underConstruction}/{violation.maximum})")

      # Then check total squadron limit (all combat ships)
      # This prevents escort spam while allowing flexible fleet composition
      if not total_squadrons.canBuildSquadron(state, houseId, shipClass):
        let violation = total_squadrons.analyzeCapacity(state, houseId)
        let underConstruction = total_squadrons.countTotalSquadronsUnderConstruction(state, houseId)

        ctx.rejectedCommands += 1
        logWarn(LogCategory.lcEconomy,
                &"{houseId} Build order REJECTED: Total squadron limit exceeded " &
                &"(commissioned={violation.current}, queued={underConstruction}, " &
                &"max={violation.maximum}, ship={shipClass}). " &
                &"Increase Industrial Units to expand capacity.")
        return ValidationResult(valid: false,
                               error: &"Total squadron limit exceeded " &
                                      &"({violation.current}+{underConstruction}/{violation.maximum}). " &
                                      &"Requires more Industrial Units.")

    # Check planet-breaker limit (1 per colony owned, assets.md:2.4.8)
    # TODO use new economy/capacity planet_breakers module
    if shipClass == ShipClass.PlanetBreaker:
      let currentPBs = state.houses[houseId].planetBreakerCount
      let maxPBs = state.getPlanetBreakerLimit(houseId)

      # Count planet-breakers under construction house-wide
      var pbsUnderConstruction = 0
      for colId, col in state.colonies:
        if col.owner == houseId:
          pbsUnderConstruction += col.constructionQueue.filterIt(
            it.projectType == ConstructionType.Ship and
            it.itemId == "PlanetBreaker"
          ).len

      if currentPBs + pbsUnderConstruction + 1 > maxPBs:
        ctx.rejectedCommands += 1
        logWarn(LogCategory.lcEconomy,
                &"{houseId} Build order REJECTED: Planet-breaker limit exceeded " &
                &"(current={currentPBs}, queued={pbsUnderConstruction}, max={maxPBs} [1 per colony])")
        return ValidationResult(valid: false,
                               error: &"Planet-breaker limit exceeded ({currentPBs}+{pbsUnderConstruction}/{maxPBs}, limited to 1 per colony)")

  # Calculate cost
  let cost = calculateBuildCommandCost(order, state)
  if cost <= 0:
    return ValidationResult(valid: false,
                           error: &"Build order: Invalid cost calculation ({cost} PP)")

  # Check budget
  let remaining = ctx.getRemainingBudget()
  if cost > remaining:
    ctx.rejectedCommands += 1
    logInfo(LogCategory.lcEconomy,
            &"Build order rejected: need {cost} PP, have {remaining} PP remaining " &
            &"(treasury={ctx.availableTreasury}, committed={ctx.committedSpending})")
    return ValidationResult(valid: false,
                           error: &"Insufficient funds: need {cost} PP, have {remaining} PP remaining")

  # Valid - commit spending
  ctx.committedSpending += cost
  logDebug(LogCategory.lcEconomy,
           &"Build order validated: {cost} PP committed, {ctx.getRemainingBudget()} PP remaining")

  return ValidationResult(valid: true, error: "")

proc previewCommandPacketCost*(packet: CommandPacket, state: GameState): CommandCostSummary =
  ## Calculate total costs for an order packet without committing
  ## Useful for UI preview before submission
  result = CommandCostSummary(
    buildCosts: 0,
    researchCosts: 0,
    espionageCosts: 0,
    totalCost: 0,
    canAfford: false,
    errors: @[],
    warnings: @[]
  )

  # Calculate build costs
  for order in packet.buildCommands:
    let cost = calculateBuildCommandCost(order, state)
    if cost > 0:
      result.buildCosts += cost
    else:
      result.warnings.add(&"Build order at {order.colonySystem}: cost calculation failed")

  # Calculate research costs
  result.researchCosts = packet.researchAllocation.economic +
                        packet.researchAllocation.science
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
      result.errors.add(&"Insufficient funds: need {result.totalCost} PP, have {house.treasury} PP")

    # Warnings for spending >90% of treasury
    if result.totalCost > (house.treasury * 9 div 10):
      result.warnings.add(&"Warning: Spending {result.totalCost}/{house.treasury} PP (>90% of treasury)")
  else:
    result.errors.add(&"House {packet.houseId} not found")

  logInfo(LogCategory.lcEconomy,
          &"{packet.houseId} Command Cost Preview: Build={result.buildCosts}PP, " &
          &"Research={result.researchCosts}PP, Espionage={result.espionageCosts}PP, " &
          &"Total={result.totalCost}PP, CanAfford={result.canAfford}")
