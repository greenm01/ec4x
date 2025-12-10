## Maintenance Phase Resolution - Phase 4 of Canonical Turn Cycle
##
## Server batch processing phase: fleet movement, construction advancement,
## diplomatic state changes, and timer updates.
##
## **Canonical Execution Order:**
##
## Step 1: Fleet Movement
## - Step 1a: Execute standing orders for fleets without explicit orders
##   * Standing orders generate fleet orders (Move, Colonize, SeekHome, etc.)
##   * Orders written to state.fleetOrders for Step 1b execution
## - Step 1b: Execute movement orders (from Command Phase Part C + standing orders)
##   * Orders: Move, SeekHome, Patrol, Hold
##   * Movement happens AFTER player submission to prevent tactical exploits
##
## Step 2: Construction & Repair Advancement
## - Advance all facility construction queues (capital ships at shipyards)
## - Advance all colony construction queues (fighters, buildings at spaceports)
## - Advance all repair queues (damaged ships, facilities)
## - Store completed projects in state.pendingCommissions for next turn's commissioning
##
## Step 3: Diplomatic Actions
## - Process diplomatic state changes (from Command Phase proposals)
## - State changes take effect AFTER all command processing complete
## - Ensures consistent turn boundary for treaty activations
##
## Step 4: Population Arrivals
## - Process Space Guild population transfers completing this turn
## - Handle blockaded/conquered destination fallback to nearest owned colony
##
## Step 5: Terraforming Projects
## - Advance active terraforming projects on colonies
## - Complete projects when timer reaches zero
##
## Step 6: Cleanup & Timer Updates
## - Decrement ongoing espionage effect counters
## - Expire pending diplomatic proposals (timeout tracking)
## - Update diplomatic status timers (dishonored status, isolation penalties)
## - Advance capacity enforcement grace period timers (from Income Phase Step 5)
##
## **Research Advancement:** (not a numbered step, happens after Step 6)
## - Attempt EL (Economic Level) upgrades with accumulated ERP
## - Attempt SL (Science Level) upgrades with accumulated SRP
## - Attempt TechField upgrades with accumulated TRP
## - Uses RP accumulated from Income Phase Step 6
##
## **Key Properties:**
## - Completed projects stored in pendingCommissions, NOT commissioned immediately
## - Commissioning happens next turn's Command Phase Part A
## - Fleet movement happens LAST to position units for next Conflict Phase

