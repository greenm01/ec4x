## AI Controller - Test/Balance Interface
##
## This file provides the interface for balance testing.
## Core AI logic is in src/ai/rba/, this file adds the high-level order generation
## functions needed by the test harness.

# Import production RBA
import ../../src/ai/rba/player
export player

# Import remaining dependencies for order generation
import std/[random, strformat, options, tables, algorithm, sequtils, hashes]
import ../../src/engine/[gamestate, fog_of_war, orders, logger, fleet, squadron, starmap]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/diplomacy/types as dip_types
import ../../src/engine/diplomacy/proposals as dip_proposals
import ../../src/engine/economy/construction
import ../../src/common/types/[core, units, tech, planets]

# =============================================================================
# Helper Functions (temporary - will be moved to production in future refactor)
# =============================================================================

proc identifyEconomicTargets*(controller: var AIController, filtered: FilteredGameState): seq[tuple[systemId: SystemId, value: float]] =
  ## Find best targets for economic warfare (blockades, raids)
  result = @[]

  let econIntel = controller.gatherEconomicIntelligence(filtered)

  for intel in econIntel:
    # Target high-value colonies of economically strong enemies
    if intel.economicStrength > 0.8:  # Only target if they're competitive
      for systemId in intel.highValueTargets:
        let colonyOpt = getColony(filtered, systemId)
        if colonyOpt.isNone:
          continue  # Can't see this colony
        let colony = colonyOpt.get()
        var value = float(colony.production)

        # Bonus for rich resources (denying them is valuable)
        if colony.resources in [ResourceRating.VeryRich, ResourceRating.Rich]:
          value *= 1.5

        result.add((systemId: systemId, value: value))

  # Sort by value (highest first)
  result.sort(proc(a, b: tuple[systemId: SystemId, value: float]): int =
    if b.value > a.value: 1
    elif b.value < a.value: -1
    else: 0
  )

proc shouldBuildMarines*(controller: AIController, filtered: FilteredGameState, colony: Colony): bool =
  ## Marines are for INVASIONS, not garrison defense
  ## Build marines when planning invasions and have/building transports
  let p = controller.personality
  let house = filtered.ownHouse

  # Don't build marines in early game - prioritize colonization
  let totalSystems = filtered.starMap.systems.len
  let targetColonies = max(5, totalSystems div 6)
  let isEarlyGame = filtered.ownColonies.len < targetColonies
  if isEarlyGame:
    return false

  # Only aggressive AIs build marines for invasion
  if p.aggression < 0.4:
    return false

  # Count existing transports and marines
  var transportCount = 0
  var totalTransportCapacity = 0
  var loadedMarines = 0

  for fleet in filtered.ownFleets:
    if fleet.owner != controller.houseId:
      continue
    for transport in fleet.spaceLiftShips:
      if transport.shipClass == ShipClass.TroopTransport:
        transportCount += 1
        totalTransportCapacity += transport.cargo.capacity
        loadedMarines += transport.cargo.quantity

  # If we have transports, build marines to fill them
  if transportCount > 0:
    let marinesNeeded = totalTransportCapacity - loadedMarines
    if marinesNeeded > 0:
      return true

  # If aggressive and have transports, keep small stockpile
  if p.aggression > 0.6 and transportCount > 0:
    let totalMarines = colony.marines
    if totalMarines < 3:
      return true

  return false

proc findNearestUncolonizedSystem(filtered: FilteredGameState, fromSystem: SystemId, fleetId: FleetId): Option[SystemId] =
  ## Find nearest uncolonized system using cube distance
  type SystemDist = tuple[systemId: SystemId, distance: int]
  var candidates: seq[SystemDist] = @[]

  let fromCoords = filtered.starMap.systems[fromSystem].coords

  for systemId, system in filtered.starMap.systems:
    if not isSystemColonized(filtered, systemId):
      # Calculate cube distance
      let dx = abs(system.coords.q - fromCoords.q)
      let dy = abs(system.coords.r - fromCoords.r)
      let dz = abs((system.coords.q + system.coords.r) - (fromCoords.q + fromCoords.r))
      let distance = (dx + dy + dz) div 2
      let item: SystemDist = (systemId: systemId, distance: distance)
      candidates.add(item)

  if candidates.len > 0:
    # Sort by distance
    candidates.sort(proc(a, b: SystemDist): int = cmp(a.distance, b.distance))

    # Use fleetId hash for deterministic but unique selection
    let minDistance = candidates[0].distance
    var closestSystems: seq[SystemId] = @[]
    for candidate in candidates:
      if candidate.distance == minDistance:
        closestSystems.add(candidate.systemId)
      else:
        break

    if closestSystems.len > 1:
      let fleetHash = hash(fleetId)
      let selectedIdx = (fleetHash and 0x7FFFFFFF) mod closestSystems.len
      return some(closestSystems[selectedIdx])
    else:
      return some(closestSystems[0])

  return none(SystemId)

# =============================================================================
# Order Generation
# =============================================================================

