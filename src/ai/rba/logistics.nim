## RBA Logistics Module
##
## Comprehensive asset lifecycle management for ALL house assets
##
## Responsibilities:
## 1. **Asset Inventory Management** - Track all ships, units, structures across empire
## 2. **Lifecycle Optimization** - Reuse vs salvage vs mothball vs upgrade decisions
## 3. **Cargo Operations** - PTU/Marine loading, fleet supply management
## 4. **Fleet Composition** - Optimal ship mix for different mission types
## 5. **Resource Distribution** - PTU transfers, ship reassignments, supply chains
## 6. **Maintenance Optimization** - Mothball underutilized assets, reactivate when needed
## 7. **Asset Efficiency** - Identify idle/underperforming assets, reallocate
##
## Philosophy:
## The budget module decides WHAT to build and HOW MUCH to spend.
## The logistics module decides HOW to USE what you already have.
##
## Example:
## - Budget: "Build 3 frigates at Colony A (cost: 300 PP)"
## - Logistics: "Transfer 2 idle frigates from rear system to frontline (cost: 0 PP)"
##
## Good logistics = fewer builds needed = more PP for other objectives

import std/[tables, options, sequtils, algorithm, math, sets, strformat]
import std/logging
import ../../common/types/[core, units, tech]
import ../../engine/[gamestate, fog_of_war, orders, order_types, fleet, spacelift, logger]
import ../../engine/economy/maintenance
import ../common/types as ai_types
import ./controller_types
import ./intelligence  # For system analysis
import ./shared/colony_assessment  # Shared defense assessment
import ./diplomacy     # For getOwnedColonies, getOwnedFleets
import ./strategic     # For threat assessment

## =============================================================================
## ASSET INVENTORY TRACKING
## =============================================================================

type
  AssetInventory* = object
    ## Complete inventory of all house assets

    # Fleet Assets
    totalFleets*: int
    activeFleets*: seq[FleetId]         # Fleets in active status
    reserveFleets*: seq[FleetId]        # Fleets in reserve status
    mothballedFleets*: seq[FleetId]     # Fleets in mothballed status

    # Ship Counts by Class
    scouts*: int
    fighters*: int
    corvettes*: int
    frigates*: int
    destroyers*: int
    cruisers*: int
    battleships*: int
    dreadnoughts*: int
    carriers*: int
    etacs*: int
    transports*: int
    raiders*: int
    planetBreakers*: int

    # SpaceLift Ships (cargo capable)
    emptyETACs*: seq[tuple[fleetId: FleetId, shipCount: int]]
    emptyTransports*: seq[tuple[fleetId: FleetId, shipCount: int]]
    loadedETACs*: seq[tuple[fleetId: FleetId, ptu: int]]
    loadedTransports*: seq[tuple[fleetId: FleetId, marines: int]]

    # Defensive Assets (per colony)
    coloniesWithStarbase*: int
    coloniesWithGroundBattery*: int
    undefendedColonies*: seq[SystemId]

    # Strategic Reserves (high-value assets)
    emergencyPTU*: int                  # PTU stockpiled for emergencies

    # Economic Assets
    totalProduction*: int               # Sum of all colony production
    totalTreasury*: int                 # Current PP reserves
    maintenanceCost*: int               # Per-turn maintenance burden

proc buildAssetInventory*(filtered: FilteredGameState, houseId: HouseId): AssetInventory =
  ## Scan entire house assets and build comprehensive inventory
  ##
  ## This is the foundation of logistics - you can't manage what you don't measure

  result = AssetInventory()
  result.totalTreasury = filtered.ownHouse.treasury

  # Count fleets and ships
  for fleet in filtered.ownFleets:
    result.totalFleets += 1

    # Classify fleet by status (not by current order)
    case fleet.status
    of FleetStatus.Active:
      result.activeFleets.add(fleet.id)
    of FleetStatus.Reserve:
      result.reserveFleets.add(fleet.id)
    of FleetStatus.Mothballed:
      result.mothballedFleets.add(fleet.id)

    # Count ships by class
    for squadron in fleet.squadrons:
      case squadron.flagship.shipClass
      of ShipClass.Scout:
        result.scouts += 1
      of ShipClass.Fighter:
        result.fighters += 1
      of ShipClass.Corvette:
        result.corvettes += 1
      of ShipClass.Frigate:
        result.frigates += 1
      of ShipClass.Destroyer:
        result.destroyers += 1
      of ShipClass.LightCruiser, ShipClass.Cruiser, ShipClass.HeavyCruiser:
        result.cruisers += 1
      of ShipClass.Battlecruiser, ShipClass.Battleship:
        result.battleships += 1
      of ShipClass.Dreadnought, ShipClass.SuperDreadnought:
        result.dreadnoughts += 1
      of ShipClass.Carrier, ShipClass.SuperCarrier:
        result.carriers += 1
      of ShipClass.Raider:
        result.raiders += 1
      of ShipClass.ETAC:
        result.etacs += 1
      of ShipClass.TroopTransport:
        result.transports += 1
      of ShipClass.Starbase:
        discard  # Starbases counted separately per colony
      of ShipClass.PlanetBreaker:
        result.planetBreakers += 1

    # Track spacelift cargo status
    for spaceLift in fleet.spaceLiftShips:
      case spaceLift.shipClass
      of ShipClass.ETAC:
        if spaceLift.isEmpty:
          result.emptyETACs.add((fleet.id, 1))
        else:
          result.loadedETACs.add((fleet.id, spaceLift.cargo.quantity))
      of ShipClass.TroopTransport:
        if spaceLift.isEmpty:
          result.emptyTransports.add((fleet.id, 1))
        else:
          result.loadedTransports.add((fleet.id, spaceLift.cargo.quantity))
      else:
        discard

  # Count fighters at colonies
  for colony in filtered.ownColonies:
    result.fighters += colony.fighterSquadrons.len

  # Count defensive assets per colony
  for colony in filtered.ownColonies:
    result.totalProduction += colony.production

    # Check defensive assets using shared assessment
    let assessment = colony_assessment.assessColonyDefenseNeeds(colony, filtered)

    if assessment.hasStarbase:
      result.coloniesWithStarbase += 1
    if assessment.hasGroundDefense:
      result.coloniesWithGroundBattery += 1
    if assessment.needsReinforcement:
      result.undefendedColonies.add(colony.systemId)

  # TODO: Calculate maintenance costs (requires querying ship stats and maintenance rates)
  # For now, estimate based on fleet count (rough heuristic)
  result.maintenanceCost = result.totalFleets * 10  # Placeholder: ~10 PP/fleet average

