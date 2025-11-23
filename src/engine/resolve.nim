## Turn resolution engine - the heart of EC4X gameplay
##
## OFFLINE GAMEPLAY SYSTEM - No network dependencies
## This module is designed to work standalone for local/hotseat multiplayer
## Network transport (Nostr) wraps around this engine without modifying it

import std/[tables, algorithm, options, random, strformat, sequtils, strutils, hashes, math]
import ../common/[hex, types/core, types/combat, types/tech, types/units]
import gamestate, orders, fleet, ship, starmap, squadron, spacelift
import economy/[types as econ_types, engine as econ_engine, construction, maintenance]
import research/[types as res_types, advancement, costs as res_costs]
import espionage/[types as esp_types, engine as esp_engine]
import diplomacy/[types as dip_types, engine as dip_engine]
import colonization/engine as col_engine
import combat/[engine as combat_engine, types as combat_types, ground]
import population/[types as pop_types]
import config/[prestige_config, espionage_config, gameplay_config, construction_config, military_config]
import commands/executor
import blockade/engine as blockade_engine
import intelligence/detection
import prestige

# TODO: Load from config/population.toml at startup
# For now using defaults from docs/specs/economy.md and config/population.toml
const
  DEFAULT_SOULS_PER_PTU = 50000  # 1 PTU = 50k souls (exact integer count)
  DEFAULT_PTU_SIZE_MILLIONS = 0.05  # For population display field conversion

type
  TurnResult* = object
    newState*: GameState
    events*: seq[GameEvent]
    combatReports*: seq[CombatReport]

  GameEvent* = object
    eventType*: GameEventType
    houseId*: HouseId
    description*: string
    systemId*: Option[SystemId]

  GameEventType* {.pure.} = enum
    ColonyEstablished, SystemCaptured, BattleOccurred, Battle, Bombardment,
    TechAdvance, FleetDestroyed, HouseEliminated, PopulationTransfer

  CombatReport* = object
    systemId*: SystemId
    attackers*: seq[HouseId]
    defenders*: seq[HouseId]
    attackerLosses*: int
    defenderLosses*: int
    victor*: Option[HouseId]

# Forward declarations for phase functions
proc resolveIncomePhase(state: var GameState, orders: Table[HouseId, OrderPacket])
proc resolveCommandPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                        events: var seq[GameEvent])
proc resolveConflictPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                         combatReports: var seq[CombatReport], events: var seq[GameEvent])
proc resolveMaintenancePhase(state: var GameState, events: var seq[GameEvent])

# Forward declarations for helper functions
proc resolveBuildOrders(state: var GameState, packet: OrderPacket, events: var seq[GameEvent])
proc resolveSquadronManagement(state: var GameState, packet: OrderPacket, events: var seq[GameEvent])
proc resolveCargoManagement(state: var GameState, packet: OrderPacket, events: var seq[GameEvent])
proc autoLoadCargo(state: var GameState, orders: Table[HouseId, OrderPacket], events: var seq[GameEvent])
proc resolvePopulationTransfers(state: var GameState, packet: OrderPacket, events: var seq[GameEvent])
proc resolvePopulationArrivals(state: var GameState, events: var seq[GameEvent])
proc resolveMovementOrder*(state: var GameState, houseId: HouseId, order: FleetOrder,
                         events: var seq[GameEvent])
proc resolveColonizationOrder(state: var GameState, houseId: HouseId, order: FleetOrder,
                              events: var seq[GameEvent])
proc resolveBattle(state: var GameState, systemId: SystemId,
                  combatReports: var seq[CombatReport], events: var seq[GameEvent])
proc resolveBombardment(state: var GameState, houseId: HouseId, order: FleetOrder,
                       events: var seq[GameEvent])

## Main Turn Resolution

proc resolveTurn*(state: GameState, orders: Table[HouseId, OrderPacket]): TurnResult =
  ## Resolve a complete game turn
  ## Returns new game state and events that occurred

  result.newState = state  # Start with current state
  result.events = @[]
  result.combatReports = @[]

  # Initialize RNG for this turn (use turn number as seed for reproducibility)
  var rng = initRand(state.turn)

  echo "Resolving turn ", state.turn, " (Year ", state.year, ", Month ", state.month, ")"

  # Phase 1: Conflict Phase
  # - Resolve space battles
  # - Process bombardments
  # - Resolve invasions
  # - Damage infrastructure (shipyards, starbases, planetary improvements)
  # NOTE: Conflict happens FIRST so damaged infrastructure affects production
  resolveConflictPhase(result.newState, orders, result.combatReports, result.events)

  # Phase 2: Income Phase
  # - Collect taxes from colonies (reduced if infrastructure damaged)
  # - Calculate production (accounts for bombed facilities)
  # - Allocate research points
  resolveIncomePhase(result.newState, orders)

  # Phase 3: Command Phase
  # - Process build orders (may fail if shipyards destroyed)
  # - Execute movement orders
  # - Process colonization
  resolveCommandPhase(result.newState, orders, result.events)

  # Phase 4: Maintenance Phase
  # - Pay fleet upkeep
  # - Advance construction projects
  # - Apply repairs to damaged facilities
  # - Check victory conditions
  resolveMaintenancePhase(result.newState, result.events)

  # Advance turn counter
  result.newState.advanceTurn()

  echo "Turn ", state.turn, " resolved. New turn: ", result.newState.turn

## Phase 1: Conflict