proc generateFleetOrders(controller: var AIController, filtered: FilteredGameState, rng: var Rand): seq[FleetOrder] =
  ## Generate fleet orders based on strategic military assessment
  ## Now updates intelligence when making decisions
  when not defined(release):
    logDebug(LogCategory.lcAI, &"{controller.houseId} generateFleetOrders called for turn {filtered.turn}")
  result = @[]
  let p = controller.personality
  let myFleets = getOwnedFleets(filtered, controller.houseId)
  when not defined(release):
    logDebug(LogCategory.lcAI, &"{controller.houseId} has {myFleets.len} fleets")

  # Update intelligence for systems we have visibility on
  # (Our colonies + systems with our fleets = automatic intel)
  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      controller.updateIntelligence(filtered, colony.systemId, filtered.turn, 1.0)

  for fleet in myFleets:
    # Fleets give us visibility into their current system
    controller.updateIntelligence(filtered, fleet.location, filtered.turn, 0.8)

  # Update coordinated operations status
  controller.updateOperationStatus(filtered)
  controller.removeCompletedOperations(filtered.turn)

  for fleet in myFleets:
    var order: FleetOrder
    order.fleetId = fleet.id
    order.priority = 1

    # Check current location for combat situation
    let currentCombat = assessCombatSituation(
      controller, filtered, fleet.location
    )

    # BALANCE FIX: Priority 0 - Stay at colony to absorb unassigned squadrons
    # If at a friendly colony with unassigned squadrons, hold position so auto-assign works
    if isSystemColonized(filtered, fleet.location):
      let colonyOpt = getColony(filtered, fleet.location)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        if colony.owner == controller.houseId and colony.unassignedSquadrons.len > 0:
          # Stay at colony to pick up newly built ships
          order.orderType = FleetOrderType.Hold
          order.targetSystem = some(fleet.location)
          order.targetFleet = none(FleetId)
          result.add(order)
          continue

    # Priority 0.5: Coordinated Operations
    # Check if this fleet is part of a coordinated operation
    for op in controller.operations:
      if fleet.id in op.requiredFleets:
        # Fleet is part of coordinated operation
        if fleet.location != op.assemblyPoint:
          # Not at assembly point - issue Rendezvous order
          order.orderType = FleetOrderType.Rendezvous
          order.targetSystem = some(op.assemblyPoint)
          order.targetFleet = none(FleetId)
          result.add(order)
          continue
        elif controller.shouldExecuteOperation(op, filtered.turn):
          # At assembly point and ready to execute
          case op.operationType
          of OperationType.Invasion:
            order.orderType = FleetOrderType.Invade
            order.targetSystem = some(op.targetSystem)
          of OperationType.Raid:
            order.orderType = FleetOrderType.Blitz
            order.targetSystem = some(op.targetSystem)
          of OperationType.Blockade:
            order.orderType = FleetOrderType.BlockadePlanet
            order.targetSystem = some(op.targetSystem)
          of OperationType.Defense:
            order.orderType = FleetOrderType.Patrol
            order.targetSystem = some(op.targetSystem)
          order.targetFleet = none(FleetId)
          result.add(order)
          continue
        else:
          # At assembly but not ready - hold position
          order.orderType = FleetOrderType.Hold
          order.targetSystem = some(fleet.location)
          order.targetFleet = none(FleetId)
          result.add(order)
          continue

    # Priority 0.75: Strategic Reserve Threat Response
    # Check if this fleet is a reserve responding to a nearby threat
    let threats = controller.respondToThreats(filtered)
    var isRespondingToThreat = false
    for threat in threats:
      if threat.reserveFleet == fleet.id:
        # Reserve fleet should move to intercept threat
        order.orderType = FleetOrderType.Move
        order.targetSystem = some(threat.threatSystem)
        order.targetFleet = none(FleetId)
        result.add(order)
        isRespondingToThreat = true
        break

    if isRespondingToThreat:
      continue

    # Priority 1: Retreat if we're in a losing battle
    if currentCombat.recommendRetreat:
      # Phase 2h: Use designated fallback system if available
      var retreatTarget = controller.findFallbackSystem(fleet.location)

      # Fallback: Find nearest friendly colony
      if retreatTarget.isNone:
        var minDist = 999
        let fromCoords = filtered.starMap.systems[fleet.location].coords
        for colony in filtered.ownColonies:
          if colony.owner == controller.houseId and colony.systemId != fleet.location:
            let toCoords = filtered.starMap.systems[colony.systemId].coords
            let dx = abs(toCoords.q - fromCoords.q)
            let dy = abs(toCoords.r - fromCoords.r)
            let dz = abs((toCoords.q + toCoords.r) - (fromCoords.q + fromCoords.r))
            let dist = (dx + dy + dz) div 2
            if dist < minDist:
              minDist = dist
              retreatTarget = some(colony.systemId)

      if retreatTarget.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = retreatTarget
        order.targetFleet = none(FleetId)
        result.add(order)
        continue
      # If no friendly colonies, hold and hope for the best
      order.orderType = FleetOrderType.Hold
      order.targetSystem = none(SystemId)
      order.targetFleet = none(FleetId)
      result.add(order)
      continue

    # Priority 2: Attack if we have good odds
    if currentCombat.recommendAttack:
      # We're already at an enemy system with good odds
      # Stay and fight (patrol to maintain presence)
      order.orderType = FleetOrderType.Patrol
      order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)
      result.add(order)
      continue

    # Priority 2.5: Check if fleet needed for colony defense (Phase 2f)
    # Before committing to offensive operations, ensure important/frontier colonies defended
    var undefendedColony: Option[SystemId] = none(SystemId)

    # First: Check important colonies (production >= 30 or strategic resources)
    let importantColonies = controller.identifyImportantColonies(filtered)
    for systemId in importantColonies:
      var hasDefense = false
      for otherFleet in myFleets:
        if otherFleet.location == systemId and otherFleet.id != fleet.id:
          hasDefense = true
          break
      let colonyOpt = getColony(filtered, systemId)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        if colony.starbases.len > 0:
          hasDefense = true
      if not hasDefense:
        undefendedColony = some(systemId)
        break

    # Second: Check frontier colonies (adjacent to enemy territory)
    if undefendedColony.isNone:
      for colony in filtered.ownColonies:
        if colony.owner != controller.houseId:
          continue
        var isFrontier = false
        let adjacentIds = filtered.starMap.getAdjacentSystems(colony.systemId)
        for neighborId in adjacentIds:
          let neighborColony = getColony(filtered, neighborId)
          if neighborColony.isSome and neighborColony.get().owner != controller.houseId:
            isFrontier = true
            break
        if isFrontier:
          var hasDefense = false
          for otherFleet in myFleets:
            if otherFleet.location == colony.systemId and otherFleet.id != fleet.id:
              hasDefense = true
              break
          if colony.starbases.len > 0:
            hasDefense = true
          if not hasDefense:
            undefendedColony = some(colony.systemId)
            break

    # If colony needs defense, position there instead of attacking
    if undefendedColony.isSome:
      if fleet.location != undefendedColony.get():
        order.orderType = FleetOrderType.Move
        order.targetSystem = undefendedColony
      else:
        order.orderType = FleetOrderType.Patrol
        order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)
      result.add(order)
      continue

    # Priority 3: Find targets to attack based on aggression OR military focus
    let militaryFocus = 1.0 - p.economicFocus
    let shouldSeekTargets = p.aggression > 0.3 or militaryFocus > 0.7

    if shouldSeekTargets:
      # Look for vulnerable enemy colonies
      var bestTarget: Option[SystemId] = none(SystemId)
      var bestOdds = 0.0

      # Economic Warfare - prioritize high-value economic targets
      # if we're economically focused (lower aggression, higher economic focus)
      if p.economicFocus > 0.6 and p.aggression < 0.6:
        # Get economic targets for warfare
        let econTargets = controller.identifyEconomicTargets(filtered)

        # Find best economic target we can reach
        for target in econTargets:
          let combat = assessCombatSituation(controller, filtered, target.systemId)
          # For economic warfare, we prefer blockades over invasions
          # Target high-value economies even with moderate odds
          if combat.estimatedCombatOdds > 0.4:  # Lower threshold for economic targets
            bestTarget = some(target.systemId)
            bestOdds = combat.estimatedCombatOdds
            break  # Take first viable economic target (already sorted by value)

      # If no economic target found (or not economically focused), use standard military targeting
      if bestTarget.isNone:
        # DEBUG: Log visibility for invasion targeting
        if filtered.visibleColonies.len > 0:
          var enemyCount = 0
          for colony in filtered.visibleColonies:
            if colony.owner != controller.houseId:
              enemyCount += 1
          if enemyCount > 0:
            logInfo(LogCategory.lcAI, &"{controller.houseId} sees {enemyCount} enemy colonies for invasion targeting")

        for colony in filtered.visibleColonies:
          if colony.owner == controller.houseId:
            continue  # Skip our own colonies

          let combat = assessCombatSituation(controller, filtered, colony.systemId)
          if combat.recommendAttack and combat.estimatedCombatOdds > bestOdds:
            bestOdds = combat.estimatedCombatOdds
            bestTarget = some(colony.systemId)

      if bestTarget.isSome:
        # ARCHITECTURE FIX: Check if fleet has troop transports (spacelift ships)
        var hasTransports = false
        for spaceLiftShip in fleet.spaceLiftShips:
          if spaceLiftShip.shipClass == ShipClass.TroopTransport:
            hasTransports = true
            break

        # IMPROVEMENT: Use 3-phase invasion viability assessment
        # Invasions give +10 prestige (highest reward!) - prioritize them
        if hasTransports:
          # Perform comprehensive 3-phase invasion assessment
          let invasion = assessInvasionViability(controller, filtered, fleet, bestTarget.get)

          if invasion.recommendInvade:
            # Full invasion - can win all 3 phases (space, starbase, ground)
            order.orderType = FleetOrderType.Invade
          elif invasion.recommendBlitz:
            # Blitz - can win space + starbase, but not ground
            # Still gets +5 prestige for starbase destruction
            order.orderType = FleetOrderType.Blitz
          elif invasion.recommendBlockade:
            # Too strong to invade, use economic warfare
            order.orderType = FleetOrderType.BlockadePlanet
          else:
            # Not viable - just do space combat
            order.orderType = FleetOrderType.Move
        else:
          # No transports, just move to attack (space combat only)
          order.orderType = FleetOrderType.Move

        order.targetSystem = bestTarget
        order.targetFleet = none(FleetId)
        result.add(order)
        continue

    # Priority 3.5: Scout Reconnaissance Missions
    # Check if this is a scout-only fleet (single squadron with scouts)
    var isScoutFleet = false
    var hasOnlyScouts = false
    if fleet.squadrons.len == 1:
      let squadron = fleet.squadrons[0]
      # Single-squadron scout fleets are ideal for spy missions (per operations.md:45)
      if squadron.flagship.shipClass == ShipClass.Scout and squadron.ships.len == 0:
        isScoutFleet = true
        hasOnlyScouts = true

    # PHASE 2G: Enhanced espionage mission targeting
    # Scouts should actively gather intelligence, not just for colonization/invasion
    if isScoutFleet:
      # Intelligence operations for scouts
      # Priority: Strategic intel > Pre-colonization recon > Pre-invasion intel

      # A) Strategic intelligence gathering - HackStarbase on enemy production centers
      # Target: Enemy colonies with high production or shipyards
      if p.techPriority > 0.3 or (1.0 - p.economicFocus) > 0.5:
        var highValueTargets: seq[SystemId] = @[]
        for colony in filtered.ownColonies:
          if colony.owner != controller.houseId:
            # High-value targets: production > 50 OR has shipyards
            if colony.production > 50 or colony.shipyards.len > 0:
              # Check if we need fresh intel (data older than 10 turns)
              if needsReconnaissanceController(controller, colony.systemId, filtered.turn):
                highValueTargets.add(colony.systemId)

        if highValueTargets.len > 0:
          # Pick closest high-value target
          var closest: Option[SystemId] = none(SystemId)
          var minDist = 999
          let fromCoords = filtered.starMap.systems[fleet.location].coords
          for sysId in highValueTargets:
            let coords = filtered.starMap.systems[sysId].coords
            let dx = abs(coords.q - fromCoords.q)
            let dy = abs(coords.r - fromCoords.r)
            let dz = abs((coords.q + coords.r) - (fromCoords.q + fromCoords.r))
            let dist = (dx + dy + dz) div 2
            if dist < minDist:
              minDist = dist
              closest = some(sysId)

          if closest.isSome:
            # Issue HackStarbase mission to gather production/fleet intel
            order.orderType = FleetOrderType.HackStarbase
            order.targetSystem = closest
            order.targetFleet = none(FleetId)
            result.add(order)
            continue

      # B) Pre-colonization reconnaissance - scout systems before sending ETACs
      if p.expansionDrive > 0.4:
        # Find uncolonized systems that need scouting
        var needsRecon: seq[SystemId] = @[]
        for systemId, system in filtered.starMap.systems:
          if not isSystemColonized(filtered, systemId) and
             needsReconnaissanceController(controller, systemId, filtered.turn):
            needsRecon.add(systemId)

        if needsRecon.len > 0:
          # Pick closest system needing recon
          var closest: Option[SystemId] = none(SystemId)
          var minDist = 999
          let fromCoords = filtered.starMap.systems[fleet.location].coords
          for sysId in needsRecon:
            let coords = filtered.starMap.systems[sysId].coords
            let dx = abs(coords.q - fromCoords.q)
            let dy = abs(coords.r - fromCoords.r)
            let dz = abs((coords.q + coords.r) - (fromCoords.q + fromCoords.r))
            let dist = (dx + dy + dz) div 2
            if dist < minDist:
              minDist = dist
              closest = some(sysId)

          if closest.isSome:
            # Issue spy mission to gather planetary intelligence
            order.orderType = FleetOrderType.SpyPlanet
            order.targetSystem = closest
            order.targetFleet = none(FleetId)
            result.add(order)
            continue

      # C) Pre-invasion intelligence - SpySystem on enemy colonies before invasion
      # Lowered threshold from 0.4 to 0.2 to enable more intelligence gathering
      if p.aggression > 0.2 or (1.0 - p.economicFocus) > 0.4:
        # Find enemy colonies that need updated intelligence
        var needsIntel: seq[SystemId] = @[]
        for colony in filtered.ownColonies:
          if colony.owner != controller.houseId and
             needsReconnaissanceController(controller, colony.systemId, filtered.turn):
            needsIntel.add(colony.systemId)

        if needsIntel.len > 0:
          # Pick closest enemy colony needing intel
          var closest: Option[SystemId] = none(SystemId)
          var minDist = 999
          let fromCoords = filtered.starMap.systems[fleet.location].coords
          for sysId in needsIntel:
            let coords = filtered.starMap.systems[sysId].coords
            let dx = abs(coords.q - fromCoords.q)
            let dy = abs(coords.r - fromCoords.r)
            let dz = abs((coords.q + coords.r) - (fromCoords.q + fromCoords.r))
            let dist = (dx + dy + dz) div 2
            if dist < minDist:
              minDist = dist
              closest = some(sysId)

          if closest.isSome:
            # Issue spy mission to gather defense intelligence
            order.orderType = FleetOrderType.SpySystem
            order.targetSystem = closest
            order.targetFleet = none(FleetId)
            result.add(order)
            continue

    # Priority 4: Expansion and Exploration
    # ARCHITECTURE FIX: Check if fleet has ETAC (spacelift ship for colonization)
    var hasETAC = false
    for spaceLiftShip in fleet.spaceLiftShips:
      if spaceLiftShip.shipClass == ShipClass.ETAC:
        hasETAC = true
        break

    if hasETAC:
      # Intelligence-driven colonization
      # ETAC fleets: Issue COLONIZE order to best uncolonized target
      # The engine will automatically move the fleet there and colonize
      let targetOpt = findBestColonizationTarget(controller, filtered, fleet.location, fleet.id)
      if targetOpt.isSome:
        # ALWAYS LOG: Critical for diagnosing colonization order timing
        # Count PTUs in fleet
        var ptuCount = 0
        for spaceLift in fleet.spaceLiftShips:
          if spaceLift.cargo.cargoType == CargoType.Colonists:
            ptuCount += spaceLift.cargo.quantity
        logInfo(LogCategory.lcAI, &"{controller.houseId} ETAC fleet {fleet.id} issuing colonize order for system {targetOpt.get()} " &
                &"(location: {fleet.location}, ETACs: {fleet.spaceLiftShips.len}, PTUs: {ptuCount})")
        order.orderType = FleetOrderType.Colonize
        order.targetSystem = targetOpt
        order.targetFleet = none(FleetId)
        result.add(order)
        continue
      else:
        # ALWAYS LOG: Warns when ETAC has no valid targets
        logWarn(LogCategory.lcAI, &"{controller.houseId} ETAC fleet {fleet.id} has NO colonization target " &
                &"(location: {fleet.location}, all systems colonized?)")
    # Priority 4.5: Reconnaissance - Scout enemy homeworlds for invasion planning
    # CRITICAL FIX: AI must gather intelligence on enemy colonies to enable invasions
    # ANY fleet can do reconnaissance - cheap expendable ships are good probe fleets
    if not hasETAC and fleet.squadrons.len == 0 and fleet.spaceLiftShips.len > 0:
      # Use cheap spacelift ships (transports, scouts, etc) for reconnaissance
      let enemyHomeworlds = identifyEnemyHomeworlds(filtered)
      var reconTarget: Option[SystemId] = none(SystemId)

      # Find closest enemy homeworld that needs reconnaissance
      var minDist = 999
      let fromCoords = filtered.starMap.systems[fleet.location].coords
      for enemySystem in enemyHomeworlds:
        if needsReconnaissance(filtered, enemySystem):
          let coords = filtered.starMap.systems[enemySystem].coords
          let dx = abs(coords.q - fromCoords.q)
          let dy = abs(coords.r - fromCoords.r)
          let dz = abs((coords.q + coords.r) - (fromCoords.q + fromCoords.r))
          let dist = (dx + dy + dz) div 2
          if dist < minDist:
            minDist = dist
            reconTarget = some(enemySystem)

      if reconTarget.isSome:
        logInfo(LogCategory.lcAI, &"{controller.houseId} fleet {fleet.id} conducting reconnaissance of enemy system {reconTarget.get()} (probe fleet)")
        order.orderType = FleetOrderType.Move
        order.targetSystem = reconTarget
        order.targetFleet = none(FleetId)
        result.add(order)
        continue

    # Priority 4.8: Generic Exploration - Scout uncolonized systems
    if p.expansionDrive > 0.3:
      # Non-ETAC fleets with expansion drive: Scout uncolonized systems
      let targetOpt = findNearestUncolonizedSystem(filtered, fleet.location, fleet.id)
      if targetOpt.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = targetOpt
        order.targetFleet = none(FleetId)
        result.add(order)
        continue

    # Priority 5: Defend home colonies (patrol)
    # Find a colony that needs defense
    var needsDefense: Option[SystemId] = none(SystemId)
    for colony in filtered.ownColonies:
      if colony.owner == controller.houseId:
        # Check if there are enemy fleets nearby (simplified: just check this colony)
        let hasEnemyFleets = calculateFleetStrengthAtSystem(
          filtered, colony.systemId, colony.owner
        ) < getFleetStrength(fleet)
        if hasEnemyFleets or colony.blockaded:
          needsDefense = some(colony.systemId)
          break

    if needsDefense.isSome:
      order.orderType = FleetOrderType.Move
      order.targetSystem = needsDefense
      order.targetFleet = none(FleetId)
    else:
      # Priority 5.5: Proactive Colony Defense (Phase 2f)
      ## **Purpose:** Address 73.8% undefended colony rate by positioning fleets proactively
      ##
      ## **Strategy:**
      ## 1. Prioritize important colonies (high production or rich resources)
      ## 2. Fall back to frontier colonies (adjacent to enemy territory)
      ## 3. Consider colony defended if it has fleet OR starbase
      ##
      ## **Defense Layering:**
      ## - Important colonies get first priority (production >= 30 or rich resources)
      ## - Frontier colonies get second priority (adjacent to enemy systems)
      ## - Fleets move to guard position or patrol if already in position
      ##
      ## **Why This Matters:**
      ## Proactive defense prevents surprise attacks and resource loss. Undefended
      ## colonies are easy targets that can snowball into strategic losses.
      ##
      ## **CRITICAL FIX:** Exempt ETAC/colonization fleets from defense duty
      ## - ETAC fleets must expand, not defend
      ## - Prevents "fleet oscillation" where all fleets recall to homeworld

      # Skip defense for ETAC fleets (they need to colonize)
      let hasETAC = fleet.spaceLiftShips.anyIt(it.shipClass == ShipClass.ETAC)
      if hasETAC:
        # ETAC fleets prioritize expansion over defense
        continue

      # Position fleets at undefended colonies (especially high-value or frontier)
      var undefendedColony: Option[SystemId] = none(SystemId)
      let importantColonies = controller.identifyImportantColonies(filtered)

      # DEBUG logging (Phase 2f)
      if importantColonies.len > 0 and filtered.turn mod 10 == 0:
        echo "  [DEBUG] ", controller.houseId, " Turn ", filtered.turn, ": ", importantColonies.len, " important colonies found"

      for systemId in importantColonies:
        # Check if colony has any defensive fleet
        var hasDefense = false
        for otherFleet in myFleets:
          if otherFleet.location == systemId and otherFleet.id != fleet.id:
            hasDefense = true
            break

        # Check if colony has starbase
        let colonyOpt = getColony(filtered, systemId)
        if colonyOpt.isSome:
          let colony = colonyOpt.get()
          if colony.starbases.len > 0:
            hasDefense = true

        if not hasDefense:
          undefendedColony = some(systemId)
          break

      # If no important colony needs defense, check frontier colonies
      if undefendedColony.isNone:
        for colony in filtered.ownColonies:
          if colony.owner != controller.houseId:
            continue

          # Check if this is a frontier colony (adjacent to enemy territory)
          var isFrontier = false
          let adjacentIds = filtered.starMap.getAdjacentSystems(colony.systemId)
          for neighborId in adjacentIds:
            if isSystemColonized(filtered, neighborId):
              let neighborOpt = getColony(filtered, neighborId)
              if neighborOpt.isSome:
                let neighbor = neighborOpt.get()
                if neighbor.owner != controller.houseId:
                  isFrontier = true
                  break

          if isFrontier:
            # Check if colony has defensive fleet
            var hasDefense = false
            for otherFleet in myFleets:
              if otherFleet.location == colony.systemId and otherFleet.id != fleet.id:
                hasDefense = true
                break

            if colony.starbases.len > 0:
              hasDefense = true

            if not hasDefense:
              undefendedColony = some(colony.systemId)
              break

      if undefendedColony.isSome:
        # Move to guard undefended colony
        if fleet.location != undefendedColony.get():
          order.orderType = FleetOrderType.Move
          order.targetSystem = undefendedColony
        else:
          # Already at colony - patrol to maintain presence
          order.orderType = FleetOrderType.Patrol
          order.targetSystem = some(fleet.location)
        order.targetFleet = none(FleetId)
        result.add(order)
        continue

      # Priority 6: Exploration - send fleets to unknown systems
      # Instead of sitting idle, explore uncolonized systems
      if p.expansionDrive > 0.2 or rng.rand(1.0) < 0.3:
        let exploreTarget = findNearestUncolonizedSystem(filtered, fleet.location, fleet.id)
        if exploreTarget.isSome:
          order.orderType = FleetOrderType.Move
          order.targetSystem = exploreTarget
          order.targetFleet = none(FleetId)
          result.add(order)
          continue

      # Default: Patrol current location
      order.orderType = FleetOrderType.Patrol
      order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)
      result.add(order)
      continue

    # SHOULD NEVER REACH HERE - all priorities should end with continue or result.add+continue
    when not defined(release):
      logWarn(LogCategory.lcAI, &"Fleet {fleet.id} reached end of order generation without being handled!")

  when not defined(release):
    logDebug(LogCategory.lcAI, &"{controller.houseId} generated {result.len} fleet orders")