## =============================================================================
## ASSET REALLOCATION STRATEGY
## =============================================================================

type
  ReallocationRecommendation* = object
    ## Recommendation for moving assets to better locations
    assetType*: string
    fromSystem*: SystemId
    toSystem*: SystemId
    reason*: string
    priorityScore*: float

proc identifyIdleAssets*(inventory: AssetInventory, filtered: FilteredGameState): seq[FleetId] =
  ## DEPRECATED: No longer needed after fleet lifecycle refactor
  ## Asset reallocation will be reimplemented if needed
  result = @[]

proc recommendAssetReallocations*(controller: AIController, inventory: AssetInventory,
                                  filtered: FilteredGameState): seq[ReallocationRecommendation] =
  ## Generate recommendations for moving assets to higher-value locations
  ##
  ## Examples:
  ## - Move idle frigates from core to frontier
  ## - Transfer scouts from saturated regions to unexplored sectors
  ## - Consolidate scattered defensive fleets into reserve pools
  ## - Move ETACs from low-production colonies to high-production shipyards

  result = @[]

  let idleFleets = identifyIdleAssets(inventory, filtered)

  for fleetId in idleFleets:
    # Find the fleet
    var targetFleet: Option[Fleet] = none(Fleet)
    for fleet in filtered.ownFleets:
      if fleet.id == fleetId:
        targetFleet = some(fleet)
        break

    if targetFleet.isNone:
      continue

    let fleet = targetFleet.get()

    # Find threatened colonies using intel
    var mostThreatenedColony: Option[tuple[systemId: SystemId, threatLevel: float]] = none(tuple[systemId: SystemId, threatLevel: float])
    for colony in filtered.ownColonies:
      # Check intel for threats near this colony
      var threatLevel = 0.0
      if colony.systemId in controller.intelligence:
        let report = controller.intelligence[colony.systemId]
        threatLevel = float(report.estimatedFleetStrength)

      # Undefended colonies with threats are priority (using shared assessment)
      let assessment = colony_assessment.assessColonyDefenseNeeds(colony, filtered)
      if assessment.needsReinforcement and threatLevel > 0:
        if mostThreatenedColony.isNone or threatLevel > mostThreatenedColony.get().threatLevel:
          mostThreatenedColony = some((colony.systemId, threatLevel))

    if mostThreatenedColony.isSome and fleet.location != mostThreatenedColony.get().systemId:
      # Recommend moving idle fleet to threatened colony
      result.add(ReallocationRecommendation(
        assetType: "Defense Fleet",
        fromSystem: fleet.location,
        toSystem: mostThreatenedColony.get().systemId,
        reason: &"Reinforce undefended colony (threat: {mostThreatenedColony.get().threatLevel:.0f})",
        priorityScore: mostThreatenedColony.get().threatLevel
      ))
      logInfo(LogCategory.lcAI, &"{controller.houseId} Reallocation: {fleetId} {fleet.location} → {mostThreatenedColony.get().systemId} (defense needed)")

## =============================================================================
## CARGO MANAGEMENT (Comprehensive)
## =============================================================================

proc generateCargoOrders*(controller: AIController, inventory: AssetInventory,
                         filtered: FilteredGameState): seq[CargoManagementOrder] =
  ## Generate all cargo loading/unloading orders for spacelift ships
  ##
  ## Priority order:
  ## 1. Load marines on transports for pending invasions (combat critical)
  ## 2. Load PTU on ETACs for pending colonizations (expansion critical)
  ## 3. Unload marines from transports after successful invasion (free capacity)
  ## 4. Emergency cargo transfers (besieged colonies, blockade running)

  result = @[]

  # CRITICAL PATH: Load transports for invasion operations
  for operation in controller.operations:
    if operation.operationType == ai_types.OperationType.Invasion:
      # Find transports in operation fleets
      for fleetId in operation.requiredFleets:
        # Find the fleet
        var targetFleet: Option[Fleet] = none(Fleet)
        for fleet in filtered.ownFleets:
          if fleet.id == fleetId:
            targetFleet = some(fleet)
            break

        if targetFleet.isNone:
          continue

        let fleet = targetFleet.get()

        # Check if fleet has empty transports at a colony
        var hasEmptyTransport = false
        for spaceLift in fleet.spaceLiftShips:
          if spaceLift.shipClass == ShipClass.TroopTransport and spaceLift.isEmpty:
            hasEmptyTransport = true
            break

        if hasEmptyTransport:
          # Find colony at fleet location to load marines
          for colony in filtered.ownColonies:
            if colony.systemId == fleet.location and colony.marines > 0:
              # Generate load order
              result.add(CargoManagementOrder(
                houseId: controller.houseId,
                colonySystem: colony.systemId,
                action: CargoManagementAction.LoadCargo,
                fleetId: fleet.id,
                cargoType: some(CargoType.Marines),
                quantity: some(1)  # Load 1 MD per transport
              ))
              logInfo(LogCategory.lcAI, &"{controller.houseId} Loading marines on transport {fleet.id} for invasion")
              break

  # EXPANSION PATH: Load ETACs for colonization
  for (fleetId, _) in inventory.emptyETACs:
    # Find the fleet with empty ETAC
    var targetFleet: Option[Fleet] = none(Fleet)
    for fleet in filtered.ownFleets:
      if fleet.id == fleetId:
        targetFleet = some(fleet)
        break

    if targetFleet.isNone:
      continue

    let fleet = targetFleet.get()

    # Check if fleet has colonize order (meaning it needs PTU)
    var needsPTU = false
    if fleet.id in filtered.ownFleetOrders:
      let order = filtered.ownFleetOrders[fleet.id]
      if order.orderType == FleetOrderType.Colonize:
        needsPTU = true

    if needsPTU:
      # Find colony at fleet location with available PTU
      for colony in filtered.ownColonies:
        if colony.systemId == fleet.location and colony.population > 1:
          # Generate load order (1 PTU = 1 population unit)
          result.add(CargoManagementOrder(
            houseId: controller.houseId,
            colonySystem: colony.systemId,
            action: CargoManagementAction.LoadCargo,
            fleetId: fleet.id,
            cargoType: some(CargoType.Colonists),
            quantity: some(1)  # Load 1 PTU per ETAC
          ))
          logInfo(LogCategory.lcAI, &"{controller.houseId} Loading colonists on ETAC {fleet.id}")
          break

  # EFFICIENCY PATH: Unload completed transports at colonies
  for (fleetId, _) in inventory.loadedTransports:
    var targetFleet: Option[Fleet] = none(Fleet)
    for fleet in filtered.ownFleets:
      if fleet.id == fleetId:
        targetFleet = some(fleet)
        break

    if targetFleet.isNone:
      continue

    let fleet = targetFleet.get()

    # Check if fleet is at a colony and not currently invading
    var atOwnColony = false
    for colony in filtered.ownColonies:
      if colony.systemId == fleet.location:
        atOwnColony = true
        break

    if atOwnColony:
      # Check if fleet has Hold order (invasion complete)
      var isIdle = false
      if fleet.id in filtered.ownFleetOrders:
        let order = filtered.ownFleetOrders[fleet.id]
        if order.orderType == FleetOrderType.Hold:
          isIdle = true
      else:
        isIdle = true

      if isIdle:
        # Unload marines to free capacity
        result.add(CargoManagementOrder(
          houseId: controller.houseId,
          colonySystem: fleet.location,
          action: CargoManagementAction.UnloadCargo,
          fleetId: fleet.id,
          cargoType: some(CargoType.Marines),
          quantity: some(0)  # 0 = unload all
        ))
        logInfo(LogCategory.lcAI, &"{controller.houseId} Unloading marines from transport {fleet.id} (mission complete)")

