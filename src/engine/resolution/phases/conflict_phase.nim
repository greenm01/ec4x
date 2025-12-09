## Conflict Phase Resolution - Phase 1 of Canonical Turn Cycle
##
## Resolves all combat and espionage operations submitted previous turn.
## Combat orders queued in Turn N-1 Command Phase execute here in Turn N.
##
## **Canonical Execution Order:**
##
## Step 1: Space Combat (simultaneous resolution)
## Step 2: Orbital Combat (simultaneous resolution)
## Step 3: Blockade Resolution (simultaneous)
## Step 4: Planetary Combat (bombard/invade/blitz, simultaneous)
## Step 5: Colonization (ETAC operations, simultaneous)
## Step 6: Espionage Operations (simultaneous)
##   6a: Spy Scout Detection (pre-combat prep, excludes detected scouts from battle)
##   6b: Fleet-Based Espionage (SpyPlanet, SpySystem, HackStarbase)
##   6c: Space Guild Espionage (EBP-based covert ops)
##   6d: Starbase Surveillance (continuous monitoring)
## Step 7: Spy Scout Travel (1-2 jumps per turn, per assets.md:2.4.2)
##
## **Implementation Note:**
## Spy detection (Step 6a) executes BEFORE combat (line 49-53) to exclude
## detected scouts from participating in battles. All other espionage operations
## execute AFTER combat to gather post-battle intelligence.

import std/[tables, options, random, sequtils, strformat]
import ../../../common/types/core
import ../../../common/logger as common_logger
import ../../gamestate, ../../orders, ../../fleet, ../../squadron, ../../logger, ../../state_helpers
import ../../espionage/[types as esp_types, engine as esp_engine]
import ../../diplomacy/[types as dip_types]
import ../../intelligence/[spy_travel, spy_resolution, espionage_intel, starbase_surveillance]
import ../[types as res_types, combat_resolution]
import ../[simultaneous_blockade, simultaneous_planetary, simultaneous_espionage, simultaneous_types, simultaneous]
import ../../prestige as prestige_types
import ../../prestige/application as prestige_app