proc hasViableColonizationTargets(filtered: FilteredGameState, houseId: HouseId): bool =
  ## Returns true if there is at least one reachable uncolonized system
  ## THE CORRECT QUESTION: "Can I still colonize?" not "Do I have enough ETACs?"
  ## This prevents building useless ETACs when all systems are colonized

  # Quick check: are there ANY uncolonized systems at all?
  var hasUncolonized = false
  for systemId, system in filtered.starMap.systems:
    if not isSystemColonized(filtered, systemId):
      hasUncolonized = true
      break

  if not hasUncolonized:
    return false  # All systems colonized - no point building ETACs

  # Check if we have any colonies that could send an ETAC
  for colony in filtered.ownColonies:
    if colony.owner == houseId:
      # Can this colony reach an uncolonized system?
      # Use the existing pathfinding logic
      for targetId, targetSys in filtered.starMap.systems:
        if not isSystemColonized(filtered, targetId):
          # Found an uncolonized system - is it reachable?
          # Simple check: if there's a path, colonization is viable
          # (More sophisticated: check for safe routes, but start simple)
          return true

  return false

proc hasIdleETAC(filtered: FilteredGameState, houseId: HouseId): bool =
  ## Returns true if we have an ETAC with PTU at a HIGH-PRODUCTION colony ready to colonize
  ## PHASE 2B FIX: Only count ETACs at productive colonies (50+ PU) - prevents blocking
  ## when ETAC is at remote low-production colony

  # Only check unassigned ETACs at high-production colonies
  for colony in filtered.ownColonies:
    if colony.owner != houseId:
      continue

    # PHASE 2B: Only count as "idle" if at high-production colony (can build replacement fast)
    if colony.production < 50:
      continue

    if colony.unassignedSpaceLiftShips.len > 0:
      for spaceLift in colony.unassignedSpaceLiftShips:
        if spaceLift.shipClass == ShipClass.ETAC:
          # Check if ETAC has colonist cargo loaded
          if spaceLift.cargo.cargoType == CargoType.Colonists and spaceLift.cargo.quantity > 0:
            return true

  # Check fleets at high-production owned colonies
  for fleet in filtered.ownFleets:
    if fleet.owner != houseId:
      continue

    # Is fleet at a high-production owned colony?
    var atHighProdColony = false
    for colony in filtered.ownColonies:
      if colony.owner == houseId and colony.systemId == fleet.location and colony.production >= 50:
        atHighProdColony = true
        break

    if atHighProdColony:
      for spaceLift in fleet.spaceLiftShips:
        if spaceLift.shipClass == ShipClass.ETAC:
          # Check if ETAC has colonist cargo loaded
          if spaceLift.cargo.cargoType == CargoType.Colonists and spaceLift.cargo.quantity > 0:
            return true

  return false

