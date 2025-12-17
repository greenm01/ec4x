## Comprehensive Fleet Organization for RBA AI
##
## Uses zero-turn commands to manage fleets at friendly colonies:
## - Detach ETACs from mixed fleets (pure colonization role)
## - Assign unassigned squadrons to existing/new fleets
## - Load appropriate cargo (marines, colonists)
## - Merge undersized fleets
##
## All operations require fleet to be at friendly colony (zero-turn constraint)

import std/[tables, options, strformat, sequtils]
import ../../common/types/core
import ../../engine/[gamestate, fleet, squadron, orders, fog_of_war, logger]
import ../../engine/commands/zero_turn_commands
import ./controller

proc detachETACsIfMixed(
  controller: AIController,
  filtered: FilteredGameState,
  fleet: Fleet,
  colony: Colony
): seq[ZeroTurnCommand] =
  ## Priority 1: Detach ETACs from mixed fleets
  ## User requirement: "AI should not keep ETAC in fleet with any other purpose"
  ##
  ## Mixed fleet = combat squadrons + ETACs
  ## Solution: Detach ETACs with 1 escort → new colonization fleet

  result = @[]

  # Check for ETACs
  var etacCount = 0
  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Expansion:
      if squadron.flagship.shipClass == ShipClass.ETAC:
        etacCount += 1

  if etacCount == 0:
    return  # No ETACs

  # Check combat squadrons (count non-Expansion squadrons)
  let combatCount = fleet.squadrons.len - etacCount

  if combatCount == 0:
    return  # Pure ETAC fleet, already optimized

  # CRITICAL FIX: Don't detach ETACs from fleets with active orders OR standing orders
  # Bug: Detaching ETACs causes fleet ID to change, invalidating orders
  # Standing orders activate AFTER zero-turn commands, so check both:
  #   1. Active orders (from previous turns, state.fleetOrders)
  #   2. Standing orders (not yet activated, state.standingOrders)
  if fleet.id in filtered.ownFleetOrders:
    let order = filtered.ownFleetOrders[fleet.id]
    logDebug(LogCategory.lcAI,
      &"Skipping ETAC detachment for {fleet.id} (active {order.orderType} order)")
    return  # Don't disrupt active mission

  # ALSO check for standing orders (AutoRepair, PatrolRoute, etc.)
  # Standing orders will activate in Maintenance Phase AFTER this runs
  if fleet.id in controller.standingOrders:
    let standingOrder = controller.standingOrders[fleet.id]
    if standingOrder.enabled and not standingOrder.suspended:
      logDebug(LogCategory.lcAI,
        &"Skipping ETAC detachment for {fleet.id} (has {standingOrder.orderType} standing order)")
      return  # Don't disrupt standing order that will activate later

  # MIXED FLEET - needs detachment

  if combatCount == 1:
    # Only 1 squadron - keep as escort for ETACs
    # Don't detach (would leave parent fleet empty)
    logDebug(LogCategory.lcAI,
      &"Fleet {fleet.id} has {etacCount} ETACs + 1 escort (optimal, no detachment needed)")
    return

  # Detach: 1 escort squadron + ONLY ETACs → new colonization fleet
  # Leave remaining combat squadrons + TroopTransports for tactical/invasion use

  var shipIndices: seq[int] = @[]

  # Add first combat squadron as escort
  var addedEscort = false
  for i, squadron in fleet.squadrons:
    if not addedEscort and squadron.squadronType != SquadronType.Expansion:
      shipIndices.add(i)
      addedEscort = true
      break

  # Add ONLY ETAC squadrons (Auxiliary/TroopTransports stay with combat fleet)
  for i, squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Expansion:
      if squadron.flagship.shipClass == ShipClass.ETAC:
        shipIndices.add(i)

  let newFleetId = controller.houseId & "_etac_" & $colony.systemId & "_" &
                   $filtered.turn

  result.add(ZeroTurnCommand(
    houseId: controller.houseId,
    commandType: ZeroTurnCommandType.DetachShips,
    sourceFleetId: some(fleet.id),
    shipIndices: shipIndices,
    newFleetId: some(newFleetId)
  ))

  # Count TroopTransports staying with combat fleet
  var troopTransportCount = 0
  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Auxiliary:
      if squadron.flagship.shipClass == ShipClass.TroopTransport:
        troopTransportCount += 1

  logInfo(LogCategory.lcAI,
    &"Detaching {etacCount} ETACs + 1 escort from {fleet.id} at {colony.systemId} " &
    &"(leaving {combatCount-1} combat squadrons + {troopTransportCount} transports)")

