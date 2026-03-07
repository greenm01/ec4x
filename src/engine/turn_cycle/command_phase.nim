## Command Phase Resolution - Phase 3 of Canonical Turn Cycle
##
## Six-step phase executing server processing and player commands.
## Per docs/engine/ec4x_canonical_turn_cycle.md Phase 3.
##
## **Canonical Steps (CMD1-CMD6):**
## - CMD1: Order Cleanup - Reset completed/stale commands to Hold
## - CMD2: Unified Commissioning - Ships, repairs, colony assets
## - CMD3: Auto-Repair Submission - Queue repairs for autoRepair colonies
## - CMD4: Colony Automation - Auto-load marines/fighters
## - CMD5: Player Submission Window - Colony mgmt, transfers, terraforming
## - CMD6: Order Processing & Validation - Fleet commands, builds, research

import std/[tables, options, random, strformat, sets]

# Logging
import ../../common/logger

# Types
import ../types/[core, game_state, command, fleet, event, tech,
                 production, prestige]

# State Core (reading)
import ../state/[engine, iterators]

# Entity Ops (writing) - none needed; fleet state updates via updateFleet()

# Systems (business logic)
import ../systems/command/commands
import ../systems/production/[commissioning, construction, repairs]
import ../systems/fleet/mechanics
import ../systems/fleet/logistics
import ../systems/colony/[engine, terraforming, salvage]
import ../systems/population/transfers
import ../systems/tech/[costs, advancement]
import ../prestige/engine as prestige_engine
import ../globals
import ../event_factory/init

# =============================================================================
# CMD1: ORDER CLEANUP
# =============================================================================

proc cleanupCompletedCommands(state: GameState, events: seq[GameEvent]) =
  ## [CMD1] Reset completed/failed/aborted commands to Hold + MissionState.None
  ##
  ## Scans events for CommandCompleted/Failed/Aborted and resets those fleets.
  ## Also resets any fleet with stale Executing state (consistency check).

  logInfo("Commands", "[CMD1] Order Cleanup - resetting completed commands")

  # Build set of fleets with completion events
  var completedFleets = initHashSet[FleetId]()
  for event in events:
    if event.eventType in {
      GameEventType.CommandCompleted,
      GameEventType.CommandFailed,
      GameEventType.CommandAborted
    }:
      if event.fleetId.isSome:
        completedFleets.incl(event.fleetId.get())

  # Reset those fleets to Hold + MissionState.None
  var resetCount = 0
  for fleetId in completedFleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isSome:
      var fleet = fleetOpt.get()
      fleet.command = createHoldCommand(fleetId)
      fleet.missionState = MissionState.None
      fleet.missionTarget = none(SystemId)
      state.updateFleet(fleetId, fleet)
      resetCount += 1

  logInfo("Commands", &"[CMD1] Reset {resetCount} fleet commands to Hold")

# =============================================================================
# CMD2: UNIFIED COMMISSIONING
# =============================================================================