proc generateBuildOrders(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[BuildOrder] =
  ## COMPREHENSIVE 4X STRATEGIC AI - Handles all asset types intelligently
  ## Ships: Combat warships, fighters, carriers, raiders, scouts, ETACs, transports
  ## Defenses: Starbases, planetary shields, ground batteries, armies, marines
  ## Facilities: Spaceports, shipyards, infrastructure
  result = @[]
  let p = controller.personality
  let house = filtered.ownHouse
  let myColonies = getOwnedColonies(filtered, controller.houseId)

  if myColonies.len == 0:
    return  # No colonies, can't build

  # ==========================================================================
  # ASSET INVENTORY - Count existing assets
  # ==========================================================================
  var scoutCount = 0
  var raiderCount = 0
  var carrierCount = 0
  var fighterCount = 0
  var etacCount = 0  # DEPRECATED: Global count (includes committed ETACs)
  var transportCount = 0
  var militaryCount = 0
  var capitalShipCount = 0  # BB, BC, DN, SD
  var starbaseCount = 0

  # BALANCE FIX: Count squadrons in fleets AND unassigned squadrons
  # ARCHITECTURE FIX: Count spacelift ships separately (NOT in squadrons)
  for fleet in filtered.ownFleets:
    if fleet.owner == controller.houseId:
      # Count combat squadrons
      for squadron in fleet.squadrons:
        case squadron.flagship.shipClass:
        of ShipClass.Scout:
          scoutCount += 1
        of ShipClass.Raider:
          raiderCount += 1
        of ShipClass.Carrier, ShipClass.SuperCarrier:
          carrierCount += 1
        of ShipClass.Fighter:
          fighterCount += 1
        of ShipClass.Battleship, ShipClass.Battlecruiser,
           ShipClass.Dreadnought, ShipClass.SuperDreadnought:
          capitalShipCount += 1
          militaryCount += 1
        of ShipClass.Starbase:
          starbaseCount += 1
        else:
          if squadron.flagship.shipType == ShipType.Military:
            militaryCount += 1

        for ship in squadron.ships:
          case ship.shipClass:
          of ShipClass.Scout:
            scoutCount += 1
          of ShipClass.Raider:
            raiderCount += 1
          of ShipClass.Fighter:
            fighterCount += 1
          else:
            if ship.shipType == ShipType.Military:
              militaryCount += 1

      # ARCHITECTURE FIX: Count spacelift ships separately
      for spaceLiftShip in fleet.spaceLiftShips:
        case spaceLiftShip.shipClass:
        of ShipClass.ETAC:
          etacCount += 1
        of ShipClass.TroopTransport:
          transportCount += 1
        else:
          discard  # Shouldn't happen, spacelift ships are only ETAC/TroopTransport

  # BALANCE FIX: Also count unassigned squadrons and spacelift ships at colonies
  for colony in myColonies:
    # Count unassigned combat squadrons
    for squadron in colony.unassignedSquadrons:
      case squadron.flagship.shipClass:
      of ShipClass.Scout:
        scoutCount += 1
      of ShipClass.Raider:
        raiderCount += 1
      of ShipClass.Carrier, ShipClass.SuperCarrier:
        carrierCount += 1
      of ShipClass.Fighter:
        fighterCount += 1
      of ShipClass.Battleship, ShipClass.Battlecruiser,
         ShipClass.Dreadnought, ShipClass.SuperDreadnought:
        capitalShipCount += 1
        militaryCount += 1
      of ShipClass.Starbase:
        starbaseCount += 1
      else:
        if squadron.flagship.shipType == ShipType.Military:
          militaryCount += 1

    # ARCHITECTURE FIX: Count unassigned spacelift ships
    for spaceLiftShip in colony.unassignedSpaceLiftShips:
      case spaceLiftShip.shipClass:
      of ShipClass.ETAC:
        etacCount += 1
      of ShipClass.TroopTransport:
        transportCount += 1
      else:
        discard

  # ==========================================================================
  # RESOURCE MANAGEMENT - Calculate maintenance affordability
  # ==========================================================================

  # Calculate total production across all colonies
  var totalProduction = 0
  for colony in myColonies:
    totalProduction += colony.production

  # Estimate current maintenance costs (approximate from squadron/spacelift counts)
  # Average maintenance: ~2 PP per squadron, ~1 PP per spacelift ship
  let totalSquadrons = militaryCount + scoutCount + raiderCount + carrierCount + fighterCount + starbaseCount
  let totalSpaceLift = etacCount + transportCount
  let estimatedMaintenance = (totalSquadrons * 2) + totalSpaceLift

  # Calculate maintenance buffer - how much production is left after maintenance
  let maintenanceBuffer = totalProduction - estimatedMaintenance
  let maintenanceRatio = if totalProduction > 0:
    float(estimatedMaintenance) / float(totalProduction)
  else:
    0.0

  # CRITICAL: AI should NOT build new ships if maintenance is already consuming too much
  # Target: Keep maintenance under 40% of production to allow for growth/colonization
  # This prevents death spirals where maintenance consumes all production
  # Formula: Allow building if (maintenance < 40% of production) AND (buffer > 20 PP)
  let canAffordMoreShips = maintenanceRatio < 0.4 and maintenanceBuffer > 20

  # Check squadron limit based on actual PU level
  # Formula from military.toml: House PU / 100 (min 8)
  # Calculate total PU from colonies
  var totalPU = 0
  for colony in myColonies:
    totalPU += colony.population  # Population units = PU

  let squadronLimit = max(8, totalPU div 100)
  # Add 1-squadron buffer to account for ships completing from previous builds
  let atSquadronLimit = totalSquadrons >= (squadronLimit - 1)

  # ==========================================================================
  # STRATEGIC ASSESSMENT - What does this AI need?
  # ==========================================================================

  # Assess military situation
  let myMilitaryStrength = calculateMilitaryStrength(filtered, controller.houseId)
  var totalEnemyStrength = 0
  var hasEnemies = false
  for otherHouse in filtered.housePrestige.keys:
    if otherHouse != controller.houseId:
      let dipState = dip_types.getDiplomaticState(
        house.diplomaticRelations,
        otherHouse
      )
      if dipState == dip_types.DiplomaticState.Enemy:
        totalEnemyStrength += calculateMilitaryStrength(filtered, otherHouse)
        hasEnemies = true

  let militaryRatio = if totalEnemyStrength > 0:
    float(myMilitaryStrength) / float(totalEnemyStrength)
  else:
    2.0  # No declared enemies

  # Check for threatened colonies
  var threatenedColonies = 0
  var criticalThreat = false
  for colony in myColonies:
    let combat = assessCombatSituation(controller, filtered, colony.systemId)
    if combat.recommendRetreat or combat.recommendReinforce:
      threatenedColonies += 1
      if combat.recommendRetreat:
        criticalThreat = true

  # ========================================================================
  # HYBRID STRATEGIC PLANNING: Phase Guidelines + Dynamic Tactical Responses
  # ========================================================================
  # The 4-act structure provides production *defaults*, but tactical needs
  # (threats, opportunities, military balance) override these guidelines

  let currentAct = getCurrentGameAct(filtered.turn)
  let totalSystems = filtered.starMap.systems.len
  let colonizationProgress = float(myColonies.len) / float(totalSystems)

  # Dynamic state assessment
  let isUnderThreat = threatenedColonies > 0 or criticalThreat
  let isMilitaryWeak = militaryRatio < 0.8  # Weaker than enemies
  let hasOpenMap = colonizationProgress < 0.5  # Still room to expand
  let militaryFocus = 1.0 - p.economicFocus

  # ETAC PRODUCTION: Driven by colonization opportunities, not just phase
  # Stop building ETACs when: (1) no targets OR (2) map mostly full (>50%)
  let canColonize = hasViableColonizationTargets(filtered, controller.houseId)
  let needETACs =
    if not canColonize or colonizationProgress > 0.5:
      # No colonization targets or map saturated - switch to conquest
      false
    elif isUnderThreat and militaryCount < 3:
      # Under threat with weak military - prioritize defense over expansion
      false
    elif currentAct == GameAct.Act1_LandGrab:
      # Act 1: Aggressive colonization (cap at 8 ETACs)
      etacCount < 8 and p.expansionDrive > 0.2
    elif currentAct == GameAct.Act2_RisingTensions and hasOpenMap:
      # Act 2: Opportunistic colonization if map still open
      etacCount < 5 and p.expansionDrive > 0.4
    else:
      # Act 3-4 or map full: No more ETACs
      false

  # SCOUT PRODUCTION: Scales with intelligence needs and map knowledge
  # More scouts = better intel = better tactical decisions
  let needScouts =
    if currentAct == GameAct.Act1_LandGrab:
      # Act 1: Basic scouts (2) for exploration
      scoutCount < 2 and p.techPriority >= 0.3
    elif currentAct == GameAct.Act2_RisingTensions or hasEnemies:
      # Act 2 or at war: Intelligence network (5 scouts)
      scoutCount < 5 and p.techPriority >= 0.3
    else:
      # Act 3-4: ELI mesh for invasion support (7 scouts)
      scoutCount < 7 and p.aggression >= 0.3

  let needMoreScouts = scoutCount < 5 and p.techPriority >= 0.4
  let needELIMesh = scoutCount < 7 and p.aggression >= 0.4 and hasEnemies

  # FRIGATE PRODUCTION: Act 1 only - cheap ships for early defense/exploration
  let needFrigates = currentAct == GameAct.Act1_LandGrab and
                     militaryCount < 5 and
                     p.expansionDrive > 0.3

  # TRANSPORT PRODUCTION: For conquest (invasions), not colonization
  # Build when: (1) have military strength AND (2) aggressive posture
  let needTransports =
    if currentAct == GameAct.Act1_LandGrab:
      # Act 1: No transports - colonize not conquer
      false
    elif isMilitaryWeak:
      # Military weak - build warships first, transports later
      false
    elif hasEnemies and militaryCount >= 5:
      # At war with adequate military - build invasion capability
      transportCount < 3 and (p.aggression > 0.3 or hasOpenMap == false)
    elif currentAct in {GameAct.Act3_TotalWar, GameAct.Act4_Endgame}:
      # Late game - conquest phase
      transportCount < 3 and p.aggression > 0.3
    else:
      false

  # MILITARY PRODUCTION: Dynamic response to threats and opportunities
  # Overrides phase guidelines when under threat or facing opportunities
  let needMilitary =
    if isUnderThreat:
      # TACTICAL OVERRIDE: Always build when under threat
      true
    elif isMilitaryWeak and hasEnemies:
      # TACTICAL OVERRIDE: Build to parity when enemies exist
      true
    elif currentAct == GameAct.Act1_LandGrab:
      # Act 1 DEFAULT: Minimal military (3 ships) unless threatened
      militaryCount < 3
    elif currentAct == GameAct.Act2_RisingTensions:
      # Act 2 DEFAULT: Build military to 8-12 ships
      militaryRatio < 1.0 or
      (p.aggression > 0.4 and militaryCount < 8) or
      (militaryFocus > 0.6 and militaryCount < 12) or
      militaryCount < 5
    elif currentAct == GameAct.Act3_TotalWar:
      # Act 3 DEFAULT: Large military for conquest
      militaryRatio < 1.2 or
      (p.aggression > 0.4 and militaryCount < 15) or
      (militaryFocus > 0.6 and militaryCount < 20) or
      militaryCount < 8
    else:  # Act 4 Endgame
      # Act 4 DEFAULT: Maximum pressure
      militaryRatio < 1.5 or militaryCount < 12

  # PRESTIGE OPTIMIZATION: Starbases give +5 prestige when destroyed (enemy)
  # Losing starbases costs -5 prestige. Build for all important colonies.
  let needDefenses = (
    threatenedColonies > 0 or  # Under attack
    starbaseCount < myColonies.len or  # Starbases for all colonies
    (hasEnemies and militaryCount < 5) or  # Enemies exist but weak military
    (starbaseCount == 0 and myColonies.len > 0)  # Always have at least one starbase
  )

  # Phase 2d: Build Raiders if we've researched CLK (cloaking advantage)
  let hasCLK = house.techTree.levels.cloakingTech > 0
  let needRaiders = (
    hasCLK and raiderCount < 3 and p.aggression > 0.4 and militaryCount > 3
  )

  let needCarriers = (
    fighterCount > 3 and carrierCount == 0 and house.treasury > 150
  )

  # Phase 2e: Fighter build strategy
  # Build fighters for aggressive/military-focused AIs
  # Start with small number even without carriers (they stay at colonies until carriers built)
  let needFighters = (
    p.aggression >= 0.3 and fighterCount < 8 and
    house.treasury > 60  # Can afford fighter + maintenance (fighter cost = 20 PP)
  )

  # ==========================================================================
  # BUILD DECISION LOGIC - Priority order with dynamic decision making
  # ==========================================================================

  # Build at most productive colonies first
  var coloniesToBuild = myColonies
  coloniesToBuild.sort(proc(a, b: Colony): int = cmp(b.production, a.production))

  # Track remaining treasury to prevent over-building
  var remainingTreasury = house.treasury

  for colony in coloniesToBuild:
    if remainingTreasury < 30:
      break  # Not enough funds for anything

    let hasShipyard = colony.shipyards.len > 0
    let hasSpaceport = colony.spaceports.len > 0
    let hasStarbase = colony.starbases.len > 0
    let needsInfrastructure = not hasSpaceport or not hasShipyard

    # ------------------------------------------------------------------------
    # INFRASTRUCTURE: Build spaceports/shipyards when needed for military
    # EARLY GAME FIX: Don't block ETAC building - homeworld starts with shipyard
    # ------------------------------------------------------------------------
    if not hasShipyard and (needMilitary or p.aggression > 0.4):
      # No shipyard at all - need to build one (shouldn't happen at homeworld)
      if hasSpaceport and house.treasury >= 150:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Shipyard"),
          industrialUnits: 0
        ))
        break  # Build shipyard first
      elif not hasSpaceport and house.treasury >= 100:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Spaceport"),
          industrialUnits: 0
        ))
        break  # Build spaceport first

    if not hasShipyard:
      continue  # Can't build ships without shipyard

    # ------------------------------------------------------------------------
    # CRISIS RESPONSE: Critical threats get immediate defense
    # ------------------------------------------------------------------------
    if criticalThreat:
      let combat = assessCombatSituation(controller, filtered, colony.systemId)
      if combat.recommendRetreat:
        # This colony is under critical attack - emergency defenses
        if not hasStarbase and house.treasury >= 300:
          result.add(BuildOrder(
            colonySystem: colony.systemId,
            buildType: BuildType.Ship,
            quantity: 1,
            shipClass: some(ShipClass.Starbase),
            buildingType: none(string),
            industrialUnits: 0
          ))
          break
        elif colony.groundBatteries < 5 and house.treasury >= 20:
          result.add(BuildOrder(
            colonySystem: colony.systemId,
            buildType: BuildType.Building,
            quantity: 1,
            shipClass: none(ShipClass),
            buildingType: some("GroundBattery"),
            industrialUnits: 0
          ))
          break

    # ------------------------------------------------------------------------
    # EARLY GAME: Initial exploration and expansion
    # CRITICAL: ETACs BEFORE scouts - colonize first, intel second
    # Priority: ETACs → Frigates → Scouts
    # CRITICAL FIX: Don't break after ETAC - allow multiple builds per turn
    # ------------------------------------------------------------------------
    # ========================================================================
    # ETAC BUILD LOGIC: Only build if colonization is still viable
    # ========================================================================
    if needETACs:
      let etacCost = getShipConstructionCost(ShipClass.ETAC)
      # Build on high-production colonies only (efficient ETAC production)
      if remainingTreasury >= etacCost and colony.production >= 50:
        # ALWAYS LOG: Critical for diagnosing colonization deadlock
        logInfo(LogCategory.lcAI, &"{controller.houseId} building ETAC at colony {colony.systemId} - " &
                &"colonization targets available (expansionDrive: {p.expansionDrive:.2f}, " &
                &"treasury: {remainingTreasury} PP, production: {colony.production} PU)")
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.ETAC),
          buildingType: none(string),
          industrialUnits: 0
        ))
        remainingTreasury -= etacCost
        # Continue to allow other builds this colony
      else:
        # ALWAYS LOG: Critical for diagnosing why ETACs aren't being built
        if house.treasury < etacCost:
          logDebug(LogCategory.lcAI, &"{controller.houseId} cannot build ETAC at {colony.systemId} - " &
                   &"insufficient funds (need {etacCost} PP, have {house.treasury} PP)")
        elif colony.production < 50:
          logDebug(LogCategory.lcAI, &"{controller.houseId} skipping ETAC build at {colony.systemId} - " &
                   &"low production ({colony.production} PU, need 50+ PU)")
    else:
      # ALWAYS LOG: Critical for understanding expansion strategy
      if not canColonize:
        logDebug(LogCategory.lcAI, &"{controller.houseId} not building ETAC - no viable colonization targets")
      elif not needETACs:
        logDebug(LogCategory.lcAI, &"{controller.houseId} not building ETAC - phase-aware logic says no (Act: {currentAct}, colonies: {myColonies.len})")
      elif p.expansionDrive <= 0.3:
        logDebug(LogCategory.lcAI, &"{controller.houseId} not building ETAC - low expansionDrive ({p.expansionDrive:.2f})")

    # ========================================================================
    # CONQUEST PHASE: Switch to Troop Transports when colonization ends
    # ========================================================================
    if not canColonize and p.aggression > 0.4 and myColonies.len >= 4:
      # No more colonies → switch to invasion fleet buildup
      let transportCost = getShipConstructionCost(ShipClass.TroopTransport)
      if remainingTreasury >= transportCost and colony.production >= 80 and rng.rand(1.0) < 0.7:
        logInfo(LogCategory.lcAI, &"{controller.houseId} building Troop Transport at colony {colony.systemId} - " &
                &"CONQUEST PHASE (no colonization targets left, aggression: {p.aggression:.2f})")
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.TroopTransport),
          buildingType: none(string),
          industrialUnits: 0
        ))
        remainingTreasury -= transportCost

    # Early game frigates for cheap exploration and combat
    # Cost 30 PP, build time 1 turn, can explore and fight
    if needFrigates:
      let frigateCost = getShipConstructionCost(ShipClass.Frigate)
      if remainingTreasury >= frigateCost and canAffordMoreShips and not atSquadronLimit:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Frigate),
          buildingType: none(string),
          industrialUnits: 0
        ))
        remainingTreasury -= frigateCost
        # Continue - allow more builds

    if needScouts:
      let scoutCost = getShipConstructionCost(ShipClass.Scout)
      if remainingTreasury >= scoutCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Scout),
          buildingType: none(string),
          industrialUnits: 0
        ))
        remainingTreasury -= scoutCost
        # Continue - allow more builds

    # ------------------------------------------------------------------------
    # Marine Garrison Management
    # MOVED AFTER ETACs: Marines are defensive, colonization is strategic
    # ------------------------------------------------------------------------
    if controller.shouldBuildMarines(filtered, colony):
      # This colony needs more marines for garrison
      if remainingTreasury >= 30:  # Cost of marines
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Marines"),
          industrialUnits: 0
        ))
        remainingTreasury -= 30
        # Continue - allow more builds

    # ------------------------------------------------------------------------
    # MID GAME: Military buildup and defense
    # ------------------------------------------------------------------------

    # Phase 2e: Fighter squadrons for aggressive AIs
    if needFighters:
      let fighterCost = getShipConstructionCost(ShipClass.Fighter)
      if remainingTreasury >= fighterCost and canAffordMoreShips and not atSquadronLimit:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Fighter),
          buildingType: none(string),
          industrialUnits: 0
        ))
        remainingTreasury -= fighterCost
        # Continue - allow more builds

    # Phase 2e: Starbases for fighter capacity (1 per 5 fighters rule)
    # Per assets.md:2.4.1: "Requires 1 operational Starbase per 5 FS (ceil)"
    let fightersAtColony = colony.fighterSquadrons.len
    let requiredStarbases = (fightersAtColony + 4) div 5  # Ceiling division
    let currentStarbases = colony.starbases.len
    if fightersAtColony > 0 and currentStarbases < requiredStarbases:
      # Need more starbases to support fighter capacity
      if remainingTreasury >= 300 and canAffordMoreShips and not atSquadronLimit:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Starbase),
          buildingType: none(string),
          industrialUnits: 0
        ))
        remainingTreasury -= 300
        # Continue - allow more builds

    # Starbases for defense (before expensive military buildup)
    # RESOURCE MANAGEMENT: Starbases also have maintenance, check affordability
    if needDefenses and not hasStarbase and remainingTreasury >= 300 and canAffordMoreShips and not atSquadronLimit:
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Starbase),
        buildingType: none(string),
        industrialUnits: 0
      ))
      remainingTreasury -= 300
      # Continue - allow more builds

    # Military ships - COMPREHENSIVE SHIP SELECTION
    # RESOURCE MANAGEMENT: Only build if we can afford maintenance
    if needMilitary and canAffordMoreShips and not atSquadronLimit:
      var shipClass: ShipClass
      var shipCost: int

      # Choose ship based on treasury, aggression, and strategic needs
      if remainingTreasury > 100 and needRaiders:
        # Raiders for ambush tactics (requires CLK research)
        shipClass = ShipClass.Raider
      elif remainingTreasury > 120 and needCarriers:
        # Carriers for fighter projection
        shipClass = ShipClass.Carrier
      elif remainingTreasury > 150 and capitalShipCount < 2 and p.aggression > 0.6:
        # Build at least 2 capital ships for aggressive AIs
        shipClass = ShipClass.Battleship
      elif remainingTreasury > 100 and militaryCount < 5:
        # Early military: Battle Cruisers
        shipClass = ShipClass.Battlecruiser
      elif remainingTreasury > 80:
        # Mid-tier: Heavy Cruisers
        shipClass = ShipClass.HeavyCruiser
      elif remainingTreasury > 60:
        # Mid-tier: Cruisers and Light Cruisers
        shipClass = if rng.rand(1.0) > 0.5: ShipClass.Cruiser else: ShipClass.LightCruiser
      elif remainingTreasury > 40:
        # Budget: Destroyers
        shipClass = ShipClass.Destroyer
      elif remainingTreasury > 30:
        # Cheap: Frigates
        shipClass = ShipClass.Frigate
      else:
        # Last resort: Corvettes
        shipClass = ShipClass.Corvette

      shipCost = getShipConstructionCost(shipClass)
      if remainingTreasury >= shipCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(shipClass),
          buildingType: none(string),
          industrialUnits: 0
        ))
        remainingTreasury -= shipCost
        # Continue - allow more builds

    # Ground defenses for threatened colonies
    if threatenedColonies > 0 and colony.groundBatteries < 5:
      let batteryCost = getBuildingCost("GroundBattery")
      if house.treasury >= batteryCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("GroundBattery"),
          industrialUnits: 0
        ))
        break

    # IMPROVEMENT: Proactive garrison management
    # Build marine garrisons BEFORE invasions threaten, not after
    # # Strategic priorities:
    # - Homeworld: 5+ marine garrison (critical)
    # - Important colonies: 3+ marines (high production, resources)
    # - Frontier colonies: 1-2 marines (minimum defense)
    # - Prepare marines for loading onto transports for invasions

    let isHomeworld = (colony.systemId == filtered.starMap.playerSystemIds[0])  # Assume homeworld
    let isImportant = (colony.production >= 50 or colony.resources == ResourceRating.Abundant)
    let isFrontier = (threatenedColonies > 0)  # Near enemies

    var targetGarrison = 0
    if isHomeworld:
      targetGarrison = 5  # Homeworld: strong garrison
    elif isImportant:
      targetGarrison = 3  # Important: medium garrison
    elif hasEnemies:
      targetGarrison = 2  # Any colony when enemies exist: minimum garrison
    else:
      targetGarrison = 1  # Peacetime: minimal garrison

    # Build marines proactively if below target
    if colony.marines < targetGarrison:
      let marineCost = getBuildingCost("Marines")
      if house.treasury >= marineCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Marines"),
          industrialUnits: 0
        ))
        break

    # Build extra marines for invasion preparation
    # If we have transports but they're not loaded (engine limitation!),
    # at least ensure colonies have spare marines available
    if needTransports and transportCount > 0 and colony.marines < targetGarrison + 2:
      let marineCost = getBuildingCost("Marines")
      if house.treasury >= marineCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Marines"),
          industrialUnits: 0
        ))
        break

    # ------------------------------------------------------------------------
    # LATE GAME: Specialized assets and optimization
    # ------------------------------------------------------------------------

    # Additional scouts for ELI mesh networks (Phase 2c)
    if (needMoreScouts or needELIMesh) and scoutCount < 7:
      let scoutCost = getShipConstructionCost(ShipClass.Scout)
      if house.treasury >= scoutCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Scout),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break

    # Troop transports for invasion capability
    if needTransports:
      let transportCost = getShipConstructionCost(ShipClass.TroopTransport)
      if house.treasury >= transportCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.TroopTransport),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break

    # Economic infrastructure
    if p.economicFocus > 0.6 and colony.infrastructure < 10 and house.treasury >= 150:
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Infrastructure,
        quantity: 1,
        shipClass: none(ShipClass),
        buildingType: none(string),
        industrialUnits: 1
      ))
      break