proc assignUnassignedSquadrons(
  controller: AIController,
  filtered: FilteredGameState,
  colony: Colony,
  fleetsHere: seq[Fleet]
): seq[ZeroTurnCommand] =
  ## Priority 2: Assign unassigned squadrons from colony pool to fleets
  ##
  ## Strategy:
  ## - Reinforce existing fleets (< 3 squadrons)
  ## - Create new fleets (groups of 2-3 squadrons)
  ## - Avoid 1-squadron fleets (assign to smallest existing fleet)

  result = @[]

  if colony.unassignedSquadrons.len == 0:
    return

  # Find fleets that need reinforcement (< 3 squadrons, active status)
  var needsReinforcement: seq[Fleet] = @[]
  for fleet in fleetsHere:
    if fleet.squadrons.len < 3 and fleet.status == FleetStatus.Active:
      needsReinforcement.add(fleet)

  # Assign squadrons to existing fleets first
  var remainingSquadrons = colony.unassignedSquadrons
  var assignedCount = 0

  for fleet in needsReinforcement:
    if remainingSquadrons.len == 0:
      break

    # Assign up to 2 squadrons to bring fleet to 3
    let needed = min(3 - fleet.squadrons.len, remainingSquadrons.len)

    for i in 0 ..< needed:
      let squadron = remainingSquadrons[0]
      result.add(ZeroTurnCommand(
        houseId: controller.houseId,
        commandType: ZeroTurnCommandType.AssignSquadronToFleet,
        colonySystem: some(colony.systemId),
        squadronId: some(squadron.id),
        targetFleetId: some(fleet.id)
      ))
      remainingSquadrons.delete(0)
      assignedCount += 1

  logDebug(LogCategory.lcAI,
    &"Assigned {assignedCount} squadrons to reinforce existing fleets at {colony.systemId}")

  # Create new fleets with remaining squadrons (groups of 2-3)
  var fleetNumber = 0

  while remainingSquadrons.len >= 2:
    let groupSize = min(3, remainingSquadrons.len)
    let newFleetId = controller.houseId & "_fleet_" & $colony.systemId &
                     "_t" & $filtered.turn & "_" & $fleetNumber

    # Assign first squadron to create new fleet
    result.add(ZeroTurnCommand(
      houseId: controller.houseId,
      commandType: ZeroTurnCommandType.AssignSquadronToFleet,
      colonySystem: some(colony.systemId),
      squadronId: some(remainingSquadrons[0].id),
      targetFleetId: none(FleetId),
      newFleetId: some(newFleetId)
    ))
    remainingSquadrons.delete(0)

    # Assign remaining squadrons to new fleet
    for i in 1 ..< groupSize:
      result.add(ZeroTurnCommand(
        houseId: controller.houseId,
        commandType: ZeroTurnCommandType.AssignSquadronToFleet,
        colonySystem: some(colony.systemId),
        squadronId: some(remainingSquadrons[0].id),
        targetFleetId: some(newFleetId)
      ))
      remainingSquadrons.delete(0)

    fleetNumber += 1

    logInfo(LogCategory.lcAI,
      &"Created new fleet {newFleetId} with {groupSize} squadrons at {colony.systemId}")

  # If 1 squadron remains, assign to smallest existing fleet
  if remainingSquadrons.len == 1:
    var smallestFleet: Option[FleetId] = none(FleetId)
    var smallestSize = 999

    for fleet in fleetsHere:
      if fleet.squadrons.len < smallestSize and fleet.status == FleetStatus.Active:
        smallestSize = fleet.squadrons.len
        smallestFleet = some(fleet.id)

    if smallestFleet.isSome:
      result.add(ZeroTurnCommand(
        houseId: controller.houseId,
        commandType: ZeroTurnCommandType.AssignSquadronToFleet,
        colonySystem: some(colony.systemId),
        squadronId: some(remainingSquadrons[0].id),
        targetFleetId: smallestFleet
      ))
      logDebug(LogCategory.lcAI,
        &"Assigned remaining squadron to smallest fleet {smallestFleet.get()}")

proc loadAppropriateCargo(
  controller: AIController,
  filtered: FilteredGameState,
  colony: Colony,
  fleet: Fleet
): seq[ZeroTurnCommand] =
  ## Priority 3: Load cargo based on fleet composition
  ##
  ## - ETAC fleets: Load colonists if available
  ## - TroopTransport fleets: Load marines if available and empty
  ## - Don't overload - check cargo capacity

  result = @[]

  # Check for empty ETACs
  var hasEmptyETAC = false
  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Expansion:
      if squadron.flagship.shipClass == ShipClass.ETAC:
        if squadron.flagship.cargo.isNone or squadron.flagship.cargo.get().quantity == 0:
          hasEmptyETAC = true
          break

  if hasEmptyETAC and colony.population > 1:
    # Load colonists (leave 1 PU minimum at colony)
    result.add(ZeroTurnCommand(
      houseId: controller.houseId,
      commandType: ZeroTurnCommandType.LoadCargo,
      sourceFleetId: some(fleet.id),
      cargoType: some(CargoType.Colonists),
      cargoQuantity: none(int)  # Load all available
    ))
    logInfo(LogCategory.lcAI,
      &"Loading colonists onto ETAC fleet {fleet.id} at {colony.systemId}")

  # Check for empty TroopTransports
  var hasEmptyTransport = false
  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Auxiliary:
      if squadron.flagship.shipClass == ShipClass.TroopTransport:
        if squadron.flagship.cargo.isNone or squadron.flagship.cargo.get().quantity == 0:
          hasEmptyTransport = true
          break

  if hasEmptyTransport and colony.marines >= 3:
    # Load marines (need minimum for defense)
    result.add(ZeroTurnCommand(
      houseId: controller.houseId,
      commandType: ZeroTurnCommandType.LoadCargo,
      sourceFleetId: some(fleet.id),
      cargoType: some(CargoType.Marines),
      cargoQuantity: none(int)  # Load all available
    ))
    logInfo(LogCategory.lcAI,
      &"Loading marines onto invasion fleet {fleet.id} at {colony.systemId}")