proc commissionEntities(state: GameState, events: var seq[GameEvent]) =
  ## [CMD2] Commission ALL pending assets that survived Conflict Phase
  ##
  ## Per canonical spec:
  ## - [CMD2a] Commission ships from Neorias (Spaceports/Shipyards)
  ## - [CMD2b] Commission repaired ships from Drydocks (payment checked here)
  ## - [CMD2c] Commission assets from colony queues (fighters, ground units,
  ##           facilities, starbases)
  ##
  ## No validation needed - if entity exists in state, it survived Conflict
  ## Phase. Destroyed/crippled facilities had queues cleared in CON2.
  ##
  ## NOTE: Ship commissioning (CMD2a, CMD2b) implements CMD4a "Auto-assign
  ## ships to fleets". Ships are always auto-assigned during commissioning.
  ## See commissioning.nim:commissionShip() for fleet assignment logic.

  logInfo("Commands", "[CMD2] Unified Commissioning")

  # Pre-step: Clear damaged facility queues (ships in destroyed docks lost)
  # This is NOT a canonical substep - it's cleanup from Conflict Phase
  logInfo("Commands", "[CMD2-pre] Clearing damaged facility queues...")
  commissioning.clearDamagedFacilityQueues(state, events)

  # Process pending commissions retained from older saved states.
  # New turn resolution now commissions completed work before the next
  # player-facing turn is published.
  if state.pendingCommissions.len > 0:
    # Separate military (ships) from planetary (fighters, ground units,
    # facilities)
    var militaryProjects: seq[CompletedProject] = @[]
    var planetaryProjects: seq[CompletedProject] = @[]

    for project in state.pendingCommissions:
      if project.projectType == BuildType.Ship:
        militaryProjects.add(project)
      else:
        planetaryProjects.add(project)

    # [CMD2a] Commission ships from Neorias (Spaceports/Shipyards)
    # Ships are auto-assigned to fleets (implements CMD4a)
    if militaryProjects.len > 0:
      logInfo("Commands",
        &"[CMD2a] Commissioning {militaryProjects.len} ships from Neorias")
      commissioning.commissionShips(state, militaryProjects, events)
    else:
      logInfo("Commands", "[CMD2a] No ships to commission")

    # [CMD2c] Commission assets from colony queues
    if planetaryProjects.len > 0:
      logInfo("Commands",
        &"[CMD2c] Commissioning {planetaryProjects.len} colony assets")
      commissioning.commissionPlanetaryDefense(state, planetaryProjects, events)
    else:
      logInfo("Commands", "[CMD2c] No colony assets to commission")

    # Clear pending commissions
    state.pendingCommissions = @[]
  else:
    logInfo("Commands", "[CMD2a] No pending commissions")

  # [CMD2b] Commission repaired ships from Drydocks
  # Repairs that completed in Production Phase are marked in repair projects
  # Query for completed repairs and commission them
  # Repaired ships are auto-assigned to fleets (implements CMD4a)
  var completedRepairs: seq[RepairProject] = @[]
  for (repairId, repair) in state.repairProjects.entities.index.pairs:
    let repairOpt = state.repairProject(repairId)
    if repairOpt.isSome:
      let r = repairOpt.get()
      if r.turnsRemaining <= 0:
        completedRepairs.add(r)

  if completedRepairs.len > 0:
    logInfo("Commands",
      &"[CMD2b] Commissioning {completedRepairs.len} repaired ships")
    commissioning.commissionRepairedShips(state, completedRepairs, events)
  else:
    logInfo("Commands", "[CMD2b] No repairs to commission")

  logInfo("Commands", "[CMD2] Unified Commissioning complete")

# =============================================================================
# CMD3: AUTO-REPAIR SUBMISSION
# =============================================================================

proc submitAutoRepairs(state: GameState, events: var seq[GameEvent]) =
  ## [CMD3] Auto-submit repair orders for colonies with autoRepair=true
  ##
  ## Per canonical spec:
  ## - Priority 1: Crippled ships -> Drydock queues
  ## - Priority 2: Crippled starbases -> Colony repair queue
  ## - Priority 2: Crippled ground units -> Colony repair queue
  ## - Priority 3: Crippled Neorias -> Colony repair queue
  ##
  ## Players can cancel/modify these during CMD5 (player window).
  ## Payment happens at commissioning (CMD2 next turn).

  logInfo("Commands", "[CMD3] Auto-Repair Submission")

  var coloniesProcessed = 0
  for colony in state.allColonies():
    if colony.autoRepair:
      repairs.submitAllAutomaticRepairs(state, colony.systemId)
      coloniesProcessed += 1

  logInfo("Commands",
    &"[CMD3] Processed auto-repairs for {coloniesProcessed} colonies")

# =============================================================================
# CMD4: COLONY AUTOMATION
# =============================================================================