proc calculateFighterCapacityUtilization(filtered: FilteredGameState, houseId: HouseId): float =
  ## Calculate percentage of fighter capacity currently used
  ## Phase 2e: Used to determine when to research Fighter Doctrine
  var totalFighters = 0
  var totalCapacity = 0

  for colony in filtered.ownColonies:
    if colony.owner == houseId:
      totalFighters += colony.fighterSquadrons.len
      # Calculate max capacity: floor(PU / 100) × FD multiplier
      let baseCapacity = colony.production div 100
      # FD multiplier from tech level (engine handles this, but we estimate)
      let fdMultiplier = filtered.ownHouse.techTree.levels.fighterDoctrine
      totalCapacity += baseCapacity * fdMultiplier

  if totalCapacity == 0:
    return 0.0

  return float(totalFighters) / float(totalCapacity)

proc generateResearchAllocation(controller: AIController, filtered: FilteredGameState): res_types.ResearchAllocation =
  ## Allocate research PP based on strategy
  ## Per economy.md:4.0:
  ## - Economic Level (EL) purchased with ERP
  ## - Science Level (SL) purchased with SRP
  ## - Technologies (CST, WEP, etc.) purchased with TRP
  result = res_types.ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int]()
  )

  let p = controller.personality
  let house = filtered.ownHouse

  # Calculate available PP budget from production
  # Get house's production from all colonies
  var totalProduction = 0
  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      totalProduction += colony.production

  # Allocate percentage of production to research based on tech priority
  let researchBudget = int(float(totalProduction) * p.techPriority)

  if researchBudget > 0:
    # Distribute research budget across EL/SL/TRP based on strategy
    if p.techPriority > 0.6:
      # Heavy research investment - balance across all three categories
      result.economic = researchBudget div 3        # 33% to EL
      result.science = researchBudget div 4         # 25% to SL

      # Remaining ~42% to technologies
      let techBudget = researchBudget - result.economic - result.science

      # Phase 2e: Check if we should prioritize Fighter Doctrine/ACO
      let capacityUtil = calculateFighterCapacityUtilization(filtered, controller.houseId)
      let needFD = capacityUtil > 0.7  # Research FD when >70% capacity used
      let fdLevel = house.techTree.levels.fighterDoctrine
      let acoLevel = house.techTree.levels.advancedCarrierOps

      if p.aggression > 0.5:
        # Aggressive: weapons + cloaking for Raiders (Phase 2d) + fighters (Phase 2e)
        if needFD and fdLevel < 3:
          # High capacity utilization - prioritize FD to expand fighter capacity
          result.technology[TechField.FighterDoctrine] = techBudget div 4     # 25%
          result.technology[TechField.AdvancedCarrierOps] = techBudget div 5  # 20% (synergy)
          result.technology[TechField.WeaponsTech] = techBudget div 4          # 25%
          result.technology[TechField.CloakingTech] = techBudget div 10        # 10%
          result.technology[TechField.ConstructionTech] = techBudget div 10    # 10%
          result.technology[TechField.ElectronicIntelligence] = techBudget div 10  # 10%
        else:
          # Standard aggressive research allocation
          result.technology[TechField.WeaponsTech] = techBudget * 2 div 5  # 40%
          result.technology[TechField.CloakingTech] = techBudget div 5     # 20% (for Raider ambush)
          result.technology[TechField.ConstructionTech] = techBudget div 5 # 20%
          result.technology[TechField.ElectronicIntelligence] = techBudget div 5  # 20%
      else:
        # Peaceful: infrastructure + counter-intel for defense
        result.technology[TechField.ConstructionTech] = techBudget div 2
        result.technology[TechField.TerraformingTech] = techBudget div 4
        result.technology[TechField.CounterIntelligence] = techBudget div 4

    elif p.techPriority >= 0.4:
      # Moderate research - focus on fundamentals (EL/SL)
      result.economic = researchBudget div 2        # 50% to EL
      result.science = researchBudget div 3         # 33% to SL

      # Remaining ~17% to key tech(s)
      let techBudget = researchBudget - result.economic - result.science
      if p.aggression > 0.5:
        # Aggressive with moderate tech: split between weapons and cloaking
        result.technology[TechField.WeaponsTech] = techBudget * 2 div 3  # 67%
        result.technology[TechField.CloakingTech] = techBudget div 3      # 33%
      else:
        result.technology[TechField.ConstructionTech] = techBudget
    else:
      # Minimal research - just EL for economic growth
      result.economic = researchBudget