proc mergeUndersizedFleets(
  controller: AIController,
  filtered: FilteredGameState,
  colony: Colony,
  fleetsHere: seq[Fleet]
): seq[ZeroTurnCommand] =
  ## Priority 4: Merge undersized fleets (1 squadron each) into larger units
  ## Prevents fleet fragmentation

  result = @[]

  var singleSquadronFleets: seq[Fleet] = @[]
  for fleet in fleetsHere:
    # Count non-Expansion squadrons (combat squadrons)
    var combatSquadrons = 0
    var hasExpansionSquadrons = false
    for squadron in fleet.squadrons:
      if squadron.squadronType == SquadronType.Expansion:
        hasExpansionSquadrons = true
      else:
        combatSquadrons += 1

    # Merge only fleets with exactly 1 combat squadron and no expansion squadrons
    if combatSquadrons == 1 and not hasExpansionSquadrons and
       fleet.status == FleetStatus.Active:
      singleSquadronFleets.add(fleet)

  # Merge pairs of 1-squadron fleets
  var i = 0
  while i + 1 < singleSquadronFleets.len:
    let sourceFleet = singleSquadronFleets[i]
    let targetFleet = singleSquadronFleets[i + 1]

    result.add(ZeroTurnCommand(
      houseId: controller.houseId,
      commandType: ZeroTurnCommandType.MergeFleets,
      sourceFleetId: some(sourceFleet.id),
      targetFleetId: some(targetFleet.id)
    ))

    logInfo(LogCategory.lcAI,
      &"Merging undersized fleets {sourceFleet.id} → {targetFleet.id} at {colony.systemId}")
    i += 2

proc organizeColonyFleets(
  controller: AIController,
  filtered: FilteredGameState,
  colony: Colony,
  fleetsHere: seq[Fleet]
): seq[ZeroTurnCommand] =
  ## Organize all fleets at a single colony
  ## Executes all 4 priorities in sequence

  result = @[]

  # Priority 1: Detach ETACs from mixed fleets
  for fleet in fleetsHere:
    let etacCommands = detachETACsIfMixed(controller, filtered, fleet, colony)
    result.add(etacCommands)

  # Priority 2: Assign new squadrons from colony pool
  if colony.unassignedSquadrons.len > 0:
    let assignCommands = assignUnassignedSquadrons(
      controller,
      filtered,
      colony,
      fleetsHere
    )
    result.add(assignCommands)

  # Priority 3: Load cargo (marines for invasion, colonists for ETACs)
  for fleet in fleetsHere:
    let cargoCommands = loadAppropriateCargo(controller, filtered, colony, fleet)
    result.add(cargoCommands)

  # Priority 4: Merge undersized fleets
  let mergeCommands = mergeUndersizedFleets(controller, filtered, colony, fleetsHere)
  result.add(mergeCommands)

proc organizeFleets*(
  controller: AIController,
  filtered: FilteredGameState
): seq[ZeroTurnCommand] =
  ## Comprehensive fleet organization using zero-turn commands
  ##
  ## Philosophy: Fleets at colonies should be optimized for their mission:
  ## - ETAC fleets: Pure colonization (1 escort + ETACs only)
  ## - Combat fleets: Pure combat (no transport squadrons)
  ## - Invasion fleets: Combat + TroopTransports with marines
  ## - Scout fleets: Pure scouts for espionage
  ##
  ## Only processes fleets AT FRIENDLY COLONIES (zero-turn requirement)

  result = @[]

  for colony in filtered.ownColonies:
    # Step 1: Identify fleets at this colony
    var fleetsHere: seq[Fleet] = @[]
    for fleet in filtered.ownFleets:
      if fleet.location == colony.systemId:
        fleetsHere.add(fleet)

    if fleetsHere.len == 0:
      continue

    # Step 2: Organize fleets by type and needs
    let orgCommands = organizeColonyFleets(
      controller,
      filtered,
      colony,
      fleetsHere
    )
    result.add(orgCommands)

  if result.len > 0:
    logInfo(LogCategory.lcAI,
      &"{controller.houseId}: Generated {result.len} fleet organization commands")