import std/[tables, options, strformat, strutils, algorithm, sequtils, random]
import ../../../common/[types/core, types/units, types/tech]
import ../../gamestate, ../../orders, ../../logger
import ../../order_types
import ../fleet_order_execution  # For movement order execution
import ../../economy/[types as econ_types, engine as econ_engine, facility_queue]
# Capacity enforcement imports removed - now in income_phase.nim
import ../../research/[types as res_types, advancement]
import ../commissioning  # For planetary defense commissioning
import ../../espionage/[types as esp_types]
import ../../diplomacy/[proposals as dip_proposals]
import ../../population/[types as pop_types]
import ../../config/[gameplay_config, population_config]
import ../[types as res_types_common]
import ../fleet_orders  # For findClosestOwnedColony
import ../diplomatic_resolution
import ../event_factory/init as event_factory
import ../../prestige
import ../../standing_orders  # For standing order execution

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
      events.add(event_factory.populationTransfer(
        transfer.houseId,
        transfer.ptuAmount,
        transfer.sourceSystem,
        transfer.destSystem,
        false,
        "destination destroyed"
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
        events.add(event_factory.populationTransfer(
          transfer.houseId,
          transfer.ptuAmount,
          transfer.sourceSystem,
          altSystemId,
          true,
          &"redirected from {transfer.destSystem} ({alternativeReason})"
        ))
      else:
        # No owned colonies - colonists are lost
        logWarn(LogCategory.lcEconomy,
          &"Transfer {transfer.id}: {transfer.ptuAmount} PTU LOST - " &
          &"destination {alternativeReason}, no owned colonies available")
        events.add(event_factory.populationTransfer(
          transfer.houseId,
          transfer.ptuAmount,
          transfer.sourceSystem,
          transfer.destSystem,
          false,
          &"{alternativeReason}, no owned colonies for delivery"
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
    events.add(event_factory.populationTransfer(
      transfer.houseId,
      transfer.ptuAmount,
      transfer.sourceSystem,
      transfer.destSystem,
      true,
      ""
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

      events.add(event_factory.terraformComplete(
        houseId,
        colonyId,
        className
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
  logInfo(LogCategory.lcOrders, &"=== Maintenance Phase === (turn={state.turn})")

  result = @[]  # Will collect completed projects from construction queues

  # ===================================================================
  # STEP 1: FLEET MOVEMENT
  # ===================================================================
  # Per FINAL_TURN_SEQUENCE.md: "Movement orders execute Turn N Maintenance Phase"

  # Step 1a: Execute standing orders for fleets without explicit orders
  # Standing orders generate fleet orders (Move, Colonize, SeekHome, etc.)
  # These are written to state.fleetOrders and picked up by Step 1b
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 1a] Executing standing orders...")
  standing_orders.executeStandingOrders(state, state.turn)
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 1a] Completed standing order execution")

  # Step 1b: Execute all movement orders (Move, SeekHome, Patrol, Hold)
  # Includes orders generated by standing orders in Step 1a
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 1b] Fleet movement execution...")
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
  logInfo(LogCategory.lcOrders, &"[MAINTENANCE STEP 1b] Completed ({combatReports.len} movement orders executed)")

  # ===================================================================
  # STEPS 4-6: POPULATION, TERRAFORMING, CLEANUP
  # ===================================================================
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEPS 4-6] Processing population, terraforming, cleanup...")

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

  # ===================================================================
  # STEP 3: DIPLOMATIC ACTIONS
  # ===================================================================
  # Process diplomatic actions (moved from Command Phase)
  # Diplomatic state changes happen AFTER all commands execute
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 3] Processing diplomatic actions...")
  diplomatic_resolution.resolveDiplomaticActions(state, orders)
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 3] Completed diplomatic actions")

  # Process active terraforming projects
  processTerraformingProjects(state, events)

  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEPS 4-6] Completed population/terraforming/cleanup")

  # ===================================================================
  # STEP 2: CONSTRUCTION & REPAIR ADVANCEMENT
  # ===================================================================
  # Advance construction queues for both facilities (capital ships) and
  # colonies (fighters/buildings)
  logInfo(LogCategory.lcEconomy, "[MAINTENANCE STEP 2] Advancing construction & repair queues...")
  let maintenanceReport = econ_engine.resolveMaintenancePhaseWithState(state)

  # Split completed projects by commissioning phase
  var planetaryProjects: seq[econ_types.CompletedProject] = @[]
  var militaryProjects: seq[econ_types.CompletedProject] = @[]

  for project in maintenanceReport.completedProjects:
    if facility_queue.isPlanetaryDefense(project):
      planetaryProjects.add(project)
    else:
      militaryProjects.add(project)

  # Step 2a: Commission planetary defense immediately (same turn)
  if planetaryProjects.len > 0:
    logInfo(LogCategory.lcEconomy,
      &"[MAINTENANCE STEP 2a] Commissioning {planetaryProjects.len} planetary defense assets")
    commissioning.commissionPlanetaryDefense(state, planetaryProjects, events)

  # Collect military projects for next turn's Command Phase commissioning
  result.add(militaryProjects)

  logInfo(LogCategory.lcEconomy,
    &"[MAINTENANCE STEP 2] Completed ({planetaryProjects.len} planetary commissioned, " &
    &"{militaryProjects.len} military pending)")

  # ===================================================================
  # HOUSE ELIMINATION CHECKS MOVED TO INCOME PHASE
  # ===================================================================
  # Per canonical turn cycle: House elimination checks happen in Income Phase Step 8
  # See: src/engine/resolution/phases/income_phase.nim (Step 8a)

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

  # ===================================================================
  # RESEARCH ADVANCEMENT
  # ===================================================================
  # Process tech advancements
  # Per economy.md:4.1: Tech upgrades can be purchased EVERY TURN if RP
  # is available
  logInfo(LogCategory.lcOrders, "[MAINTENANCE] Processing research advancements...")
  var totalAdvancements = 0
  for houseId, house in state.houses.mpairs:
    # Try to advance Economic Level (EL) with accumulated ERP
    let currentEL = house.techTree.levels.economicLevel
    let elAdv = attemptELAdvancement(house.techTree, currentEL)
    if elAdv.isSome:
      totalAdvancements += 1
      let adv = elAdv.get()
      logInfo(LogCategory.lcResearch,
        &"{house.name}: EL {adv.elFromLevel} → {adv.elToLevel} " &
        &"(spent {adv.elCost} ERP)")
      if adv.prestigeEvent.isSome:
        applyPrestigeEvent(state, houseId, adv.prestigeEvent.get())
        logDebug(LogCategory.lcResearch,
          &"+{adv.prestigeEvent.get().amount} prestige")
      events.add(event_factory.techAdvance(
        houseId,
        "Economic Level",
        adv.elToLevel
      ))

    # Try to advance Science Level (SL) with accumulated SRP
    let currentSL = house.techTree.levels.scienceLevel
    let slAdv = attemptSLAdvancement(house.techTree, currentSL)
    if slAdv.isSome:
      totalAdvancements += 1
      let adv = slAdv.get()
      logInfo(LogCategory.lcResearch,
        &"{house.name}: SL {adv.slFromLevel} → {adv.slToLevel} " &
        &"(spent {adv.slCost} SRP)")
      if adv.prestigeEvent.isSome:
        applyPrestigeEvent(state, houseId, adv.prestigeEvent.get())
        logDebug(LogCategory.lcResearch,
          &"+{adv.prestigeEvent.get().amount} prestige")
      events.add(event_factory.techAdvance(
        houseId,
        "Science Level",
        adv.slToLevel
      ))

    # Try to advance technology fields with accumulated TRP
    for field in [TechField.ConstructionTech, TechField.WeaponsTech,
                  TechField.TerraformingTech, TechField.ElectronicIntelligence,
                  TechField.CounterIntelligence]:
      let advancement = attemptTechAdvancement(state, houseId, house.techTree, field)
      if advancement.isSome:
        totalAdvancements += 1
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
        events.add(event_factory.techAdvance(
          houseId,
          $field,
          adv.techToLevel
        ))

  logInfo(LogCategory.lcOrders, &"[MAINTENANCE] Research advancements completed ({totalAdvancements} total advancements)")

  # Victory condition check moved to Income Phase (per FINAL_TURN_SEQUENCE.md)
