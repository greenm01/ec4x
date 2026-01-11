## Planetary Combat System
##
## Implements bombardment, invasion, and blitz mechanics.
## Fleet attacks on colonies with ground defenses.
##
## Per docs/specs/07-combat.md Section 7.7-7.8

import std/[random, options, tables, sequtils, strformat]
import ../../types/[core, game_state, combat, ship, facilities, colony, ground_unit]
import ../../state/engine
import ../../globals
import ./strength
import ./cer
import ./hits

# Forward declarations
proc calculateGroundBatteryAS*(state: GameState, colonyId: ColonyId): int32
proc calculateMarineAS*(state: GameState, fleets: seq[FleetId]): int32
proc calculateGroundForceAS*(state: GameState, colonyId: ColonyId): int32

proc shieldReduction*(state: GameState, colonyId: ColonyId): float32 =
  ## Calculate damage reduction from planetary shields
  ## Per docs/specs/reference.md Section 9.3
  ## Shields are house-level tech - if colony has operational shield unit, use house's SLD level

  # Find operational PlanetaryShield units
  var hasOperationalShield = false
  for unit in state.groundUnitsAtColony(colonyId):
    if unit.stats.unitType == GroundClass.PlanetaryShield and
       unit.state != CombatState.Destroyed:
      hasOperationalShield = true
      break

  if not hasOperationalShield:
    return 0.0

  # Get colony owner's shield tech level
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return 0.0

  let houseOpt = state.house(colonyOpt.get().owner)
  if houseOpt.isNone:
    return 0.0

  let house = houseOpt.get()
  let sldLevel = house.techTree.levels.sld

  # Get reduction from config (shields tech config has hitsBlocked per level)
  if sldLevel < 1 or sldLevel > 6:
    return 0.0

  return gameConfig.tech.sld.levels[sldLevel].hitsBlocked

proc allBatteriesDestroyed*(state: GameState, colonyId: ColonyId): bool =
  ## Check if all ground batteries at colony are destroyed
  ## Per docs/specs/07-combat.md Section 7.7

  # Check ground batteries
  for unit in state.groundUnitsAtColony(colonyId):
    if unit.stats.unitType == GroundClass.GroundBattery and
       unit.state != CombatState.Destroyed:
      return false # At least one battery operational

  return true # No operational batteries found

proc destroyShields*(state: GameState, colonyId: ColonyId) =
  ## Destroy planetary shields when marines land during standard invasion
  ## Per docs/specs/07-combat.md Section 7.8.1
  ## "Shields and spaceports immediately destroyed upon marine landing"
  ##
  ## NOTE: Blitz operations do NOT call this - shields captured intact if successful

  for unit in state.groundUnitsAtColony(colonyId):
    # Only destroy planetary shields
    if unit.stats.unitType == GroundClass.PlanetaryShield:
      var updatedUnit = unit
      updatedUnit.state = CombatState.Destroyed
      state.updateGroundUnit(unit.id, updatedUnit)

proc destroySpaceports*(state: GameState, colonyId: ColonyId) =
  ## Destroy all spaceports when marines land during invasion
  ## Per docs/specs/07-combat.md Section 7.8.1
  ## "Shields and spaceports immediately destroyed upon marine landing"

  for neoria in state.neoriasAtColony(colonyId):
    # Only destroy spaceports (planet-based facilities)
    if neoria.neoriaClass == NeoriaClass.Spaceport:
      var updatedNeoria = neoria
      updatedNeoria.state = CombatState.Destroyed
      state.updateNeoria(neoria.id, updatedNeoria)

proc applyInfrastructureDamage*(
  state: GameState, colonyId: ColonyId, damage: int32
) =
  ## Apply infrastructure damage to colony
  ## Per docs/specs/07-combat.md Section 7.7
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  var colony = colonyOpt.get()
  let currentIU = colony.infrastructure
  let damageAmount = min(damage, currentIU)

  colony.infrastructure = currentIU - damageAmount
  state.updateColony(colonyId, colony)