## =============================================================================
## POPULATION TRANSFER OPTIMIZATION
## =============================================================================

proc generatePopulationTransfers*(controller: AIController, inventory: AssetInventory,
                                 filtered: FilteredGameState): seq[PopulationTransferOrder] =
  ## Optimize PTU distribution using Space Guild instant transfers
  ##
  ## Cost: 1 PP per PTU transferred (economy.md Section 3.7)
  ## Benefit: Accelerate new colony growth, boost frontier defenses
  ##
  ## Transfer Strategy:
  ## - FROM: Mature core colonies (>100 IU, excess population)
  ## - TO: New frontier colonies (<50 IU, high growth potential)
  ## - AVOID: Transferring from threatened colonies (need population for defense)

  result = @[]

  # Only do transfers if treasury is healthy (>500 PP)
  if inventory.totalTreasury < 500:
    return @[]

  let myColonies = filtered.ownColonies

  # Identify donors (mature, safe colonies with excess population)
  var donors: seq[tuple[colony: Colony, score: float]] = @[]
  for colony in myColonies:
    # Check if mature (infrastructure >= 5)
    if colony.infrastructure < 5:
      continue

    # Check if has excess population (pop > 5)
    if colony.population <= 5:
      continue

    # Check if safe (no enemy fleets in intel reports nearby)
    var threatLevel = 0.0
    for systemId, report in controller.intelligence:
      # Check intel reports for enemy activity near this colony
      # (simplified - just checking if we have recent intel on threats)
      if report.hasColony and report.owner.isSome and report.owner.get() != controller.houseId:
        # Enemy colony detected - calculate threat
        threatLevel += 0.5

    # Safe colonies have low threat
    if threatLevel > 2.0:
      continue  # Too dangerous to transfer population away

    # Calculate donor score (higher = better donor)
    let donorScore = float(colony.infrastructure) + float(colony.population) - threatLevel
    donors.add((colony, donorScore))

    logInfo(LogCategory.lcAI, &"{controller.houseId} Donor candidate: {colony.systemId} (score: {donorScore:.1f})")

  # Identify recipients (new colonies with growth potential)
  var recipients: seq[tuple[colony: Colony, score: float]] = @[]
  for colony in myColonies:
    # Check if new (infrastructure < 5)
    if colony.infrastructure >= 5:
      continue

    # Check resource rating (VeryRich/Rich preferred)
    let resourceBonus = case colony.resources
      of ResourceRating.VeryRich: 3.0
      of ResourceRating.Rich: 2.0
      of ResourceRating.Abundant: 1.0
      else: 0.5

    # Check if frontier (has unexplored adjacent systems in intel)
    var frontierBonus = 0.0
    # Use intelligence to check if this is a frontier system
    if colony.systemId in controller.intelligence:
      let report = controller.intelligence[colony.systemId]
      if report.confidenceLevel < 1.0:  # Low confidence = frontier area
        frontierBonus = 1.0

    # Calculate recipient score (higher = better recipient)
    let recipientScore = resourceBonus + frontierBonus + (10.0 - float(colony.infrastructure))
    recipients.add((colony, recipientScore))

    logInfo(LogCategory.lcAI, &"{controller.houseId} Recipient candidate: {colony.systemId} (score: {recipientScore:.1f})")

  # Sort by score (best first)
  donors.sort(proc(a, b: auto): int =
    if a.score > b.score: -1 elif a.score < b.score: 1 else: 0)
  recipients.sort(proc(a, b: auto): int =
    if a.score > b.score: -1 elif a.score < b.score: 1 else: 0)

  # Generate transfers (match best donors with best recipients)
  let maxTransfers = min(min(donors.len, recipients.len), 3)  # Max 3 transfers per turn
  var ppBudget = inventory.totalTreasury div 10  # Use 10% of treasury for transfers

  for i in 0..<maxTransfers:
    if ppBudget <= 0:
      break

    let donor = donors[i].colony
    let recipient = recipients[i].colony

    # Transfer 1 PTU (costs 1 PP)
    if ppBudget >= 1:
      result.add(PopulationTransferOrder(
        sourceColony: donor.systemId,
        destColony: recipient.systemId,
        ptuAmount: 1
      ))
      ppBudget -= 1

      logInfo(LogCategory.lcAI, &"{controller.houseId} PTU transfer: {donor.systemId} → {recipient.systemId} (1 PTU, 1 PP)")

## =============================================================================
## FLEET LIFECYCLE: RESERVE / MOTHBALL / SALVAGE / REACTIVATE
## =============================================================================

type
  FleetLifecycleDecision* {.pure.} = enum
    KeepActive,     # Continue normal operations
    PlaceReserve,   # 50% maintenance, half AS/DS, can't move (ops.md 6.2.17)
    Mothball,       # 0% maintenance, offline, screened (ops.md 6.2.18)
    Salvage,        # Disband for 50% PC value (ops.md 6.2.16)
    Reactivate      # Return to active duty (ops.md 6.2.19)