proc resolveConflictPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                         combatReports: var seq[CombatReport], events: var seq[GameEvent]) =
  ## Phase 1: Resolve all combat and infrastructure damage
  ## This happens FIRST so damaged facilities affect production
  echo "  [Conflict Phase]"

  # Find all systems with hostile fleets
  var combatSystems: seq[SystemId] = @[]

  for systemId, system in state.starMap.systems:
    # Check if multiple houses have fleets here
    var housesPresent: seq[HouseId] = @[]
    for fleet in state.fleets.values:
      if fleet.location == systemId and fleet.owner notin housesPresent:
        housesPresent.add(fleet.owner)

    if housesPresent.len > 1:
      # Check if any are at war
      # TODO: Check diplomatic relations
      # For now, assume all non-allied fleets fight
      combatSystems.add(systemId)

  # Resolve battles in each system
  for systemId in combatSystems:
    resolveBattle(state, systemId, combatReports, events)

  # Process espionage actions (per gameplay.md:1.3.1 - resolved in Conflict Phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      # Process espionage action if present (max 1 per turn per diplomacy.md:8.2)
      if packet.espionageAction.isSome:
        let attempt = packet.espionageAction.get()

        # Get target's CIC level from tech tree
        # CRITICAL: Tech starts at level 1 (CIC1), not 0! (gameplay.md:1.2)
        let targetCICLevel = case state.houses[attempt.target].techTree.levels.counterIntelligence
          of 1: esp_types.CICLevel.CIC1
          of 2: esp_types.CICLevel.CIC2
          of 3: esp_types.CICLevel.CIC3
          of 4: esp_types.CICLevel.CIC4
          of 5: esp_types.CICLevel.CIC5
          else: esp_types.CICLevel.CIC1  # Fallback to base level
        let targetCIP = if attempt.target in state.houses:
                          state.houses[attempt.target].espionageBudget.cipPoints
                        else:
                          0

        # Execute espionage action with detection roll
        # Use XOR instead of + to avoid overflow when combining hashes
        var rng = initRand(int64(state.turn) xor attempt.attacker.hash() xor attempt.target.hash())
        let result = esp_engine.executeEspionage(
          attempt,
          targetCICLevel,
          targetCIP,
          rng
        )

        # Apply results
        if result.success:
          echo "    ", attempt.attacker, " espionage: ", result.description

          # Apply prestige changes
          for prestigeEvent in result.attackerPrestigeEvents:
            state.houses[attempt.attacker].prestige += prestigeEvent.amount
          for prestigeEvent in result.targetPrestigeEvents:
            state.houses[attempt.target].prestige += prestigeEvent.amount

          # Apply ongoing effects
          if result.effect.isSome:
            state.ongoingEffects.add(result.effect.get())

          # Apply immediate effects (SRP theft, IU damage, etc.)
          if result.srpStolen > 0:
            # Steal SRP from target
            if attempt.target in state.houses:
              state.houses[attempt.target].techTree.accumulated.science =
                max(0, state.houses[attempt.target].techTree.accumulated.science - result.srpStolen)
              state.houses[attempt.attacker].techTree.accumulated.science += result.srpStolen
              echo "      Stole ", result.srpStolen, " SRP from ", attempt.target

        else:
          echo "    ", attempt.attacker, " espionage DETECTED by ", attempt.target
          # Apply detection prestige penalties
          for prestigeEvent in result.attackerPrestigeEvents:
            state.houses[attempt.attacker].prestige += prestigeEvent.amount

  # Process bombardment orders (damages infrastructure before income phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        if order.orderType == FleetOrderType.Bombard:
          resolveBombardment(state, houseId, order, events)

## Helper: Auto-balance unassigned squadrons to fleets at colony

proc autoBalanceSquadronsToFleets(state: var GameState, colony: var gamestate.Colony, systemId: SystemId) =
  ## Auto-assign unassigned squadrons to fleets at colony, balancing squadron count
  ## Only assigns to stationary fleets (those with Hold orders or no orders)
  if colony.unassignedSquadrons.len == 0:
    return

  # Find all stationary fleets at this system owned by colony owner
  var stationaryFleets: seq[FleetId] = @[]
  for fleetId, fleet in state.fleets:
    if fleet.location == systemId and fleet.owner == colony.owner:
      # Check if fleet has movement orders
      var hasMovementOrder = false
      # TODO: Check orders to see if fleet is moving (need access to orders here)
      # For now, assume all fleets at colony are stationary
      if not hasMovementOrder:
        stationaryFleets.add(fleetId)

  # If no fleets exist at colony, create one
  if stationaryFleets.len == 0:
    let newFleetId = colony.owner & "_fleet_" & $systemId & "_" & $state.turn
    state.fleets[newFleetId] = Fleet(
      id: newFleetId,
      owner: colony.owner,
      location: systemId,
      squadrons: @[]
    )
    stationaryFleets.add(newFleetId)
    echo "      Created new fleet ", newFleetId, " for auto-assignment"

  # Distribute unassigned squadrons to balance fleet strength
  # Assign each squadron to the weakest fleet (by total attack strength)
  while colony.unassignedSquadrons.len > 0:
    let squadron = colony.unassignedSquadrons[0]
    colony.unassignedSquadrons.delete(0)

    # Find fleet with lowest total attack strength
    var weakestFleetId = stationaryFleets[0]
    var lowestStrength = 0
    for fleetId in stationaryFleets:
      var fleetStrength = 0
      for sq in state.fleets[fleetId].squadrons:
        fleetStrength += sq.flagship.stats.attackStrength
        for ship in sq.ships:
          fleetStrength += ship.stats.attackStrength

      if fleetId == stationaryFleets[0] or fleetStrength < lowestStrength:
        lowestStrength = fleetStrength
        weakestFleetId = fleetId

    state.fleets[weakestFleetId].squadrons.add(squadron)
    echo "      Auto-assigned squadron ", squadron.id, " to fleet ", weakestFleetId, " (strength balancing)"

## Phase 2: Income

