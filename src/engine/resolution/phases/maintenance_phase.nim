## Maintenance Phase - Phase 0A Step: Upkeep, effect decrements, and status updates
##
## This module handles the Maintenance Phase of turn resolution, including:
## - Decrementing ongoing espionage effect counters
## - Expiring pending diplomatic proposals
## - Processing Space Guild population transfers
## - Processing active terraforming projects
## - Updating diplomatic status timers (dishonored, isolation)
## - Running maintenance engine for construction queues
## - Checking elimination conditions (no colonies, defensive collapse)
## - Enforcing squadron capacity limits (fighters, planet-breakers, capitals)
## - Processing tech advancements (EL, SL, TechFields)
## - Checking victory conditions
##
## This is part of the Phase 0A refactoring to separate resolution phases
## into focused, single-responsibility modules.

import std/[tables, options, strformat, strutils, algorithm, sequtils, random]
import ../../../common/[types/core, types/units, types/tech]
import ../../gamestate, ../../orders, ../../logger
import ../../order_types
import ../fleet_order_execution  # For movement order execution
import ../../economy/[types as econ_types, engine as econ_engine]
# Capacity enforcement imports removed - now in income_phase.nim
import ../../research/[types as res_types, advancement]
import ../../espionage/[types as esp_types]
import ../../diplomacy/[proposals as dip_proposals]
import ../../population/[types as pop_types]
import ../../config/[gameplay_config, population_config]
import ../[types as res_types_common]
import ../fleet_orders  # For findClosestOwnedColony
import ../diplomatic_resolution
import ../../prestige

# Forward declaration for helper procs
proc resolvePopulationArrivals*(state: var GameState,
                                events: var seq[GameEvent])
proc processTerraformingProjects(state: var GameState,
                                  events: var seq[GameEvent])

proc resolvePopulationArrivals*(state: var GameState,
                                events: var seq[GameEvent]) =
  ## Process Space Guild population transfers that arrive this turn
  ## Implements risk handling per config/population.toml [transfer_risks]
  ## Per config: dest_blockaded_behavior = "closest_owned"
  ## Per config: dest_collapsed_behavior = "closest_owned"
  logDebug(LogCategory.lcGeneral, &"[Processing Space Guild Arrivals]")

  var arrivedTransfers: seq[int] = @[]  # Indices to remove after processing

  for idx, transfer in state.populationInTransit:
    if transfer.arrivalTurn != state.turn:
      continue  # Not arriving this turn

    let soulsToDeliver = transfer.ptuAmount * soulsPerPtu()

    # Check destination status
    if transfer.destSystem notin state.colonies:
      # Destination colony no longer exists
      logWarn(LogCategory.lcEconomy,
        &"Transfer {transfer.id}: {transfer.ptuAmount} PTU LOST - " &
        &"destination colony destroyed")
      arrivedTransfers.add(idx)
      events.add(GameEvent(
        eventType: GameEventType.PopulationTransfer,
        houseId: transfer.houseId,
        description: $transfer.ptuAmount & " PTU lost - destination " &
                    $transfer.destSystem & " destroyed",
        systemId: some(transfer.destSystem)
      ))
      continue

    var destColony = state.colonies[transfer.destSystem]

    # Check if destination requires alternative delivery
    # Space Guild makes best-faith effort to deliver somewhere safe
    # Per config/population.toml: dest_blockaded_behavior = "closest_owned"
    # Per config/population.toml: dest_collapsed_behavior = "closest_owned"
    # Per config/population.toml: dest_conquered_behavior = "closest_owned"
    var needsAlternativeDestination = false
    var alternativeReason = ""

    if destColony.owner != transfer.houseId:
      # Destination conquered - Guild tries to find alternative colony
      needsAlternativeDestination = true
      alternativeReason = "conquered by " & $destColony.owner
    elif destColony.blockaded:
      needsAlternativeDestination = true
      alternativeReason = "blockaded"
    elif destColony.souls < soulsPerPtu():
      needsAlternativeDestination = true
      alternativeReason = "collapsed below minimum viable population"

    if needsAlternativeDestination:
      # Space Guild attempts to deliver to closest owned colony
      let alternativeDest = findClosestOwnedColony(state, transfer.destSystem,
                                                   transfer.houseId)

      if alternativeDest.isSome:
        # Deliver to alternative colony
        let altSystemId = alternativeDest.get()
        var altColony = state.colonies[altSystemId]
        altColony.souls += soulsToDeliver
        altColony.population = altColony.souls div 1_000_000
        state.colonies[altSystemId] = altColony

        logWarn(LogCategory.lcEconomy,
          &"Transfer {transfer.id}: {transfer.ptuAmount} PTU redirected to " &
          &"{altSystemId} - original destination {transfer.destSystem} " &
          &"{alternativeReason}")
        events.add(GameEvent(
          eventType: GameEventType.PopulationTransfer,
          houseId: transfer.houseId,
          description: $transfer.ptuAmount & " PTU redirected from " &
                      $transfer.destSystem & " (" & alternativeReason &
                      ") to " & $altSystemId,
          systemId: some(altSystemId)
        ))
      else:
        # No owned colonies - colonists are lost
        logWarn(LogCategory.lcEconomy,
          &"Transfer {transfer.id}: {transfer.ptuAmount} PTU LOST - " &
          &"destination {alternativeReason}, no owned colonies available")
        events.add(GameEvent(
          eventType: GameEventType.PopulationTransfer,
          houseId: transfer.houseId,
          description: $transfer.ptuAmount & " PTU lost - " &
                      $transfer.destSystem & " " & alternativeReason &
                      ", no owned colonies for delivery",
          systemId: some(transfer.destSystem)
        ))

      arrivedTransfers.add(idx)
      continue

    # Successful delivery!
    destColony.souls += soulsToDeliver
    destColony.population = destColony.souls div 1_000_000
    state.colonies[transfer.destSystem] = destColony

    logInfo(LogCategory.lcEconomy,
      &"Transfer {transfer.id}: {transfer.ptuAmount} PTU arrived at " &
      &"{transfer.destSystem} ({soulsToDeliver} souls)")
    events.add(GameEvent(
      eventType: GameEventType.PopulationTransfer,
      houseId: transfer.houseId,
      description: $transfer.ptuAmount & " PTU arrived at " &
                  $transfer.destSystem & " from " & $transfer.sourceSystem,
      systemId: some(transfer.destSystem)
    ))

    arrivedTransfers.add(idx)

  # Remove processed transfers (in reverse order to preserve indices)
  for idx in countdown(arrivedTransfers.len - 1, 0):
    state.populationInTransit.del(arrivedTransfers[idx])