proc processColonyAutomation(
    state: GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent]
) =
  ## [CMD4] Automatically organize newly commissioned assets
  ##
  ## Per canonical spec:
  ## - [CMD4a] Auto-assign ships to fleets
  ##   NOTE: Already handled in CMD2 commissioning. Ships are always
  ##   auto-assigned to fleets during commissionShip(). See
  ##   commissioning.nim for implementation.
  ##
  ## - [CMD4b] Auto-load marines onto transports (autoLoadMarines)
  ## - [CMD4c] Auto-load fighters onto carriers (autoLoadFighters)
  ##
  ## Players see organized fleets/cargo in CMD5 (player window).

  logInfo("Commands", "[CMD4] Colony Automation")

  # [CMD4a] Auto-assign ships to fleets
  # NOTE: Handled in CMD2 commissioning - see commissionShip()
  # Ships are always auto-assigned; there is no toggle for this behavior.

  # [CMD4b] Auto-load marines onto transports (autoLoadMarines)
  # [CMD4c] Auto-load fighters onto carriers (autoLoadFighters)
  # autoLoadCargo handles marines; fighters handled by commissioning module
  # via autoLoadFightersToCarriers() after commissioning fighters
  mechanics.autoLoadCargo(state, orders, events)

  logInfo("Commands", "[CMD4] Colony Automation complete")

# =============================================================================
# CMD5: PLAYER SUBMISSION WINDOW
# =============================================================================

proc processPlayerSubmissions(
    state: GameState,
    orders: var Table[HouseId, CommandPacket],
    events: var seq[GameEvent]
) =
  ## [CMD5] Process player-submitted administrative commands
  ##
  ## Per canonical spec:
  ## - [CMD5a] Zero-turn administrative commands (immediate)
  ## - [CMD5b] Query commands (read-only)
  ## - [CMD5c] Command submission (queued for CMD6)
  ##
  ## This step processes colony management, population transfers, terraforming.

  logInfo("Commands", "[CMD5] Player Submission Window")

  for (houseId, house) in state.activeHousesWithId():
    if houseId in orders:
      # Zero-turn administrative commands (execute immediately).
      logInfo("Commands",
        &"[CMD5-ZTC] Processing {orders[houseId].zeroTurnCommands.len} " &
        &"ZTCs for house {houseId}")
      for ztc in orders[houseId].zeroTurnCommands:
        let result = submitZeroTurnCommand(state, ztc, events)
        if result.success:
          # Remap temporary fleet IDs in fleet commands so CMD6 finds
          # the real fleet created by DetachShips.
          if ztc.commandType == ZeroTurnCommandType.DetachShips and
              result.newFleetId.isSome and ztc.newFleetId.isSome:
            let tempId = ztc.newFleetId.get()
            let realId = result.newFleetId.get()
            if tempId != realId:
              for cmd in orders[houseId].fleetCommands.mitems:
                if cmd.fleetId == tempId:
                  cmd.fleetId = realId
        else:
          events.add(
            orderRejected(
              houseId,
              $ztc.commandType,
              result.error,
              fleetId = ztc.sourceFleetId
            )
          )

      # Colony management commands (tax rates, auto-flags)
      state.resolveColonyCommands(orders[houseId])

      # Scrap/salvage commands (zero-turn administrative)
      state.resolveScrapCommands(orders[houseId], events)

      # Population transfers (Space Guild)
      resolvePopulationTransfers(state, orders[houseId], events)

      # Terraforming commands
      terraforming.resolveTerraformCommands(state, orders[houseId], events)

  logInfo("Commands", "[CMD5] Player Submission Window complete")

# =============================================================================
# CMD6: ORDER PROCESSING & VALIDATION
# =============================================================================

