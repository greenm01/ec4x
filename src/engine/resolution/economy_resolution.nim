## Economy resolution - Income, construction, and maintenance operations
##
## This module handles all economy-related resolution including:
## - Income phase with resource collection and espionage effects
## - Build orders and construction management
## - Squadron management and fleet organization
## - Cargo management for spacelift ships
## - Population transfers via Space Guild
## - Terraforming operations
## - Maintenance phase with upkeep and effect tracking
##
## **Construction & Commissioning Phase Architecture**
##
## This module handles construction and commissioning because these operations
## represent the economic/industrial workflow of turning treasury resources
## into operational military units. The flow is:
##
## 1. **Build Phase** (`resolveBuildOrders`):
##    - Houses spend treasury on construction projects
##    - Progress tracks toward completion over multiple turns
##    - Represents shipyard/factory industrial capacity
##
## 2. **Commissioning Phase** (within construction completion):
##    - Completed ships are added to `colony.unassignedSquadrons`
##    - Represents the "delivery" of industrial output
##
## 3. **Fleet Organization Phase** (`autoBalanceSquadronsToFleets`):
##    - Unassigned squadrons are organized into operational fleets
##    - New fleets are created if no stationary fleets exist
##    - Only Active fleets are considered (excludes Reserve/Mothballed)
##    - Represents the transition from industrial output to military readiness
##
## This architecture keeps the economic turn resolution (treasury → ships → fleets)
## separate from tactical fleet operations (movement, combat, espionage) which are
## handled in fleet_orders.nim and combat_resolution.nim.
##
## The auto-fleet creation here enables newly-built units (especially scouts)
## to immediately begin operational duties without requiring explicit player orders.

import std/[tables, algorithm, options, random, sequtils, hashes, math, strutils, strformat]
import ../../common/[hex, types/core, types/combat, types/units, types/tech]
import ../gamestate, ../orders, ../fleet, ../squadron, ../ship, ../spacelift, ../starmap, ../logger
import ../economy/[types as econ_types, engine as econ_engine, construction, maintenance]
import ../research/[types as res_types, costs as res_costs, effects as res_effects, advancement]
import ../espionage/[types as esp_types, engine as esp_engine]
import ../diplomacy/[types as dip_types, proposals as dip_proposals]
import ../blockade/engine as blockade_engine
import ../intelligence/[detection, types as intel_types, generator as intel_gen, starbase_surveillance, scout_intel]
import ../population/[types as pop_types]
import ../config/[espionage_config, population_config, ground_units_config, construction_config, gameplay_config, military_config]
import ../colonization/engine as col_engine
import ./types  # Common resolution types
import ./fleet_orders  # For findClosestOwnedColony

# Forward declarations
proc autoBalanceSquadronsToFleets(state: var GameState, colony: var gamestate.Colony, systemId: SystemId, orders: Table[HouseId, OrderPacket])
proc autoLoadFightersToCarriers(state: var GameState, colony: var gamestate.Colony, systemId: SystemId, orders: Table[HouseId, OrderPacket])