proc resolveIncomePhase(state: var GameState, orders: Table[HouseId, OrderPacket]) =
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
          echo "    Starbase at system ", effect.targetSystem.get(), " is crippled"

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
          # TODO: Check for actual starbase presence in colony
          # For now, assume all colonies have detection capability
          hasStarbase = false  # Will be true when we track starbases

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
      # TODO: Generate intelligence reports based on mission type
      survivingScouts[scoutId] = scout

      case scout.mission
      of SpyMissionType.SpyOnPlanet:
        echo "    Spy scout ", scoutId, " gathering planetary intelligence at system ", scoutLocation
      of SpyMissionType.HackStarbase:
        echo "    Spy scout ", scoutId, " hacking starbase at system ", scoutLocation
      of SpyMissionType.SpyOnSystem:
        echo "    Spy scout ", scoutId, " conducting system surveillance at ", scoutLocation

  # Update spy scouts in game state (remove detected ones)
  state.spyScouts = survivingScouts

  # Convert GameState colonies to economy engine format
  var econColonies: seq[econ_types.Colony] = @[]
  for systemId, colony in state.colonies:
    # Convert Colony to economy Colony type
    # grossOutput starts at 0 and will be calculated by economy engine
    econColonies.add(econ_types.Colony(
      systemId: colony.systemId,
      owner: colony.owner,
      populationUnits: colony.population,  # Map population (millions) to PU
      populationTransferUnits: 0,  # TODO: Track PTU separately
      industrial: econ_types.IndustrialUnits(units: colony.infrastructure * 10),  # Map infrastructure to IU
      planetClass: colony.planetClass,
      resources: colony.resources,
      grossOutput: 0,  # Will be calculated by economy engine
      taxRate: 50,  # TODO: Get from house tax policy
      underConstruction: none(econ_types.ConstructionProject),  # TODO: Convert construction
      infrastructureDamage: if colony.blockaded: 0.6 else: 0.0  # Blockade = 60% infrastructure damage
    ))

  # Build house tax policies (TODO: store in House)
  var houseTaxPolicies = initTable[HouseId, econ_types.TaxPolicy]()
  for houseId in state.houses.keys:
    houseTaxPolicies[houseId] = econ_types.TaxPolicy(
      currentRate: 50,  # Default
      history: @[50]
    )

  # Build house tech levels
  var houseTechLevels = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTechLevels[houseId] = house.techTree.levels.energyLevel  # TODO: Use actual EL

  # Build house treasuries
  var houseTreasuries = initTable[HouseId, int]()
  for houseId, house in state.houses:
    houseTreasuries[houseId] = house.treasury

  # Call economy engine
  let incomeReport = econ_engine.resolveIncomePhase(
    econColonies,
    houseTaxPolicies,
    houseTechLevels,
    houseTreasuries
  )

  # Apply results back to game state
  for houseId, houseReport in incomeReport.houseReports:
    state.houses[houseId].treasury = houseTreasuries[houseId]
    echo "    ", state.houses[houseId].name, ": +", houseReport.totalNet, " PP (Gross: ", houseReport.totalGross, ")"

    # Update colony production fields from income reports
    for colonyReport in houseReport.colonies:
      if colonyReport.colonyId in state.colonies:
        state.colonies[colonyReport.colonyId].production = colonyReport.grossOutput

    # Apply prestige events from economic activities
    for event in houseReport.prestigeEvents:
      state.houses[houseId].prestige += event.amount
      echo "      Prestige: ",
           (if event.amount > 0: "+" else: ""), event.amount,
           " (", event.description, ") -> ", state.houses[houseId].prestige

    # Apply blockade prestige penalties
    # Per operations.md:6.2.6: "-2 prestige per colony under blockade"
    let blockadePenalty = blockade_engine.calculateBlockadePrestigePenalty(state, houseId)
    if blockadePenalty < 0:
      let blockadedCount = blockade_engine.getBlockadedColonies(state, houseId).len
      state.houses[houseId].prestige += blockadePenalty
      echo "      Prestige: ", blockadePenalty, " (", blockadedCount,
           " colonies under blockade) -> ", state.houses[houseId].prestige

  # Process construction completion - decrement turns and complete projects
  for systemId, colony in state.colonies.mpairs:
    if colony.underConstruction.isSome:
      var project = colony.underConstruction.get()
      project.turnsRemaining -= 1

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

          if isSpaceLift:
            # Create SpaceLiftShip (individual unit, not squadron)
            let shipId = colony.owner & "_" & $shipClass & "_" & $systemId & "_" & $state.turn
            let spaceLiftShip = newSpaceLiftShip(shipId, shipClass, colony.owner, systemId)
            colony.unassignedSpaceLiftShips.add(spaceLiftShip)
            echo "      Commissioned ", shipClass, " spacelift ship at ", systemId

            # Auto-assign to fleets if enabled
            if colony.autoAssignFleets and colony.unassignedSpaceLiftShips.len > 0:
              # Find stationary fleets at this system
              for fleetId, fleet in state.fleets.mpairs:
                if fleet.location == systemId and fleet.owner == colony.owner:
                  # Transfer spacelift ship to fleet
                  fleet.spaceLiftShips.add(spaceLiftShip)
                  colony.unassignedSpaceLiftShips.setLen(colony.unassignedSpaceLiftShips.len - 1)
                  echo "      Auto-assigned ", shipClass, " to fleet ", fleetId
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

            # If colony has auto-assign enabled, balance unassigned squadrons to fleets
            if colony.autoAssignFleets and colony.unassignedSquadrons.len > 0:
              autoBalanceSquadronsToFleets(state, colony, systemId)

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
            colony.planetaryShieldLevel = state.houses[colony.owner].techTree.levels.shieldLevel
            echo "      Added Planetary Shield (SLD", colony.planetaryShieldLevel, ") to system ", systemId

        of econ_types.ConstructionType.Industrial:
          # IU investment - industrial capacity was added when project started
          # Just log completion
          echo "      Industrial expansion completed at system ", systemId

        of econ_types.ConstructionType.Infrastructure:
          # Infrastructure was already added during creation
          # Just log completion
          echo "      Infrastructure expansion completed at system ", systemId

        # Clear construction slot
        colony.underConstruction = none(econ_types.ConstructionProject)
      else:
        # Still under construction
        colony.underConstruction = some(project)

  # Process research allocation
  # Per economy.md:4.0: Players allocate PP to research each turn
  # PP is converted to ERP/SRP/TRP based on current tech levels and GHO
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]
      let allocation = packet.researchAllocation

      # Calculate GHO for this house
      var gho = 0
      for colony in state.colonies.values:
        if colony.owner == houseId:
          gho += colony.production

      # Get current tech levels
      let currentSL = state.houses[houseId].techTree.levels.shieldLevel  # Science Level

      # Convert PP allocations to RP
      let earnedRP = res_costs.allocateResearch(allocation, gho, currentSL)

      # Accumulate RP
      state.houses[houseId].techTree.accumulated.economic += earnedRP.economic
      state.houses[houseId].techTree.accumulated.science += earnedRP.science

      for field, trp in earnedRP.technology:
        if field notin state.houses[houseId].techTree.accumulated.technology:
          state.houses[houseId].techTree.accumulated.technology[field] = 0
        state.houses[houseId].techTree.accumulated.technology[field] += trp

      # Log allocations
      if allocation.economic > 0:
        echo "      ", houseId, " allocated ", allocation.economic, " PP → ", earnedRP.economic, " ERP",
             " (total: ", state.houses[houseId].techTree.accumulated.economic, " ERP)"
      if allocation.science > 0:
        echo "      ", houseId, " allocated ", allocation.science, " PP → ", earnedRP.science, " SRP",
             " (total: ", state.houses[houseId].techTree.accumulated.science, " SRP)"
      for field, pp in allocation.technology:
        if pp > 0 and field in earnedRP.technology:
          let totalTRP = state.houses[houseId].techTree.accumulated.technology.getOrDefault(field, 0)
          echo "      ", houseId, " allocated ", pp, " PP → ", earnedRP.technology[field], " TRP (", field, ")",
               " (total: ", totalTRP, " TRP)"

## Phase 3: Command