proc processResearchDeposits(
    state: GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent]
) =
  ## Process pool-level PP deposits, explicit tech purchases, and liquidation
  ## Per canonical spec CMD6d (new deposit/purchase model)

  for (houseId, _) in state.activeHousesWithId():
    if houseId notin orders:
      continue

    let packet = orders[houseId]
    let deposits = packet.researchDeposits
    let purchases = packet.techPurchases
    let liquidation = packet.researchLiquidation

    var house = state.house(houseId).get()
    var gho = 0'i32
    for colony in state.coloniesOwned(houseId):
      gho += colony.production
    if gho <= 0:
      gho = 1
    let sl = house.techTree.levels.sl
    let ml = house.techTree.levels.ml

    proc applyResearchPrestige(event: PrestigeEvent) =
      house.prestige += event.amount
      state.applyPrestigeEvent(houseId, event)

    # --- Step 1: Liquidation (RP -> PP at 2:1 ratio) ---
    var liquidatedPP = 0'i32
    if liquidation.erp > 0:
      let amount = min(liquidation.erp, house.techTree.accumulated.erp)
      house.techTree.accumulated.erp -= amount
      liquidatedPP += amount div 2
    if liquidation.srp > 0:
      let amount = min(liquidation.srp, house.techTree.accumulated.srp)
      house.techTree.accumulated.srp -= amount
      liquidatedPP += amount div 2
    if liquidation.mrp > 0:
      let amount = min(liquidation.mrp, house.techTree.accumulated.mrp)
      house.techTree.accumulated.mrp -= amount
      liquidatedPP += amount div 2
    if liquidatedPP > 0:
      house.treasury += liquidatedPP
      let prestigePenalty = gameConfig.prestige.penalties.researchLiquidation
      let prestigeEvent = PrestigeEvent(
        source: PrestigeSource.ResearchLiquidation,
        amount: prestigePenalty,
        description: "Research liquidation penalty",
      )
      applyResearchPrestige(prestigeEvent)
      logInfo("Research",
        &"{houseId} liquidated RP for {liquidatedPP} PP")

    # --- Step 2: Validate and apply PP deposits ---
    let totalDepositPP = deposits.erp + deposits.srp + deposits.mrp
    if totalDepositPP > 0:
      let affordable = min(totalDepositPP, house.treasury)
      let scale = if affordable < totalDepositPP:
        float(affordable) / float(totalDepositPP)
      else:
        1.0

      let erpPP = int32(float(deposits.erp) * scale)
      let srpPP = int32(float(deposits.srp) * scale)
      let mrpPP = int32(float(deposits.mrp) * scale)
      let actualPP = erpPP + srpPP + mrpPP

      # Convert PP -> RP per pool
      if erpPP > 0:
        house.techTree.accumulated.erp += convertPPToERP(erpPP, gho, sl)
      if srpPP > 0:
        house.techTree.accumulated.srp += convertPPToSRP(srpPP, gho, sl)
      if mrpPP > 0:
        house.techTree.accumulated.mrp += convertPPToMRP(mrpPP, gho, ml)

      house.treasury -= actualPP
      logInfo("Research",
        &"{houseId} deposited {actualPP} PP into research pools")

    # --- Step 3: Process root-level purchases, then branch techs ---

    # SL purchase first (gates other techs)
    if purchases.science:
      let currentSL = house.techTree.levels.sl
      let cost = slUpgradeCost(currentSL)
      if cost > 0 and house.techTree.accumulated.srp >= cost:
        house.techTree.accumulated.srp -= cost
        house.techTree.levels.sl += 1
        let prestigeAmount = gameConfig.prestige.economic.techAdvancement
        let pe = PrestigeEvent(
          source: PrestigeSource.TechAdvancement,
          amount: prestigeAmount,
          description: "Science Level " & $currentSL & " → " & $(currentSL + 1),
        )
        applyResearchPrestige(pe)
        logInfo("Research",
          &"{houseId} purchased SL {currentSL} -> {currentSL + 1}")

    if purchases.military:
      let currentML = house.techTree.levels.ml
      let cost = mlUpgradeCost(currentML)
      if cost > 0 and house.techTree.accumulated.mrp >= cost:
        house.techTree.accumulated.mrp -= cost
        house.techTree.levels.ml += 1
        let prestigeAmount = gameConfig.prestige.economic.techAdvancement
        let pe = PrestigeEvent(
          source: PrestigeSource.TechAdvancement,
          amount: prestigeAmount,
          description: "Military Level " & $currentML & " → " &
            $(currentML + 1),
        )
        applyResearchPrestige(pe)
        logInfo("Research",
          &"{houseId} purchased ML {currentML} -> {currentML + 1}")

    # EL purchase
    if purchases.economic:
      let currentEL = house.techTree.levels.el
      let cost = elUpgradeCost(currentEL)
      if cost > 0 and house.techTree.accumulated.erp >= cost:
        house.techTree.accumulated.erp -= cost
        house.techTree.levels.el += 1
        let prestigeAmount = gameConfig.prestige.economic.techAdvancement
        let pe = PrestigeEvent(
          source: PrestigeSource.TechAdvancement,
          amount: prestigeAmount,
          description: "Economic Level " & $currentEL & " → " & $(currentEL + 1),
        )
        applyResearchPrestige(pe)
        logInfo("Research",
          &"{houseId} purchased EL {currentEL} -> {currentEL + 1}")

    # Tech field purchases
    for field in purchases.technology:
      let currentLevel =
        case field
        of TechField.ConstructionTech: house.techTree.levels.cst
        of TechField.WeaponsTech: house.techTree.levels.wep
        of TechField.TerraformingTech: house.techTree.levels.ter
        of TechField.ElectronicIntelligence: house.techTree.levels.eli
        of TechField.CloakingTech: house.techTree.levels.clk
        of TechField.ShieldTech: house.techTree.levels.sld
        of TechField.CounterIntelligence: house.techTree.levels.cic
        of TechField.StrategicLiftTech: house.techTree.levels.stl
        of TechField.FlagshipCommandTech: house.techTree.levels.fc
        of TechField.StrategicCommandTech: house.techTree.levels.sc
        of TechField.FighterDoctrine: house.techTree.levels.fd
        of TechField.AdvancedCarrierOps: house.techTree.levels.aco

      let cost = techUpgradeCost(field, currentLevel)
      if cost <= 0:
        continue

      let gateLevel =
        if field.isSrpField():
          house.techTree.levels.sl.int
        else:
          house.techTree.levels.ml.int
      let reqLevel = techGateRequiredForLevel(field, currentLevel.int + 1)
      if gateLevel < reqLevel:
        continue

      # Deduct from appropriate pool
      if field.isSrpField():
        if house.techTree.accumulated.srp < cost:
          continue
        house.techTree.accumulated.srp -= cost
      else:
        if house.techTree.accumulated.mrp < cost:
          continue
        house.techTree.accumulated.mrp -= cost

      # Advance level
      case field
      of TechField.ConstructionTech: house.techTree.levels.cst += 1
      of TechField.WeaponsTech: house.techTree.levels.wep += 1
      of TechField.TerraformingTech: house.techTree.levels.ter += 1
      of TechField.ElectronicIntelligence: house.techTree.levels.eli += 1
      of TechField.CloakingTech: house.techTree.levels.clk += 1
      of TechField.ShieldTech: house.techTree.levels.sld += 1
      of TechField.CounterIntelligence: house.techTree.levels.cic += 1
      of TechField.StrategicLiftTech: house.techTree.levels.stl += 1
      of TechField.FlagshipCommandTech: house.techTree.levels.fc += 1
      of TechField.StrategicCommandTech: house.techTree.levels.sc += 1
      of TechField.FighterDoctrine: house.techTree.levels.fd += 1
      of TechField.AdvancedCarrierOps: house.techTree.levels.aco += 1

      let prestigeAmount = gameConfig.prestige.economic.techAdvancement
      let pe = PrestigeEvent(
        source: PrestigeSource.TechAdvancement,
        amount: prestigeAmount,
        description: $field & " " & $currentLevel & " → " & $(currentLevel + 1),
      )
      applyResearchPrestige(pe)
      logInfo("Research",
        &"{houseId} purchased {field} {currentLevel} -> {currentLevel + 1}")

      # CST dock capacity upgrade
      if field == TechField.ConstructionTech:
        applyDockCapacityUpgrade(state, houseId)

    # Write back house changes
    state.updateHouse(houseId, house)