proc generateDiplomaticActions(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[DiplomaticAction] =
  ## Generate diplomatic actions based on strategic assessment
  result = @[]
  let p = controller.personality
  let myHouse = filtered.ownHouse

  # Priority 0: Respond to pending proposals
  # AI must respond to proposals before proposing new actions
  # TODO: FilteredGameState needs to expose pending proposals
  #[
  for proposal in filtered.pendingProposals:
    if proposal.target == controller.houseId and proposal.status == dip_proposals.ProposalStatus.Pending:
      # Assess the proposer
      let assessment = assessDiplomaticSituation(controller, filtered, proposal.proposer)

      # Decision logic: Accept if beneficial, reject if enemy, wait if uncertain
      if assessment.recommendPact and not assessment.recommendEnemy:
        # Accept proposal
        result.add(DiplomaticAction(
          targetHouse: proposal.proposer,
          actionType: DiplomaticActionType.AcceptProposal,
          proposalId: some(proposal.id),
          message: none(string)
        ))
        return result  # Only one action per turn

      elif assessment.recommendEnemy or proposal.expiresIn <= 1:
        # Reject if enemy or about to expire
        result.add(DiplomaticAction(
          targetHouse: proposal.proposer,
          actionType: DiplomaticActionType.RejectProposal,
          proposalId: some(proposal.id),
          message: none(string)
        ))
        return result  # Only one action per turn

      # Otherwise wait and think about it (let it pend)
  ]#

  # Assess all other houses
  var assessments: seq[DiplomaticAssessment] = @[]
  for otherHouseId in filtered.housePrestige.keys:
    if otherHouseId == controller.houseId:
      continue
    assessments.add(assessDiplomaticSituation(controller, filtered, otherHouseId))

  # Priority 1: Break pacts if strategically advantageous (rare)
  # PRESTIGE OPTIMIZATION: Pact violations cost -10 prestige - avoid unless huge advantage
  for assessment in assessments:
    if assessment.recommendBreak and assessment.currentState == dip_types.DiplomaticState.NonAggression:
      # Double-check with random roll to avoid too frequent violations (-10 prestige penalty)
      if rng.rand(1.0) < 0.2:  # Only 20% chance even when recommended
        result.add(DiplomaticAction(
          targetHouse: assessment.targetHouse,
          actionType: DiplomaticActionType.BreakPact
        ))
        return result  # Only one action per turn

  # Priority 2: Propose pacts with strategic partners
  # PRESTIGE OPTIMIZATION: Forming pacts gives +5 prestige - pursue actively
  # BALANCE FIX: Don't form pacts too aggressively - creates peaceful meta
  for assessment in assessments:
    if assessment.recommendPact and assessment.currentState == dip_types.DiplomaticState.Neutral:
      # Check if we can form pacts (not isolated)
      if dip_types.canFormPact(myHouse.violationHistory):
        # Check if we can reinstate with this specific house
        if dip_types.canReinstatePact(myHouse.violationHistory, assessment.targetHouse, filtered.turn):
          # BALANCE FIX: Only form pacts if diplomatic-focused OR random chance
          # This prevents everyone from pacting with everyone
          let pactChance = if p.diplomacyValue > 0.6: 0.6 else: 0.2
          if rng.rand(1.0) < pactChance:
            result.add(DiplomaticAction(
              targetHouse: assessment.targetHouse,
              actionType: DiplomaticActionType.ProposeNonAggressionPact
            ))
            return result  # Only one action per turn

  # Priority 3: Declare enemy against weak/aggressive targets
  for assessment in assessments:
    if assessment.recommendEnemy and assessment.currentState == dip_types.DiplomaticState.Neutral:
      # Aggressive strategies more likely to declare enemies
      let declareChance = p.aggression * 0.5
      if rng.rand(1.0) < declareChance:
        result.add(DiplomaticAction(
          targetHouse: assessment.targetHouse,
          actionType: DiplomaticActionType.DeclareEnemy
        ))
        return result  # Only one action per turn

  # Priority 4: Normalize relations with dangerous enemies
  for assessment in assessments:
    if not assessment.recommendEnemy and assessment.currentState == dip_types.DiplomaticState.Enemy:
      # Only if we're significantly weaker
      if assessment.relativeMilitaryStrength < 0.6:
        result.add(DiplomaticAction(
          targetHouse: assessment.targetHouse,
          actionType: DiplomaticActionType.SetNeutral
        ))
        return result  # Only one action per turn