proc resolveCommandPhase(state: var GameState, orders: Table[HouseId, OrderPacket],
                        events: var seq[GameEvent]) =
  ## Phase 3: Execute orders
  ## Build orders may fail if shipyards were destroyed in conflict phase
  echo "  [Command Phase]"

  # Process build orders first
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveBuildOrders(state, orders[houseId], events)

  # Process Space Guild population transfers
  for houseId in state.houses.keys:
    if houseId in orders:
      resolvePopulationTransfers(state, orders[houseId], events)

  # Process diplomatic actions (per gameplay.md:1.3.3 - Command Phase)
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]

      for action in packet.diplomaticActions:
        case action.actionType
        of DiplomaticActionType.ProposeNonAggressionPact:
          # TODO: Implement pact proposal system for multiplayer
          # See docs/architecture/diplomacy_proposals.md for full design
          #
          # Current behavior: Auto-accept (works for AI/offline games)
          # Multiplayer needs: Pending proposals, accept/reject actions, notifications
          #
          # Implementation phases:
          # 1. Add PendingProposal type to GameState
          # 2. Create proposal instead of immediate pact
          # 3. Add AcceptProposal/RejectProposal actions
          # 4. Implement proposal expiration in maintenance phase
          # 5. Add AI response logic (accept/reject based on strategy)
          # 6. Add notification system for players
          #
          echo "    ", houseId, " proposed Non-Aggression Pact to ", action.targetHouse
          # For now, auto-accept pacts (works fine for AI vs AI)
          if action.targetHouse in state.houses and not state.houses[action.targetHouse].eliminated:
            # Proposer establishes pact on their side
            let eventOpt1 = dip_engine.proposePact(
              state.houses[houseId].diplomaticRelations,
              action.targetHouse,
              state.houses[houseId].violationHistory,
              state.turn
            )
            # Target accepts (auto-accept for now)
            let eventOpt2 = dip_engine.proposePact(
              state.houses[action.targetHouse].diplomaticRelations,
              houseId,
              state.houses[action.targetHouse].violationHistory,
              state.turn
            )
            if eventOpt1.isSome and eventOpt2.isSome:
              echo "      Pact established"
            else:
              echo "      Pact proposal failed (blocked by isolation or cooldown)"

        of DiplomaticActionType.BreakPact:
          # Breaking a pact triggers violation penalties (diplomacy.md:8.1.2)
          echo "    ", houseId, " breaking pact with ", action.targetHouse

          # Check if there's actually a pact to break
          let currentState = dip_engine.getDiplomaticState(
            state.houses[houseId].diplomaticRelations,
            action.targetHouse
          )

          if currentState == dip_types.DiplomaticState.NonAggression:
            # Record violation
            let violation = dip_engine.recordViolation(
              state.houses[houseId].violationHistory,
              houseId,
              action.targetHouse,
              state.turn,
              "Broke Non-Aggression Pact"
            )

            # Apply prestige penalties
            let prestigeEvents = dip_engine.applyViolationPenalties(
              houseId,
              action.targetHouse,
              state.houses[houseId].violationHistory,
              state.turn
            )

            for event in prestigeEvents:
              state.houses[houseId].prestige += event.amount
              echo "      ", event.description, ": ", event.amount, " prestige"

            # Apply dishonored status (3 turns per diplomacy.md:8.1.2)
            state.houses[houseId].dishonoredStatus = dip_types.DishonoredStatus(
              active: true,
              turnsRemaining: 3,
              violationTurn: state.turn
            )
            echo "      Dishonored for 3 turns"

            # Apply diplomatic isolation (5 turns per diplomacy.md:8.1.2)
            state.houses[houseId].diplomaticIsolation = dip_types.DiplomaticIsolation(
              active: true,
              turnsRemaining: 5,
              violationTurn: state.turn
            )
            echo "      Isolated for 5 turns"

            # Set status to Enemy
            dip_engine.setDiplomaticState(
              state.houses[houseId].diplomaticRelations,
              action.targetHouse,
              dip_types.DiplomaticState.Enemy,
              state.turn
            )
          else:
            echo "      No pact exists to break"

        of DiplomaticActionType.DeclareEnemy:
          echo "    ", houseId, " declared ", action.targetHouse, " as Enemy"
          dip_engine.setDiplomaticState(
            state.houses[houseId].diplomaticRelations,
            action.targetHouse,
            dip_types.DiplomaticState.Enemy,
            state.turn
          )

        of DiplomaticActionType.SetNeutral:
          echo "    ", houseId, " set ", action.targetHouse, " to Neutral"
          dip_engine.setDiplomaticState(
            state.houses[houseId].diplomaticRelations,
            action.targetHouse,
            dip_types.DiplomaticState.Neutral,
            state.turn
          )

  # Process squadron management orders (form squadrons, transfer ships, assign to fleets)
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveSquadronManagement(state, orders[houseId], events)

  # Process cargo management (manual loading/unloading)
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveCargoManagement(state, orders[houseId], events)

  # Auto-load cargo at colonies (if no manual cargo order exists)
  autoLoadCargo(state, orders, events)

  # Process all fleet orders (sorted by priority)
  var allFleetOrders: seq[(HouseId, FleetOrder)] = @[]

  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        allFleetOrders.add((houseId, order))

  # Sort by priority
  allFleetOrders.sort do (a, b: (HouseId, FleetOrder)) -> int:
    cmp(a[1].priority, b[1].priority)

  # Execute all fleet orders through the new executor
  for (houseId, order) in allFleetOrders:
    let result = executeFleetOrder(state, houseId, order)

    if result.success:
      echo "    [", $order.orderType, "] ", result.message
      # Add events from order execution
      for eventMsg in result.eventsGenerated:
        events.add(GameEvent(
          eventType: GameEventType.Battle,  # TODO: Add more specific event types
          houseId: houseId,
          description: eventMsg,
          systemId: order.targetSystem
        ))

      # Some orders need additional processing after validation
      case order.orderType
      of FleetOrderType.Move, FleetOrderType.SeekHome, FleetOrderType.Patrol:
        # Executor validates, this does actual pathfinding and movement
        resolveMovementOrder(state, houseId, order, events)
      of FleetOrderType.Colonize:
        # Executor validates, this does actual colony creation
        resolveColonizationOrder(state, houseId, order, events)
      else:
        discard  # Fully handled by executor
    else:
      echo "    [", $order.orderType, "] FAILED: ", result.message