proc processOrderValidation(
    state: GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent]
) =
  ## [CMD6] Validate and store fleet commands, process builds and research
  ##
  ## Per canonical spec:
  ## - [CMD6a] Validate fleet commands (store in Fleet.command)
  ## - [CMD6b] Process build orders (pay PP upfront)
  ## - [CMD6c] Process repair orders (manual)
  ## - [CMD6d] Process tech research allocation

  logInfo("Commands", "[CMD6] Order Processing & Validation")

  # [CMD6a] Validate and store fleet commands
  logInfo("Commands", "[CMD6a] Validating fleet commands...")
  var ordersStored = 0
  var ordersRejected = 0

  for (houseId, house) in state.activeHousesWithId():
    if houseId notin orders:
      continue

    for cmd in orders[houseId].fleetCommands:
      let validation = validateFleetCommand(cmd, state, houseId)

      if validation.valid:
        let fleetOpt = state.fleet(cmd.fleetId)
        if fleetOpt.isSome:
          var fleet = fleetOpt.get()
          fleet.command = cmd
          fleet.missionState = MissionState.Traveling
          fleet.missionTarget = cmd.targetSystem
          state.updateFleet(cmd.fleetId, fleet)
          ordersStored += 1

          logDebug("Commands",
            &"  [STORED] Fleet {cmd.fleetId}: {cmd.commandType}")
      else:
        ordersRejected += 1
        logDebug("Commands",
          &"  [REJECTED] Fleet {cmd.fleetId}: {cmd.commandType} - " &
          validation.error)
        events.add(
          orderRejected(
            houseId,
            $cmd.commandType,
            validation.error,
            fleetId = some(cmd.fleetId)
          )
        )

  logInfo("Commands",
    &"[CMD6a] Fleet commands: {ordersStored} stored, {ordersRejected} rejected")

  # [CMD6b] Process build orders (pay PP upfront)
  logInfo("Commands", "[CMD6b] Processing build orders...")
  for (houseId, house) in state.activeHousesWithId():
    if houseId in orders:
      construction.resolveBuildOrders(state, orders[houseId], events)

  # [CMD6c] Process manual repair orders
  logInfo("Commands", "[CMD6c] Processing manual repair orders...")
  for (houseId, house) in state.activeHousesWithId():
    if houseId in orders:
      for repairCmd in orders[houseId].repairCommands:
        discard repairs.processManualRepairCommand(state, repairCmd)

  # [CMD6d] Process tech research deposits + purchases + liquidation
  logInfo("Commands", "[CMD6d] Processing research deposits...")
  processResearchDeposits(state, orders, events)

  logInfo("Commands", "[CMD6] Order Processing & Validation complete")

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