proc generateEspionageAction(controller: AIController, filtered: FilteredGameState, rng: var Rand): Option[esp_types.EspionageAttempt] =
  ## Generate espionage action based on strategy and personality
  ## Use personality weights to determine if we should use espionage
  let p = controller.personality
  let house = filtered.ownHouse

  # Check if we have EBP to use espionage (need at least 5 EBP for basic actions)
  if house.espionageBudget.ebpPoints < 5:
    return none(esp_types.EspionageAttempt)

  # CRITICAL: Don't do espionage if prestige is low
  # Detection costs -2 prestige, victims lose -1 to -7 prestige
  # If prestige < 20, focus on prestige-safe activities (expansion, tech, economy)
  if house.prestige < 20:
    return none(esp_types.EspionageAttempt)

  # Use espionage based on personality rather than strategy enum
  # High risk tolerance + low aggression = espionage focus
  let espionageChance = p.riskTolerance * 0.5 + (1.0 - p.aggression) * 0.3 + p.techPriority * 0.2

  # Reduce espionage frequency dramatically - it's a prestige drain
  # Even with high espionage personality, only 20% chance per turn
  if rng.rand(1.0) > (espionageChance * 0.2):
    return none(esp_types.EspionageAttempt)

  # Find a target house
  var targetHouses: seq[HouseId] = @[]
  for houseId in filtered.housePrestige.keys:
    if houseId != controller.houseId:
      targetHouses.add(houseId)

  if targetHouses.len == 0:
    return none(esp_types.EspionageAttempt)

  let target = targetHouses[rng.rand(targetHouses.len - 1)]

  # Simple espionage attempt (tech theft)
  return some(esp_types.EspionageAttempt(
    attacker: controller.houseId,
    target: target,
    action: esp_types.EspionageAction.TechTheft,
    targetSystem: none(SystemId)
  ))