proc evaluateFleetLifecycle*(fleet: Fleet, inventory: AssetInventory,
                             filtered: FilteredGameState): FleetLifecycleDecision =
  ## Determine optimal lifecycle state for a fleet
  ##
  ## Decision Tree:
  ## 1. SALVAGE if: Obsolete ships + treasury critical (<100 PP)
  ## 2. MOTHBALL if: Treasury low (<200 PP) + idle + safe system + has spaceport
  ## 3. RESERVE if: Treasury low (<300 PP) + idle + safe system + no spaceport
  ## 4. REACTIVATE if: Treasury healthy (>1000 PP) + not in combat
  ## 5. KEEP ACTIVE otherwise

  # TODO: Implement once we can query:
  # - Fleet tech level (is it obsolete?)
  # - Fleet location (is it in safe rear system?)
  # - Colony facilities (does system have spaceport for mothball?)
  # - Fleet idle status (is it doing anything useful?)

  # Placeholder logic:
  if inventory.totalTreasury < 100:
    # Critical treasury - consider salvaging obsolete fleets
    return FleetLifecycleDecision.Salvage
  elif inventory.totalTreasury < 200:
    # Low treasury - mothball idle fleets
    return FleetLifecycleDecision.Mothball
  elif inventory.totalTreasury < 300:
    # Moderate treasury - place on reserve
    return FleetLifecycleDecision.PlaceReserve
  else:
    return FleetLifecycleDecision.KeepActive

proc identifyReserveCandidates*(controller: AIController, inventory: AssetInventory,
                                filtered: FilteredGameState): seq[FleetId] =
  ## Find active fleets that should be placed on reserve status
  ##
  ## Reserve (ops.md 6.2.17):
  ## - 50% maintenance cost (better than active, not as good as mothball)
  ## - Half AS/DS in combat (still somewhat useful defensively)
  ## - Cannot move (must be at friendly colony)
  ##
  ## Use when:
  ## - Treasury stressed (200-300 PP) but not critical
  ## - Fleet needed for defense but not offense
  ## - No spaceport available for mothballing

  result = @[]

  if inventory.totalTreasury < 200 or inventory.totalTreasury > 300:
    return @[]  # Reserve only for moderate treasury stress

  # Track colonies that already have reserve fleets (one per colony limit)
  var coloniesWithReserve: HashSet[SystemId]
  for fleet in filtered.ownFleets:
    if fleet.status == FleetStatus.Reserve:
      coloniesWithReserve.incl(fleet.location)

  # Evaluate all active fleets
  for fleet in filtered.ownFleets:
    # Skip if already reserve/mothballed
    if fleet.status in [FleetStatus.Reserve, FleetStatus.Mothballed]:
      continue

    # Check if fleet is at a colony
    var atColony = false
    var hasSpaceport = false
    for colony in filtered.ownColonies:
      if colony.systemId == fleet.location:
        atColony = true
        hasSpaceport = colony.spaceports.len > 0
        break

    if not atColony:
      continue  # Reserve requires being at colony

    if hasSpaceport:
      continue  # Has spaceport - prefer mothball instead

    # One per colony limit
    if fleet.location in coloniesWithReserve:
      continue

    # Check if system is safe (no enemy threats in intel)
    var threatLevel = 0.0
    if fleet.location in controller.intelligence:
      let report = controller.intelligence[fleet.location]
      if report.estimatedFleetStrength > 0:
        threatLevel = float(report.estimatedFleetStrength)

    if threatLevel >= 100.0:
      continue  # System under threat, keep fleet active

    # Check if fleet is needed for active operations
    var neededForOperation = false
    for op in controller.operations:
      if fleet.id in op.requiredFleets:
        neededForOperation = true
        break

    if neededForOperation:
      continue  # Fleet assigned to operation, don't reserve

    # This fleet is a good candidate
    result.add(fleet.id)
    coloniesWithReserve.incl(fleet.location)  # Track for one-per-colony
    logInfo(LogCategory.lcAI, &"{controller.houseId} Reserve candidate: {fleet.id} at {fleet.location} (treasury={inventory.totalTreasury}PP, no spaceport, safe)")

proc identifyMothballCandidates*(controller: AIController, inventory: AssetInventory,
                                 filtered: FilteredGameState): seq[FleetId] =
  ## Find active fleets that should be mothballed to save maintenance
  ##
  ## Mothball (ops.md 6.2.18):
  ## - 0% maintenance (maximum savings)
  ## - Offline (no combat contribution)
  ## - Screened in combat (protected from destruction)
  ## - Just needs friendly colony (powered down in orbit)
  ## - 1-turn reactivation delay
  ##
  ## TWO mothballing paths:
  ## 1. FINANCIAL: Treasury stressed + high maintenance burden
  ## 2. IDLE FLEETS: Strategic redundancy in safe rear systems
  ##
  ## Philosophy: Mothball idle rear-area fleets, not "obsolete" ship classes.
  ## Swarm tactics (cheap ship masses) are valid strategy in simultaneous combat.

  result = @[]

  # Determine mothballing strategy
  var financialMothball = false
  var idleFleetMothball = false

  # Path 1: Financial stress mothballing
  if inventory.totalTreasury < 500:
    let maintenanceRatio = float(inventory.maintenanceCost) / float(inventory.totalProduction)
    if maintenanceRatio >= 0.15:  # 15%+ of production going to maintenance
      financialMothball = true
      logInfo(LogCategory.lcAI, &"{controller.houseId} Mothball: Financial stress (treasury={inventory.totalTreasury}PP, maint={maintenanceRatio*100:.1f}%)")

  # Path 2: Idle fleet mothballing (strategic redundancy management)
  if inventory.totalFleets >= 4:  # Have enough fleets to identify true redundancy
    idleFleetMothball = true
    logInfo(LogCategory.lcAI, &"{controller.houseId} Mothball: Idle fleet check (fleets={inventory.totalFleets})")

  if not financialMothball and not idleFleetMothball:
    return @[]

  # Track colonies that already have mothballed fleets (one per colony limit)
  var coloniesWithMothball: HashSet[SystemId]
  for fleet in filtered.ownFleets:
    if fleet.status == FleetStatus.Mothballed:
      coloniesWithMothball.incl(fleet.location)

  # Evaluate all active fleets
  for fleet in filtered.ownFleets:
    # Skip if already reserve/mothballed
    if fleet.status in [FleetStatus.Reserve, FleetStatus.Mothballed]:
      continue

    # Check if fleet is at a colony
    var atColony = false
    for colony in filtered.ownColonies:
      if colony.systemId == fleet.location:
        atColony = true
        break

    if not atColony:
      continue  # Mothball requires being at colony

    # One per colony limit
    if fleet.location in coloniesWithMothball:
      continue

    # Check if system is safe (use intel reports)
    var isSafeSystem = true
    if fleet.location in controller.intelligence:
      let report = controller.intelligence[fleet.location]
      if report.estimatedFleetStrength > 50:
        isSafeSystem = false  # Enemy fleet detected

    if not isSafeSystem:
      continue  # Don't mothball in threatened systems

    # Check if fleet is needed for active operations
    var neededForOperation = false
    for op in controller.operations:
      if fleet.id in op.requiredFleets:
        neededForOperation = true
        break

    if neededForOperation:
      continue  # Fleet assigned to operation, don't mothball

    # Check if this system has redundant fleets (multiple fleets at same colony)
    var fleetsAtThisSystem = 0
    for f in filtered.ownFleets:
      if f.location == fleet.location and f.status == FleetStatus.Active:
        fleetsAtThisSystem += 1

    let hasRedundancy = fleetsAtThisSystem > 1

    # Mothball decision based on active path
    var shouldMothball = false
    var reason = ""

    if financialMothball and isSafeSystem:
      # Financial path: mothball ANY fleet in safe system to reduce maintenance
      shouldMothball = true
      reason = "financial"
    elif idleFleetMothball and isSafeSystem and hasRedundancy and not neededForOperation:
      # Idle fleet path: mothball redundant fleets in safe rear systems
      # Only if: safe system + multiple fleets + not assigned to operation
      shouldMothball = true
      reason = "idle/redundant"

    if shouldMothball:
      result.add(fleet.id)
      coloniesWithMothball.incl(fleet.location)  # Track for one-per-colony
      logInfo(LogCategory.lcAI, &"{controller.houseId} Mothballing {fleet.id} ({reason}, fleets_here={fleetsAtThisSystem}, location={fleet.location})")