proc resolveBuildOrders(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  ## Process construction orders for a house
  echo "    Processing build orders for ", state.houses[packet.houseId].name

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

    # Check if colony already has construction in progress
    if colony.underConstruction.isSome:
      echo "      Build order failed: system ", order.colonySystem, " already building something"
      continue

    # Convert gamestate.Colony to economy.Colony for construction functions
    var econColony = econ_types.Colony(
      systemId: colony.systemId,
      owner: colony.owner,
      populationUnits: colony.population,
      populationTransferUnits: 0,
      industrial: econ_types.IndustrialUnits(
        units: colony.infrastructure,  # Map infrastructure to IU
        investmentCost: 30  # Base cost
      ),
      planetClass: colony.planetClass,
      resources: colony.resources,
      underConstruction: none(econ_types.ConstructionProject)
    )

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

      project = construction.createIndustrialProject(econColony, units)
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

    # Start construction
    if construction.startConstruction(econColony, project):
      # Convert back and update game state
      var updatedColony = colony
      updatedColony.underConstruction = some(project)
      state.colonies[order.colonySystem] = updatedColony

      echo "      Started construction at system ", order.colonySystem, ": ", projectDesc
      echo "        Cost: ", project.costTotal, " PP, Est. ", project.turnsRemaining, " turns"

      # Generate event
      events.add(GameEvent(
        eventType: GameEventType.ColonyEstablished,  # TODO: Add ConstructionStarted event type
        houseId: packet.houseId,
        description: "Started " & projectDesc & " at system " & $order.colonySystem,
        systemId: some(order.colonySystem)
      ))
    else:
      echo "      Construction start failed at system ", order.colonySystem

proc resolveSquadronManagement(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
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
      # TODO: Implement ship transfer logic
      echo "    TransferShip not yet implemented"

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

      if foundSquadron.isNone:
        echo "    AssignToFleet failed: Squadron ", order.squadronId.get(), " not found at system"
        continue

      let squadron = foundSquadron.get()

      # Remove squadron from source fleet
      if sourceFleetId.isSome:
        let srcFleet = state.fleets[sourceFleetId.get()]
        var newSquadrons: seq[Squadron] = @[]
        for squad in srcFleet.squadrons:
          if squad.id != order.squadronId.get():
            newSquadrons.add(squad)
        state.fleets[sourceFleetId.get()].squadrons = newSquadrons

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

proc resolveCargoManagement(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
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
            let maxPTUs = availableSouls div DEFAULT_SOULS_PER_PTU
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
          let soulsToLoad = totalLoaded * DEFAULT_SOULS_PER_PTU
          colony.souls -= soulsToLoad
          # Update display field (population in millions)
          colony.population = colony.souls div 1_000_000
          echo "    Removed ", totalLoaded, " PTU (", soulsToLoad, " souls, ", totalLoaded.float * DEFAULT_PTU_SIZE_MILLIONS, "M) from colony"
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
          let soulsToUnload = quantity * DEFAULT_SOULS_PER_PTU
          colony.souls += soulsToUnload
          # Update display field (population in millions)
          colony.population = colony.souls div 1_000_000
          echo "    Unloaded ", quantity, " PTU (", soulsToUnload, " souls, ", quantity.float * DEFAULT_PTU_SIZE_MILLIONS, "M) from ", ship.id, " to colony"
        else:
          discard

        modifiedShips.add(mutableShip)

      # Write back modified state
      if totalUnloaded > 0:
        fleet.spaceLiftShips = modifiedShips
        state.fleets[order.fleetId] = fleet
        state.colonies[order.colonySystem] = colony
        echo "    Successfully unloaded ", totalUnloaded, " ", unloadedType, " at ", order.colonySystem

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

proc resolvePopulationTransfers(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
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
    if destColony.souls < DEFAULT_SOULS_PER_PTU:
      echo "      Transfer failed: destination colony ", transfer.destColony, " has only ", destColony.souls,
           " souls (needs ≥", DEFAULT_SOULS_PER_PTU, " to accept transfers)"
      continue

    # Convert PTU amount to souls for exact transfer
    let soulsToTransfer = transfer.ptuAmount * DEFAULT_SOULS_PER_PTU

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

proc resolvePopulationArrivals(state: var GameState, events: var seq[GameEvent]) =
  ## Process Space Guild population transfers that arrive this turn
  ## Implements risk handling per config/population.toml [transfer_risks]
  echo "  [Processing Space Guild Arrivals]"

  var arrivedTransfers: seq[int] = @[]  # Indices to remove after processing

  for idx, transfer in state.populationInTransit:
    if transfer.arrivalTurn != state.turn:
      continue  # Not arriving this turn

    let soulsToDeliver = transfer.ptuAmount * DEFAULT_SOULS_PER_PTU

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

    # Check if destination blockaded
    if destColony.blockaded:
      # dest_blockaded_behavior = "return"
      # Return PTUs to source colony if it still exists and is owned
      if transfer.sourceSystem in state.colonies:
        var sourceColony = state.colonies[transfer.sourceSystem]
        if sourceColony.owner == transfer.houseId:
          sourceColony.souls += soulsToDeliver
          sourceColony.population = sourceColony.souls div 1_000_000
          state.colonies[transfer.sourceSystem] = sourceColony
          echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU RETURNED to ", transfer.sourceSystem, " - destination blockaded"
          events.add(GameEvent(
            eventType: GameEventType.PopulationTransfer,
            houseId: transfer.houseId,
            description: $transfer.ptuAmount & " PTU returned from " & $transfer.destSystem & " (blockaded) to " & $transfer.sourceSystem,
            systemId: some(transfer.sourceSystem)
          ))
        else:
          echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination blockaded, source conquered"
      else:
        echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination blockaded, source destroyed"

      arrivedTransfers.add(idx)
      continue

    # Check if destination below minimum viable (< 1 PTU)
    if destColony.souls < DEFAULT_SOULS_PER_PTU:
      # Destination colony collapsed below functional threshold
      # Return to source if possible
      if transfer.sourceSystem in state.colonies:
        var sourceColony = state.colonies[transfer.sourceSystem]
        if sourceColony.owner == transfer.houseId:
          sourceColony.souls += soulsToDeliver
          sourceColony.population = sourceColony.souls div 1_000_000
          state.colonies[transfer.sourceSystem] = sourceColony
          echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU RETURNED to ", transfer.sourceSystem, " - destination below minimum viable"
        else:
          echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination collapsed, source conquered"
      else:
        echo "    Transfer ", transfer.id, ": ", transfer.ptuAmount, " PTU LOST - destination collapsed, source destroyed"

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

proc autoLoadCargo(state: var GameState, orders: Table[HouseId, OrderPacket], events: var seq[GameEvent]) =
  ## Automatically load available marines/colonists onto empty transports at colonies
  ## Only auto-load if no manual cargo order exists for that fleet

  # Build set of fleets with manual cargo orders
  var manualCargoFleets: seq[FleetId] = @[]
  for houseId, packet in orders:
    for order in packet.cargoManagement:
      manualCargoFleets.add(order.fleetId)

  # Process each colony
  for systemId, colony in state.colonies:
    # Find fleets at this colony
    for fleetId, fleet in state.fleets:
      if fleet.location != systemId or fleet.owner != colony.owner:
        continue

      # Skip if fleet has manual cargo orders
      if fleetId in manualCargoFleets:
        continue

      # Auto-load empty transports if colony has inventory
      var colony = state.colonies[systemId]
      var fleet = state.fleets[fleetId]
      var modifiedShips: seq[SpaceLiftShip] = @[]
      var modified = false

      for ship in fleet.spaceLiftShips:
        var mutableShip = ship

        if ship.isCrippled or ship.cargo.cargoType != CargoType.None:
          modifiedShips.add(mutableShip)
          continue  # Skip crippled ships or ships already loaded

        # Determine what cargo this ship can carry
        case ship.shipClass
        of ShipClass.TroopTransport:
          # Auto-load marines if available
          if colony.marines > 0:
            let loadAmount = min(1, colony.marines)  # TroopTransport capacity = 1 MD
            if mutableShip.loadCargo(CargoType.Marines, loadAmount):
              colony.marines -= loadAmount
              modified = true
              echo "    [Auto] Loaded ", loadAmount, " Marines onto ", ship.id, " at ", systemId

        of ShipClass.ETAC:
          # Auto-load colonists if available (1 PTU commitment)
          # ETACs carry exactly 1 PTU for colonization missions
          # Per config/population.toml [transfer_limits] min_source_pu_remaining = 1
          let minSoulsToKeep = 1_000_000  # 1 PU minimum
          if colony.souls > minSoulsToKeep + DEFAULT_SOULS_PER_PTU:
            if mutableShip.loadCargo(CargoType.Colonists, 1):
              colony.souls -= DEFAULT_SOULS_PER_PTU
              colony.population = colony.souls div 1_000_000
              modified = true
              echo "    [Auto] Loaded 1 PTU onto ", ship.id, " at ", systemId

        else:
          discard  # Other ship classes don't have spacelift capability

        modifiedShips.add(mutableShip)

      # Write back modified state if any cargo was loaded
      if modified:
        fleet.spaceLiftShips = modifiedShips
        state.fleets[fleetId] = fleet
        state.colonies[systemId] = colony

proc resolveMovementOrder*(state: var GameState, houseId: HouseId, order: FleetOrder,
                         events: var seq[GameEvent]) =
  ## Execute a fleet movement order with pathfinding and lane traversal rules
  ## Per operations.md:6.1 - Lane traversal rules:
  ##   - Major lanes: 2 jumps per turn if all systems owned by player
  ##   - Major lanes: 1 jump per turn if jumping into unexplored/rival system
  ##   - Minor/Restricted lanes: 1 jump per turn maximum
  ##   - Crippled ships or Spacelift ships cannot cross Restricted lanes

  if order.targetSystem.isNone:
    return

  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return

  var fleet = fleetOpt.get()
  let targetId = order.targetSystem.get()
  let startId = fleet.location

  # Already at destination
  if startId == targetId:
    echo "    Fleet ", order.fleetId, " already at destination"
    return

  echo "    Fleet ", order.fleetId, " moving from ", startId, " to ", targetId

  # Find path to destination (operations.md:6.1)
  let pathResult = state.starMap.findPath(startId, targetId, fleet)

  if not pathResult.found:
    echo "      No valid path found (blocked by restricted lanes or terrain)"
    return

  if pathResult.path.len < 2:
    echo "      Invalid path"
    return

  # Determine how many jumps the fleet can make this turn
  var jumpsAllowed = 1  # Default: 1 jump per turn

  # Check if we can do 2 major lane jumps (operations.md:6.1)
  if pathResult.path.len >= 3:
    # Check if all systems along path are owned by this house
    var allSystemsOwned = true
    for systemId in pathResult.path:
      if systemId notin state.colonies or state.colonies[systemId].owner != houseId:
        allSystemsOwned = false
        break

    # Check if next two jumps are both major lanes
    var nextTwoAreMajor = true
    if allSystemsOwned:
      for i in 0..<min(2, pathResult.path.len - 1):
        let fromSys = pathResult.path[i]
        let toSys = pathResult.path[i + 1]

        # Find lane type between these systems
        var laneIsMajor = false
        for lane in state.starMap.lanes:
          if (lane.source == fromSys and lane.destination == toSys) or
             (lane.source == toSys and lane.destination == fromSys):
            if lane.laneType == LaneType.Major:
              laneIsMajor = true
            break

        if not laneIsMajor:
          nextTwoAreMajor = false
          break

    # Apply 2-jump rule for major lanes in friendly territory
    if allSystemsOwned and nextTwoAreMajor:
      jumpsAllowed = 2

  # Execute movement (up to jumpsAllowed systems)
  let actualJumps = min(jumpsAllowed, pathResult.path.len - 1)
  let newLocation = pathResult.path[actualJumps]

  fleet.location = newLocation
  state.fleets[order.fleetId] = fleet

  echo "      Moved ", actualJumps, " jump(s) to system ", newLocation

  # Check for fleet encounters at destination
  # Find other fleets at the same location
  for otherFleetId, otherFleet in state.fleets:
    if otherFleetId != order.fleetId and otherFleet.location == newLocation:
      if otherFleet.owner != houseId:
        echo "      Encountered fleet ", otherFleetId, " (", otherFleet.owner, ") at ", newLocation
        # Combat will be resolved in conflict phase next turn
        # This just logs the encounter

proc resolveColonizationOrder(state: var GameState, houseId: HouseId, order: FleetOrder,
                              events: var seq[GameEvent]) =
  ## Establish a new colony with prestige rewards
  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Check if system already colonized
  if targetId in state.colonies:
    echo "    System ", targetId, " already colonized"
    return

  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return

  # Check system exists
  if targetId notin state.starMap.systems:
    echo "    System ", targetId, " not found in starMap"
    return

  # TODO: Planet class and resources should be pre-generated or determined by system properties
  # For now, assume ETAC scouts found a benign world with abundant resources
  let planetClass = PlanetClass.Benign
  let resources = ResourceRating.Abundant

  # Create ETAC colony with 1 PTU (50k souls)
  let colony = createETACColony(targetId, houseId, planetClass, resources)

  # Use colonization engine to establish with prestige
  let result = col_engine.establishColony(
    houseId,
    targetId,
    colony.planetClass,
    colony.resources,
    1  # ETAC carries exactly 1 PTU
  )

  if result.success:
    state.colonies[targetId] = colony

    # Apply prestige award
    if result.prestigeEvent.isSome:
      let prestigeEvent = result.prestigeEvent.get()
      state.houses[houseId].prestige += prestigeEvent.amount
      echo "    ", state.houses[houseId].name, " colonized system ", targetId,
           " (+", prestigeEvent.amount, " prestige)"

    events.add(GameEvent(
      eventType: GameEventType.ColonyEstablished,
      houseId: houseId,
      description: "Established colony at system " & $targetId,
      systemId: some(targetId)
    ))

## Phase 1: Conflict (helper functions)

proc getTargetBucket(shipClass: ShipClass): TargetBucket =
  ## Determine target bucket from ship class
  case shipClass
  of ShipClass.Raider: TargetBucket.Raider
  of ShipClass.Fighter: TargetBucket.Fighter
  of ShipClass.Destroyer: TargetBucket.Destroyer
  of ShipClass.Starbase: TargetBucket.Starbase
  else: TargetBucket.Capital

proc resolveBattle(state: var GameState, systemId: SystemId,
                  combatReports: var seq[CombatReport], events: var seq[GameEvent]) =
  ## Resolve space battle in a system
  echo "    Battle at ", systemId

  # 1. Gather all fleets at this system
  var fleetsAtSystem: seq[(FleetId, Fleet)] = @[]
  for fleetId, fleet in state.fleets:
    if fleet.location == systemId:
      fleetsAtSystem.add((fleetId, fleet))

  if fleetsAtSystem.len < 2:
    # Need at least 2 fleets for combat
    return

  # 2. Determine system ownership for attacker/defender grouping
  let systemOwner = if systemId in state.colonies:
                      some(state.colonies[systemId].owner)
                    else:
                      none(HouseId)

  # 3. Group fleets by house (multiple fleets per house combine into one Task Force)
  var houseFleets: Table[HouseId, seq[Fleet]] = initTable[HouseId, seq[Fleet]]()
  for (fleetId, fleet) in fleetsAtSystem:
    if fleet.owner notin houseFleets:
      houseFleets[fleet.owner] = @[]
    houseFleets[fleet.owner].add(fleet)

  # 4. Check if there's actual conflict (need at least 2 different houses)
  if houseFleets.len < 2:
    return

  # 5. Build Task Forces for combat (Fleet now uses Squadrons!)
  var taskForces: Table[HouseId, TaskForce] = initTable[HouseId, TaskForce]()

  for houseId, fleets in houseFleets:
    # Convert all house fleets to CombatSquadrons
    var combatSquadrons: seq[CombatSquadron] = @[]

    for fleet in fleets:
      for squadron in fleet.squadrons:
        # Wrap Squadron in CombatSquadron
        let combatSq = CombatSquadron(
          squadron: squadron,
          state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
          damageThisTurn: 0,
          crippleRound: 0,
          bucket: getTargetBucket(squadron.flagship.shipClass),
          targetWeight: 1.0
        )
        combatSquadrons.add(combatSq)

    # Create TaskForce for this house
    taskForces[houseId] = TaskForce(
      house: houseId,
      squadrons: combatSquadrons,
      roe: 5,  # Default ROE
      isCloaked: false,
      moraleModifier: 0,
      scoutBonus: false,
      isDefendingHomeworld: false
    )

  # 6. Determine attacker and defender
  var attackerHouses: seq[HouseId] = @[]
  var defenderHouses: seq[HouseId] = @[]

  for houseId in taskForces.keys:
    if systemOwner.isSome and systemOwner.get() == houseId:
      defenderHouses.add(houseId)
    else:
      attackerHouses.add(houseId)

  # If no clear defender, first house is defender
  if defenderHouses.len == 0 and attackerHouses.len > 0:
    defenderHouses.add(attackerHouses[0])
    attackerHouses.delete(0)

  # 7. Create battle context and resolve
  # Collect all task forces for battle
  var allTaskForces: seq[TaskForce] = @[]
  for houseId, tf in taskForces:
    allTaskForces.add(tf)

  var battleContext = BattleContext(
    systemId: systemId,
    taskForces: allTaskForces,
    seed: 0,  # TODO: Use deterministic seed from game state
    maxRounds: 20
  )

  # Execute battle
  let outcome = combat_engine.resolveCombat(battleContext)

  # 8. Apply losses to game state
  # Collect surviving squadrons by ID
  var survivingSquadronIds: Table[SquadronId, CombatSquadron] = initTable[SquadronId, CombatSquadron]()
  for tf in outcome.survivors:
    for combatSq in tf.squadrons:
      survivingSquadronIds[combatSq.squadron.id] = combatSq

  # Update or remove fleets based on survivors
  for (fleetId, fleet) in fleetsAtSystem:
    var updatedSquadrons: seq[Squadron] = @[]

    for squadron in fleet.squadrons:
      if squadron.id in survivingSquadronIds:
        # Squadron survived - update crippled status
        let survivorState = survivingSquadronIds[squadron.id]
        var updatedSquadron = squadron
        updatedSquadron.flagship.isCrippled = (survivorState.state == CombatState.Crippled)
        updatedSquadrons.add(updatedSquadron)

    # Update fleet with surviving squadrons, or remove if none survived
    if updatedSquadrons.len > 0:
      state.fleets[fleetId] = Fleet(
        squadrons: updatedSquadrons,
        id: fleet.id,
        owner: fleet.owner,
        location: fleet.location
      )
    else:
      # Fleet destroyed
      state.fleets.del(fleetId)

  # 9. Count losses by house
  var houseLosses: Table[HouseId, int] = initTable[HouseId, int]()
  for houseId, fleets in houseFleets:
    let totalSquadrons = fleets.mapIt(it.squadrons.len).foldl(a + b, 0)
    let survivingSquadrons = outcome.survivors.filterIt(it.house == houseId)
                                   .mapIt(it.squadrons.len).foldl(a + b, 0)
    houseLosses[houseId] = totalSquadrons - survivingSquadrons

  # 10. Generate combat report
  let victor = outcome.victor
  let attackerLosses = attackerHouses.mapIt(houseLosses.getOrDefault(it, 0)).foldl(a + b, 0)
  let defenderLosses = defenderHouses.mapIt(houseLosses.getOrDefault(it, 0)).foldl(a + b, 0)

  let report = CombatReport(
    systemId: systemId,
    attackers: attackerHouses,
    defenders: defenderHouses,
    attackerLosses: attackerLosses,
    defenderLosses: defenderLosses,
    victor: victor
  )
  combatReports.add(report)

  # Award prestige for combat
  if victor.isSome:
    let victorHouse = victor.get()
    let victorPrestige = getPrestigeValue(PrestigeSource.CombatVictory)
    state.houses[victorHouse].prestige += victorPrestige
    echo "      ", state.houses[victorHouse].name, " victory (+", victorPrestige, " prestige)"

    # Award prestige for squadrons destroyed
    let enemyLosses = if victorHouse in attackerHouses: defenderLosses else: attackerLosses
    if enemyLosses > 0:
      let squadronPrestige = getPrestigeValue(PrestigeSource.SquadronDestroyed) * enemyLosses
      state.houses[victorHouse].prestige += squadronPrestige
      echo "      ", state.houses[victorHouse].name, " destroyed ", enemyLosses, " squadrons (+", squadronPrestige, " prestige)"

  # Generate event
  let victorName = if victor.isSome: state.houses[victor.get()].name else: "No one"
  events.add(GameEvent(
    eventType: GameEventType.Battle,
    houseId: if victor.isSome: victor.get() else: "",
    description: "Battle at " & $systemId & ". Victor: " & victorName,
    systemId: some(systemId)
  ))

  echo "      Battle complete. Victor: ", victorName

proc resolveBombardment(state: var GameState, houseId: HouseId, order: FleetOrder,
                       events: var seq[GameEvent]) =
  ## Process orbital bombardment order
  # NOTE: Like resolveBattle(), this requires Squadron conversion
  # Bombardment system (ground.nim:329) needs seq[CombatSquadron]
  # Current Fleet has seq[Ship] without combat stats

  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    echo "      Bombardment failed: fleet not found"
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    echo "      Bombardment failed: fleet not at target system"
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    echo "      Bombardment failed: no colony at target"
    return

  # Fleet now uses Squadrons - convert to CombatSquadrons
  var combatSquadrons: seq[CombatSquadron] = @[]
  for squadron in fleet.squadrons:
    let combatSq = CombatSquadron(
      squadron: squadron,
      state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: getTargetBucket(squadron.flagship.shipClass),
      targetWeight: 1.0
    )
    combatSquadrons.add(combatSq)

  # Get colony's planetary defense
  let colony = state.colonies[targetId]
  # TODO: Build full PlanetaryDefense from colony data
  var defense = PlanetaryDefense(
    shields: none(ShieldLevel),
    groundBatteries: @[],  # TODO: Get from colony
    groundForces: @[],  # TODO: Get from colony military units
    spaceport: false
  )

  # Conduct bombardment
  let result = conductBombardment(combatSquadrons, defense, seed = 0, maxRounds = 3)

  # Apply damage to colony
  var updatedColony = colony
  # Infrastructure damage from bombardment result
  # Note: BombardmentResult returns detailed round-by-round data
  # For now, count destroyed infrastructure units from final state
  let infrastructureLoss = 1  # TODO: Calculate from result
  updatedColony.infrastructure -= infrastructureLoss
  if updatedColony.infrastructure < 0:
    updatedColony.infrastructure = 0

  # Ships-in-dock destruction (economy.md:5.0)
  # If infrastructure is damaged, ships under construction can be destroyed
  var shipsDestroyedInDock = false
  if infrastructureLoss > 0 and updatedColony.underConstruction.isSome:
    let project = updatedColony.underConstruction.get()
    if project.projectType == econ_types.ConstructionType.Ship:
      # Ship under construction is destroyed with NO refund (per economy.md:5.0)
      # Full cost was paid upfront, funds are lost when ship is destroyed
      updatedColony.underConstruction = none(econ_types.ConstructionProject)
      shipsDestroyedInDock = true
      echo "      Ship under construction destroyed in bombardment!"

  state.colonies[targetId] = updatedColony

  echo "      Bombardment at ", targetId, ": ", infrastructureLoss, " infrastructure destroyed"

  # Generate event
  var eventDesc = "Bombarded system " & $targetId & ", destroyed " & $infrastructureLoss & " infrastructure"
  if shipsDestroyedInDock:
    eventDesc &= " (ship under construction destroyed)"

  events.add(GameEvent(
    eventType: GameEventType.Bombardment,
    houseId: houseId,
    description: eventDesc,
    systemId: some(targetId)
  ))

## Phase 4: Maintenance

proc resolveMaintenancePhase(state: var GameState, events: var seq[GameEvent]) =
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

  # Process Space Guild population transfers arriving this turn
  resolvePopulationArrivals(state, events)

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

  # Convert colonies for maintenance phase
  var econColonies: seq[econ_types.Colony] = @[]
  for systemId, colony in state.colonies:
    econColonies.add(econ_types.Colony(
      systemId: colony.systemId,
      owner: colony.owner,
      populationUnits: colony.population,
      populationTransferUnits: 0,
      industrial: econ_types.IndustrialUnits(units: colony.infrastructure * 10),
      planetClass: colony.planetClass,
      resources: colony.resources,
      grossOutput: colony.production,
      taxRate: 50,
      underConstruction: none(econ_types.ConstructionProject),
      infrastructureDamage: 0.0
    ))

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
    econColonies,
    houseFleetData,
    houseTreasuries
  )

  # Apply results back to game state
  for houseId, upkeep in maintenanceReport.houseUpkeep:
    state.houses[houseId].treasury = houseTreasuries[houseId]
    echo "    ", state.houses[houseId].name, ": -", upkeep, " PP maintenance"

  # Report and handle completed projects
  for completed in maintenanceReport.completedProjects:
    echo "    Completed: ", completed.projectType, " at system ", completed.colonyId

    # Special handling for fighter squadrons
    if completed.projectType == econ_types.ConstructionType.Building and
       completed.itemId == "FighterSquadron":
      # Commission fighter squadron at colony
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Create new fighter squadron
        let fighterSq = FighterSquadron(
          id: $completed.colonyId & "-FS-" & $(colony.fighterSquadrons.len + 1),
          commissionedTurn: state.turn
        )

        colony.fighterSquadrons.add(fighterSq)
        state.colonies[completed.colonyId] = colony

        echo "      Commissioned fighter squadron ", fighterSq.id, " at ", completed.colonyId

        # Generate event
        events.add(GameEvent(
          eventType: GameEventType.ColonyEstablished,  # TODO: Add FighterCommissioned event type
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
          eventType: GameEventType.ColonyEstablished,  # TODO: Add StarbaseCommissioned event type
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
          eventType: GameEventType.ColonyEstablished,
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
          eventType: GameEventType.ColonyEstablished,
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
          eventType: GameEventType.ColonyEstablished,
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
          eventType: GameEventType.ColonyEstablished,
          houseId: colony.owner,
          description: "Planetary Shield SLD" & $colony.planetaryShieldLevel & " deployed at " & $completed.colonyId,
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
            eventType: GameEventType.ColonyEstablished,
            houseId: owner,
            description: $shipClass & " commissioned at " & $completed.colonyId,
            systemId: some(completed.colonyId)
          ))

        except ValueError:
          echo "      ERROR: Invalid ship class: ", completed.itemId

  # Check for elimination and defensive collapse
  let gameplayConfig = globalGameplayConfig
  for houseId, house in state.houses:
    # Standard elimination: no colonies and no fleets
    let colonies = state.getHouseColonies(houseId)
    let fleets = state.getHouseFleets(houseId)

    if colonies.len == 0 and fleets.len == 0:
      state.houses[houseId].eliminated = true
      events.add(GameEvent(
        eventType: GameEventType.HouseEliminated,
        houseId: houseId,
        description: house.name & " has been eliminated!",
        systemId: none(SystemId)
      ))
      echo "    ", house.name, " eliminated!"
      continue

    # Defensive collapse: prestige < threshold for consecutive turns
    if house.prestige < gameplayConfig.elimination.defensive_collapse_threshold:
      state.houses[houseId].negativePrestigeTurns += 1
      echo "    ", house.name, " at risk: prestige ", house.prestige,
           " (", state.houses[houseId].negativePrestigeTurns, "/",
           gameplayConfig.elimination.defensive_collapse_turns, " turns until elimination)"

      if state.houses[houseId].negativePrestigeTurns >= gameplayConfig.elimination.defensive_collapse_turns:
        state.houses[houseId].eliminated = true
        events.add(GameEvent(
          eventType: GameEventType.HouseEliminated,
          houseId: houseId,
          description: house.name & " has collapsed from negative prestige!",
          systemId: none(SystemId)
        ))
        echo "    ", house.name, " eliminated by defensive collapse!"
    else:
      # Reset counter when prestige recovers
      state.houses[houseId].negativePrestigeTurns = 0

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
            eventType: GameEventType.ColonyEstablished,  # TODO: Add FighterDisbanded event type
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
      let currentEL = house.techTree.levels.energyLevel
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
      let currentSL = house.techTree.levels.shieldLevel
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