# =============================================================================
# Main Order Generation
# =============================================================================

proc generatePopulationTransfers(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[PopulationTransferOrder] =
  ## Generate Space Guild population transfer orders
  ## Per config/population.toml and economy.md:3.7
  result = @[]
  let p = controller.personality
  let house = filtered.ownHouse

  # Only economically-focused AI uses population transfers
  if p.economicFocus < 0.5 or p.expansionDrive < 0.4:
    return result

  # Need minimum treasury (transfers are expensive)
  if house.treasury < 500:
    return result

  # Find overpopulated source colonies and underpopulated destinations
  var sources: seq[tuple[systemId: SystemId, pop: int]] = @[]
  var destinations: seq[tuple[systemId: SystemId, pop: int]] = @[]

  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      if colony.population > 15:  # Overpopulated
        sources.add((colony.systemId, colony.population))
      elif colony.population < 10 and colony.population > 0:  # Growing colony
        destinations.add((colony.systemId, colony.population))

  if sources.len == 0 or destinations.len == 0:
    return result

  # Transfer from highest pop source to lowest pop destination
  sources.sort(proc(a, b: auto): int = b.pop - a.pop)
  destinations.sort(proc(a, b: auto): int = a.pop - b.pop)

  # One transfer per turn (they're expensive)
  result.add(PopulationTransferOrder(
    sourceColony: sources[0].systemId,
    destColony: destinations[0].systemId,
    ptuAmount: 1  # Conservative: 1 PTU at a time
  ))

proc generateSquadronManagement(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[SquadronManagementOrder] =
  ## Generate squadron management orders (commissioning and fleet assignment)
  ## The engine auto-commissions ships, but AI can manually manage squadrons if needed
  result = @[]

  # Currently the engine handles auto-commissioning well
  # AI can add manual squadron management here if needed for advanced tactics
  # For now, rely on engine's automatic squadron formation

proc generateCargoManagement(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[CargoManagementOrder] =
  ## Generate cargo loading/unloading orders for spacelift operations
  ## Load marines for invasions, colonists for colonization
  result = @[]
  let p = controller.personality

  # Aggressive AI loads marines for invasions
  if p.aggression < 0.4:
    return result

  # Find fleets with spacelift capability at colonies
  for colony in filtered.ownColonies:
    if colony.owner != controller.houseId:
      continue

    # Check if we have fleets here with spacelift ships
    for fleet in filtered.ownFleets:
      if fleet.owner == controller.houseId and fleet.location == colony.systemId:
        # Check if fleet has spacelift capability
        var hasSpacelift = false
        for squadron in fleet.squadrons:
          if squadron.flagship.shipClass in [ShipClass.TroopTransport, ShipClass.ETAC]:
            hasSpacelift = true
            break

        if hasSpacelift:
          # Load marines if we have them and fleet isn't full
          if colony.marines > 5:
            result.add(CargoManagementOrder(
              houseId: controller.houseId,
              colonySystem: colony.systemId,
              action: CargoManagementAction.LoadCargo,
              fleetId: fleet.id,
              cargoType: some(CargoType.Marines),
              quantity: some(3)  # Load 3 marine units
            ))
            return result  # One cargo operation per turn

  return result

proc generateAIOrders*(controller: var AIController, filtered: FilteredGameState, rng: var Rand): OrderPacket =
  ## Generate complete order packet for an AI player using fog-of-war filtered view
  ##
  ## IMPORTANT: AI receives FilteredGameState, NOT full GameState
  ## This enforces limited visibility - AI only sees:
  ## - Own assets (full detail)
  ## - Enemy assets in occupied/owned systems
  ## - Stale intel from intelligence database
  ##
  ## Context available:
  ## - controller.lastTurnReport: Previous turn's report (for AI learning)
  ## - filtered: Fog-of-war filtered game state for this house
  ## - controller.personality: Strategic personality parameters
  ## - controller.intelligence: System intelligence reports
  ## - controller.operations: Coordinated operations
  ##
  ## TODO: Gradually refactor helper functions to use FilteredGameState directly
  ## For now, we create a temporary GameState-like structure for compatibility

  let p = controller.personality
  let house = filtered.ownHouse

  # Strategic planning before generating orders
  # Update operation status (check which fleets have reached assembly points)
  controller.updateOperationStatus(filtered)

  # Phase 2h: Update fallback routes (every 5 turns)
  if filtered.turn mod 5 == 0:
    controller.updateFallbackRoutes(filtered)

  # Manage strategic reserves (assign fleets to defend important colonies)
  controller.manageStrategicReserves(filtered)

  # Plan new coordinated operations if moderately aggressive and have free fleets
  # Threshold: 0.4 allows Balanced strategy (0.5) to invade, not just Aggressive (0.8)
  if p.aggression >= 0.4 and controller.countAvailableFleets(filtered) >= 2:
    let opportunities = controller.identifyInvasionOpportunities(filtered)
    if opportunities.len > 0:
      # Plan invasion of highest-value target
      controller.planCoordinatedInvasion(filtered, opportunities[0], filtered.turn)

  result = OrderPacket(
    houseId: controller.houseId,
    turn: filtered.turn,
    fleetOrders: generateFleetOrders(controller, filtered, rng),
    buildOrders: generateBuildOrders(controller, filtered, rng),
    researchAllocation: generateResearchAllocation(controller, filtered),
    diplomaticActions: generateDiplomaticActions(controller, filtered, rng),
    populationTransfers: generatePopulationTransfers(controller, filtered, rng),
    squadronManagement: generateSquadronManagement(controller, filtered, rng),
    cargoManagement: generateCargoManagement(controller, filtered, rng),
    espionageAction: generateEspionageAction(controller, filtered, rng),
    ebpInvestment: 0,
    cipInvestment: 0
  )

  # Set espionage budget based on personality (not strategy enum)
  # Use riskTolerance + (1-aggression) as proxy for espionage focus
  let espionageFocus = (p.riskTolerance + (1.0 - p.aggression)) / 2.0

  # CRITICAL: Base investment on PRODUCTION (PP), not treasury (IU)
  # This prevents catastrophic over-investment penalties
  let ebpCost = 15  # PP per EBP (from config/espionage.toml)
  let cipCost = 15  # PP per CIP (from config/espionage.toml)
  let safeThreshold = 10  # Stay at 10% threshold (from config/espionage.toml)
  let turnProduction = house.espionageBudget.turnBudget  # Actual production this turn

  # Calculate maximum safe budget that won't trigger penalties
  let maxSafeBudget = turnProduction * safeThreshold div 100

  if espionageFocus > 0.6:
    # High espionage focus - invest up to 10% of production (at threshold)
    let budget = maxSafeBudget
    result.ebpInvestment = min(budget div ebpCost, 50)
    result.cipInvestment = min((budget - (result.ebpInvestment * ebpCost)) div cipCost, 25)
  elif espionageFocus > 0.4:
    # Moderate espionage focus - invest up to 6% of production (below threshold)
    let budget = turnProduction * 6 div 100
    result.ebpInvestment = min(budget div ebpCost, 20)
    result.cipInvestment = min((budget - (result.ebpInvestment * ebpCost)) div cipCost, 10)
  else:
    # Low espionage focus - invest up to 3% of production (well below threshold)
    let budget = turnProduction * 3 div 100
    result.ebpInvestment = min(budget div ebpCost, 10)
    result.cipInvestment = min((budget - (result.ebpInvestment * ebpCost)) div cipCost, 5)

# =============================================================================
# Export
# =============================================================================

export AIStrategy, AIPersonality, AIController
export newAIController, generateAIOrders, getStrategyPersonality