proc resolveConflictPhase*(state: var GameState, orders: Table[HouseId, OrderPacket],
                          combatReports: var seq[res_types.CombatReport],
                          events: var seq[res_types.GameEvent], rng: var Rand) =
  ## Phase 1: Resolve all combat and infrastructure damage
  ## This happens FIRST so damaged facilities affect production
  logInfo(LogCategory.lcOrders, &"=== Conflict Phase === (turn={state.turn})")
  logInfo(LogCategory.lcOrders, &"Using RNG for combat resolution (seed={state.turn})")

  # ===================================================================
  # STEP 6a: SPY SCOUT DETECTION (Pre-Combat Prep)
  # ===================================================================
  # Resolve spy scout detection BEFORE combat
  # Spy scouts that go undetected remain hidden and don't participate in combat
  # Per assets.md:2.4.2 - detection checks occur each turn for active spy scouts
  logInfo(LogCategory.lcOrders, "[CONFLICT STEP 6a] Spy scout detection (pre-combat prep)...")
  let detectionResults = spy_resolution.resolveSpyDetection(state, events)
  for msg in detectionResults:
    logInfo("Intelligence", "Spy detection", msg)
  logInfo(LogCategory.lcOrders, &"[CONFLICT STEP 6a] Completed ({detectionResults.len} detection checks)")

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

          # Combat occurs if houses are enemies OR hostile (no pact protection)
          # BUT: Cloaked fleets can remain hidden unless detected
          if relation == dip_types.DiplomaticState.Enemy or
             relation == dip_types.DiplomaticState.Hostile:

            # STEALTH DETECTION CHECK
            # Check if either side is cloaked and undetected
            # TODO: Proper ELI Mesh detection for Raiders/Scouts
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

  # ===================================================================
  # STEPS 1 & 2: SPACE & ORBITAL COMBAT
  # ===================================================================
  # Resolve combat in each system (operations.md:7.0)
  logInfo(LogCategory.lcOrders, &"[CONFLICT STEPS 1 & 2] Resolving space/orbital combat ({combatSystems.len} systems)...")
  for systemId in combatSystems:
    resolveBattle(state, systemId, orders, combatReports, events, rng)
  logInfo(LogCategory.lcOrders, &"[CONFLICT STEPS 1 & 2] Completed ({combatReports.len} battles resolved)")

  # ===================================================================
  # STEP 3: BLOCKADE RESOLUTION
  # ===================================================================
  # Resolve all blockade attempts simultaneously to prevent
  # first-mover advantage
  logInfo(LogCategory.lcOrders, "[CONFLICT STEP 3] Resolving blockade attempts...")
  let blockadeResults = simultaneous_blockade.resolveBlockades(state, orders,
                                                                rng)
  logInfo(LogCategory.lcOrders, &"[CONFLICT STEP 3] Completed ({blockadeResults.len} blockade attempts)")

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
  # STEP 4: PLANETARY COMBAT RESOLUTION
  # ===================================================================
  # Resolve all planetary combat (bombard/invade/blitz) simultaneously
  logInfo(LogCategory.lcOrders, "[CONFLICT STEP 4] Resolving planetary combat...")
  let planetaryCombatResults = simultaneous_planetary.resolvePlanetaryCombat(
    state, orders, rng)
  logInfo(LogCategory.lcOrders, &"[CONFLICT STEP 4] Completed ({planetaryCombatResults.len} planetary combat attempts)")

  # ===================================================================
  # STEP 5: COLONIZATION
  # ===================================================================
  # ETACs establish colonies, resolve conflicts (winner-takes-all)
  # Fallback logic for losers with AutoColonize standing orders
  logInfo(LogCategory.lcOrders, "[CONFLICT STEP 5] Resolving colonization attempts...")
  let colonizationResults = simultaneous.resolveColonization(
    state, orders, rng, events)
  logInfo(LogCategory.lcOrders, &"[CONFLICT STEP 5] Completed ({colonizationResults.len} colonization attempts)")

  # ===================================================================
  # STEP 6b: FLEET-BASED ESPIONAGE
  # ===================================================================
  # Resolve fleet-based espionage orders simultaneously
  logInfo(LogCategory.lcOrders, "[CONFLICT STEP 6b] Fleet-based espionage (SpyPlanet, SpySystem, HackStarbase)...")
  let espionageResults = simultaneous_espionage.resolveEspionage(state,
                                                                  orders, rng)
  logInfo(LogCategory.lcOrders, &"[CONFLICT STEP 6b] Completed ({espionageResults.len} fleet espionage attempts)")

  # ===================================================================
  # STEP 6c: SPACE GUILD ESPIONAGE (EBP-based)
  # ===================================================================
  # Process OrderPacket.espionageAction (EBP-based espionage)
  logInfo(LogCategory.lcOrders, "[CONFLICT STEP 6c] Space Guild espionage (EBP-based covert ops)...")
  simultaneous_espionage.processEspionageActions(state, orders, rng, events)
  logInfo(LogCategory.lcOrders, "[CONFLICT STEP 6c] Completed EBP-based espionage processing")

  # ===================================================================
  # STEP 6d: STARBASE SURVEILLANCE
  # ===================================================================
  # Process starbase surveillance (continuous monitoring every turn)
  # Per Conflict Phase Step 6d: Intelligence gathering happens AFTER combat
  logInfo(LogCategory.lcOrders, "[CONFLICT STEP 6d] Starbase surveillance (continuous monitoring)...")
  var survRng = initRand(state.turn + 12345)  # Unique seed for surveillance
  starbase_surveillance.processAllStarbaseSurveillance(state, state.turn, survRng)
  logInfo(LogCategory.lcOrders, "[CONFLICT STEP 6d] Completed starbase surveillance")

  # ===================================================================
  # STEP 7: SPY SCOUT TRAVEL
  # ===================================================================
  # Move traveling spy scouts through jump lanes
  # Per assets.md:2.4.2 - scouts travel 1-2 jumps per turn based on lane control
  # Detection checks occur at intermediate systems
  logInfo(LogCategory.lcOrders, "[CONFLICT STEP 7] Spy scout travel (1-2 jumps per turn)...")
  let travelResults = spy_travel.resolveSpyScoutTravel(state)
  for msg in travelResults:
    logInfo("Intelligence", "Spy scout travel", msg)
  logInfo(LogCategory.lcOrders, &"[CONFLICT STEP 7] Completed ({travelResults.len} scout movements)")