proc identifySalvageCandidates*(controller: AIController, inventory: AssetInventory,
                                filtered: FilteredGameState): seq[FleetId] =
  ## Find fleets that should be salvaged for immediate PP
  ##
  ## Salvage (ops.md 6.2.16):
  ## - Fleet disbanded permanently
  ## - Recover 50% of ships' PC value
  ## - Instant PP injection to treasury
  ## - Must be at friendly colony
  ##
  ## Use when:
  ## - Treasury CRITICAL (<100 PP) - need emergency funds
  ## - Fleet completely obsolete (tech level 2+ levels behind enemy)
  ## - Ships damaged beyond repair cost-effectively
  ## - Better to rebuild than maintain old ships

  result = @[]

  # Only salvage in dire financial circumstances
  if inventory.totalTreasury > 100:
    return @[]

  # Evaluate all active fleets
  for fleet in filtered.ownFleets:
    # Skip if already reserve/mothballed (they have lower maintenance anyway)
    if fleet.status in [FleetStatus.Reserve, FleetStatus.Mothballed]:
      continue

    # Check if fleet is at a colony
    var atColony = false
    for colony in filtered.ownColonies:
      if colony.systemId == fleet.location:
        atColony = true
        break

    if not atColony:
      continue  # Salvage requires being at colony

    # Don't salvage fleets needed for operations
    var neededForOperation = false
    for op in controller.operations:
      if fleet.id in op.requiredFleets:
        neededForOperation = true
        break

    if neededForOperation:
      continue  # Fleet assigned to operation, don't salvage

    # Calculate fleet tech level and damage
    var totalTechLevel = 0
    var squadronCount = 0
    var crippledCount = 0
    for squadron in fleet.squadrons:
      let techLevel = case squadron.flagship.shipClass
        of ShipClass.Corvette, ShipClass.Scout: 1
        of ShipClass.Frigate: 2
        of ShipClass.Destroyer, ShipClass.LightCruiser: 3
        of ShipClass.Cruiser, ShipClass.HeavyCruiser: 4
        of ShipClass.Battlecruiser, ShipClass.Battleship: 5
        of ShipClass.Dreadnought, ShipClass.SuperDreadnought: 6
        else: 3
      totalTechLevel += techLevel
      squadronCount += 1
      if squadron.flagship.isCrippled:
        crippledCount += 1

    let avgTechLevel = if squadronCount > 0: float(totalTechLevel) / float(squadronCount) else: 0.0
    let damageRatio = if squadronCount > 0: float(crippledCount) / float(squadronCount) else: 0.0

    # Salvage if very obsolete (tech < 2) OR heavily damaged (>50% crippled)
    let isVeryObsolete = avgTechLevel < 2.0
    let isHeavilyDamaged = damageRatio > 0.5

    if isVeryObsolete or isHeavilyDamaged:
      result.add(fleet.id)
      let reason = if isVeryObsolete: "obsolete" else: "damaged"
      logInfo(LogCategory.lcAI, &"{controller.houseId} SALVAGE candidate: {fleet.id} ({reason}, tech {avgTechLevel:.1f}, {damageRatio*100:.0f}% damaged)")

proc estimateFleetCombatPower(fleet: Fleet): int =
  ## Estimate fleet's total combat power (AS + DS)
  result = 0
  for squadron in fleet.squadrons:
    # Sum attack strength
    result += squadron.flagship.stats.attackStrength
    for ship in squadron.ships:
      result += ship.stats.attackStrength
    # Sum defense strength
    result += squadron.flagship.stats.defenseStrength
    for ship in squadron.ships:
      result += ship.stats.defenseStrength

proc estimateFleetTechLevel(fleet: Fleet): float =
  ## Calculate average tech level of fleet
  var totalTechLevel = 0
  var squadronCount = 0
  for squadron in fleet.squadrons:
    let techLevel = case squadron.flagship.shipClass
      of ShipClass.Corvette, ShipClass.Scout: 1
      of ShipClass.Frigate: 2
      of ShipClass.Destroyer, ShipClass.LightCruiser: 3
      of ShipClass.Cruiser, ShipClass.HeavyCruiser: 4
      of ShipClass.Battlecruiser, ShipClass.Battleship: 5
      of ShipClass.Dreadnought, ShipClass.SuperDreadnought: 6
      else: 3
    totalTechLevel += techLevel
    squadronCount += 1
  result = if squadronCount > 0: float(totalTechLevel) / float(squadronCount) else: 0.0