proc processTerraformingProjects(state: var GameState,
                                  events: var seq[GameEvent]) =
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

      logInfo(LogCategory.lcEconomy,
        &"{house.name} completed terraforming of {colonyId} to {className} " &
        &"(class {project.targetClass})")

      events.add(GameEvent(
        eventType: GameEventType.TerraformComplete,
        houseId: houseId,
        description: house.name & " completed terraforming colony " &
                    $colonyId & " to " & className,
        systemId: some(colonyId)
      ))
    else:
      logDebug(LogCategory.lcEconomy,
        &"{house.name} terraforming {colonyId}: {project.turnsRemaining} " &
        &"turn(s) remaining")
      # Update project
      colony.activeTerraforming = some(project)

proc resolveMaintenancePhase*(state: var GameState,
                              events: var seq[GameEvent],
                              orders: Table[HouseId, OrderPacket],
                              rng: var Rand):
                              seq[econ_types.CompletedProject] =
  ## Phase 4: Upkeep, effect decrements, and diplomatic status updates
  ## Returns completed projects for commissioning in next turn's Command Phase
  logDebug(LogCategory.lcGeneral, &"[Maintenance Phase]")

  result = @[]  # Will collect completed projects from construction queues

  # ===================================================================
  # STEP 1: FLEET MOVEMENT
  # ===================================================================
  # Per FINAL_TURN_SEQUENCE.md: "Movement orders execute Turn N Maintenance Phase"
  # Execute all movement orders (Move, SeekHome, Patrol, Hold)
  logDebug(LogCategory.lcGeneral, "[MAINTENANCE] Step 1: Fleet Movement")

  var combatReports: seq[res_types_common.CombatReport] = @[]
  fleet_order_execution.executeFleetOrdersFiltered(
    state,
    orders,
    events,
    combatReports,
    rng,
    isMovementOrder,  # Filter: only movement orders
    "Maintenance Phase - Fleet Movement"
  )

  # Decrement ongoing espionage effect counters
  var remainingEffects: seq[esp_types.OngoingEffect] = @[]
  for effect in state.ongoingEffects:
    var updatedEffect = effect
    updatedEffect.turnsRemaining -= 1

    if updatedEffect.turnsRemaining > 0:
      remainingEffects.add(updatedEffect)
      logDebug(LogCategory.lcGeneral,
        &"Effect on {updatedEffect.targetHouse} expires in " &
        &"{updatedEffect.turnsRemaining} turn(s)")
    else:
      logDebug(LogCategory.lcGeneral,
        &"Effect on {updatedEffect.targetHouse} has expired")

  state.ongoingEffects = remainingEffects

  # Expire pending diplomatic proposals
  for proposal in state.pendingProposals.mitems:
    if proposal.status == dip_proposals.ProposalStatus.Pending:
      proposal.expiresIn -= 1

      if proposal.expiresIn <= 0:
        proposal.status = dip_proposals.ProposalStatus.Expired
        logDebug(LogCategory.lcGeneral,
          &"Proposal {proposal.id} expired ({proposal.proposer} → " &
          &"{proposal.target})")

  # Clean up old proposals (keep 10 turn history)
  let currentTurn = state.turn
  state.pendingProposals.keepIf(proc(p: dip_proposals.PendingProposal): bool =
    p.status == dip_proposals.ProposalStatus.Pending or
    (currentTurn - p.submittedTurn) < 10
  )

  # Process Space Guild population transfers arriving this turn
  resolvePopulationArrivals(state, events)

  # Process diplomatic actions (moved from Command Phase)
  # Diplomatic state changes happen AFTER all commands execute
  diplomatic_resolution.resolveDiplomaticActions(state, orders)

  # Process active terraforming projects
  processTerraformingProjects(state, events)

  # Update diplomatic status timers for all houses
  for houseId, house in state.houses.mpairs:
    # Update dishonored status
    if house.dishonoredStatus.active:
      house.dishonoredStatus.turnsRemaining -= 1
      if house.dishonoredStatus.turnsRemaining <= 0:
        house.dishonoredStatus.active = false
        logInfo(LogCategory.lcGeneral,
          &"{house.name} is no longer dishonored")

    # Update diplomatic isolation
    if house.diplomaticIsolation.active:
      house.diplomaticIsolation.turnsRemaining -= 1
      if house.diplomaticIsolation.turnsRemaining <= 0:
        house.diplomaticIsolation.active = false
        logInfo(LogCategory.lcGeneral,
          &"{house.name} is no longer diplomatically isolated")

  # Call maintenance engine with full state support
  # This properly advances both facility queues (capital ships) AND
  # colony queues (fighters/buildings)
  let maintenanceReport = econ_engine.resolveMaintenancePhaseWithState(state)

  # Collect completed projects for commissioning (happens in next turn's
  # Command Phase)
  result.add(maintenanceReport.completedProjects)

  logInfo(LogCategory.lcEconomy,
    &"Maintenance phase complete: {result.len} projects ready for " &
    &"commissioning")

  # Check for elimination and defensive collapse
  let gameplayConfig = globalGameplayConfig
  for houseId, house in state.houses:
    # Standard elimination: no colonies and no invasion capability
    let colonies = state.getHouseColonies(houseId)
    let fleets = state.getHouseFleets(houseId)

    if colonies.len == 0:
      # No colonies - check if house has invasion capability
      # (marines on transports)
      var hasInvasionCapability = false

      for fleet in fleets:
        for transport in fleet.spaceLiftShips:
          if transport.cargo.cargoType == CargoType.Marines and
             transport.cargo.quantity > 0:
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
        logInfo(LogCategory.lcGeneral,
          &"{house.name} eliminated! ({reason})")
        continue

    # Defensive collapse: prestige < threshold for consecutive turns
    # CRITICAL: Get house once, modify elimination/counter, write back
    var houseToUpdate = state.houses[houseId]

    if house.prestige <
       gameplayConfig.elimination.defensive_collapse_threshold:
      houseToUpdate.negativePrestigeTurns += 1
      logWarn(LogCategory.lcGeneral,
        &"{house.name} at risk: prestige {house.prestige} " &
        &"({houseToUpdate.negativePrestigeTurns}/" &
        &"{gameplayConfig.elimination.defensive_collapse_turns} turns " &
        &"until elimination)")

      if houseToUpdate.negativePrestigeTurns >=
         gameplayConfig.elimination.defensive_collapse_turns:
        houseToUpdate.eliminated = true
        houseToUpdate.status = HouseStatus.DefensiveCollapse
        events.add(GameEvent(
          eventType: GameEventType.HouseEliminated,
          houseId: houseId,
          description: house.name & " has collapsed from negative prestige!",
          systemId: none(SystemId)
        ))
        logInfo(LogCategory.lcGeneral,
          &"{house.name} eliminated by defensive collapse!")
    else:
      # Reset counter when prestige recovers
      houseToUpdate.negativePrestigeTurns = 0

    # Write back modified house
    state.houses[houseId] = houseToUpdate

  # ===================================================================
  # CAPACITY ENFORCEMENT MOVED TO INCOME PHASE
  # ===================================================================
  # Per FINAL_TURN_SEQUENCE.md, capacity enforcement now happens in Income
  # Phase Step 5 (AFTER IU loss from blockades/combat, BEFORE resource
  # collection).
  #
  # This ensures capacity limits are enforced based on the turn's actual IU
  # after all combat/blockade effects are applied.
  #
  # See: src/engine/resolution/phases/income_phase.nim lines 309-383

  # Process tech advancements
  # Per economy.md:4.1: Tech upgrades can be purchased EVERY TURN if RP
  # is available
  logDebug(LogCategory.lcGeneral, &"Tech Advancement")
  for houseId, house in state.houses.mpairs:
    # Try to advance Economic Level (EL) with accumulated ERP
    let currentEL = house.techTree.levels.economicLevel
    let elAdv = attemptELAdvancement(house.techTree, currentEL)
    if elAdv.isSome:
      let adv = elAdv.get()
      logInfo(LogCategory.lcResearch,
        &"{house.name}: EL {adv.elFromLevel} → {adv.elToLevel} " &
        &"(spent {adv.elCost} ERP)")
      if adv.prestigeEvent.isSome:
        applyPrestigeEvent(state, houseId, adv.prestigeEvent.get())
        logDebug(LogCategory.lcResearch,
          &"+{adv.prestigeEvent.get().amount} prestige")
      events.add(GameEvent(
        eventType: GameEventType.TechAdvance,
        houseId: houseId,
        description: &"Economic Level advanced to {adv.elToLevel}",
        systemId: none(SystemId)
      ))

    # Try to advance Science Level (SL) with accumulated SRP
    let currentSL = house.techTree.levels.scienceLevel
    let slAdv = attemptSLAdvancement(house.techTree, currentSL)
    if slAdv.isSome:
      let adv = slAdv.get()
      logInfo(LogCategory.lcResearch,
        &"{house.name}: SL {adv.slFromLevel} → {adv.slToLevel} " &
        &"(spent {adv.slCost} SRP)")
      if adv.prestigeEvent.isSome:
        applyPrestigeEvent(state, houseId, adv.prestigeEvent.get())
        logDebug(LogCategory.lcResearch,
          &"+{adv.prestigeEvent.get().amount} prestige")
      events.add(GameEvent(
        eventType: GameEventType.TechAdvance,
        houseId: houseId,
        description: &"Science Level advanced to {adv.slToLevel}",
        systemId: none(SystemId)
      ))

    # Try to advance technology fields with accumulated TRP
    for field in [TechField.ConstructionTech, TechField.WeaponsTech,
                  TechField.TerraformingTech, TechField.ElectronicIntelligence,
                  TechField.CounterIntelligence]:
      let advancement = attemptTechAdvancement(house.techTree, field)
      if advancement.isSome:
        let adv = advancement.get()
        logInfo(LogCategory.lcResearch,
          &"{house.name}: {field} {adv.techFromLevel} → " &
          &"{adv.techToLevel} (spent {adv.techCost} TRP)")

        # Apply prestige if available
        if adv.prestigeEvent.isSome:
          applyPrestigeEvent(state, houseId, adv.prestigeEvent.get())
          logDebug(LogCategory.lcResearch,
            &"+{adv.prestigeEvent.get().amount} prestige")

        # Generate event
        events.add(GameEvent(
          eventType: GameEventType.TechAdvance,
          houseId: houseId,
          description: &"{field} advanced to level {adv.techToLevel}",
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

    logInfo(LogCategory.lcGeneral,
      &"*** {victorName} has won the game! ***")
