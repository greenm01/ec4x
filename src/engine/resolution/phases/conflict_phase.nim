## Conflict Phase Resolution
##
## Phase 1 of turn resolution - resolves all combat and espionage operations
## submitted previous turn.
##
## **Execution Order:**
## 1. Spy Scout Detection
## 2. Space/Orbital Combat
## 3. Blockade Resolution (simultaneous)
## 4. Planetary Combat (simultaneous)
## 5. Colonization (simultaneous)
## 6. Espionage Operations (simultaneous - fleet + EBP)
## 7. Spy Scout Travel

import std/[tables, options, random, sequtils, strformat]
import ../../../common/types/core
import ../../../common/logger as common_logger
import ../../gamestate, ../../orders, ../../fleet, ../../squadron, ../../logger, ../../state_helpers
import ../../espionage/[types as esp_types, engine as esp_engine]
import ../../diplomacy/[types as dip_types]
import ../../intelligence/[spy_travel, spy_resolution, espionage_intel]
import ../[types as res_types, combat_resolution]
import ../[simultaneous_blockade, simultaneous_planetary, simultaneous_espionage, simultaneous_types, simultaneous]
import ../../prestige as prestige_types
import ../../prestige/application as prestige_app

proc resolveConflictPhase*(state: var GameState, orders: Table[HouseId, OrderPacket],
                          combatReports: var seq[res_types.CombatReport],
                          events: var seq[res_types.GameEvent], rng: var Rand) =
  ## Phase 1: Resolve all combat and infrastructure damage
  ## This happens FIRST so damaged facilities affect production
  logInfo("Resolve", "=== Conflict Phase ===", "turn=", $state.turn)
  logRNG("Using RNG for combat resolution", "seed=", $state.turn)

  # Resolve spy scout detection BEFORE combat
  # Spy scouts that go undetected remain hidden and don't participate in combat
  # Per assets.md:2.4.2 - detection checks occur each turn for active spy scouts
  let detectionResults = spy_resolution.resolveSpyDetection(state)
  for msg in detectionResults:
    logInfo("Intelligence", "Spy detection", msg)

  # Find all systems with hostile fleets
  var combatSystems: seq[SystemId] = @[]

  for systemId, system in state.starMap.systems:
    # Check if multiple houses have fleets here
    var housesPresent: seq[HouseId] = @[]
    var houseFleets: Table[HouseId, seq[Fleet]] = initTable[HouseId, seq[Fleet]]()

    for fleet in state.fleets.values:
      if fleet.location == systemId:
        if fleet.owner notin housesPresent:
          housesPresent.add(fleet.owner)
          houseFleets[fleet.owner] = @[]
        houseFleets[fleet.owner].add(fleet)

    if housesPresent.len > 1:
      # Check if any pairs of houses are at war AND can detect each other
      var combatDetected = false
      for i in 0..<housesPresent.len:
        for j in (i+1)..<housesPresent.len:
          let house1 = housesPresent[i]
          let house2 = housesPresent[j]

          # Check diplomatic state between these two houses
          let relation = dip_types.getDiplomaticState(
            state.houses[house1].diplomaticRelations,
            house2
          )

          # Combat occurs if houses are enemies OR neutral (no pact protection)
          # BUT: Cloaked fleets can remain hidden unless detected
          if relation == dip_types.DiplomaticState.Enemy or
             relation == dip_types.DiplomaticState.Neutral:

            # STEALTH DETECTION CHECK
            # Check if either side is cloaked and undetected
            let house1Cloaked = houseFleets[house1].anyIt(it.isCloaked())
            let house2Cloaked = houseFleets[house2].anyIt(it.isCloaked())
            let house1HasScouts = houseFleets[house1].anyIt(it.squadrons.anyIt(it.hasScouts()))
            let house2HasScouts = houseFleets[house2].anyIt(it.squadrons.anyIt(it.hasScouts()))

            # Combat only triggers if both sides can detect each other
            # If house1 is cloaked, house2 needs scouts to detect them
            # If house2 is cloaked, house1 needs scouts to detect them
            let house1Detected = not house1Cloaked or house2HasScouts
            let house2Detected = not house2Cloaked or house1HasScouts

            if house1Detected and house2Detected:
              combatDetected = true
              break
        if combatDetected:
          break

      if combatDetected:
        combatSystems.add(systemId)

  # Resolve combat in each system (operations.md:7.0)
  for systemId in combatSystems:
    resolveBattle(state, systemId, orders, combatReports, events, rng)

  # ===================================================================
  # SIMULTANEOUS BLOCKADE RESOLUTION
  # ===================================================================
  # Resolve all blockade attempts simultaneously to prevent
  # first-mover advantage
  let blockadeResults = simultaneous_blockade.resolveBlockades(state, orders,
                                                                rng)
  logDebug(LogCategory.lcOrders, &"[SIMULTANEOUS BLOCKADE] Resolved {blockadeResults.len} blockade attempts")

  # Apply blockade results to colonies
  for result in blockadeResults:
    if result.outcome == ResolutionOutcome.Success:
      if result.actualTarget.isSome:
        let targetId = result.actualTarget.get()
        if targetId in state.colonies:
          state.withColony(targetId):
            colony.blockaded = true
            if result.houseId notin colony.blockadedBy:
              colony.blockadedBy.add(result.houseId)
            colony.blockadeTurns += 1
          logInfo("Combat", "Blockade established",
                  "blockader=", $result.houseId, " target=", $targetId)

  # ===================================================================
  # SIMULTANEOUS PLANETARY COMBAT RESOLUTION
  # ===================================================================
  # Resolve all planetary combat (bombard/invade/blitz) simultaneously
  let planetaryCombatResults = simultaneous_planetary.resolvePlanetaryCombat(
    state, orders, rng)
  logDebug(LogCategory.lcOrders, &"[SIMULTANEOUS PLANETARY COMBAT] Resolved {planetaryCombatResults.len} planetary combat attempts")

  # ===================================================================
  # SIMULTANEOUS COLONIZATION RESOLUTION
  # ===================================================================
  # ETACs establish colonies, resolve conflicts (winner-takes-all)
  # Fallback logic for losers with AutoColonize standing orders
  let colonizationResults = simultaneous.resolveColonization(
    state, orders, rng, events)
  logDebug(LogCategory.lcOrders, &"[SIMULTANEOUS COLONIZATION] " &
           &"Resolved {colonizationResults.len} colonization attempts")

  # ===================================================================
  # SIMULTANEOUS ESPIONAGE RESOLUTION
  # ===================================================================
  # Resolve fleet-based espionage orders simultaneously
  let espionageResults = simultaneous_espionage.resolveEspionage(state,
                                                                  orders, rng)
  logDebug(LogCategory.lcOrders, &"[SIMULTANEOUS ESPIONAGE] Resolved {espionageResults.len} fleet espionage attempts")

  # Process OrderPacket.espionageAction (EBP-based espionage)
  logDebug(LogCategory.lcOrders, "[ESPIONAGE ACTIONS] Processing EBP-based espionage actions...")
  simultaneous_espionage.processEspionageActions(state, orders, rng)
  logDebug(LogCategory.lcOrders, "[ESPIONAGE ACTIONS] Completed EBP-based espionage processing")

  # ===================================================================
  # SPY SCOUT TRAVEL
  # ===================================================================
  # Move traveling spy scouts through jump lanes
  # Per assets.md:2.4.2 - scouts travel 1-2 jumps per turn based on lane control
  # Detection checks occur at intermediate systems
  let travelResults = spy_travel.resolveSpyScoutTravel(state)
  for msg in travelResults:
    logInfo("Intelligence", "Spy scout travel", msg)