proc calculateFleetMaintenanceCost(fleet: Fleet, targetStatus: FleetStatus): int =
  ## Calculate total maintenance cost for a fleet at the target status
  ## Uses actual ship maintenance costs from economy/maintenance module
  result = 0
  for squadron in fleet.squadrons:
    # Flagship
    result += getShipMaintenanceCost(squadron.flagship.shipClass, squadron.flagship.isCrippled, targetStatus)
    # Escort ships
    for ship in squadron.ships:
      result += getShipMaintenanceCost(ship.shipClass, ship.isCrippled, targetStatus)

proc identifyReactivationCandidates*(controller: AIController, inventory: AssetInventory,
                                    filtered: FilteredGameState): seq[FleetId] =
  ## SMART REACTIVATION: Selective, cost-benefit based, operation-aware
  ##
  ## Priority order:
  ## 1. Operations need ships (even if treasury low)
  ## 2. Critical threats (selective, close defense gap)
  ## 3. Treasury recovered (gradual, reserve before mothball)

  result = @[]

  # Build a lookup of all inactive fleets with their stats
  type FleetCandidate = object
    fleetId: FleetId
    fleet: Fleet
    combatPower: int
    techLevel: float
    maintenanceCost: int
    isReserve: bool  # Reserve = 50% maint, Mothball = 100% maint
    location: SystemId

  var candidates: seq[FleetCandidate] = @[]

  # Gather reserve fleets
  for fleetId in inventory.reserveFleets:
    # Find fleet in ownFleets sequence
    for fleet in filtered.ownFleets:
      if fleet.id == fleetId:
        candidates.add(FleetCandidate(
          fleetId: fleetId,
          fleet: fleet,
          combatPower: estimateFleetCombatPower(fleet),
          techLevel: estimateFleetTechLevel(fleet),
          maintenanceCost: calculateFleetMaintenanceCost(fleet, FleetStatus.Active),  # Cost when reactivated
          isReserve: true,
          location: fleet.location
        ))
        break

  # Gather mothballed fleets
  for fleetId in inventory.mothballedFleets:
    # Find fleet in ownFleets sequence
    for fleet in filtered.ownFleets:
      if fleet.id == fleetId:
        candidates.add(FleetCandidate(
          fleetId: fleetId,
          fleet: fleet,
          combatPower: estimateFleetCombatPower(fleet),
          techLevel: estimateFleetTechLevel(fleet),
          maintenanceCost: calculateFleetMaintenanceCost(fleet, FleetStatus.Active),  # Cost when reactivated
          isReserve: false,
          location: fleet.location
        ))
        break

  if candidates.len == 0:
    return @[]  # Nothing to reactivate

  # =========================================================================
  # PRIORITY 1: OPERATION-DRIVEN REACTIVATION
  # =========================================================================
  # If we have planned operations, check if they need more ships

  for op in controller.operations:
    # Count active fleets assigned to this operation
    let assignedCount = op.requiredFleets.len

    # Determine if operation needs more ships
    let minRequired = case op.operationType
      of OperationType.Invasion: 3  # Need strong assault force
      of OperationType.Raid: 2      # Need fast strike team
      of OperationType.Defense: 2   # Need defensive screen
      of OperationType.Blockade: 1  # Can manage with one fleet

    if assignedCount < minRequired:
      # Operation needs more ships - reactivate closest capable fleets
      let needed = minRequired - assignedCount
      logInfo(LogCategory.lcAI, &"{controller.houseId} Operation at {op.targetSystem} needs {needed} more fleets")

      # Find candidates near the assembly point
      var nearbyFleets: seq[FleetCandidate] = @[]
      for candidate in candidates:
        if candidate.location == op.assemblyPoint or candidate.location == op.targetSystem:
          nearbyFleets.add(candidate)

      # If not enough nearby, consider all fleets
      if nearbyFleets.len < needed:
        nearbyFleets = candidates

      # Sort by combat power (strongest first)
      nearbyFleets.sort(proc(a, b: FleetCandidate): int = cmp(b.combatPower, a.combatPower))

      # Reactivate top N fleets needed
      for i in 0 ..< min(needed, nearbyFleets.len):
        result.add(nearbyFleets[i].fleetId)
        logInfo(LogCategory.lcAI, &"{controller.houseId} Reactivating {nearbyFleets[i].fleetId} for {op.operationType} operation (power={nearbyFleets[i].combatPower})")

      if result.len > 0:
        return result  # Operation needs are highest priority

  # =========================================================================
  # PRIORITY 2: THREAT-DRIVEN REACTIVATION (SELECTIVE)
  # =========================================================================
  # Calculate defense gap at threatened colonies

  for colony in filtered.ownColonies:
    # Check intelligence for threats at this colony
    if colony.systemId in controller.intelligence:
      let report = controller.intelligence[colony.systemId]
      let threatLevel = report.estimatedFleetStrength

      if threatLevel > 100:  # Significant threat detected
        # Calculate our current defense at this system
        var ourDefense = 0
        for fleetId, fleet in filtered.ownFleets:
          if fleet.owner == controller.houseId and fleet.location == colony.systemId and fleet.status == FleetStatus.Active:
            ourDefense += estimateFleetCombatPower(fleet)

        # Add starbase defense (simplified: 100 points per starbase)
        ourDefense += colony.starbases.len * 100

        let defenseGap = threatLevel - ourDefense

        if defenseGap > 50:  # Significant gap, need reinforcements
          logInfo(LogCategory.lcAI, &"{controller.houseId} Defense gap at {colony.systemId}: threat={threatLevel}, defense={ourDefense}, gap={defenseGap}")

          # Find fleets at this colony
          var localDefenders: seq[FleetCandidate] = @[]
          for candidate in candidates:
            if candidate.location == colony.systemId:
              localDefenders.add(candidate)

          # Sort by combat power per maintenance cost (efficiency)
          localDefenders.sort(proc(a, b: FleetCandidate): int =
            let aEfficiency = if a.maintenanceCost > 0: a.combatPower div a.maintenanceCost else: a.combatPower
            let bEfficiency = if b.maintenanceCost > 0: b.combatPower div b.maintenanceCost else: b.combatPower
            cmp(bEfficiency, aEfficiency)
          )

          # Reactivate only enough to close the gap
          var reactivatedPower = 0
          for candidate in localDefenders:
            if reactivatedPower < defenseGap:
              result.add(candidate.fleetId)
              reactivatedPower += candidate.combatPower
              logInfo(LogCategory.lcAI, &"{controller.houseId} Reactivating {candidate.fleetId} for defense (power={candidate.combatPower}, maint={candidate.maintenanceCost})")

          if result.len > 0:
            return result  # Threat response is high priority

  # =========================================================================
  # PRIORITY 3: TREASURY-DRIVEN REACTIVATION (GRADUAL)
  # =========================================================================

  # Healthy treasury (>1000 PP): Can afford to reactivate fleets
  if inventory.totalTreasury > 1000:
    # Calculate current average tech level of active fleet
    var activeTechSum = 0.0
    var activeFleetCount = 0
    for fleetId in inventory.activeFleets:
      for fleet in filtered.ownFleets:
        if fleet.id == fleetId:
          activeTechSum += estimateFleetTechLevel(fleet)
          activeFleetCount += 1
          break
    let avgActiveTech = if activeFleetCount > 0: activeTechSum / float(activeFleetCount) else: 3.0

    # Treasury 1000-2000: Reactivate reserve fleets (50% maint)
    if inventory.totalTreasury < 2000:
      for candidate in candidates:
        if candidate.isReserve:
          # Only reactivate if not obsolete
          if candidate.techLevel >= avgActiveTech - 1.0:
            result.add(candidate.fleetId)
            logInfo(LogCategory.lcAI, &"{controller.houseId} Reactivating reserve {candidate.fleetId} (treasury recovered, tech={candidate.techLevel:.1f})")
          else:
            logInfo(LogCategory.lcAI, &"{controller.houseId} Skipping obsolete reserve {candidate.fleetId} (tech={candidate.techLevel:.1f} vs avg={avgActiveTech:.1f})")
      return result

    # Treasury >2000: Reactivate mothballed fleets (0% → 100% maint jump)
    if inventory.totalTreasury >= 2000:
      for candidate in candidates:
        # Only reactivate non-obsolete fleets
        if candidate.techLevel >= avgActiveTech - 1.5:
          result.add(candidate.fleetId)
          let fleetType = if candidate.isReserve: "reserve" else: "mothballed"
          logInfo(LogCategory.lcAI, &"{controller.houseId} Reactivating {fleetType} {candidate.fleetId} (treasury healthy, tech={candidate.techLevel:.1f})")
        else:
          logInfo(LogCategory.lcAI, &"{controller.houseId} Skipping obsolete {candidate.fleetId} (tech={candidate.techLevel:.1f} vs avg={avgActiveTech:.1f})")
      return result

  # No reactivation criteria met
  return @[]