proc resolveCommandPhase*(
    state: GameState,
    orders: var Table[HouseId, CommandPacket],
    events: var seq[GameEvent],
    rng: var Rand,
) =
  ## Command Phase Resolution - Phase 3 of Canonical Turn Cycle
  ##
  ## Executes six steps per docs/engine/ec4x_canonical_turn_cycle.md:
  ## - CMD1: Order Cleanup
  ## - CMD2: Unified Commissioning (includes CMD4a auto-assign to fleets)
  ## - CMD3: Auto-Repair Submission
  ## - CMD4: Colony Automation (auto-load marines/fighters)
  ## - CMD5: Player Submission Window
  ## - CMD6: Order Processing & Validation

  logInfo("Commands", &"=== Command Phase === (turn={state.turn})")

  # CMD1: Order Cleanup
  state.cleanupCompletedCommands(events)

  # CMD2: Unified Commissioning
  state.commissionEntities(events)

  # CMD3: Auto-Repair Submission
  state.submitAutoRepairs(events)

  # CMD4: Colony Automation
  state.processColonyAutomation(orders, events)

  # CMD5: Player Submission Window
  state.processPlayerSubmissions(orders, events)

  # CMD6: Order Processing & Validation
  state.processOrderValidation(orders, events)

  logInfo("Commands", "=== Command Phase Complete ===")