proc resolveBuildOrders*(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process construction orders for a house with budget validation
  ## Prevents overspending by tracking committed costs
  echo "    Processing build orders for ", state.houses[packet.houseId].name

  # Initialize budget validation context
  # Use CURRENT treasury from state (NOT snapshot from OrderPacket)
  # This ensures validation matches the actual treasury after income/maintenance
  let house = state.houses[packet.houseId]
  var budgetContext = orders.initOrderValidationContext(house.treasury)

  logInfo(LogCategory.lcEconomy,
          &"{packet.houseId} Build Order Validation: {packet.buildOrders.len} orders, " &
          &"{house.treasury} PP available (current treasury after income/maintenance)")

  for order in packet.buildOrders:
    # Validate colony exists
    if order.colonySystem notin state.colonies:
      echo "      Build order failed: colony not found at system ", order.colonySystem
      continue

    # Validate colony ownership
    let colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      echo "      Build order failed: colony not owned by ", packet.houseId
      continue

    # Check if colony has dock capacity for more construction projects
    # NEW: Build queue system - colonies can have multiple projects up to dock capacity
    # EXCEPTION: Fighters are built planet-side and don't consume dock capacity (economy.md:3.10)
    let isFighter = (order.buildType == BuildType.Ship and
                     order.shipClass.isSome and
                     order.shipClass.get() == ShipClass.Fighter)

    if not isFighter and not colony.canAcceptMoreProjects():
      let capacity = colony.getConstructionDockCapacity()
      let active = colony.getActiveConstructionProjects()
      echo "      Build order failed: system ", order.colonySystem, " at capacity (", active, "/", capacity, " docks used)"
      continue

    # Validate budget BEFORE creating construction project
    let validationResult = orders.validateBuildOrderWithBudget(order, state, budgetContext)
    if not validationResult.valid:
      echo "      Build order failed: ", validationResult.error
      logInfo(LogCategory.lcEconomy,
              &"{packet.houseId} Build order rejected at {order.colonySystem}: {validationResult.error}")
      continue

    # NOTE: No conversion needed! gamestate.Colony now has all economic fields
    # (populationUnits, industrial, grossOutput, taxRate, infrastructureDamage)
    # Construction functions work directly with unified Colony type

    # Create construction project based on build type
    var project: econ_types.ConstructionProject
    var projectDesc: string

    case order.buildType
    of BuildType.Infrastructure:
      # Infrastructure investment (IU expansion)
      let units = order.industrialUnits
      if units <= 0:
        echo "      Infrastructure order failed: invalid unit count ", units
        continue

      project = construction.createIndustrialProject(colony, units)
      projectDesc = "Industrial expansion: " & $units & " IU"

    of BuildType.Ship:
      # Ship construction
      if order.shipClass.isNone:
        echo "      Ship construction failed: no ship class specified"
        continue

      let shipClass = order.shipClass.get()
      project = construction.createShipProject(shipClass)
      projectDesc = "Ship construction: " & $shipClass

    of BuildType.Building:
      # Building construction
      if order.buildingType.isNone:
        echo "      Building construction failed: no building type specified"
        continue

      let buildingType = order.buildingType.get()
      project = construction.createBuildingProject(buildingType)
      projectDesc = "Building construction: " & buildingType

    # Start construction (NOTE: startConstruction modifies colony in-place)
    var mutableColony = colony
    # Check if construction slot is already occupied
    let wasOccupied = mutableColony.underConstruction.isSome

    if construction.startConstruction(mutableColony, project):
      # Update game state with modified colony
      # Only add to queue if construction slot was already occupied
      # (if slot was empty, startConstruction already set it to underConstruction)
      if wasOccupied:
        mutableColony.constructionQueue.add(project)
      state.colonies[order.colonySystem] = mutableColony

      # CRITICAL FIX: Deduct construction cost from house treasury
      # IMPORTANT: Use get-modify-write pattern (Nim Table copy semantics!)
      var house = state.houses[packet.houseId]
      let oldTreasury = house.treasury
      house.treasury -= project.costTotal
      state.houses[packet.houseId] = house

      let queuePos = mutableColony.constructionQueue.len
      let capacity = mutableColony.getConstructionDockCapacity()
      echo "      Started construction at system ", order.colonySystem, ": ", projectDesc
      echo "        Cost: ", project.costTotal, " PP, Est. ", project.turnsRemaining, " turns (Queue: ", queuePos, "/", capacity, " docks)"
      echo "        Treasury: ", oldTreasury, " PP → ", house.treasury, " PP"

      # Generate event
      events.add(GameEvent(
        eventType: GameEventType.ConstructionStarted,
        houseId: packet.houseId,
        description: "Started " & projectDesc & " at system " & $order.colonySystem,
        systemId: some(order.colonySystem)
      ))
    else:
      echo "      Construction start failed at system ", order.colonySystem

  # Log budget validation summary
  let successfulOrders = packet.buildOrders.len - budgetContext.rejectedOrders
  logInfo(LogCategory.lcEconomy,
          &"{packet.houseId} Build Order Summary: {successfulOrders}/{packet.buildOrders.len} orders accepted, " &
          &"{budgetContext.committedSpending} PP committed, " &
          &"{budgetContext.getRemainingBudget()} PP remaining, " &
          &"{budgetContext.rejectedOrders} orders rejected due to insufficient funds")

proc resolveSquadronManagement*(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process squadron management orders: form squadrons, transfer ships, assign to fleets
  for order in packet.squadronManagement:
    # Validate colony exists and is owned by house
    if order.colonySystem notin state.colonies:
      echo "    Squadron management failed: System ", order.colonySystem, " has no colony"
      continue

    var colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      echo "    Squadron management failed: ", packet.houseId, " does not own system ", order.colonySystem
      continue

    case order.action
    of SquadronManagementAction.TransferShip:
      # Transfer ship between squadrons at this colony
      if order.sourceSquadronId.isNone or order.shipIndex.isNone:
        echo "    TransferShip failed: Missing source squadron or ship index"
        continue

      if order.targetSquadronId.isNone:
        echo "    TransferShip failed: Missing target squadron"
        continue

      # Find source and target squadrons in fleets at this colony
      var sourceFleet: Option[FleetId] = none(FleetId)
      var targetFleet: Option[FleetId] = none(FleetId)
      var sourceSquadIndex: int = -1
      var targetSquadIndex: int = -1

      # Locate source squadron
      for fleetId, fleet in state.fleets:
        if fleet.location == order.colonySystem and fleet.owner == packet.houseId:
          for i, squad in fleet.squadrons:
            if squad.id == order.sourceSquadronId.get():
              sourceFleet = some(fleetId)
              sourceSquadIndex = i
              break
          if sourceFleet.isSome:
            break

      if sourceFleet.isNone:
        echo "    TransferShip failed: Source squadron ", order.sourceSquadronId.get(), " not found"
        continue

      # Locate target squadron
      for fleetId, fleet in state.fleets:
        if fleet.location == order.colonySystem and fleet.owner == packet.houseId:
          for i, squad in fleet.squadrons:
            if squad.id == order.targetSquadronId.get():
              targetFleet = some(fleetId)
              targetSquadIndex = i
              break
          if targetFleet.isSome:
            break

      if targetFleet.isNone:
        echo "    TransferShip failed: Target squadron ", order.targetSquadronId.get(), " not found"
        continue

      # Remove ship from source squadron
      let shipIndex = order.shipIndex.get()
      var sourceSquad = state.fleets[sourceFleet.get()].squadrons[sourceSquadIndex]

      if shipIndex < 0 or shipIndex >= sourceSquad.ships.len:
        echo "    TransferShip failed: Invalid ship index ", shipIndex, " (squadron has ", sourceSquad.ships.len, " ships)"
        continue

      let shipOpt = sourceSquad.removeShip(shipIndex)
      if shipOpt.isNone:
        echo "    TransferShip failed: Could not remove ship from source squadron"
        continue

      let ship = shipOpt.get()

      # Add ship to target squadron
      var targetSquad = state.fleets[targetFleet.get()].squadrons[targetSquadIndex]

      if not targetSquad.addShip(ship):
        echo "    TransferShip failed: Could not add ship to target squadron (may be full or incompatible)"
        # Put ship back in source squadron
        discard sourceSquad.addShip(ship)
        state.fleets[sourceFleet.get()].squadrons[sourceSquadIndex] = sourceSquad
        continue

      # Update both squadrons in state
      state.fleets[sourceFleet.get()].squadrons[sourceSquadIndex] = sourceSquad
      state.fleets[targetFleet.get()].squadrons[targetSquadIndex] = targetSquad

      echo "    Transferred ship from ", order.sourceSquadronId.get(), " to ", order.targetSquadronId.get()

    of SquadronManagementAction.AssignToFleet:
      # Assign existing squadron to fleet (move between fleets or create new fleet)
      if order.squadronId.isNone:
        echo "    AssignToFleet failed: No squadron ID specified"
        continue

      # Find squadron in existing fleets at this colony
      var foundSquadron: Option[Squadron] = none(Squadron)
      var sourceFleetId: Option[FleetId] = none(FleetId)

      for fleetId, fleet in state.fleets:
        if fleet.location == order.colonySystem and fleet.owner == packet.houseId:
          for i, squad in fleet.squadrons:
            if squad.id == order.squadronId.get():
              foundSquadron = some(squad)
              sourceFleetId = some(fleetId)
              break
          if foundSquadron.isSome:
            break

      # If not found in fleets, check unassigned squadrons at colony
      if foundSquadron.isNone:
        for i, squad in colony.unassignedSquadrons:
          if squad.id == order.squadronId.get():
            foundSquadron = some(squad)
            # Remove from unassigned list
            var newUnassigned: seq[Squadron] = @[]
            for j, s in colony.unassignedSquadrons:
              if j != i:
                newUnassigned.add(s)
            colony.unassignedSquadrons = newUnassigned
            break

      if foundSquadron.isNone:
        echo "    AssignToFleet failed: Squadron ", order.squadronId.get(), " not found at system"
        continue

      let squadron = foundSquadron.get()

      # Remove squadron from source fleet
      if sourceFleetId.isSome:
        # CRITICAL: Get fleet, modify squadrons, write back to persist
        var srcFleet = state.fleets[sourceFleetId.get()]
        var newSquadrons: seq[Squadron] = @[]
        for squad in srcFleet.squadrons:
          if squad.id != order.squadronId.get():
            newSquadrons.add(squad)
        srcFleet.squadrons = newSquadrons
        state.fleets[sourceFleetId.get()] = srcFleet

        # If source fleet is now empty, remove it
        if newSquadrons.len == 0:
          state.fleets.del(sourceFleetId.get())
          echo "    Removed empty fleet ", sourceFleetId.get()

      # Add squadron to target fleet or create new one
      if order.targetFleetId.isSome:
        # Assign to existing fleet
        let targetId = order.targetFleetId.get()
        if targetId in state.fleets:
          state.fleets[targetId].squadrons.add(squadron)
          echo "    Assigned squadron ", squadron.id, " to fleet ", targetId
        else:
          echo "    AssignToFleet failed: Target fleet ", targetId, " does not exist"
      else:
        # Create new fleet
        let newFleetId = packet.houseId & "_fleet_" & $order.colonySystem & "_" & $state.turn
        state.fleets[newFleetId] = Fleet(
          id: newFleetId,
          owner: packet.houseId,
          location: order.colonySystem,
          squadrons: @[squadron]
        )
        echo "    Created new fleet ", newFleetId, " with squadron ", squadron.id

    # Update colony in state
    state.colonies[order.colonySystem] = colony

proc resolveCargoManagement*(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process manual cargo management orders (load/unload)
  for order in packet.cargoManagement:
    # Validate colony exists and is owned by house
    if order.colonySystem notin state.colonies:
      echo "    Cargo management failed: System ", order.colonySystem, " has no colony"
      continue

    let colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      echo "    Cargo management failed: ", packet.houseId, " does not own system ", order.colonySystem
      continue

    # Validate fleet exists and is at colony
    let fleetOpt = state.getFleet(order.fleetId)
    if fleetOpt.isNone:
      echo "    Cargo management failed: Fleet ", order.fleetId, " does not exist"
      continue

    let fleet = fleetOpt.get()
    if fleet.location != order.colonySystem:
      echo "    Cargo management failed: Fleet ", order.fleetId, " not at colony ", order.colonySystem
      continue

    case order.action
    of CargoManagementAction.LoadCargo:
      if order.cargoType.isNone:
        echo "    LoadCargo failed: No cargo type specified"
        continue

      let cargoType = order.cargoType.get()
      var requestedQty = if order.quantity.isSome: order.quantity.get() else: 0  # 0 = all available

      # Get mutable colony and fleet
      var colony = state.colonies[order.colonySystem]
      var fleet = fleetOpt.get()
      var totalLoaded = 0

      # Check colony inventory based on cargo type
      var availableUnits = case cargoType
        of CargoType.Marines: colony.marines
        of CargoType.Colonists:
          # Calculate how many complete PTUs can be loaded from exact population
          # Using souls field for accurate counting (no float rounding errors)
          # Per config/population.toml [ptu_definition] min_population_remaining = 0 (allow evacuation)
          # However, per [transfer_limits] min_source_pu_remaining = 1 (must keep 1 PU minimum)
          # This prevents total evacuation while allowing near-complete evacuation
          let minSoulsToKeep = 1_000_000  # 1 PU = 1 million souls (config/population.toml)
          if colony.souls <= minSoulsToKeep:
            0  # Cannot load any PTUs, colony at minimum viable population
          else:
            let availableSouls = colony.souls - minSoulsToKeep
            let maxPTUs = availableSouls div soulsPerPtu()
            maxPTUs
        else: 0

      if availableUnits <= 0:
        echo "    LoadCargo failed: No ", cargoType, " available at ", order.colonySystem
        continue

      # If quantity = 0, load all available
      if requestedQty == 0:
        requestedQty = availableUnits

      # Load cargo onto compatible spacelift ships
      var remainingToLoad = min(requestedQty, availableUnits)
      var modifiedShips: seq[SpaceLiftShip] = @[]

      for ship in fleet.spaceLiftShips:
        if remainingToLoad <= 0:
          modifiedShips.add(ship)
          continue

        if ship.isCrippled:
          modifiedShips.add(ship)
          continue

        # Determine ship capacity and compatible cargo type
        let shipCargoType = case ship.shipClass
          of ShipClass.TroopTransport: CargoType.Marines
          of ShipClass.ETAC: CargoType.Colonists
          else: CargoType.None

        if shipCargoType != cargoType:
          modifiedShips.add(ship)
          continue  # Ship can't carry this cargo type

        # Try to load cargo onto this ship
        var mutableShip = ship
        let loadAmount = min(remainingToLoad, mutableShip.cargo.capacity - mutableShip.cargo.quantity)
        if mutableShip.loadCargo(cargoType, loadAmount):
          totalLoaded += loadAmount
          remainingToLoad -= loadAmount
          echo "    Loaded ", loadAmount, " ", cargoType, " onto ", ship.shipClass, " ", ship.id

        modifiedShips.add(mutableShip)

      # Update colony inventory
      if totalLoaded > 0:
        case cargoType
        of CargoType.Marines:
          colony.marines -= totalLoaded
        of CargoType.Colonists:
          # Colonists come from population: 1 PTU = 50k souls
          # Use souls field for exact counting (no rounding errors)
          let soulsToLoad = totalLoaded * soulsPerPtu()
          colony.souls -= soulsToLoad
          # Update display field (population in millions)
          colony.population = colony.souls div 1_000_000
          echo "    Removed ", totalLoaded, " PTU (", soulsToLoad, " souls, ", totalLoaded.float * ptuSizeMillions(), "M) from colony"
        else:
          discard

        # Write back modified state
        fleet.spaceLiftShips = modifiedShips
        state.fleets[order.fleetId] = fleet
        state.colonies[order.colonySystem] = colony
        echo "    Successfully loaded ", totalLoaded, " ", cargoType, " at ", order.colonySystem

    of CargoManagementAction.UnloadCargo:
      # Get mutable colony and fleet
      var colony = state.colonies[order.colonySystem]
      var fleet = fleetOpt.get()
      var modifiedShips: seq[SpaceLiftShip] = @[]
      var totalUnloaded = 0
      var unloadedType = CargoType.None

      # Unload cargo from spacelift ships
      for ship in fleet.spaceLiftShips:
        var mutableShip = ship

        if mutableShip.cargo.cargoType == CargoType.None:
          modifiedShips.add(mutableShip)
          continue  # No cargo to unload

        # Unload cargo back to colony inventory
        let (cargoType, quantity) = mutableShip.unloadCargo()
        totalUnloaded += quantity
        unloadedType = cargoType

        case cargoType
        of CargoType.Marines:
          colony.marines += quantity
          echo "    Unloaded ", quantity, " Marines from ", ship.id, " to colony"
        of CargoType.Colonists:
          # Colonists are delivered to population: 1 PTU = 50k souls
          # Use souls field for exact counting (no rounding errors)
          let soulsToUnload = quantity * soulsPerPtu()
          colony.souls += soulsToUnload
          # Update display field (population in millions)
          colony.population = colony.souls div 1_000_000
          echo "    Unloaded ", quantity, " PTU (", soulsToUnload, " souls, ", quantity.float * ptuSizeMillions(), "M) from ", ship.id, " to colony"
        else:
          discard

        modifiedShips.add(mutableShip)

      # Write back modified state
      if totalUnloaded > 0:
        fleet.spaceLiftShips = modifiedShips
        state.fleets[order.fleetId] = fleet
        state.colonies[order.colonySystem] = colony
        echo "    Successfully unloaded ", totalUnloaded, " ", unloadedType, " at ", order.colonySystem

proc resolveTerraformOrders*(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process terraforming orders - initiate new terraforming projects
  ## Per economy.md Section 4.7
  for order in packet.terraformOrders:
    # Validate colony exists and is owned by house
    if order.colonySystem notin state.colonies:
      echo "    Terraforming failed: System ", order.colonySystem, " has no colony"
      continue

    var colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      echo "    Terraforming failed: ", packet.houseId, " does not own system ", order.colonySystem
      continue

    # Check if already terraforming
    if colony.activeTerraforming.isSome:
      echo "    Terraforming failed: ", order.colonySystem, " already has active terraforming project"
      continue

    # Get house tech level
    if packet.houseId notin state.houses:
      echo "    Terraforming failed: House ", packet.houseId, " not found"
      continue

    let house = state.houses[packet.houseId]
    let terLevel = house.techTree.levels.terraformingTech

    # Validate TER level requirement
    let currentClass = ord(colony.planetClass) + 1  # Convert enum to class number (1-7)
    if not res_effects.canTerraform(currentClass, terLevel):
      let targetClass = currentClass + 1
      echo "    Terraforming failed: TER level ", terLevel, " insufficient for class ", currentClass, " -> ", targetClass, " (requires TER ", targetClass, ")"
      continue

    # Calculate costs and duration
    let targetClass = currentClass + 1
    let ppCost = res_effects.getTerraformingBaseCost(currentClass)
    let turnsRequired = res_effects.getTerraformingSpeed(terLevel)

    # Check house treasury has sufficient PP
    if house.treasury < ppCost:
      echo "    Terraforming failed: Insufficient PP (need ", ppCost, ", have ", house.treasury, ")"
      continue

    # Deduct PP cost from house treasury
    state.houses[packet.houseId].treasury -= ppCost

    # Create terraforming project
    let project = TerraformProject(
      startTurn: state.turn,
      turnsRemaining: turnsRequired,
      targetClass: targetClass,
      ppCost: ppCost,
      ppPaid: ppCost
    )

    colony.activeTerraforming = some(project)
    state.colonies[order.colonySystem] = colony

    let className = case targetClass
      of 1: "Extreme"
      of 2: "Desolate"
      of 3: "Hostile"
      of 4: "Harsh"
      of 5: "Benign"
      of 6: "Lush"
      of 7: "Eden"
      else: "Unknown"

    echo "    ", house.name, " initiated terraforming of ", order.colonySystem,
         " to ", className, " (class ", targetClass, ") - Cost: ", ppCost, " PP, Duration: ", turnsRequired, " turns"

    events.add(GameEvent(
      eventType: GameEventType.TerraformComplete,
      houseId: packet.houseId,
      description: house.name & " initiated terraforming of colony " & $order.colonySystem &
                  " to " & className & " (cost: " & $ppCost & " PP, duration: " & $turnsRequired & " turns)",
      systemId: some(order.colonySystem)
    ))

proc hasVisibilityOn(state: GameState, systemId: SystemId, houseId: HouseId): bool =
  ## Check if a house has visibility on a system (fog of war)
  ## A house can see a system if:
  ## - They own a colony there
  ## - They have a fleet present
  ## - They have a spy scout present

  # Check if house owns colony in this system
  if systemId in state.colonies:
    if state.colonies[systemId].owner == houseId:
      return true

  # Check if house has any fleets in this system
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId and fleet.location == systemId:
      return true

  # Check if house has spy scouts in this system
  for scoutId, scout in state.spyScouts:
    if scout.owner == houseId and scout.location == systemId and not scout.detected:
      return true

  return false

proc canGuildTraversePath(state: GameState, path: seq[SystemId], transferringHouse: HouseId): bool =
  ## Check if Space Guild can traverse a path for a given house
  ## Guild validates path using the house's known intel (fog of war)
  ## Returns false if:
  ## - Path crosses system the house has no visibility on (intel leak prevention)
  ## - Path crosses enemy-controlled system (blockade)
  for systemId in path:
    # Player must have visibility on this system (prevents intel leak exploit)
    if not hasVisibilityOn(state, systemId, transferringHouse):
      return false

    # If system has a colony, it must be friendly (not enemy-controlled)
    if systemId in state.colonies:
      let colony = state.colonies[systemId]
      if colony.owner != transferringHouse:
        # Enemy-controlled system - Guild cannot pass through
        return false

  return true

proc calculateTransitTime(state: GameState, sourceSystem: SystemId, destSystem: SystemId, houseId: HouseId): tuple[turns: int, jumps: int] =
  ## Calculate Space Guild transit time and jump distance
  ## Per config/population.toml: turns_per_jump = 1, minimum_turns = 1
  ## Uses pathfinding to calculate actual jump lane distance
  ## Returns (turns: -1, jumps: 0) if path crosses enemy territory (Guild cannot complete transfer)
  if sourceSystem == destSystem:
    return (turns: 1, jumps: 0)  # Minimum 1 turn even for same system, 0 jumps

  # Space Guild civilian transports can use all lanes (not restricted by fleet composition)
  # Create a dummy fleet that can traverse all lanes
  let dummyFleet = Fleet(
    id: "transit_calc",
    owner: "GUILD".HouseId,
    location: sourceSystem,
    squadrons: @[],
    spaceliftShips: @[]
  )

  # Use starmap pathfinding to get actual jump distance
  let pathResult = state.starMap.findPath(sourceSystem, destSystem, dummyFleet)

  if pathResult.found:
    # Check if path crosses enemy territory
    if not canGuildTraversePath(state, pathResult.path, houseId):
      return (turns: -1, jumps: 0)  # Cannot traverse enemy territory

    # Path length - 1 = number of jumps (e.g., [A, B, C] = 2 jumps)
    # 1 turn per jump per config/population.toml
    let jumps = pathResult.path.len - 1
    return (turns: max(1, jumps), jumps: jumps)
  else:
    # No valid path found (shouldn't happen on a connected map, but handle gracefully)
    # Fall back to hex distance as approximation
    if sourceSystem in state.starMap.systems and destSystem in state.starMap.systems:
      let source = state.starMap.systems[sourceSystem]
      let dest = state.starMap.systems[destSystem]
      let hexDist = distance(source.coords, dest.coords)
      let jumps = hexDist.int
      return (turns: max(1, jumps), jumps: jumps)
    else:
      return (turns: 1, jumps: 0)  # Ultimate fallback

proc calculateTransferCost(planetClass: PlanetClass, ptuAmount: int, jumps: int): int =
  ## Calculate Space Guild transfer cost per config/population.toml
  ## Formula: base_cost_per_ptu × ptu_amount × (1 + (jumps - 1) × 0.20)
  ## Source: docs/specs/economy.md Section 3.7, config/population.toml [transfer_costs]

  # Base cost per PTU by planet class (config/population.toml)
  let baseCostPerPTU = case planetClass
    of PlanetClass.Eden: 4
    of PlanetClass.Lush: 5
    of PlanetClass.Benign: 6
    of PlanetClass.Harsh: 8
    of PlanetClass.Hostile: 10
    of PlanetClass.Desolate: 12
    of PlanetClass.Extreme: 15

  # Distance modifier: +20% per jump beyond first (config/population.toml [transfer_modifiers])
  # First jump has no modifier, subsequent jumps add 20% each
  let distanceMultiplier = if jumps > 0:
    1.0 + (float(jumps - 1) * 0.20)
  else:
    1.0  # Same system, no distance penalty

  # Total cost = base × ptu × distance_modifier (rounded up)
  let totalCost = ceil(float(baseCostPerPTU * ptuAmount) * distanceMultiplier).int

  return totalCost

proc resolvePopulationTransfers*(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process Space Guild population transfers between colonies
  ## Source: docs/specs/economy.md Section 3.7, config/population.toml
  echo "    Processing population transfers for ", state.houses[packet.houseId].name

  for transfer in packet.populationTransfers:
    # Validate source colony exists and is owned by house
    if transfer.sourceColony notin state.colonies:
      echo "      Transfer failed: source colony ", transfer.sourceColony, " not found"
      continue

    var sourceColony = state.colonies[transfer.sourceColony]
    if sourceColony.owner != packet.houseId:
      echo "      Transfer failed: source colony ", transfer.sourceColony, " not owned by ", packet.houseId
      continue

    # Validate destination colony exists and is owned by house
    if transfer.destColony notin state.colonies:
      echo "      Transfer failed: destination colony ", transfer.destColony, " not found"
      continue

    var destColony = state.colonies[transfer.destColony]
    if destColony.owner != packet.houseId:
      echo "      Transfer failed: destination colony ", transfer.destColony, " not owned by ", packet.houseId
      continue

    # Critical validation: Destination must have ≥1 PTU (50k souls) to be a functional colony
    if destColony.souls < soulsPerPtu():
      echo "      Transfer failed: destination colony ", transfer.destColony, " has only ", destColony.souls,
           " souls (needs ≥", soulsPerPtu(), " to accept transfers)"
      continue

    # Convert PTU amount to souls for exact transfer
    let soulsToTransfer = transfer.ptuAmount * soulsPerPtu()

    # Validate source has enough souls (can transfer any amount, even fractional PTU)
    if sourceColony.souls < soulsToTransfer:
      echo "      Transfer failed: source colony ", transfer.sourceColony, " has only ", sourceColony.souls,
           " souls (needs ", soulsToTransfer, " for ", transfer.ptuAmount, " PTU)"
      continue

    # Calculate transit time and jump distance
    let (transitTime, jumps) = calculateTransitTime(state, transfer.sourceColony, transfer.destColony, packet.houseId)

    # Check if Guild can complete the transfer (path must be known and not blocked)
    if transitTime < 0:
      echo "      Transfer failed: No safe Guild route between ",
           transfer.sourceColony, " and ", transfer.destColony,
           " (requires scouted path through friendly/neutral territory)"
      continue

    let arrivalTurn = state.turn + transitTime

    # Calculate transfer cost based on destination planet class and jump distance
    # Per config/population.toml and docs/specs/economy.md Section 3.7
    let cost = calculateTransferCost(destColony.planetClass, transfer.ptuAmount, jumps)

    # Check house treasury and deduct cost
    var house = state.houses[packet.houseId]
    if house.treasury < cost:
      echo "      Transfer failed: Insufficient funds (need ", cost, " PP, have ", house.treasury, " PP)"
      continue

    # Deduct cost from treasury
    house.treasury -= cost
    state.houses[packet.houseId] = house

    # Deduct souls from source colony immediately (they've departed)
    sourceColony.souls -= soulsToTransfer
    sourceColony.population = sourceColony.souls div 1_000_000
    state.colonies[transfer.sourceColony] = sourceColony

    # Create in-transit entry
    let transferId = $packet.houseId & "_" & $transfer.sourceColony & "_" & $transfer.destColony & "_" & $state.turn
    let inTransit = pop_types.PopulationInTransit(
      id: transferId,
      houseId: packet.houseId,
      sourceSystem: transfer.sourceColony,
      destSystem: transfer.destColony,
      ptuAmount: transfer.ptuAmount,
      costPaid: cost,
      arrivalTurn: arrivalTurn
    )
    state.populationInTransit.add(inTransit)

    echo "      Space Guild transporting ", transfer.ptuAmount, " PTU (", soulsToTransfer, " souls) from ",
         transfer.sourceColony, " to ", transfer.destColony, " (arrives turn ", arrivalTurn, ", cost: ", cost, " PP)"

    events.add(GameEvent(
      eventType: GameEventType.PopulationTransfer,
      houseId: packet.houseId,
      description: "Space Guild transporting " & $transfer.ptuAmount & " PTU from " & $transfer.sourceColony & " to " & $transfer.destColony & " (ETA: turn " & $arrivalTurn & ", cost: " & $cost & " PP)",
      systemId: some(transfer.sourceColony)
    ))

proc resolvePopulationArrivals*(state: var GameState, events: var seq[GameEvent]) =
  ## Process Space Guild population transfers that arrive this turn
  ## Implements risk handling per config/population.toml [transfer_risks]
  ## Per config: dest_blockaded_behavior = "closest_owned"
  ## Per config: dest_collapsed_behavior = "closest_owned"
  echo "  [Processing Space Guild Arrivals]"

  var arrivedTransfers: seq[int] = @[]  # Indices to remove after processing

  for idx, transfer in state.populationInTransit:
    if transfer.arrivalTurn != state.turn:
      continue  # Not arriving this turn

    let soulsToDeliver = transfer.ptuAmount * soulsPerPtu()

    # Check destination status
    if transfer.destSystem notin state.colonies:
      # Destination colony no longer exists
      echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination colony destroyed"
      arrivedTransfers.add(idx)
      events.add(GameEvent(
        eventType: GameEventType.PopulationTransfer,
        houseId: transfer.houseId,
        description: $transfer.ptuAmount & " PTU lost - destination " & $transfer.destSystem & " destroyed",
        systemId: some(transfer.destSystem)
      ))
      continue

    var destColony = state.colonies[transfer.destSystem]

    # Check if destination conquered (no longer owned by originating house)
    if destColony.owner != transfer.houseId:
      # dest_conquered_behavior = "lost"
      echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination conquered by ", destColony.owner
      arrivedTransfers.add(idx)
      events.add(GameEvent(
        eventType: GameEventType.PopulationTransfer,
        houseId: transfer.houseId,
        description: $transfer.ptuAmount & " PTU lost - destination " & $transfer.destSystem & " conquered",
        systemId: some(transfer.destSystem)
      ))
      continue

    # Check if destination blockaded or collapsed
    # Per config/population.toml: dest_blockaded_behavior = "closest_owned"
    # Per config/population.toml: dest_collapsed_behavior = "closest_owned"
    var needsAlternativeDestination = false
    var alternativeReason = ""

    if destColony.blockaded:
      needsAlternativeDestination = true
      alternativeReason = "blockaded"
    elif destColony.souls < soulsPerPtu():
      needsAlternativeDestination = true
      alternativeReason = "collapsed below minimum viable population"

    if needsAlternativeDestination:
      # Space Guild attempts to deliver to closest owned colony
      let alternativeDest = findClosestOwnedColony(state, transfer.destSystem, transfer.houseId)

      if alternativeDest.isSome:
        # Deliver to alternative colony
        let altSystemId = alternativeDest.get()
        var altColony = state.colonies[altSystemId]
        altColony.souls += soulsToDeliver
        altColony.population = altColony.souls div 1_000_000
        state.colonies[altSystemId] = altColony

        echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU redirected to ", altSystemId,
             " - original destination ", transfer.destSystem, " ", alternativeReason
        events.add(GameEvent(
          eventType: GameEventType.PopulationTransfer,
          houseId: transfer.houseId,
          description: $transfer.ptuAmount & " PTU redirected from " & $transfer.destSystem & " (" & alternativeReason & ") to " & $altSystemId,
          systemId: some(altSystemId)
        ))
      else:
        # No owned colonies - colonists are lost
        echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination ", alternativeReason, ", no owned colonies available"
        events.add(GameEvent(
          eventType: GameEventType.PopulationTransfer,
          houseId: transfer.houseId,
          description: $transfer.ptuAmount & " PTU lost - " & $transfer.destSystem & " " & alternativeReason & ", no owned colonies for delivery",
          systemId: some(transfer.destSystem)
        ))

      arrivedTransfers.add(idx)
      continue

    # Successful delivery!
    destColony.souls += soulsToDeliver
    destColony.population = destColony.souls div 1_000_000
    state.colonies[transfer.destSystem] = destColony

    echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU arrived at ", transfer.destSystem, " (", soulsToDeliver, " souls)"
    events.add(GameEvent(
      eventType: GameEventType.PopulationTransfer,
      houseId: transfer.houseId,
      description: $transfer.ptuAmount & " PTU arrived at " & $transfer.destSystem & " from " & $transfer.sourceSystem,
      systemId: some(transfer.destSystem)
    ))

    arrivedTransfers.add(idx)

  # Remove processed transfers (in reverse order to preserve indices)
  for idx in countdown(arrivedTransfers.len - 1, 0):
    state.populationInTransit.del(arrivedTransfers[idx])

proc processTerraformingProjects(state: var GameState, events: var seq[GameEvent]) =
  ## Process active terraforming projects for all houses
  ## Per economy.md Section 4.7

  for colonyId, colony in state.colonies.mpairs:
    if colony.activeTerraforming.isNone:
      continue

    let houseId = colony.owner
    if houseId notin state.houses:
      continue

    let house = state.houses[houseId]
    var project = colony.activeTerraforming.get()
    project.turnsRemaining -= 1

    if project.turnsRemaining <= 0:
      # Terraforming complete!
      # Convert int class number (1-7) back to PlanetClass enum (0-6)
      colony.planetClass = PlanetClass(project.targetClass - 1)
      colony.activeTerraforming = none(TerraformProject)

      let className = case project.targetClass
        of 1: "Extreme"
        of 2: "Desolate"
        of 3: "Hostile"
        of 4: "Harsh"
        of 5: "Benign"
        of 6: "Lush"
        of 7: "Eden"
        else: "Unknown"

      echo "    ", house.name, " completed terraforming of ", colonyId,
           " to ", className, " (class ", project.targetClass, ")"

      events.add(GameEvent(
        eventType: GameEventType.TerraformComplete,
        houseId: houseId,
        description: house.name & " completed terraforming colony " & $colonyId &
                    " to " & className,
        systemId: some(colonyId)
      ))
    else:
      echo "    ", house.name, " terraforming ", colonyId,
           ": ", project.turnsRemaining, " turn(s) remaining"
      # Update project
      colony.activeTerraforming = some(project)

proc resolveMaintenancePhase*(state: var GameState, events: var seq[GameEvent], orders: Table[HouseId, OrderPacket]) =
  ## Phase 4: Upkeep, effect decrements, and diplomatic status updates
  echo "  [Maintenance Phase]"

  # Decrement ongoing espionage effect counters
  var remainingEffects: seq[esp_types.OngoingEffect] = @[]
  for effect in state.ongoingEffects:
    var updatedEffect = effect
    updatedEffect.turnsRemaining -= 1

    if updatedEffect.turnsRemaining > 0:
      remainingEffects.add(updatedEffect)
      echo "    Effect on ", updatedEffect.targetHouse, " expires in ",
           updatedEffect.turnsRemaining, " turn(s)"
    else:
      echo "    Effect on ", updatedEffect.targetHouse, " has expired"

  state.ongoingEffects = remainingEffects

  # Expire pending diplomatic proposals
  for proposal in state.pendingProposals.mitems:
    if proposal.status == dip_proposals.ProposalStatus.Pending:
      proposal.expiresIn -= 1

      if proposal.expiresIn <= 0:
        proposal.status = dip_proposals.ProposalStatus.Expired
        echo "    Proposal ", proposal.id, " expired (", proposal.proposer, " -> ", proposal.target, ")"

  # Clean up old proposals (keep 10 turn history)
  let currentTurn = state.turn
  state.pendingProposals.keepIf(proc(p: dip_proposals.PendingProposal): bool =
    p.status == dip_proposals.ProposalStatus.Pending or
    (currentTurn - p.submittedTurn) < 10
  )

  # Process Space Guild population transfers arriving this turn
  resolvePopulationArrivals(state, events)

  # Process active terraforming projects
  processTerraformingProjects(state, events)

  # Update diplomatic status timers for all houses
  for houseId, house in state.houses.mpairs:
    # Update dishonored status
    if house.dishonoredStatus.active:
      house.dishonoredStatus.turnsRemaining -= 1
      if house.dishonoredStatus.turnsRemaining <= 0:
        house.dishonoredStatus.active = false
        echo "    ", house.name, " is no longer dishonored"

    # Update diplomatic isolation
    if house.diplomaticIsolation.active:
      house.diplomaticIsolation.turnsRemaining -= 1
      if house.diplomaticIsolation.turnsRemaining <= 0:
        house.diplomaticIsolation.active = false
        echo "    ", house.name, " is no longer diplomatically isolated"

  # Convert colonies table to sequence for maintenance phase
  # NOTE: No type conversion needed - gamestate.Colony has all economic fields
  var coloniesSeq: seq[Colony] = @[]
  for systemId, colony in state.colonies:
    coloniesSeq.add(colony)

  # Build house fleet data
  var houseFleetData = initTable[HouseId, seq[(ShipClass, bool)]]()
  for houseId in state.houses.keys:
    houseFleetData[houseId] = @[]
    for fleet in state.getHouseFleets(houseId):
      for squadron in fleet.squadrons:
        # Get actual ship class and crippled status from squadron
        houseFleetData[houseId].add((squadron.flagship.shipClass, squadron.flagship.isCrippled))

  # Build house treasuries
  var houseTreasuries = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTreasuries[houseId] = house.treasury

  # Call maintenance engine
  let maintenanceReport = econ_engine.resolveMaintenancePhase(
    coloniesSeq,
    houseFleetData,
    houseTreasuries
  )

  # CRITICAL: Write modified colonies back to state
  # Construction advances in coloniesSeq, must persist to state.colonies
  for colony in coloniesSeq:
    state.colonies[colony.systemId] = colony

  # Apply results back to game state
  for houseId, upkeep in maintenanceReport.houseUpkeep:
    # CRITICAL: Get, modify, write back to persist
    var house = state.houses[houseId]
    house.treasury = houseTreasuries[houseId]
    echo "    ", house.name, ": -", upkeep, " PP maintenance"
    state.houses[houseId] = house

  # Report and handle completed projects
  for completed in maintenanceReport.completedProjects:
    echo "    Completed: ", completed.projectType, " at system ", completed.colonyId

    # Special handling for fighter squadrons
    # Fighters can come through as either:
    # 1. ConstructionType.Building with itemId="FighterSquadron" (legacy/planned)
    # 2. ConstructionType.Ship with itemId="Fighter" (current system via budget.nim)
    if (completed.projectType == econ_types.ConstructionType.Building and
        completed.itemId == "FighterSquadron") or
       (completed.projectType == econ_types.ConstructionType.Ship and
        completed.itemId == "Fighter"):
      # Commission fighter squadron at colony
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Create new fighter squadron
        let fighterSq = FighterSquadron(
          id: $completed.colonyId & "-FS-" & $(colony.fighterSquadrons.len + 1),
          commissionedTurn: state.turn
        )

        colony.fighterSquadrons.add(fighterSq)

        echo "      Commissioned fighter squadron ", fighterSq.id, " at ", completed.colonyId

        # Fighters remain at colony by default - player must manually load onto carriers
        # Per assets.md:2.4.1 - fighters are colony-owned until explicitly transferred

        state.colonies[completed.colonyId] = colony

        # Generate event
        events.add(GameEvent(
          eventType: GameEventType.ShipCommissioned,
          houseId: colony.owner,
          description: "Fighter Squadron commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for starbases
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Starbase":
      # Commission starbase at colony
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Create new starbase
        let starbase = Starbase(
          id: $completed.colonyId & "-SB-" & $(colony.starbases.len + 1),
          commissionedTurn: state.turn,
          isCrippled: false
        )

        colony.starbases.add(starbase)
        state.colonies[completed.colonyId] = colony

        echo "      Commissioned starbase ", starbase.id, " at ", completed.colonyId
        echo "        Total operational starbases: ", getOperationalStarbaseCount(colony)
        echo "        Growth bonus: ", int(getStarbaseGrowthBonus(colony) * 100.0), "%"

        # Generate event
        events.add(GameEvent(
          eventType: GameEventType.ShipCommissioned,
          houseId: colony.owner,
          description: "Starbase commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for spaceports
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Spaceport":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Create new spaceport (5 docks per facilities_config.toml)
        let spaceport = Spaceport(
          id: $completed.colonyId & "-SP-" & $(colony.spaceports.len + 1),
          commissionedTurn: state.turn,
          docks: 5  # From facilities_config: spaceport.docks
        )

        colony.spaceports.add(spaceport)
        state.colonies[completed.colonyId] = colony

        echo "      Commissioned spaceport ", spaceport.id, " at ", completed.colonyId
        echo "        Total construction docks: ", getTotalConstructionDocks(colony)

        events.add(GameEvent(
          eventType: GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Spaceport commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for shipyards
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Shipyard":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Validate spaceport prerequisite
        if not hasSpaceport(colony):
          echo "      ERROR: Shipyard construction failed - no spaceport at ", completed.colonyId
          # This shouldn't happen if build validation worked correctly
          continue

        # Create new shipyard (10 docks per facilities_config.toml)
        let shipyard = Shipyard(
          id: $completed.colonyId & "-SY-" & $(colony.shipyards.len + 1),
          commissionedTurn: state.turn,
          docks: 10,  # From facilities_config: shipyard.docks
          isCrippled: false
        )

        colony.shipyards.add(shipyard)
        state.colonies[completed.colonyId] = colony

        echo "      Commissioned shipyard ", shipyard.id, " at ", completed.colonyId
        echo "        Total construction docks: ", getTotalConstructionDocks(colony)

        events.add(GameEvent(
          eventType: GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Shipyard commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for ground batteries
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "GroundBattery":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Add ground battery (instant construction, 1 turn)
        colony.groundBatteries += 1
        state.colonies[completed.colonyId] = colony

        echo "      Deployed ground battery at ", completed.colonyId
        echo "        Total ground defenses: ", getTotalGroundDefense(colony)

        events.add(GameEvent(
          eventType: GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Ground battery deployed at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for planetary shields (replacement, not upgrade)
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId.startsWith("PlanetaryShield"):
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Extract shield level from itemId (e.g., "PlanetaryShield-3" -> 3)
        # For now, assume sequential upgrades
        let newLevel = colony.planetaryShieldLevel + 1
        colony.planetaryShieldLevel = min(newLevel, 6)  # Max SLD6
        state.colonies[completed.colonyId] = colony

        echo "      Deployed planetary shield SLD", colony.planetaryShieldLevel, " at ", completed.colonyId
        echo "        Block chance: ", int(getShieldBlockChance(colony.planetaryShieldLevel) * 100.0), "%"

        events.add(GameEvent(
          eventType: GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Planetary Shield SLD" & $colony.planetaryShieldLevel & " deployed at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for Marines (MD)
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Marine":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Get population cost from config
        let marinePopCost = globalGroundUnitsConfig.marine_division.population_cost
        const minViablePopulation = 1_000_000  # 1 PU minimum for colony viability

        if colony.souls < marinePopCost:
          echo "      WARNING: Colony ", completed.colonyId, " lacks population to recruit Marines (",
               colony.souls, " souls < ", marinePopCost, ")"
        elif colony.souls - marinePopCost < minViablePopulation:
          echo "      WARNING: Colony ", completed.colonyId, " cannot recruit Marines - would leave colony below minimum viable size (",
               colony.souls - marinePopCost, " < ", minViablePopulation, " souls)"
        else:
          colony.marines += 1  # Add 1 Marine Division
          colony.souls -= marinePopCost  # Deduct recruited souls
          colony.population = colony.souls div 1_000_000  # Update display population
          state.colonies[completed.colonyId] = colony

          echo "      Recruited Marine Division at ", completed.colonyId
          echo "        Total Marines: ", colony.marines, " MD (", colony.souls, " souls remaining)"

          events.add(GameEvent(
            eventType: GameEventType.UnitRecruited,
            houseId: colony.owner,
            description: "Marine Division recruited at " & $completed.colonyId & " (total: " & $colony.marines & " MD)",
            systemId: some(completed.colonyId)
          ))

    # Special handling for Armies (AA)
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Army":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Get population cost from config
        let armyPopCost = globalGroundUnitsConfig.army.population_cost
        const minViablePopulation = 1_000_000  # 1 PU minimum for colony viability

        if colony.souls < armyPopCost:
          echo "      WARNING: Colony ", completed.colonyId, " lacks population to muster Army (",
               colony.souls, " souls < ", armyPopCost, ")"
        elif colony.souls - armyPopCost < minViablePopulation:
          echo "      WARNING: Colony ", completed.colonyId, " cannot muster Army - would leave colony below minimum viable size (",
               colony.souls - armyPopCost, " < ", minViablePopulation, " souls)"
        else:
          colony.armies += 1  # Add 1 Army Division
          colony.souls -= armyPopCost  # Deduct recruited souls
          colony.population = colony.souls div 1_000_000  # Update display population
          state.colonies[completed.colonyId] = colony

          echo "      Mustered Army Division at ", completed.colonyId
          echo "        Total Armies: ", colony.armies, " AA (", colony.souls, " souls remaining)"

          events.add(GameEvent(
            eventType: GameEventType.UnitRecruited,
            houseId: colony.owner,
            description: "Army Division mustered at " & $completed.colonyId & " (total: " & $colony.armies & " AA)",
            systemId: some(completed.colonyId)
          ))

    # Handle ship construction
    elif completed.projectType == econ_types.ConstructionType.Ship:
      if completed.colonyId in state.colonies:
        let colony = state.colonies[completed.colonyId]
        let owner = colony.owner

        # Parse ship class from itemId
        try:
          let shipClass = parseEnum[ShipClass](completed.itemId)
          let techLevel = state.houses[owner].techTree.levels.weaponsTech

          # Create the ship
          let ship = newEnhancedShip(shipClass, techLevel)

          # Find squadrons at this system belonging to this house
          var assignedSquadron: SquadronId = ""
          for fleetId, fleet in state.fleets:
            if fleet.owner == owner and fleet.location == completed.colonyId:
              for squadron in fleet.squadrons:
                if canAddShip(squadron, ship):
                  # Found a squadron with capacity
                  assignedSquadron = squadron.id
                  break
              if assignedSquadron != "":
                break

          # Add ship to existing squadron or create new one
          if assignedSquadron != "":
            # Add to existing squadron
            for fleetId, fleet in state.fleets.mpairs:
              if fleet.owner == owner:
                for squadron in fleet.squadrons.mitems:
                  if squadron.id == assignedSquadron:
                    discard addShip(squadron, ship)
                    echo "      Commissioned ", shipClass, " and assigned to squadron ", squadron.id
                    break

          else:
            # Create new squadron with this ship as flagship
            let newSquadronId = $owner & "_sq_" & $state.fleets.len & "_" & $state.turn
            let newSq = newSquadron(ship, newSquadronId, owner, completed.colonyId)

            # Find or create fleet at this location
            var targetFleetId = ""
            for fleetId, fleet in state.fleets:
              if fleet.owner == owner and fleet.location == completed.colonyId:
                targetFleetId = fleetId
                break

            if targetFleetId == "":
              # Create new fleet at colony
              targetFleetId = $owner & "_fleet" & $(state.fleets.len + 1)
              state.fleets[targetFleetId] = Fleet(
                id: targetFleetId,
                owner: owner,
                location: completed.colonyId,
                squadrons: @[newSq]
              )
              echo "      Commissioned ", shipClass, " in new fleet ", targetFleetId
            else:
              # Add squadron to existing fleet
              state.fleets[targetFleetId].squadrons.add(newSq)
              echo "      Commissioned ", shipClass, " in new squadron ", newSq.id

          # Generate event
          events.add(GameEvent(
            eventType: GameEventType.ShipCommissioned,
            houseId: owner,
            description: $shipClass & " commissioned at " & $completed.colonyId,
            systemId: some(completed.colonyId)
          ))

        except ValueError:
          echo "      ERROR: Invalid ship class: ", completed.itemId

  # Check for elimination and defensive collapse
  let gameplayConfig = globalGameplayConfig
  for houseId, house in state.houses:
    # Standard elimination: no colonies and no invasion capability
    let colonies = state.getHouseColonies(houseId)
    let fleets = state.getHouseFleets(houseId)

    if colonies.len == 0:
      # No colonies - check if house has invasion capability (marines on transports)
      var hasInvasionCapability = false

      for fleet in fleets:
        for transport in fleet.spaceLiftShips:
          if transport.cargo.cargoType == CargoType.Marines and transport.cargo.quantity > 0:
            hasInvasionCapability = true
            break
        if hasInvasionCapability:
          break

      # Eliminate if no fleets OR no loaded transports with marines
      if fleets.len == 0 or not hasInvasionCapability:
        # CRITICAL: Get, modify, write back to persist
        var houseToUpdate = state.houses[houseId]
        houseToUpdate.eliminated = true
        state.houses[houseId] = houseToUpdate

        let reason = if fleets.len == 0:
          "no remaining forces"
        else:
          "no marines for reconquest"

        events.add(GameEvent(
          eventType: GameEventType.HouseEliminated,
          houseId: houseId,
          description: house.name & " has been eliminated - " & reason & "!",
          systemId: none(SystemId)
        ))
        echo "    ", house.name, " eliminated! (", reason, ")"
        continue

    # Defensive collapse: prestige < threshold for consecutive turns
    # CRITICAL: Get house once, modify elimination/counter, write back
    var houseToUpdate = state.houses[houseId]

    if house.prestige < gameplayConfig.elimination.defensive_collapse_threshold:
      houseToUpdate.negativePrestigeTurns += 1
      echo "    ", house.name, " at risk: prestige ", house.prestige,
           " (", houseToUpdate.negativePrestigeTurns, "/",
           gameplayConfig.elimination.defensive_collapse_turns, " turns until elimination)"

      if houseToUpdate.negativePrestigeTurns >= gameplayConfig.elimination.defensive_collapse_turns:
        houseToUpdate.eliminated = true
        houseToUpdate.status = HouseStatus.DefensiveCollapse
        events.add(GameEvent(
          eventType: GameEventType.HouseEliminated,
          houseId: houseId,
          description: house.name & " has collapsed from negative prestige!",
          systemId: none(SystemId)
        ))
        echo "    ", house.name, " eliminated by defensive collapse!"
    else:
      # Reset counter when prestige recovers
      houseToUpdate.negativePrestigeTurns = 0

    # Write back modified house
    state.houses[houseId] = houseToUpdate

  # Check squadron limits (military.toml)
  echo "  Checking squadron limits..."
  for houseId, house in state.houses:
    if house.eliminated:
      continue

    let current = state.getHouseSquadronCount(houseId)
    let limit = state.getSquadronLimit(houseId)
    let totalPU = state.getHousePopulationUnits(houseId)

    if current > limit:
      echo "    WARNING: ", house.name, " over squadron limit!"
      echo "      Current: ", current, " squadrons, Limit: ", limit, " (", totalPU, " PU)"
      # Note: In full implementation, this would trigger grace period timer
      # and eventual auto-disband per military.toml:capacity_violation_grace_period
    elif current == limit:
      echo "    ", house.name, ": At squadron limit (", current, "/", limit, ")"
    else:
      echo "    ", house.name, ": ", current, "/", limit, " squadrons (", totalPU, " PU)"

  # Check fighter squadron capacity violations (assets.md:2.4.1)
  echo "  Checking fighter squadron capacity..."
  let militaryConfig = globalMilitaryConfig.fighter_mechanics

  for systemId, colony in state.colonies.mpairs:
    let house = state.houses[colony.owner]
    if house.eliminated:
      continue

    # Get FD multiplier from house tech level
    let fdMultiplier = getFighterDoctrineMultiplier(house.techTree.levels)

    # Check current capacity
    let current = getCurrentFighterCount(colony)
    let capacity = getFighterCapacity(colony, fdMultiplier)
    let popCapacity = getFighterPopulationCapacity(colony, fdMultiplier)
    let infraCapacity = getFighterInfrastructureCapacity(colony)

    # Check if over capacity
    let isOverCapacity = current > capacity

    if isOverCapacity:
      # Determine violation type
      let violationType = if popCapacity < current:
        "population"
      elif infraCapacity < current:
        "infrastructure"
      else:
        "unknown"

      # Start or continue violation
      if not colony.capacityViolation.active:
        # New violation - start grace period
        colony.capacityViolation = CapacityViolation(
          active: true,
          violationType: violationType,
          turnsRemaining: militaryConfig.capacity_violation_grace_period,
          violationTurn: state.turn
        )
        echo "    WARNING: ", house.name, " - System ", systemId, " over fighter capacity!"
        echo "      Current: ", current, " FS, Capacity: ", capacity,
             " (Pop: ", popCapacity, ", Infra: ", infraCapacity, ")"
        echo "      Violation type: ", violationType
        echo "      Grace period: ", militaryConfig.capacity_violation_grace_period, " turns"
      else:
        # Existing violation - decrement timer
        colony.capacityViolation.turnsRemaining -= 1
        echo "    ", house.name, " - System ", systemId, " capacity violation continues"
        echo "      Current: ", current, " FS, Capacity: ", capacity
        echo "      Grace period remaining: ", colony.capacityViolation.turnsRemaining, " turn(s)"

        # Check if grace period expired
        if colony.capacityViolation.turnsRemaining <= 0:
          # Auto-disband excess fighters (oldest first)
          let excess = current - capacity
          echo "      Grace period expired! Auto-disbanding ", excess, " excess fighter squadron(s)"

          # Remove oldest squadrons first
          for i in 0..<excess:
            if colony.fighterSquadrons.len > 0:
              let disbanded = colony.fighterSquadrons[0]
              colony.fighterSquadrons.delete(0)
              echo "        Disbanded: ", disbanded.id

          # Clear violation
          colony.capacityViolation = CapacityViolation(
            active: false,
            violationType: "",
            turnsRemaining: 0,
            violationTurn: 0
          )

          # Generate event
          events.add(GameEvent(
            eventType: GameEventType.UnitDisbanded,
            houseId: colony.owner,
            description: $excess & " fighter squadrons auto-disbanded at " & $systemId & " (capacity violation)",
            systemId: some(systemId)
          ))

    elif colony.capacityViolation.active:
      # Was in violation but now resolved
      echo "    ", house.name, " - System ", systemId, " capacity violation resolved!"
      colony.capacityViolation = CapacityViolation(
        active: false,
        violationType: "",
        turnsRemaining: 0,
        violationTurn: 0
      )
    elif current > 0:
      # Normal status report
      echo "    ", house.name, " - System ", systemId, ": ", current, "/", capacity,
           " FS (Pop: ", popCapacity, ", Infra: ", infraCapacity, ")"

  # Process tech advancements on upgrade turns
  # Per economy.md:4.1: Levels purchased on turns 1 and 7 (bi-annual)
  if isUpgradeTurn(state.turn):
    echo "  Tech Advancement (Upgrade Turn)"
    for houseId, house in state.houses.mpairs:
      # Try to advance Economic Level (EL) with accumulated ERP
      let currentEL = house.techTree.levels.economicLevel
      let elAdv = attemptELAdvancement(house.techTree, currentEL)
      if elAdv.isSome:
        let adv = elAdv.get()
        echo "    ", house.name, ": EL ", adv.fromLevel, " → ", adv.toLevel,
             " (spent ", adv.cost, " ERP)"
        if adv.prestigeEvent.isSome:
          house.prestige += adv.prestigeEvent.get().amount
          echo "      +", adv.prestigeEvent.get().amount, " prestige"
        events.add(GameEvent(
          eventType: GameEventType.TechAdvance,
          houseId: houseId,
          description: &"Economic Level advanced to {adv.toLevel}",
          systemId: none(SystemId)
        ))

      # Try to advance Science Level (SL) with accumulated SRP
      let currentSL = house.techTree.levels.scienceLevel
      let slAdv = attemptSLAdvancement(house.techTree, currentSL)
      if slAdv.isSome:
        let adv = slAdv.get()
        echo "    ", house.name, ": SL ", adv.fromLevel, " → ", adv.toLevel,
             " (spent ", adv.cost, " SRP)"
        if adv.prestigeEvent.isSome:
          house.prestige += adv.prestigeEvent.get().amount
          echo "      +", adv.prestigeEvent.get().amount, " prestige"
        events.add(GameEvent(
          eventType: GameEventType.TechAdvance,
          houseId: houseId,
          description: &"Science Level advanced to {adv.toLevel}",
          systemId: none(SystemId)
        ))

      # Try to advance technology fields with accumulated TRP
      for field in [TechField.ConstructionTech, TechField.WeaponsTech,
                    TechField.TerraformingTech, TechField.ElectronicIntelligence,
                    TechField.CounterIntelligence]:
        let advancement = attemptTechAdvancement(house.techTree, field)
        if advancement.isSome:
          let adv = advancement.get()
          echo "    ", house.name, ": ", field, " ", adv.fromLevel, " → ", adv.toLevel,
               " (spent ", adv.cost, " TRP)"

          # Apply prestige if available
          if adv.prestigeEvent.isSome:
            house.prestige += adv.prestigeEvent.get().amount
            echo "      +", adv.prestigeEvent.get().amount, " prestige"

          # Generate event
          events.add(GameEvent(
            eventType: GameEventType.TechAdvance,
            houseId: houseId,
            description: &"{field} advanced to level {adv.toLevel}",
            systemId: none(SystemId)
          ))

  # Check victory condition
  let victorOpt = state.checkVictoryCondition()
  if victorOpt.isSome:
    let victorId = victorOpt.get()
    state.phase = GamePhase.Completed

    # Find victor by house id (handle case where table key != house.id)
    var victorName = "Unknown"
    for houseId, house in state.houses:
      if house.id == victorId:
        victorName = house.name
        break

    echo "  *** ", victorName, " has won the game! ***"
proc resolveIncomePhase*(state: var GameState, orders: Table[HouseId, OrderPacket]) =
  ## Phase 2: Collect income and allocate resources
  ## Production is calculated AFTER conflict, so damaged infrastructure produces less
  ## Also applies ongoing espionage effects (SRP/NCV/Tax reductions)
  echo "  [Income Phase]"

  # Apply blockade status to all colonies
  # Per operations.md:6.2.6: "Blockades established during the Conflict Phase
  # reduce GCO for that same turn's Income Phase calculation - there is no delay"
  blockade_engine.applyBlockades(state)

  # Apply ongoing espionage effects to houses
  var activeEffects: seq[esp_types.OngoingEffect] = @[]
  for effect in state.ongoingEffects:
    if effect.turnsRemaining > 0:
      activeEffects.add(effect)

      case effect.effectType
      of esp_types.EffectType.SRPReduction:
        echo "    ", effect.targetHouse, " affected by SRP reduction (-",
             int(effect.magnitude * 100), "%)"
      of esp_types.EffectType.NCVReduction:
        echo "    ", effect.targetHouse, " affected by NCV reduction (-",
             int(effect.magnitude * 100), "%)"
      of esp_types.EffectType.TaxReduction:
        echo "    ", effect.targetHouse, " affected by tax reduction (-",
             int(effect.magnitude * 100), "%)"
      of esp_types.EffectType.StarbaseCrippled:
        if effect.targetSystem.isSome:
          let systemId = effect.targetSystem.get()
          echo "    Starbase at system ", systemId, " is crippled"

          # Apply crippled state to starbase in colony
          if systemId in state.colonies:
            var colony = state.colonies[systemId]
            if colony.owner == effect.targetHouse:
              for starbase in colony.starbases.mitems:
                if not starbase.isCrippled:
                  starbase.isCrippled = true
                  echo "      Applied crippled state to starbase ", starbase.id
              state.colonies[systemId] = colony
      of esp_types.EffectType.IntelBlocked:
        echo "    ", effect.targetHouse, " protected by counter-intelligence sweep"
      of esp_types.EffectType.IntelCorrupted:
        echo "    ", effect.targetHouse, "'s intelligence corrupted by disinformation (+/-",
             int(effect.magnitude * 100), "% variance)"

  state.ongoingEffects = activeEffects

  # Process EBP/CIP purchases (diplomacy.md:8.2)
  # EBP and CIP cost 40 PP each
  # Over-investment penalty: lose 1 prestige per 1% over 5% of turn budget
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      if packet.ebpInvestment > 0 or packet.cipInvestment > 0:
        let ebpCost = packet.ebpInvestment * globalEspionageConfig.costs.ebp_cost_pp
        let cipCost = packet.cipInvestment * globalEspionageConfig.costs.cip_cost_pp
        let totalCost = ebpCost + cipCost

        # Deduct from treasury
        if state.houses[houseId].treasury >= totalCost:
          state.houses[houseId].treasury -= totalCost
          state.houses[houseId].espionageBudget.ebpPoints += packet.ebpInvestment
          state.houses[houseId].espionageBudget.cipPoints += packet.cipInvestment
          state.houses[houseId].espionageBudget.ebpInvested = ebpCost
          state.houses[houseId].espionageBudget.cipInvested = cipCost

          echo "    ", houseId, " purchased ", packet.ebpInvestment, " EBP, ",
               packet.cipInvestment, " CIP (", totalCost, " PP)"

          # Check for over-investment penalty (configurable threshold from espionage.toml)
          let turnBudget = state.houses[houseId].espionageBudget.turnBudget
          if turnBudget > 0:
            let totalInvestment = ebpCost + cipCost
            let investmentPercent = (totalInvestment * 100) div turnBudget
            let threshold = globalEspionageConfig.investment.threshold_percentage

            if investmentPercent > threshold:
              let prestigePenalty = -(investmentPercent - threshold) * globalEspionageConfig.investment.penalty_per_percent
              state.houses[houseId].prestige += prestigePenalty
              echo "      Over-investment penalty: ", prestigePenalty, " prestige"
        else:
          echo "    ", houseId, " insufficient funds for EBP/CIP purchase"

  # Process spy scout detection and intelligence gathering
  # Per assets.md:2.4.2: "For every turn that a spy Scout operates in unfriendly
  # system occupied by rival ELI, the rival will roll on the Spy Detection Table"
  var survivingScouts = initTable[string, SpyScout]()

  for scoutId, scout in state.spyScouts:
    if scout.detected:
      # Scout was detected in a previous turn
      continue

    var wasDetected = false
    let scoutLocation = scout.location

    # Check if system has rival ELI units (fleets with scouts or starbases)
    # Get all houses in the system (from fleets and colonies)
    var housesInSystem: seq[HouseId] = @[]

    # Check for colonies (starbases provide detection)
    if scoutLocation in state.colonies:
      let colony = state.colonies[scoutLocation]
      if colony.owner != scout.owner:
        housesInSystem.add(colony.owner)

    # Check for fleets with scouts
    for fleetId, fleet in state.fleets:
      if fleet.location == scoutLocation and fleet.owner != scout.owner:
        # Check if fleet has scouts
        for squadron in fleet.squadrons:
          if squadron.flagship.shipClass == ShipClass.Scout:
            if not housesInSystem.contains(fleet.owner):
              housesInSystem.add(fleet.owner)
            break

    # For each rival house in system, roll detection
    for rivalHouse in housesInSystem:
      # Build ELI unit from fleets
      var detectorELI: seq[int] = @[]
      var hasStarbase = false

      # Check for colony with starbase
      if scoutLocation in state.colonies:
        let colony = state.colonies[scoutLocation]
        if colony.owner == rivalHouse:
          # Check for operational starbase presence (not crippled)
          for starbase in colony.starbases:
            if not starbase.isCrippled:
              hasStarbase = true
              break

      # Collect ELI from fleets
      for fleetId, fleet in state.fleets:
        if fleet.location == scoutLocation and fleet.owner == rivalHouse:
          for squadron in fleet.squadrons:
            if squadron.flagship.shipClass == ShipClass.Scout:
              detectorELI.add(squadron.flagship.stats.techLevel)

      # Attempt detection if there are ELI units
      if detectorELI.len > 0:
        let detectorUnit = ELIUnit(
          eliLevels: detectorELI,
          isStarbase: hasStarbase
        )

        # Roll detection with turn RNG
        var rng = initRand(state.turn + scoutId.hash())
        let detectionResult = detectSpyScout(detectorUnit, scout.eliLevel, rng)

        if detectionResult.detected:
          echo "    Spy scout ", scoutId, " detected by ", rivalHouse,
               " (ELI ", detectionResult.effectiveELI, " vs ", scout.eliLevel,
               ", rolled ", detectionResult.roll, " > ", detectionResult.threshold, ")"
          wasDetected = true
          break

    if wasDetected:
      # Scout is destroyed, don't add to surviving scouts
      echo "    Spy scout ", scoutId, " destroyed"
    else:
      # Scout survives and gathers intelligence
      survivingScouts[scoutId] = scout

      # Generate intelligence reports based on mission type
      # Enhanced scout intelligence system automatically:
      # - Generates detailed scout encounter reports
      # - Tracks fleet movement history over time
      # - Tracks construction activity over multiple visits
      case scout.mission
      of SpyMissionType.SpyOnPlanet:
        echo "    Spy scout ", scoutId, " gathering planetary intelligence at system ", scoutLocation
        scout_intel.processScoutIntelligence(state, scoutId, scout.owner, scoutLocation)
        echo "      Enhanced colony intel: population, industry, defenses, construction tracking"

      of SpyMissionType.HackStarbase:
        echo "    Spy scout ", scoutId, " hacking starbase at system ", scoutLocation
        let report = intel_gen.generateStarbaseIntelReport(state, scout.owner, scoutLocation, intel_types.IntelQuality.Spy)
        if report.isSome:
          var house = state.houses[scout.owner]
          house.intelligence.addStarbaseReport(report.get())
          state.houses[scout.owner] = house
          echo "      Intel: Treasury ", report.get().treasuryBalance.get(0), " PP, Tax rate ", report.get().taxRate.get(0.0), "%"

      of SpyMissionType.SpyOnSystem:
        echo "    Spy scout ", scoutId, " conducting system surveillance at ", scoutLocation
        scout_intel.processScoutIntelligence(state, scoutId, scout.owner, scoutLocation)
        echo "      Enhanced system intel: fleet composition, movement patterns, cargo details"

  # Update spy scouts in game state (remove detected ones)
  state.spyScouts = survivingScouts

  # Process starbase surveillance (continuous monitoring every turn)
  echo "  Processing starbase surveillance..."
  var survRng = initRand(state.turn + 12345)  # Unique seed for surveillance
  starbase_surveillance.processAllStarbaseSurveillance(state, state.turn, survRng)

  # Convert colonies table to sequence for income phase
  # NOTE: No type conversion needed - gamestate.Colony has all economic fields
  var coloniesSeqIncome: seq[Colony] = @[]
  for systemId, colony in state.colonies:
    coloniesSeqIncome.add(colony)

  # Build house tax policies from House state
  var houseTaxPolicies = initTable[HouseId, econ_types.TaxPolicy]()
  for houseId, house in state.houses:
    houseTaxPolicies[houseId] = house.taxPolicy

  # Build house tech levels (Economic Level = economicLevel field)
  var houseTechLevels = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTechLevels[houseId] = house.techTree.levels.economicLevel  # EL = economicLevel (confusing naming)

  # Build house treasuries
  var houseTreasuries = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTreasuries[houseId] = house.treasury

  # Call economy engine
  let incomeReport = econ_engine.resolveIncomePhase(
    coloniesSeqIncome,
    houseTaxPolicies,
    houseTechLevels,
    houseTreasuries
  )

  # Apply results back to game state
  for houseId, houseReport in incomeReport.houseReports:
    # CRITICAL: Get house once, modify all fields, write back to persist
    var house = state.houses[houseId]
    house.treasury = houseTreasuries[houseId]
    # Store income report for intelligence gathering (HackStarbase missions)
    house.latestIncomeReport = some(houseReport)
    echo "    ", house.name, ": +", houseReport.totalNet, " PP (Gross: ", houseReport.totalGross, ")"

    # Update colony production fields from income reports
    for colonyReport in houseReport.colonies:
      if colonyReport.colonyId in state.colonies:
        # CRITICAL: Get colony, modify, write back to persist
        var colony = state.colonies[colonyReport.colonyId]
        colony.production = colonyReport.grossOutput
        state.colonies[colonyReport.colonyId] = colony

    # Apply prestige events from economic activities
    for event in houseReport.prestigeEvents:
      house.prestige += event.amount
      echo "      Prestige: ",
           (if event.amount > 0: "+" else: ""), event.amount,
           " (", event.description, ") -> ", house.prestige

    # Write back modified house
    state.houses[houseId] = house

    # Apply blockade prestige penalties
    # Per operations.md:6.2.6: "-2 prestige per colony under blockade"
    let blockadePenalty = blockade_engine.calculateBlockadePrestigePenalty(state, houseId)
    if blockadePenalty < 0:
      let blockadedCount = blockade_engine.getBlockadedColonies(state, houseId).len
      state.houses[houseId].prestige += blockadePenalty
      echo "      Prestige: ", blockadePenalty, " (", blockadedCount,
           " colonies under blockade) -> ", state.houses[houseId].prestige

  # Process construction completion - decrement turns and complete projects
  # NEW: Process ALL projects in construction queue (not just legacy single project)
  for systemId, colony in state.colonies.mpairs:
    # Process build queue (all projects in parallel)
    var completedProjects: seq[econ_types.ConstructionProject] = @[]
    var remainingProjects: seq[econ_types.ConstructionProject] = @[]

    # DEBUG: Log queue contents
    if colony.constructionQueue.len > 0:
      echo &"    DEBUG: System {systemId} has {colony.constructionQueue.len} projects in queue"
      for project in colony.constructionQueue:
        echo &"      - {project.itemId}: {project.turnsRemaining} turns remaining"

    for project in colony.constructionQueue.mitems:
      project.turnsRemaining -= 1

      if project.turnsRemaining <= 0:
        completedProjects.add(project)
      else:
        remainingProjects.add(project)

    # Process completed projects
    for project in completedProjects:
      if project.turnsRemaining <= 0:
        # Construction complete!
        echo "    Construction completed at system ", systemId, ": ", project.itemId

        case project.projectType
        of econ_types.ConstructionType.Ship:
          # Commission ship from Spaceport/Shipyard
          let shipClass = parseEnum[ShipClass](project.itemId)
          let techLevel = state.houses[colony.owner].techTree.levels.constructionTech

          # ARCHITECTURE FIX: Check if this is a spacelift ship (NOT a combat squadron)
          let isSpaceLift = shipClass in [ShipClass.ETAC, ShipClass.TroopTransport]

          # ARCHITECTURE FIX: Fighters go to colony.fighterSquadrons, not fleets
          let isFighter = shipClass == ShipClass.Fighter

          if isFighter:
            # Create fighter squadron at colony
            let fighterSq = FighterSquadron(
              id: $systemId & "-FS-" & $(colony.fighterSquadrons.len + 1),
              commissionedTurn: state.turn
            )

            colony.fighterSquadrons.add(fighterSq)
            echo "      Commissioned fighter squadron ", fighterSq.id, " at ", systemId
          elif isSpaceLift:
            # Create SpaceLiftShip (individual unit, not squadron)
            let shipId = colony.owner & "_" & $shipClass & "_" & $systemId & "_" & $state.turn
            var spaceLiftShip = newSpaceLiftShip(shipId, shipClass, colony.owner, systemId)

            # Auto-load PTU onto ETAC at commissioning with extraction cost
            # Larger colonies spare PTUs more cheaply due to exponential PU→PTU relationship
            # Formula: extraction_cost = 1.0 / (1.0 + 0.00657 * pu)
            # Examples: 100 PU colony loses 0.60 PU, 1000 PU colony loses only 0.13 PU
            # Note: Space Guild transfers will have ADDITIONAL costs beyond just extraction
            # See docs/specs/economy.md:15-27 for PTU mechanics
            if shipClass == ShipClass.ETAC and colony.population > 1:
              # Calculate extraction cost (PU lost from colony to create 1 PTU)
              let extractionCost = 1.0 / (1.0 + 0.00657 * colony.population.float)

              # Apply cost by reducing colony population (affects future GCO/production)
              let newPopulation = colony.population.float - extractionCost
              colony.population = max(1, newPopulation.int)

              # Load PTU onto ETAC
              spaceLiftShip.cargo.cargoType = CargoType.Colonists
              spaceLiftShip.cargo.quantity = 1
              logInfo(LogCategory.lcEconomy, &"Loaded 1 PTU onto {shipId} (extraction: {extractionCost:.2f} PU from {systemId})")

            colony.unassignedSpaceLiftShips.add(spaceLiftShip)
            logInfo(LogCategory.lcEconomy, &"Commissioned {shipClass} spacelift ship at {systemId}")

            # Auto-assign to fleets if enabled
            if colony.autoAssignFleets and colony.unassignedSpaceLiftShips.len > 0:
              # Find stationary fleets at this system
              for fleetId, fleet in state.fleets.mpairs:
                if fleet.location == systemId and fleet.owner == colony.owner:
                  # Transfer spacelift ship to fleet
                  fleet.spaceLiftShips.add(spaceLiftShip)
                  # Remove the spacelift ship we just assigned (it's the last one we added)
                  colony.unassignedSpaceLiftShips.delete(colony.unassignedSpaceLiftShips.len - 1)

                  # WARN if ETAC assigned without PTU (potential colonization failure)
                  if shipClass == ShipClass.ETAC and
                     (spaceLiftShip.cargo.cargoType != CargoType.Colonists or spaceLiftShip.cargo.quantity == 0):
                    logWarn(LogCategory.lcFleet, &"Empty ETAC {shipId} assigned to fleet {fleetId} - colonization will fail!")

                  logInfo(LogCategory.lcFleet, &"Auto-assigned {shipClass} to fleet {fleetId}")
                  break

          else:
            # Combat ship - create squadron as normal
            let newShip = newEnhancedShip(shipClass, techLevel)

            # Intelligent tactical squadron assignment
            # Try to add escorts to existing unassigned squadrons first (battle-ready groups)
            # Capital ships always create new squadrons (they're flagships)
            var addedToSquadron = false

            let isCapitalShip = shipClass in [
              ShipClass.Battleship, ShipClass.Dreadnought, ShipClass.SuperDreadnought,
              ShipClass.Carrier, ShipClass.SuperCarrier, ShipClass.Battlecruiser,
              ShipClass.HeavyCruiser, ShipClass.Cruiser
            ]

            let isEscort = shipClass in [
              ShipClass.Scout, ShipClass.Frigate, ShipClass.Destroyer,
              ShipClass.Corvette, ShipClass.LightCruiser
            ]

            # Escorts try to join existing unassigned squadrons for balanced combat groups
            if isEscort:
              # Try to join unassigned capital ship squadrons first
              for squadron in colony.unassignedSquadrons.mitems:
                let flagshipIsCapital = squadron.flagship.shipClass in [
                  ShipClass.Battleship, ShipClass.Dreadnought, ShipClass.SuperDreadnought,
                  ShipClass.Carrier, ShipClass.SuperCarrier, ShipClass.Battlecruiser,
                  ShipClass.HeavyCruiser, ShipClass.Cruiser
                ]
                if flagshipIsCapital and squadron.canAddShip(newShip):
                  squadron.ships.add(newShip)
                  echo "      Commissioned ", shipClass, " and added to unassigned capital squadron ", squadron.id
                  addedToSquadron = true
                  break

              # If no capital squadrons, try joining escort squadrons
              if not addedToSquadron:
                for squadron in colony.unassignedSquadrons.mitems:
                  if squadron.flagship.shipClass == shipClass and squadron.canAddShip(newShip):
                    squadron.ships.add(newShip)
                    echo "      Commissioned ", shipClass, " and added to unassigned escort squadron ", squadron.id
                    addedToSquadron = true
                    break

            # Capital ships and unassigned escorts create new squadrons at colony
            if not addedToSquadron:
              let squadronId = colony.owner & "_sq_" & $systemId & "_" & $state.turn & "_" & project.itemId
              let newSquadron = newSquadron(newShip, squadronId, colony.owner, systemId)
              colony.unassignedSquadrons.add(newSquadron)
              echo "      Commissioned ", shipClass, " into new unassigned squadron at ", systemId

            # Fleet Organization: Automatically organize newly-commissioned squadrons into fleets
            # This completes the economic production pipeline: Treasury → Construction → Commissioning → Fleet
            # Without this step, units remain in unassignedSquadrons and cannot execute operational orders
            # (e.g., scouts cannot perform espionage, carriers cannot deploy to defensive positions)
            if colony.autoAssignFleets and colony.unassignedSquadrons.len > 0:
              autoBalanceSquadronsToFleets(state, colony, systemId, orders)

        of econ_types.ConstructionType.Building:
          # Add building to colony
          if project.itemId == "Spaceport":
            let spaceportId = colony.owner & "_spaceport_" & $systemId & "_" & $state.turn
            let spaceport = Spaceport(
              id: spaceportId,
              commissionedTurn: state.turn,
              docks: 5  # 5 construction docks per spaceport
            )
            colony.spaceports.add(spaceport)
            echo "      Added Spaceport to system ", systemId

          elif project.itemId == "Shipyard":
            let shipyardId = colony.owner & "_shipyard_" & $systemId & "_" & $state.turn
            let shipyard = Shipyard(
              id: shipyardId,
              commissionedTurn: state.turn,
              docks: 10  # 10 construction docks per shipyard
            )
            colony.shipyards.add(shipyard)
            echo "      Added Shipyard to system ", systemId

          elif project.itemId == "GroundBattery":
            colony.groundBatteries += 1
            echo "      Added Ground Battery to system ", systemId

          elif project.itemId == "PlanetaryShield":
            # Set planetary shield level based on house's SLD tech
            colony.planetaryShieldLevel = state.houses[colony.owner].techTree.levels.shieldTech
            echo "      Added Planetary Shield (SLD", colony.planetaryShieldLevel, ") to system ", systemId

        of econ_types.ConstructionType.Industrial:
          # IU investment - industrial capacity was added when project started
          # Just log completion
          echo "      Industrial expansion completed at system ", systemId

        of econ_types.ConstructionType.Infrastructure:
          # Infrastructure was already added during creation
          # Just log completion
          echo "      Infrastructure expansion completed at system ", systemId

    # Update construction queue with remaining (in-progress) projects
    colony.constructionQueue = remainingProjects

    # LEGACY SUPPORT: Update underConstruction field for backwards compatibility
    # Keep the first in-progress project as the "active" one
    if remainingProjects.len > 0:
      colony.underConstruction = some(remainingProjects[0])
    else:
      colony.underConstruction = none(econ_types.ConstructionProject)

    # CRITICAL: Write back colony to persist ALL modifications in this loop iteration
    # Even with mpairs, nested seq/field modifications require explicit write-back:
    # - fighterSquadrons (commissioned fighters)
    # - unassignedSpaceLiftShips (commissioned transports/ETACs)
    # - population (ETAC PTU extraction cost)
    # - constructionQueue (completed/remaining projects)
    # - underConstruction (legacy field)
    state.colonies[systemId] = colony

  # Process research allocation
  # Per economy.md:4.0: Players allocate PP to research each turn
  # PP is converted to ERP/SRP/TRP based on current tech levels and GHO
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]
      let allocation = packet.researchAllocation

      # Calculate total PP cost for this research allocation
      var totalResearchCost = allocation.economic + allocation.science
      for field, pp in allocation.technology:
        totalResearchCost += pp

      # Scale down research allocation if treasury cannot afford it
      # Research is planned at AI time but processed after Income Phase
      # This prevents negative treasury from over-aggressive research budgets
      var scaledAllocation = allocation
      if totalResearchCost > state.houses[houseId].treasury:
        # Calculate scaling factor (how much we can actually afford)
        let affordablePercent = float(state.houses[houseId].treasury) / float(totalResearchCost)

        # Scale all allocations proportionally
        scaledAllocation.economic = int(float(allocation.economic) * affordablePercent)
        scaledAllocation.science = int(float(allocation.science) * affordablePercent)

        var scaledTech = initTable[TechField, int]()
        for field, pp in allocation.technology:
          scaledTech[field] = int(float(pp) * affordablePercent)
        scaledAllocation.technology = scaledTech

        # Recalculate actual cost
        totalResearchCost = scaledAllocation.economic + scaledAllocation.science
        for field, pp in scaledAllocation.technology:
          totalResearchCost += pp

        echo "      ", houseId, " research budget scaled down by ", int(affordablePercent * 100), "% due to treasury constraints"

      # Deduct research cost from treasury (CRITICAL FIX)
      # Research competes with builds for treasury resources
      if totalResearchCost > 0:
        state.houses[houseId].treasury -= totalResearchCost
        echo "      ", houseId, " spent ", totalResearchCost, " PP on research (treasury: ",
             state.houses[houseId].treasury + totalResearchCost, " → ", state.houses[houseId].treasury, ")"

      # Calculate GHO for this house
      var gho = 0
      for colony in state.colonies.values:
        if colony.owner == houseId:
          gho += colony.production

      # Get current tech levels
      let currentSL = state.houses[houseId].techTree.levels.scienceLevel  # Science Level

      # Convert PP allocations to RP (use SCALED allocation, not original)
      let earnedRP = res_costs.allocateResearch(scaledAllocation, gho, currentSL)

      # Accumulate RP
      state.houses[houseId].techTree.accumulated.economic += earnedRP.economic
      state.houses[houseId].techTree.accumulated.science += earnedRP.science

      for field, trp in earnedRP.technology:
        if field notin state.houses[houseId].techTree.accumulated.technology:
          state.houses[houseId].techTree.accumulated.technology[field] = 0
        state.houses[houseId].techTree.accumulated.technology[field] += trp

      # Log allocations (use SCALED allocation for accurate reporting)
      if scaledAllocation.economic > 0:
        echo "      ", houseId, " allocated ", scaledAllocation.economic, " PP → ", earnedRP.economic, " ERP",
             " (total: ", state.houses[houseId].techTree.accumulated.economic, " ERP)"
      if scaledAllocation.science > 0:
        echo "      ", houseId, " allocated ", scaledAllocation.science, " PP → ", earnedRP.science, " SRP",
             " (total: ", state.houses[houseId].techTree.accumulated.science, " SRP)"
      for field, pp in scaledAllocation.technology:
        if pp > 0 and field in earnedRP.technology:
          let totalTRP = state.houses[houseId].techTree.accumulated.technology.getOrDefault(field, 0)
          echo "      ", houseId, " allocated ", pp, " PP → ", earnedRP.technology[field], " TRP (", field, ")",
               " (total: ", totalTRP, " TRP)"

## Phase 3: Command


proc autoBalanceSquadronsToFleets(state: var GameState, colony: var gamestate.Colony, systemId: SystemId, orders: Table[HouseId, OrderPacket]) =
  ## Auto-assign unassigned squadrons to fleets at colony, balancing squadron count
  ##
  ## **Purpose:** Automatically organize newly-commissioned ships into operational fleets
  ## during the Construction & Commissioning phase of economy resolution.
  ##
  ## **Behavior:**
  ## 1. Looks for Active stationary fleets at colony (Hold orders or no orders)
  ## 2. If candidate fleets exist: distributes unassigned squadrons evenly across them
  ## 3. If NO candidate fleets exist: creates new single-squadron fleets for each unassigned squadron
  ##
  ## **Fleet Status Filtering:**
  ## - Only considers `FleetStatus.Active` fleets for auto-assignment
  ## - Excludes `FleetStatus.Reserve` (50% maintenance, reduced combat effectiveness)
  ## - Excludes `FleetStatus.Mothballed` (0% maintenance, offline storage)
  ##
  ## **Why This Matters:**
  ## This function is critical for AI operational effectiveness. Without it, newly-built
  ## units (especially scouts) remain in `colony.unassignedSquadrons` indefinitely and
  ## never execute their intended missions. For example, scouts cannot perform espionage
  ## missions unless they are organized into fleets.
  ##
  ## **Architecture Note:**
  ## This function lives in economy_resolution.nim because fleet organization from
  ## newly-commissioned ships is part of the industrial → military transition, not
  ## tactical fleet operations. It represents the final step in the economic production
  ## pipeline: Treasury → Construction → Commissioning → Fleet Organization.
  if colony.unassignedSquadrons.len == 0:
    return

  # Get all fleets at this colony owned by same house
  var candidateFleets: seq[FleetId] = @[]
  for fleetId, fleet in state.fleets:
    if fleet.owner == colony.owner and fleet.location == systemId:
      # Only consider Active fleets (exclude Reserve and Mothballed)
      if fleet.status != FleetStatus.Active:
        continue

      # Check if fleet has stationary orders (Hold or no orders)
      var isStationary = true

      # Check if fleet has orders
      if colony.owner in orders:
        for order in orders[colony.owner].fleetOrders:
          if order.fleetId == fleetId:
            # Fleet has orders - only stationary if Hold
            if order.orderType != FleetOrderType.Hold:
              isStationary = false
            break

      if isStationary:
        candidateFleets.add(fleetId)

  if candidateFleets.len == 0:
    # No existing stationary fleets - create new fleets for unassigned squadrons
    # Group squadrons by type to create role-specific fleets
    while colony.unassignedSquadrons.len > 0:
      let squadron = colony.unassignedSquadrons[0]
      let newFleetId = colony.owner & "_fleet_" & $systemId & "_" & $state.turn & "_" & squadron.id
      state.fleets[newFleetId] = Fleet(
        id: newFleetId,
        owner: colony.owner,
        location: systemId,
        squadrons: @[squadron]
      )
      colony.unassignedSquadrons.delete(0)
      echo "    Auto-created fleet ", newFleetId, " for unassigned squadron ", squadron.id
    return

  # Calculate target squadron count per fleet (balanced distribution)
  let totalSquadrons = colony.unassignedSquadrons.len +
                        candidateFleets.mapIt(state.fleets[it].squadrons.len).foldl(a + b, 0)
  let targetPerFleet = totalSquadrons div candidateFleets.len

  # Assign squadrons to fleets to reach target count
  for fleetId in candidateFleets:
    var fleet = state.fleets[fleetId]
    while fleet.squadrons.len < targetPerFleet and colony.unassignedSquadrons.len > 0:
      let squadron = colony.unassignedSquadrons[0]
      fleet.squadrons.add(squadron)
      colony.unassignedSquadrons.delete(0)
    state.fleets[fleetId] = fleet

proc autoLoadFightersToCarriers(state: var GameState, colony: var gamestate.Colony, systemId: SystemId, orders: Table[HouseId, OrderPacket]) =
  ## Auto-load colony-based fighters onto available carriers at colony
  ##
  ## **Purpose:** When fighters are commissioned or released from carrier ownership,
  ## automatically load them onto available carriers rather than leaving them at the colony.
  ##
  ## **Behavior:**
  ## 1. Find Active carriers at colony with available hangar capacity
  ## 2. Only consider stationary carriers (Hold orders or no orders)
  ## 3. Load fighters onto carriers until capacity is reached
  ## 4. Fighters remain at colony if no suitable carriers available
  ##
  ## **Carrier Requirements:**
  ## - Must be `FleetStatus.Active` (excludes Reserve/Mothballed)
  ## - Must have available hangar space (based on ACO tech level)
  ## - Must be stationary (Hold orders or no movement orders)
  ## - Must be at the colony location
  ##
  ## **Why This Matters:**
  ## Empty carriers represent wasted operational capacity. Auto-loading ensures
  ## carriers maintain their tactical effectiveness without requiring manual
  ## micromanagement. This is especially important for:
  ## - Newly commissioned fighters going directly to defense fleets
  ## - Fighters released after carrier capacity violations
  ## - Maintaining carrier readiness at defensive positions
  if colony.fighterSquadrons.len == 0:
    return

  # Get house's ACO tech level for carrier capacity calculation
  let house = state.houses.getOrDefault(colony.owner)
  let acoLevel = house.techTree.levels.advancedCarrierOps

  # Find all Active carriers at colony with available capacity
  var candidateCarriers: seq[tuple[fleetId: FleetId, squadronIdx: int]] = @[]

  for fleetId, fleet in state.fleets:
    if fleet.owner == colony.owner and fleet.location == systemId:
      # Only consider Active fleets
      if fleet.status != FleetStatus.Active:
        continue

      # Check if fleet has stationary orders (Hold or no orders)
      var isStationary = true
      if colony.owner in orders:
        for order in orders[colony.owner].fleetOrders:
          if order.fleetId == fleetId:
            # Fleet has orders - only stationary if Hold
            if order.orderType != FleetOrderType.Hold:
              isStationary = false
            break

      if not isStationary:
        continue

      # Find carrier squadrons with available capacity
      for idx, squadron in fleet.squadrons:
        if squadron.flagship.shipClass == ShipClass.Carrier:
          if squadron.hasAvailableHangarSpace(acoLevel):
            candidateCarriers.add((fleetId, idx))

  if candidateCarriers.len == 0:
    return

  # Load fighters onto carriers with available space
  var loadedCount = 0
  for carrier in candidateCarriers:
    if colony.fighterSquadrons.len == 0:
      break

    var fleet = state.fleets[carrier.fleetId]
    var squadron = fleet.squadrons[carrier.squadronIdx]

    # Load fighters until carrier is full
    while squadron.hasAvailableHangarSpace(acoLevel) and colony.fighterSquadrons.len > 0:
      let fighter = colony.fighterSquadrons[0]
      squadron.embarkedFighters.add(CarrierFighter(
        id: fighter.id,
        commissionedTurn: fighter.commissionedTurn
      ))
      colony.fighterSquadrons.delete(0)
      loadedCount += 1

    # Update squadron and fleet in state
    fleet.squadrons[carrier.squadronIdx] = squadron
    state.fleets[carrier.fleetId] = fleet

  if loadedCount > 0:
    echo "    Auto-loaded ", loadedCount, " fighters to carriers at ", systemId