## =============================================================================
## FLEET COMPOSITION OPTIMIZATION
## =============================================================================

type
  FleetRole* {.pure.} = enum
    Invasion,      # Assault fleets: transports + escorts
    Defense,       # Interceptor fleets: fighters + fast ships
    Raid,          # Hit-and-run: raiders + cloaking ships
    Patrol,        # General purpose: balanced mix
    Blockade,      # Economic warfare: sustained presence
    Exploration    # Scout-heavy: discovery + intel

  OptimalComposition* = object
    ## Ideal ship mix for a given fleet role
    role*: FleetRole
    minScouts*: int
    minEscorts*: int          # Frigates/destroyers
    minCapitalShips*: int     # Cruisers/battleships
    minTransports*: int       # For invasion fleets
    minFighters*: int         # For carrier groups
    maxSlowShips*: int        # For raid fleets (no battleships)

proc getOptimalComposition*(role: FleetRole): OptimalComposition =
  ## Define ideal ship composition for each fleet role
  result.role = role

  case role
  of FleetRole.Invasion:
    result.minScouts = 1         # Intel gathering
    result.minEscorts = 3        # Screen transports
    result.minCapitalShips = 2   # Win space battle
    result.minTransports = 2     # Carry marines
    result.minFighters = 0       # Optional carrier support

  of FleetRole.Defense:
    result.minScouts = 1         # Early warning
    result.minEscorts = 5        # Intercept raiders
    result.minCapitalShips = 1   # Anchor defense
    result.minTransports = 0     # Not needed
    result.minFighters = 6       # Fighter screen

  of FleetRole.Raid:
    result.minScouts = 2         # Find targets
    result.minEscorts = 4        # Fast raiders
    result.minCapitalShips = 0   # Too slow
    result.maxSlowShips = 1      # Avoid battleships
    result.minTransports = 0     # Not assault

  of FleetRole.Patrol:
    result.minScouts = 1
    result.minEscorts = 2
    result.minCapitalShips = 1

  of FleetRole.Blockade:
    result.minScouts = 1         # Monitor system
    result.minEscorts = 3        # Sustained presence
    result.minCapitalShips = 2   # Deter breakout attempts

  of FleetRole.Exploration:
    result.minScouts = 3         # Primary mission
    result.minEscorts = 1        # Light escort
    result.minCapitalShips = 0   # Not needed

proc analyzeFleetComposition*(fleet: Fleet, role: FleetRole): tuple[compliant: bool, gaps: seq[string]] =
  ## Check if fleet has optimal composition for its role
  result.compliant = true
  result.gaps = @[]

  let optimal = getOptimalComposition(role)

  # TODO: Count ships by category in fleet
  # TODO: Compare against optimal composition
  # TODO: Generate list of gaps (e.g., "Need 2 more transports")

  # Example:
  # if fleet.transportCount < optimal.minTransports:
  #   result.compliant = false
  #   result.gaps.add(&"Need {optimal.minTransports - fleet.transportCount} more transports")

proc recommendFleetRebalancing*(controller: AIController, inventory: AssetInventory,
                                filtered: FilteredGameState): seq[SquadronManagementOrder] =
  ## Generate squadron transfer orders to optimize fleet compositions
  ##
  ## Strategy:
  ## 1. Analyze each fleet's role (based on orders/location)
  ## 2. Check if composition matches optimal for that role
  ## 3. Generate transfer orders to fix gaps
  ## 4. Source ships from idle fleets or reserves

  result = @[]

  # For now, implement basic fleet rebalancing for invasion operations
  for operation in controller.operations:
    if operation.operationType == ai_types.OperationType.Invasion:
      # Check if invasion fleets need transports
      for fleetId in operation.requiredFleets:
        var targetFleet: Option[Fleet] = none(Fleet)
        for fleet in filtered.ownFleets:
          if fleet.id == fleetId:
            targetFleet = some(fleet)
            break

        if targetFleet.isNone:
          continue

        let fleet = targetFleet.get()

        # Check if fleet has transports
        var hasTransport = false
        for spaceLift in fleet.spaceLiftShips:
          if spaceLift.shipClass == ShipClass.TroopTransport:
            hasTransport = true
            break

        if not hasTransport:
          # Need to add transport to this fleet
          # Find a colony with unassigned transports
          for colony in filtered.ownColonies:
            if colony.unassignedSpaceLiftShips.len > 0:
              # Found unassigned transport - add to fleet
              # (Note: Actual squadron management order would be generated here)
              # For now just log the need
              logInfo(LogCategory.lcAI, &"{controller.houseId} Fleet {fleetId} needs transport for invasion (found at {colony.systemId})")
              break

  # Additional rebalancing logic can be added here
  # - Transfer scouts to exploration fleets
  # - Consolidate damaged ships
  # - Balance fighter squadrons across carriers
  # etc.