proc applyBombardmentExcessHits*(
  state: GameState, colonyId: ColonyId, excessHits: int32
) =
  ## Distribute bombardment excess hits (after batteries destroyed)
  ## Damages: Spaceports → Ground forces → Infrastructure/Population
  ## Per docs/specs/07-combat.md Section 7.7.6
  ##
  ## **Targeting Priority Logic:**
  ## 1. Spaceports: Large planetary facilities, easily visible and targetable from orbit
  ## 2. Ground forces: Dispersed infantry/garrisons, mobile and harder to target precisely
  ## 3. Infrastructure/Population: Collateral damage from indiscriminate bombardment

  if excessHits <= 0:
    return

  var remainingHits = excessHits

  # Phase 1: Destroy spaceports (large planetary facilities, visible from orbit)
  # Each spaceport has DS - requires multiple hits to destroy
  if remainingHits > 0:
    for neoria in state.neoriasAtColony(colonyId):
      if remainingHits <= 0:
        break

      # Only target spaceports (planet-based facilities)
      if neoria.neoriaClass != NeoriaClass.Spaceport:
        continue

      # Skip if already destroyed
      if neoria.state == CombatState.Destroyed:
        continue

      # Get DS from facility config (convert NeoriaClass to FacilityClass)
      let facilityClass = case neoria.neoriaClass
        of NeoriaClass.Spaceport: FacilityClass.Spaceport
        of NeoriaClass.Shipyard: FacilityClass.Shipyard
        of NeoriaClass.Drydock: FacilityClass.Drydock

      let spaceportDS = gameConfig.facilities.facilities[facilityClass].defenseStrength

      var updatedNeoria = neoria
      if neoria.state == CombatState.Undamaged:
        # Need DS hits to cripple
        if remainingHits >= spaceportDS:
          updatedNeoria.state = CombatState.Crippled
          remainingHits -= spaceportDS
          state.updateNeoria(neoria.id, updatedNeoria)
      elif neoria.state == CombatState.Crippled:
        # Need 50% DS to destroy crippled facility
        let hitsNeeded = int32(float32(spaceportDS) * 0.5)
        if remainingHits >= hitsNeeded:
          updatedNeoria.state = CombatState.Destroyed
          remainingHits -= hitsNeeded
          state.updateNeoria(neoria.id, updatedNeoria)

  # Phase 2: Damage ground forces (armies/marines)
  # Dispersed ground targets, harder to hit from orbit
  if remainingHits > 0:
    # First pass: Cripple undamaged ground forces
    for unit in state.groundUnitsAtColony(colonyId):
      if remainingHits <= 0:
        break

      # Only armies and marines take bombardment damage
      if unit.stats.unitType notin [GroundClass.Army, GroundClass.Marine]:
        continue

      if unit.state != CombatState.Undamaged:
        continue

      let hitsNeeded =
        if unit.stats.unitType == GroundClass.Army:
          gameConfig.groundUnits.units[GroundClass.Army].defenseStrength
        else:
          gameConfig.groundUnits.units[GroundClass.Marine].defenseStrength

      if remainingHits >= hitsNeeded:
        var updatedUnit = unit
        updatedUnit.state = CombatState.Crippled
        remainingHits -= hitsNeeded
        state.updateGroundUnit(unit.id, updatedUnit)

    # Second pass: Destroy crippled ground forces (only if no undamaged remain)
    let hasUndamagedGroundForces =
      block:
        var found = false
        for unit in state.groundUnitsAtColony(colonyId):
          if unit.stats.unitType in [GroundClass.Army, GroundClass.Marine] and
             unit.state == CombatState.Undamaged:
            found = true
            break
        found

    if not hasUndamagedGroundForces and remainingHits > 0:
      for unit in state.groundUnitsAtColony(colonyId):
        if remainingHits <= 0:
          break

        # Only armies and marines
        if unit.stats.unitType notin [GroundClass.Army, GroundClass.Marine]:
          continue

        if unit.state != CombatState.Crippled:
          continue

        # Crippled units have 50% DS
        let baseDS =
          if unit.stats.unitType == GroundClass.Army:
            gameConfig.groundUnits.units[GroundClass.Army].defenseStrength
          else:
            gameConfig.groundUnits.units[GroundClass.Marine].defenseStrength

        let hitsNeeded = int32(float32(baseDS) * 0.5)
        if remainingHits >= hitsNeeded:
          var updatedUnit = unit
          updatedUnit.state = CombatState.Destroyed
          remainingHits -= hitsNeeded
          state.updateGroundUnit(unit.id, updatedUnit)

  # Phase 3: Remaining hits damage infrastructure and population
  if remainingHits > 0:
    # Split remaining hits 50/50 between infrastructure and population
    let infrastructureHits = remainingHits div 2
    let populationHits = remainingHits - infrastructureHits

    # Damage infrastructure (IU)
    applyInfrastructureDamage(state, colonyId, infrastructureHits)

    # Damage population (casualties)
    let colonyOpt = state.colony(colonyId)
    if colonyOpt.isSome:
      var colony = colonyOpt.get()
      # 1 hit = 1 PTU killed (50,000 souls per config)
      let casualties = populationHits * gameConfig.economy.ptuDefinition.soulsPerPtu
      colony.population = max(0'i32, colony.population - casualties)
      state.updateColony(colonyId, colony)

proc applyHitsToBatteries*(
  state: GameState, colonyId: ColonyId, hits: int32
): int32 =
  ## Apply hits to ground batteries
  ## Returns remaining hits after all batteries destroyed
  ## Per docs/specs/07-combat.md Section 7.7

  var remainingHits = hits

  # Phase 1: Cripple all undamaged batteries
  for unit in state.groundUnitsAtColony(colonyId):
    if remainingHits <= 0:
      break

    # Only process ground batteries
    if unit.stats.unitType != GroundClass.GroundBattery:
      continue

    if unit.state != CombatState.Undamaged:
      continue

    let hitsNeeded = gameConfig.groundUnits.units[GroundClass.GroundBattery].defenseStrength
    if remainingHits >= hitsNeeded:
      var updatedUnit = unit
      updatedUnit.state = CombatState.Crippled
      remainingHits -= hitsNeeded
      state.updateGroundUnit(unit.id, updatedUnit)

  # Phase 2: Destroy crippled batteries
  let hasUndamaged =
    block:
      var found = false
      for unit in state.groundUnitsAtColony(colonyId):
        if unit.stats.unitType == GroundClass.GroundBattery and
           unit.state == CombatState.Undamaged:
          found = true
          break
      found

  if not hasUndamaged and remainingHits > 0:
    for unit in state.groundUnitsAtColony(colonyId):
      if remainingHits <= 0:
        break

      # Only process ground batteries
      if unit.stats.unitType != GroundClass.GroundBattery:
        continue

      if unit.state != CombatState.Crippled:
        continue

      # Crippled batteries have 50% DS
      let baseDS = gameConfig.groundUnits.units[GroundClass.GroundBattery].defenseStrength
      let hitsNeeded = int32(float32(baseDS) * 0.5)
      if remainingHits >= hitsNeeded:
        var updatedUnit = unit
        updatedUnit.state = CombatState.Destroyed
        remainingHits -= hitsNeeded
        state.updateGroundUnit(unit.id, updatedUnit)

  return remainingHits

proc calculateGroundBatteryAS*(state: GameState, colonyId: ColonyId): int32 =
  ## Calculate total AS from ground batteries
  ## Per docs/specs/07-combat.md Section 7.7
  result = 0

  for unit in state.groundUnitsAtColony(colonyId):
    # Only ground batteries contribute
    if unit.stats.unitType != GroundClass.GroundBattery:
      continue

    if unit.state == CombatState.Destroyed:
      continue

    let baseAS = gameConfig.groundUnits.units[GroundClass.GroundBattery].attackStrength
    let multiplier =
      if unit.state == CombatState.Crippled:
        0.5
      else:
        1.0

    result += int32(float32(baseAS) * multiplier)

proc propagateTransportDamageToMarines*(
  state: GameState,
  oldShipStates: Table[ShipId, CombatState],
  ships: seq[ShipId]
) =
  ## Propagate transport damage to marines aboard
  ##
  ## **When This Applies:**
  ## ONLY during **Blitz Phase 1** bombardment (Section 7.8.2)
  ## - Ground batteries fire at ALL fleet ships including transports
  ## - Transports are vulnerable while marines still aboard
  ## - If transport hit, marines aboard take proportional damage
  ##
  ## **Does NOT Apply To:**
  ## - Regular Bombardment: Transports screened (auxiliary vessels)
  ## - Standard Invasion: All batteries destroyed before transports approach
  ##
  ## **Damage Propagation Model:**
  ## - Transport crippled → Marines crippled (if undamaged)
  ## - Transport destroyed → Marines destroyed
  ##
  ## **Rationale:**
  ## Marines aboard transports in orbit are vulnerable to weapons fire.
  ## Once they land, ground combat rules apply (see applyHitsToGroundUnits).
  ##
  ## Call this AFTER applyHits() to sync marine states with transport states.

  for shipId in ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue

    let ship = shipOpt.get()

    # Only process troop transports
    if ship.shipClass != ShipClass.TroopTransport:
      continue

    # Check if transport state changed during combat
    let oldState = oldShipStates.getOrDefault(shipId, CombatState.Undamaged)
    if oldState == ship.state:
      continue # No damage, skip

    # Propagate damage to marines aboard
    for unit in state.groundUnitsOnTransport(shipId):
      # Only marines participate in invasion combat
      if unit.stats.unitType != GroundClass.Marine:
        continue

      var updatedUnit = unit
      # Apply damage transition based on transport state
      if ship.state == CombatState.Destroyed:
        # Transport destroyed → all marines destroyed
        updatedUnit.state = CombatState.Destroyed
      elif ship.state == CombatState.Crippled and unit.state == CombatState.Undamaged:
        # Transport crippled → undamaged marines become crippled
        # (Already crippled marines stay crippled, not destroyed)
        updatedUnit.state = CombatState.Crippled

      state.updateGroundUnit(unit.id, updatedUnit)

proc calculateMarineAS*(state: GameState, fleets: seq[FleetId]): int32 =
  ## Calculate total AS from marine units in fleets
  ## Per docs/specs/07-combat.md Section 7.8
  ##
  ## **Note on Transport Damage:**
  ## This proc only checks marine combat state, NOT transport state.
  ## Marines are already damaged when their transport is hit (see
  ## propagateTransportDamageToMarines), so no additional multiplier needed.
  ## Destroyed transports are excluded entirely.
  result = 0

  for fleetId in fleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isNone:
      continue

    let fleet = fleetOpt.get()
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isNone:
        continue

      let ship = shipOpt.get()

      # Only troop transports carry marines
      if ship.shipClass == ShipClass.TroopTransport:
        if ship.state == CombatState.Destroyed:
          continue # Destroyed transports contribute nothing

        # Get all ground units on this transport
        for unit in state.groundUnitsOnTransport(shipId):
          # Only marines participate in invasion
          if unit.stats.unitType == GroundClass.Marine:
            if unit.state != CombatState.Destroyed:
              # Get base marine AS from config
              let baseAS = gameConfig.groundUnits.units[GroundClass.Marine].attackStrength

              # Apply marine's own combat state
              # (Transport damage already propagated to marine state)
              let multiplier =
                if unit.state == CombatState.Crippled:
                  0.5
                else:
                  1.0

              result += int32(float32(baseAS) * multiplier)

proc applyHitsToGroundUnits*(
  state: GameState,
  groundUnitIds: seq[GroundUnitId],
  hits: int32
) =
  ## Apply hits to a list of ground units (armies/marines)
  ## Used during invasion and blitz ground combat
  ## Per docs/specs/07-combat.md Section 7.8

  var remainingHits = hits

  # Phase 1: Cripple undamaged units
  for groundUnitId in groundUnitIds:
    if remainingHits <= 0:
      break

    let unitOpt = state.groundUnit(groundUnitId)
    if unitOpt.isNone:
      continue

    var unit = unitOpt.get()

    # Only armies and marines participate in ground combat
    if unit.stats.unitType notin [GroundClass.Army, GroundClass.Marine]:
      continue

    if unit.state != CombatState.Undamaged:
      continue

    let hitsNeeded =
      if unit.stats.unitType == GroundClass.Army:
        gameConfig.groundUnits.units[GroundClass.Army].defenseStrength
      else:
        gameConfig.groundUnits.units[GroundClass.Marine].defenseStrength

    if remainingHits >= hitsNeeded:
      unit.state = CombatState.Crippled
      remainingHits -= hitsNeeded
      state.updateGroundUnit(groundUnitId, unit)

  # Phase 2: Destroy crippled units (only if no undamaged remain)
  let hasUndamaged =
    block:
      var found = false
      for groundUnitId in groundUnitIds:
        let unitOpt = state.groundUnit(groundUnitId)
        if unitOpt.isSome:
          let unit = unitOpt.get()
          if unit.stats.unitType in [GroundClass.Army, GroundClass.Marine] and
             unit.state == CombatState.Undamaged:
            found = true
            break
      found

  if not hasUndamaged and remainingHits > 0:
    for groundUnitId in groundUnitIds:
      if remainingHits <= 0:
        break

      let unitOpt = state.groundUnit(groundUnitId)
      if unitOpt.isNone:
        continue

      var unit = unitOpt.get()

      if unit.stats.unitType notin [GroundClass.Army, GroundClass.Marine]:
        continue

      if unit.state != CombatState.Crippled:
        continue

      # Crippled units have 50% DS
      let baseDS =
        if unit.stats.unitType == GroundClass.Army:
          gameConfig.groundUnits.units[GroundClass.Army].defenseStrength
        else:
          gameConfig.groundUnits.units[GroundClass.Marine].defenseStrength

      let hitsNeeded = int32(float32(baseDS) * 0.5)
      if remainingHits >= hitsNeeded:
        unit.state = CombatState.Destroyed
        remainingHits -= hitsNeeded
        state.updateGroundUnit(groundUnitId, unit)

proc calculateGroundForceAS*(state: GameState, colonyId: ColonyId): int32 =
  ## Calculate total AS from ground forces defending colony
  ## Per docs/specs/07-combat.md Section 7.8
  result = 0

  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  # Get all ground units at colony
  for unit in state.groundUnitsAtColony(colonyId):
    # Only armies and marines defend (not batteries or shields)
    if unit.stats.unitType in [GroundClass.Army, GroundClass.Marine]:
      if unit.state != CombatState.Destroyed:
        # Get base AS from config
        let baseAS =
          if unit.stats.unitType == GroundClass.Army:
            gameConfig.groundUnits.units[GroundClass.Army].attackStrength
          else:
            gameConfig.groundUnits.units[GroundClass.Marine].attackStrength

        # Apply combat state multiplier
        let multiplier =
          if unit.state == CombatState.Crippled:
            0.5
          else:
            1.0

        result += int32(float32(baseAS) * multiplier)

proc resolveBombardment*(
  state: GameState,
  attackerFleets: seq[FleetId],
  targetColony: ColonyId,
  rng: var Rand
): CombatResult =
  ## Bombardment: Fleet vs Ground Batteries + Shields
  ## Per docs/specs/07-combat.md Section 7.7

  result = CombatResult(
    theater: CombatTheater.Planetary,
    rounds: 0,
    attackerSurvived: true,
    defenderSurvived: true,
    attackerRetreatedFleets: @[],
    defenderRetreatedFleets: @[]
  )

  var round = 1'i32
  let maxRounds = 3 # Bombardment limited to 3 rounds per turn

  while round <= maxRounds:
    result.rounds = round

    # Calculate attacker AS (fleet bombardment strength)
    var planetBreakerAS = 0'i32
    var regularAS = 0'i32
    var hasPlanetBreaker = false

    for fleetId in attackerFleets:
      let fleetOpt = state.fleet(fleetId)
      if fleetOpt.isNone:
        continue

      let fleet = fleetOpt.get()
      for shipId in fleet.ships:
        let shipOpt = state.ship(shipId)
        if shipOpt.isNone:
          continue

        let ship = shipOpt.get()
        let shipAS = calculateShipAS(state, ship)

        if ship.shipClass == ShipClass.PlanetBreaker:
          planetBreakerAS += shipAS
          hasPlanetBreaker = true
        else:
          regularAS += shipAS

    # Calculate defender AS (ground batteries)
    let defenderAS = calculateGroundBatteryAS(state, targetColony)

    # Calculate DRM
    let attackerDRM =
      if hasPlanetBreaker:
        4'i32 # Planet-Breaker bonus
      else:
        0'i32
    let defenderDRM = 0'i32

    # Roll CER using Space/Orbital table (NOT Ground Combat table)
    # Per docs/specs/07-combat.md Section 7.7.3 Step 3:
    # "Bombardment uses Space/Orbital CRT (not Ground Combat CRT). Maximum 1.0× CER."
    let attackerCER = rollCER(rng, attackerDRM, CombatTheater.Orbital)
    let defenderCER = rollCER(rng, defenderDRM, CombatTheater.Orbital)

    # Calculate hits
    var attackerHits = 0'i32

    # Planet-Breaker hits bypass shields!
    let planetBreakerHits = int32(float32(planetBreakerAS) * attackerCER.cer)

    # Regular hits reduced by shields
    let colonyOpt = state.colony(targetColony)
    if colonyOpt.isNone:
      result.defenderSurvived = false
      return

    let shieldReduction = shieldReduction(state, targetColony)
    let regularHits =
      int32(float32(regularAS) * attackerCER.cer * (1.0 - shieldReduction))

    attackerHits = planetBreakerHits + regularHits

    let defenderHits = int32(float32(defenderAS) * defenderCER.cer)

    # Apply hits to batteries and capture excess
    let excessHits = applyHitsToBatteries(state, targetColony, attackerHits)

    # Apply hits to fleets (collect all ships)
    var attackerShips: seq[ShipId] = @[]
    for fleetId in attackerFleets:
      let fleetOpt = state.fleet(fleetId)
      if fleetOpt.isSome:
        let fleet = fleetOpt.get()
        attackerShips.add(fleet.ships)

    # Apply hits using standard hit application rules
    applyHits(state, attackerShips, defenderHits)

    # Check if batteries destroyed
    if allBatteriesDestroyed(state, targetColony):
      # Bombardment successful - apply excess hits to colony
      applyBombardmentExcessHits(state, targetColony, excessHits)
      result.defenderSurvived = false
      break

    round += 1

  return result

proc resolveInvasion*(
  state: GameState,
  attackerFleets: seq[FleetId],
  targetColony: ColonyId,
  rng: var Rand
): CombatResult =
  ## Standard Invasion: Marines vs Ground Forces
  ## Per docs/specs/07-combat.md Section 7.8.1
  ##
  ## **Prerequisites (MANDATORY):**
  ## - Orbital supremacy achieved (won orbital combat)
  ## - ALL ground batteries destroyed (validated below)
  ## - Troop Transports with loaded Marines present
  ##
  ## **Why Battery Clearance Required:**
  ## Batteries fire on landing transports during approach.
  ## Transports must land safely after batteries eliminated.
  ## Use Blitz if you want to land under fire (high risk/reward).
  ##
  ## **Invasion Process:**
  ## 1. Marines land → Shields/spaceports destroyed (line 713-714)
  ## 2. Ground combat: Marines vs Ground Forces (armies/colonial marines)
  ## 3. Defender gets +2 DRM (prepared defenses) + homeworld bonus
  ## 4. If attackers win: 50% infrastructure destroyed (sabotage)

  result = CombatResult(
    theater: CombatTheater.Planetary,
    rounds: 0,
    attackerSurvived: true,
    defenderSurvived: true,
    attackerRetreatedFleets: @[],
    defenderRetreatedFleets: @[]
  )

  # VALIDATION: All batteries must be destroyed before invasion
  # Per docs/specs/07-combat.md Section 7.8.1 line 924
  if not allBatteriesDestroyed(state, targetColony):
    # Validation failed - return early with rounds = 0
    # Orchestrator detects this (rounds == 0 + attackerSurvived = false)
    # and fires OrderFailed event with reason "batteries still operational"
    # See: combat/orchestrator.nim lines 358-379
    result.attackerSurvived = false
    return result

  # Marines land - shields and spaceports destroyed
  destroyShields(state, targetColony)
  destroySpaceports(state, targetColony)

  # Get ground unit lists for damage application
  var marineIds: seq[GroundUnitId] = @[]
  for fleetId in attackerFleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isNone:
      continue
    let fleet = fleetOpt.get()
    for shipId in fleet.ships:
      marineIds.add(state.groundUnitsOnTransport(shipId).mapIt(it.id))

  var defenderIds: seq[GroundUnitId] = @[]
  defenderIds = state.groundUnitsAtColony(targetColony).mapIt(it.id)

  var round = 1'i32
  let maxRounds = 20

  while round <= maxRounds:
    result.rounds = round

    # Calculate current AS based on surviving units
    let attackerAS = calculateMarineAS(state, attackerFleets)
    let defenderAS = calculateGroundForceAS(state, targetColony)

    # Check if either side eliminated
    if attackerAS == 0:
      result.attackerSurvived = false
      break
    if defenderAS == 0:
      result.defenderSurvived = false
      break

    # Calculate DRM
    let attackerDRM = 0'i32

    # Check if defending homeworld
    let colonyOpt = state.colony(targetColony)
    let isHomeworld =
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        state.starMap.homeWorlds.getOrDefault(colony.systemId) == colony.owner
      else:
        false

    let defenderDRM = 2'i32 + (if isHomeworld: 1'i32 else: 0'i32)

    # Roll CER (ground combat table)
    let attackerCER = rollCER(rng, attackerDRM, CombatTheater.Planetary)
    let defenderCER = rollCER(rng, defenderDRM, CombatTheater.Planetary)

    # Calculate hits
    let attackerHits = int32(float32(attackerAS) * attackerCER.cer)
    let defenderHits = int32(float32(defenderAS) * defenderCER.cer)

    # Apply damage to ground units
    applyHitsToGroundUnits(state, marineIds, defenderHits)
    applyHitsToGroundUnits(state, defenderIds, attackerHits)

    round += 1

  # Safety check: ground combat must resolve to elimination
  # If we hit max rounds with survivors on both sides, something is wrong
  if result.attackerSurvived and result.defenderSurvived:
    let attackerAS = calculateMarineAS(state, attackerFleets)
    let defenderAS = calculateGroundForceAS(state, targetColony)
    raise newException(Defect,
      &"Ground combat stalemate after {maxRounds} rounds: " &
      &"colony={targetColony}, attackerAS={attackerAS}, defenderAS={defenderAS}. " &
      "Marines cannot retreat - combat must resolve to elimination.")

  # If attackers won, 50% infrastructure destroyed
  if not result.defenderSurvived and result.attackerSurvived:
    let colonyOpt = state.colony(targetColony)
    if colonyOpt.isSome:
      let colony = colonyOpt.get()
      let infrastructureLoss = int32(float32(colony.infrastructure) * 0.5)
      applyInfrastructureDamage(state, targetColony, infrastructureLoss)

  return result

proc resolveBlitz*(
  state: GameState,
  attackerFleets: seq[FleetId],
  targetColony: ColonyId,
  rng: var Rand
): CombatResult =
  ## Blitz: One bombardment round + immediate invasion
  ## Marines land under fire (risky but preserves infrastructure)
  ## Per docs/specs/07-combat.md Section 7.8

  result = CombatResult(
    theater: CombatTheater.Planetary,
    rounds: 0,
    attackerSurvived: true,
    defenderSurvived: true,
    attackerRetreatedFleets: @[],
    defenderRetreatedFleets: @[]
  )

  # Phase 1: One bombardment round (batteries fire at ALL fleet ships!)
  # Per docs/specs/07-combat.md Section 7.8.2 Phase 1
  # **KEY DIFFERENCE FROM STANDARD INVASION:**
  # Batteries NOT cleared first - marines land under fire (high risk!)
  # Transports are VULNERABLE during this phase (not screened)

  # Calculate fleet bombardment AS (all combat ships, not marines!)
  var planetBreakerAS = 0'i32
  var regularAS = 0'i32
  var hasPlanetBreaker = false

  for fleetId in attackerFleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isNone:
      continue

    let fleet = fleetOpt.get()
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isNone:
        continue

      let ship = shipOpt.get()
      let shipAS = calculateShipAS(state, ship)

      if ship.shipClass == ShipClass.PlanetBreaker:
        planetBreakerAS += shipAS
        hasPlanetBreaker = true
      else:
        regularAS += shipAS

  let defenderAS = calculateGroundBatteryAS(state, targetColony)

  # DRM: This is orbital bombardment, not ground combat
  let attackerDRM = if hasPlanetBreaker: 4'i32 else: 0'i32
  let defenderDRM = 0'i32 # No bonus - batteries firing at orbiting ships

  # CER: Use Space/Orbital table (bombardment), NOT Ground table
  let attackerCER = rollCER(rng, attackerDRM, CombatTheater.Orbital)
  let defenderCER = rollCER(rng, defenderDRM, CombatTheater.Orbital)

  # Calculate hits (Planet-Breaker bypasses shields)
  let shieldReduction = shieldReduction(state, targetColony)

  let planetBreakerHits = int32(float32(planetBreakerAS) * attackerCER.cer)
  let regularHits = int32(float32(regularAS) * attackerCER.cer * (1.0 - shieldReduction))
  let attackerHits = planetBreakerHits + regularHits

  let defenderHits = int32(float32(defenderAS) * defenderCER.cer)

  # Apply hits to batteries (excess not needed in blitz Phase 1)
  discard applyHitsToBatteries(state, targetColony, attackerHits)

  # Collect all fleet ships for damage application
  var allShips: seq[ShipId] = @[]
  for fleetId in attackerFleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isSome:
      let fleet = fleetOpt.get()
      allShips.add(fleet.ships)

  # Capture ship states BEFORE applying hits
  # Needed to detect which transports were damaged (for marine damage propagation)
  var oldShipStates: Table[ShipId, CombatState]
  for shipId in allShips:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      oldShipStates[shipId] = shipOpt.get().state

  # Apply hits to ALL fleet ships (including transports!)
  # Per docs/specs/07-combat.md Section 7.8.2 line 1011
  # "Ground batteries fire at ALL fleet ships (including Troop Transports!)"
  applyHits(state, allShips, defenderHits)

  # Propagate transport damage to marines aboard
  # If transport crippled/destroyed, marines aboard also crippled/destroyed
  # This is the ONLY place this mechanic applies (Blitz Phase 1)
  propagateTransportDamageToMarines(state, oldShipStates, allShips)

  # Check if transports survived - if all destroyed, mission fails
  var hasOperationalTransports = false
  for shipId in allShips:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.shipClass == ShipClass.TroopTransport and ship.state != CombatState.Destroyed:
        hasOperationalTransports = true
        break

  if not hasOperationalTransports:
    # All transports destroyed - blitz fails
    result.attackerSurvived = false
    return result

  # Phase 2: Marines land immediately
  # NOTE: Shields NOT destroyed in blitz - they're captured intact if successful!
  # Per docs/specs/07-combat.md Section 7.8.2: "Shields, batteries, spaceports captured functional"

  # Phase 3: Ground combat with batteries participating (defender +3 DRM)

  # Get ground unit lists for damage application
  var marineIds: seq[GroundUnitId] = @[]
  for fleetId in attackerFleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isNone:
      continue
    let fleet = fleetOpt.get()
    for shipId in fleet.ships:
      marineIds.add(state.groundUnitsOnTransport(shipId).mapIt(it.id))

  var defenderGroundIds: seq[GroundUnitId] = @[]
  var batteryIds: seq[GroundUnitId] = @[]
  for unit in state.groundUnitsAtColony(targetColony):
    if unit.stats.unitType == GroundClass.GroundBattery:
      batteryIds.add(unit.id)
    elif unit.stats.unitType in [GroundClass.Army, GroundClass.Marine]:
      defenderGroundIds.add(unit.id)

  var round = 1'i32
  let maxRounds = 20'i32

  while round <= maxRounds:
    result.rounds = round

    # Calculate current AS based on surviving units
    let marineAS = calculateMarineAS(state, attackerFleets)
    let groundAS = calculateGroundForceAS(state, targetColony)
    let batteryAS = calculateGroundBatteryAS(state, targetColony)
    let totalDefenderAS = groundAS + batteryAS

    # Check if either side eliminated
    if marineAS == 0:
      result.attackerSurvived = false
      break
    if totalDefenderAS == 0:
      result.defenderSurvived = false
      break

    # Check if defending homeworld
    let colonyOpt = state.colony(targetColony)
    let isHomeworld =
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        state.starMap.homeWorlds.getOrDefault(colony.systemId) == colony.owner
      else:
        false

    # DRM calculation - Landing under fire bonus
    let attackerDRM_round = 0'i32
    let defenderDRM_round = 3'i32 + (if isHomeworld: 1'i32 else: 0'i32)

    let attackerCER_round = rollCER(rng, attackerDRM_round, CombatTheater.Planetary)
    let defenderCER_round = rollCER(rng, defenderDRM_round, CombatTheater.Planetary)

    let attackerHits_round = int32(float32(marineAS) * attackerCER_round.cer)
    let defenderHits_round = int32(float32(totalDefenderAS) * defenderCER_round.cer)

    # Apply damage to ground units
    # Distribute attacker hits proportionally between ground forces and batteries
    if totalDefenderAS > 0:
      let groundPortion = float32(groundAS) / float32(totalDefenderAS)
      let batteryPortion = float32(batteryAS) / float32(totalDefenderAS)

      let groundHits = int32(float32(attackerHits_round) * groundPortion)
      let batteryHits = int32(float32(attackerHits_round) * batteryPortion)

      applyHitsToGroundUnits(state, defenderGroundIds, groundHits)
      discard applyHitsToBatteries(state, targetColony, batteryHits)

    applyHitsToGroundUnits(state, marineIds, defenderHits_round)

    round += 1

  # Safety check: ground combat must resolve to elimination
  # If we hit max rounds with survivors on both sides, something is wrong
  if result.attackerSurvived and result.defenderSurvived:
    let marineAS = calculateMarineAS(state, attackerFleets)
    let groundAS = calculateGroundForceAS(state, targetColony)
    let batteryAS = calculateGroundBatteryAS(state, targetColony)
    raise newException(Defect,
      &"Blitz ground combat stalemate after {maxRounds} rounds: " &
      &"colony={targetColony}, marineAS={marineAS}, groundAS={groundAS}, " &
      &"batteryAS={batteryAS}. Marines cannot retreat - combat must resolve to elimination.")

  # If attackers won, 0% infrastructure destroyed (captured intact!)
  # This is the key advantage of blitz

  return result

## Design Notes:
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.7 - Bombardment
## - docs/specs/07-combat.md Section 7.8 - Invasion & Blitz
## - docs/specs/reference.md Section 9.3 - Shield Mechanics
##
## **Bombardment Mechanics:**
## - Fleet AS vs Ground Battery AS
## - Planetary shields reduce regular damage (not Planet-Breaker)
## - Planet-Breaker ships bypass shields entirely
## - Limited to 3 rounds per turn
## - Excess hits damage infrastructure
## - Transports SCREENED (auxiliary vessels, not vulnerable)
##
## **Standard Invasion Mechanics:**
## - VALIDATION: Requires all batteries destroyed first (mandatory prerequisite)
## - If validation fails, invasion aborted (game event fired)
## - Marines land safely → shields/spaceports destroyed
## - Marines vs Ground Forces
## - Defender gets +2 DRM (prepared defenses), +1 if homeworld
## - 50% infrastructure destroyed if attackers win
## - Transports NOT VULNERABLE (batteries already eliminated)
##
## **Blitz Mechanics:**
## - Phase 1: One bombardment round (batteries fire at ALL ships including transports!)
## - **Marine Damage Propagation**: Transport hit → Marines aboard damaged
##   - Transport crippled → Marines crippled (if undamaged)
##   - Transport destroyed → Marines destroyed
##   - This mechanic ONLY applies during Blitz Phase 1 (not regular bombardment/invasion)
## - Phase 2: Marines land immediately under fire (if transports survive)
## - Phase 3: Ground combat with batteries + ground forces (defender +3 DRM)
## - 0% infrastructure destroyed if attackers win (captured intact!)
## - High risk (transports vulnerable, +3 DRM), high reward (intact capture)
##
## **Implementation Notes:**
## - Ground unit damage properly tracked (no placeholder systems)
## - Uses standard hit application from hits module (no code duplication)
## - Bombardment excess hits properly applied after batteries destroyed
## - All combat follows standard damage model: Cripple all → Destroy crippled
## - Marine damage propagation called after Blitz Phase 1 applyHits (see propagateTransportDamageToMarines)