## =============================================================================
## LOGISTICS MASTER PLANNER
## =============================================================================

proc generateLogisticsOrders*(controller: AIController, filtered: FilteredGameState,
                              currentAct: ai_types.GameAct): tuple[
                                cargo: seq[CargoManagementOrder],
                                population: seq[PopulationTransferOrder],
                                squadrons: seq[SquadronManagementOrder],
                                fleetOrders: seq[FleetOrder]
                              ] =
  ## Master function to generate ALL logistics-related orders
  ##
  ## This is called by orders.nim to handle asset lifecycle management
  ## BEFORE budget module generates new build orders
  ##
  ## Philosophy: Use what you have before building more

  # Step 1: Build comprehensive asset inventory
  let inventory = buildAssetInventory(filtered, controller.houseId)

  logInfo(LogCategory.lcAI, &"{controller.houseId} Logistics: {inventory.totalFleets} fleets, " &
                           &"{inventory.scouts} scouts, {inventory.etacs} ETACs, " &
                           &"{inventory.undefendedColonies.len} undefended colonies")

  # Step 2: Generate cargo orders (highest priority - combat/expansion critical)
  result.cargo = generateCargoOrders(controller, inventory, filtered)

  # Step 3: Generate population transfers (optimize growth)
  result.population = generatePopulationTransfers(controller, inventory, filtered)

  # Step 4: Optimize fleet compositions for operations
  result.squadrons = recommendFleetRebalancing(controller, inventory, filtered)

  # Step 5: Fleet lifecycle management (Reserve/Mothball/Salvage/Reactivate)
  result.fleetOrders = @[]

  # Fleet lifecycle management based on treasury health
  # NOTE: Functions have their own internal checks, we just call them based on general conditions

  if inventory.totalTreasury < 100:
    # CRITICAL treasury - salvage obsolete fleets for emergency PP
    let salvageCandidates = identifySalvageCandidates(controller, inventory, filtered)
    for fleetId in salvageCandidates:
      result.fleetOrders.add(FleetOrder(
        fleetId: fleetId,
        orderType: FleetOrderType.Salvage,
        targetSystem: none(SystemId),
        targetFleet: none(FleetId),
        priority: 200  # Highest priority - emergency funds
      ))
      logInfo(LogCategory.lcAI, &"{controller.houseId} SALVAGING fleet {fleetId} for emergency PP (treasury critical)")

  # Check for mothball candidates (handles both financial + obsolescence paths)
  let mothballCandidates = identifyMothballCandidates(controller, inventory, filtered)
  for fleetId in mothballCandidates:
    result.fleetOrders.add(FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Mothball,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 150
    ))
    logInfo(LogCategory.lcAI, &"{controller.houseId} Mothballing fleet {fleetId} (0% maint)")

  if inventory.totalTreasury >= 200 and inventory.totalTreasury <= 300:
    # MODERATE treasury - check for reserve candidates
    let reserveCandidates = identifyReserveCandidates(controller, inventory, filtered)
    for fleetId in reserveCandidates:
      result.fleetOrders.add(FleetOrder(
        fleetId: fleetId,
        orderType: FleetOrderType.Reserve,
        targetSystem: none(SystemId),
        targetFleet: none(FleetId),
        priority: 125
      ))
      logInfo(LogCategory.lcAI, &"{controller.houseId} Placing fleet {fleetId} on reserve (50% maint, half combat)")

  if inventory.totalTreasury > 1000:
    # HEALTHY treasury - reactivate mothballed/reserve fleets
    let reactivationCandidates = identifyReactivationCandidates(controller, inventory, filtered)
    for fleetId in reactivationCandidates:
      result.fleetOrders.add(FleetOrder(
        fleetId: fleetId,
        orderType: FleetOrderType.Reactivate,
        targetSystem: none(SystemId),
        targetFleet: none(FleetId),
        priority: 100
      ))
      logInfo(LogCategory.lcAI, &"{controller.houseId} Reactivating fleet {fleetId} (treasury recovered, full combat)")

## =============================================================================
## DIAGNOSTIC HELPER
## =============================================================================

proc generateLogisticsSummary*(controller: AIController, filtered: FilteredGameState): string =
  ## Generate human-readable logistics report for debugging
  let inventory = buildAssetInventory(filtered, controller.houseId)

  result = &"""
=== Logistics Summary: {controller.houseId} ===
Treasury: {inventory.totalTreasury} PP
Production: {inventory.totalProduction} PP/turn
Maintenance: {inventory.maintenanceCost} PP/turn ({float(inventory.maintenanceCost)/float(inventory.totalProduction)*100:.1f}%)

FLEET ASSETS:
- Total Fleets: {inventory.totalFleets}
- Active: {inventory.activeFleets.len}
- Reserve: {inventory.reserveFleets.len}
- Mothballed: {inventory.mothballedFleets.len}

SHIP INVENTORY:
- Scouts: {inventory.scouts}
- Escorts: {inventory.corvettes + inventory.frigates + inventory.destroyers}
- Capital Ships: {inventory.cruisers + inventory.battleships + inventory.dreadnoughts}
- Carriers: {inventory.carriers} (fighters: {inventory.fighters})
- ETACs: {inventory.etacs}
- Transports: {inventory.transports}
- Raiders: {inventory.raiders}
- Planet-Breakers: {inventory.planetBreakers}

DEFENSIVE ASSETS:
- Colonies with Starbase: {inventory.coloniesWithStarbase}
- Colonies with Ground Batteries: {inventory.coloniesWithGroundBattery}
- Undefended Colonies: {inventory.undefendedColonies.len}

CARGO STATUS:
- Empty ETACs: {inventory.emptyETACs.len}
- Loaded ETACs: {inventory.loadedETACs.len}
- Empty Transports: {inventory.emptyTransports.len}
- Loaded Transports: {inventory.loadedTransports.len}
"""
