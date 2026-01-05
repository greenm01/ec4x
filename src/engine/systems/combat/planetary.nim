## Planetary Combat System
##
## Implements bombardment, invasion, and blitz mechanics.
## Fleet attacks on colonies with ground defenses.
##
## Per docs/specs/07-combat.md Section 7.7-7.8

import std/[random, options, tables]
import ../../types/[core, game_state, combat, ship, facilities, colony, ground_unit]
import ../../state/engine
import ../../globals
import ./strength
import ./cer

# Forward declarations
proc calculateGroundBatteryAS*(state: GameState, colonyId: ColonyId): int32
proc calculateMarineAS*(state: GameState, fleets: seq[FleetId]): int32
proc calculateGroundForceAS*(state: GameState, colonyId: ColonyId): int32

proc getShieldReduction*(state: GameState, colonyId: ColonyId): float32 =
  ## Calculate damage reduction from planetary shields
  ## Per docs/specs/reference.md Section 9.3
  ## Shields are house-level tech - if colony has operational shield unit, use house's SLD level

  # Check if colony has any ground units
  if not state.groundUnits.byColony.hasKey(colonyId):
    return 0.0

  # Find operational PlanetaryShield units
  var hasOperationalShield = false
  for groundUnitId in state.groundUnits.byColony[colonyId]:
    let unitOpt = state.groundUnit(groundUnitId)
    if unitOpt.isSome:
      let unit = unitOpt.get()
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

  let colony = colonyOpt.get()
  let houseOpt = state.house(colony.owner)
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

  # Check kastras (starbases with batteries)
  if state.kastras.byColony.hasKey(colonyId):
    for kastraId in state.kastras.byColony[colonyId]:
      let kastraOpt = state.kastra(kastraId)
      if kastraOpt.isSome:
        let kastra = kastraOpt.get()
        if kastra.state != CombatState.Destroyed:
          return false # At least one battery operational

  return true # No operational batteries found

proc destroyShields*(state: var GameState, colonyId: ColonyId) =
  ## Destroy planetary shields when marines land during standard invasion
  ## Per docs/specs/07-combat.md Section 7.8.1
  ## "Shields and spaceports immediately destroyed upon marine landing"
  ##
  ## NOTE: Blitz operations do NOT call this - shields captured intact if successful

  if not state.groundUnits.byColony.hasKey(colonyId):
    return

  for groundUnitId in state.groundUnits.byColony[colonyId]:
    let unitOpt = state.groundUnit(groundUnitId)
    if unitOpt.isNone:
      continue

    var unit = unitOpt.get()

    # Only destroy planetary shields
    if unit.stats.unitType == GroundClass.PlanetaryShield:
      unit.state = CombatState.Destroyed
      state.updateGroundUnit(groundUnitId, unit)

proc destroySpaceports*(state: var GameState, colonyId: ColonyId) =
  ## Destroy all spaceports when marines land during invasion
  ## Per docs/specs/07-combat.md Section 7.8.1
  ## "Shields and spaceports immediately destroyed upon marine landing"

  if not state.neorias.byColony.hasKey(colonyId):
    return

  for neoriaId in state.neorias.byColony[colonyId]:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isNone:
      continue

    var neoria = neoriaOpt.get()

    # Only destroy spaceports (planet-based facilities)
    if neoria.neoriaClass == NeoriaClass.Spaceport:
      neoria.state = CombatState.Destroyed
      state.updateNeoria(neoriaId, neoria)

proc applyInfrastructureDamage*(
  state: var GameState, colonyId: ColonyId, damage: int32
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
  state: var GameState, colonyId: ColonyId, excessHits: int32
) =
  ## Distribute bombardment excess hits (after batteries destroyed)
  ## Damages: Ground forces → Spaceports → Infrastructure
  ## Per docs/specs/07-combat.md Section 7.7.6
  ##
  ## TODO: Implement proper ground force tracking
  ## TODO: Implement proper spaceport targeting

  if excessHits <= 0:
    return

  var remainingHits = excessHits

  # Phase 1: Damage ground forces (armies/marines)
  # TODO: Implement proper ground unit damage
  # For now, this is a placeholder - ground forces are tracked via population
  # When ground unit tracking is implemented, apply hits here

  # Phase 2: Destroy spaceports
  # Each spaceport has DS - requires multiple hits to destroy
  if state.neorias.byColony.hasKey(colonyId) and remainingHits > 0:
    for neoriaId in state.neorias.byColony[colonyId]:
      if remainingHits <= 0:
        break

      let neoriaOpt = state.neoria(neoriaId)
      if neoriaOpt.isNone:
        continue

      var neoria = neoriaOpt.get()

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

      if neoria.state == CombatState.Undamaged:
        # Need DS hits to cripple
        if remainingHits >= spaceportDS:
          neoria.state = CombatState.Crippled
          remainingHits -= spaceportDS
          state.updateNeoria(neoriaId, neoria)
      elif neoria.state == CombatState.Crippled:
        # Need 50% DS to destroy crippled facility
        let hitsNeeded = int32(float32(spaceportDS) * 0.5)
        if remainingHits >= hitsNeeded:
          neoria.state = CombatState.Destroyed
          remainingHits -= hitsNeeded
          state.updateNeoria(neoriaId, neoria)

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
  state: var GameState, colonyId: ColonyId, hits: int32
) =
  ## Apply hits to ground batteries (kastras)
  ## Per docs/specs/07-combat.md Section 7.7

  var remainingHits = hits

  # Get all kastras at colony
  if not state.kastras.byColony.hasKey(colonyId):
    return

  # Phase 1: Cripple all undamaged batteries
  for kastraId in state.kastras.byColony[colonyId]:
    if remainingHits <= 0:
      break

    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isNone:
      continue

    var kastra = kastraOpt.get()
    if kastra.state != CombatState.Undamaged:
      continue

    let hitsNeeded = kastra.stats.defenseStrength
    if remainingHits >= hitsNeeded:
      kastra.state = CombatState.Crippled
      remainingHits -= hitsNeeded
      state.updateKastra(kastraId, kastra)

  # Phase 2: Destroy crippled batteries
  let hasUndamaged =
    block:
      var found = false
      for kastraId in state.kastras.byColony[colonyId]:
        let kastraOpt = state.kastra(kastraId)
        if kastraOpt.isSome and kastraOpt.get().state == CombatState.Undamaged:
          found = true
          break
      found

  if not hasUndamaged and remainingHits > 0:
    for kastraId in state.kastras.byColony[colonyId]:
      if remainingHits <= 0:
        break

      let kastraOpt = state.kastra(kastraId)
      if kastraOpt.isNone:
        continue

      var kastra = kastraOpt.get()
      if kastra.state != CombatState.Crippled:
        continue

      # Crippled batteries have 50% DS
      let hitsNeeded = int32(float32(kastra.stats.defenseStrength) * 0.5)
      if remainingHits >= hitsNeeded:
        kastra.state = CombatState.Destroyed
        remainingHits -= hitsNeeded
        state.updateKastra(kastraId, kastra)

proc calculateGroundBatteryAS*(state: GameState, colonyId: ColonyId): int32 =
  ## Calculate total AS from ground batteries
  ## Per docs/specs/07-combat.md Section 7.7
  result = 0

  if not state.kastras.byColony.hasKey(colonyId):
    return

  for kastraId in state.kastras.byColony[colonyId]:
    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isNone:
      continue

    let kastra = kastraOpt.get()
    if kastra.state == CombatState.Destroyed:
      continue

    let baseAS = kastra.stats.attackStrength
    let multiplier =
      if kastra.state == CombatState.Crippled:
        0.5
      else:
        1.0

    result += int32(float32(baseAS) * multiplier)

proc calculateMarineAS*(state: GameState, fleets: seq[FleetId]): int32 =
  ## Calculate total AS from marine units in fleets
  ## Per docs/specs/07-combat.md Section 7.8
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
        if not state.groundUnits.byTransport.hasKey(shipId):
          continue # No units loaded

        var transportMarineAS = 0'i32
        for groundUnitId in state.groundUnits.byTransport[shipId]:
          let unitOpt = state.groundUnit(groundUnitId)
          if unitOpt.isNone:
            continue

          let unit = unitOpt.get()

          # Only marines participate in invasion
          if unit.stats.unitType == GroundClass.Marine:
            if unit.state != CombatState.Destroyed:
              # Get base marine AS from config
              let baseAS = gameConfig.groundUnits.units[GroundClass.Marine].attackStrength

              # Apply unit combat state multiplier
              let unitMultiplier =
                if unit.state == CombatState.Crippled:
                  0.5
                else:
                  1.0

              transportMarineAS += int32(float32(baseAS) * unitMultiplier)

        # Apply ship damage multiplier to total transport AS
        let shipMultiplier =
          if ship.state == CombatState.Crippled:
            0.5 # Crippled transport reduces effectiveness
          else:
            1.0

        result += int32(float32(transportMarineAS) * shipMultiplier)

proc calculateGroundForceAS*(state: GameState, colonyId: ColonyId): int32 =
  ## Calculate total AS from ground forces defending colony
  ## Per docs/specs/07-combat.md Section 7.8
  result = 0

  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  # Get all ground units at colony
  if not state.groundUnits.byColony.hasKey(colonyId):
    return # No ground forces

  for groundUnitId in state.groundUnits.byColony[colonyId]:
    let unitOpt = state.groundUnit(groundUnitId)
    if unitOpt.isNone:
      continue

    let unit = unitOpt.get()

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
  state: var GameState,
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

    # Roll CER (ground combat table)
    let attackerCER = rollCER(rng, attackerDRM, CombatTheater.Planetary)
    let defenderCER = rollCER(rng, defenderDRM, CombatTheater.Planetary)

    # Calculate hits
    var attackerHits = 0'i32

    # Planet-Breaker hits bypass shields!
    let planetBreakerHits = int32(float32(planetBreakerAS) * attackerCER)

    # Regular hits reduced by shields
    let colonyOpt = state.colony(targetColony)
    if colonyOpt.isNone:
      result.defenderSurvived = false
      return

    let colony = colonyOpt.get()
    let shieldReduction = getShieldReduction(state, targetColony)
    let regularHits =
      int32(float32(regularAS) * attackerCER * (1.0 - shieldReduction))

    attackerHits = planetBreakerHits + regularHits

    let defenderHits = int32(float32(defenderAS) * defenderCER)

    # Apply hits to batteries
    applyHitsToBatteries(state, targetColony, attackerHits)

    # Apply hits to fleets (collect all ships)
    var attackerShips: seq[ShipId] = @[]
    for fleetId in attackerFleets:
      let fleetOpt = state.fleet(fleetId)
      if fleetOpt.isSome:
        let fleet = fleetOpt.get()
        attackerShips.add(fleet.ships)

    # Import hits module to apply hits to ships
    # Note: This creates circular dependency - needs refactoring
    # For now, we'll duplicate the hit application logic
    var remainingHits = defenderHits

    # Phase 1: Cripple undamaged ships
    for shipId in attackerShips:
      if remainingHits <= 0:
        break

      let shipOpt = state.ship(shipId)
      if shipOpt.isNone:
        continue

      var ship = shipOpt.get()
      if ship.state != CombatState.Undamaged:
        continue

      let hitsNeeded = ship.stats.defenseStrength
      if remainingHits >= hitsNeeded:
        if ship.shipClass == ShipClass.Fighter:
          ship.state = CombatState.Destroyed
        else:
          ship.state = CombatState.Crippled
        remainingHits -= hitsNeeded
        state.updateShip(shipId, ship)

    # Check if batteries destroyed
    if allBatteriesDestroyed(state, targetColony):
      # Bombardment successful - apply excess hits to ground forces, spaceports, IU, population
      let excessHits = remainingHits
      applyBombardmentExcessHits(state, targetColony, excessHits)
      result.defenderSurvived = false
      break

    round += 1

  return result

proc resolveInvasion*(
  state: var GameState,
  attackerFleets: seq[FleetId],
  targetColony: ColonyId,
  rng: var Rand
): CombatResult =
  ## Standard Invasion: Marines vs Ground Forces
  ## Requires all batteries destroyed first
  ## Per docs/specs/07-combat.md Section 7.8

  result = CombatResult(
    theater: CombatTheater.Planetary,
    rounds: 0,
    attackerSurvived: true,
    defenderSurvived: true,
    attackerRetreatedFleets: @[],
    defenderRetreatedFleets: @[]
  )

  # Check prerequisite: batteries must be destroyed
  if not allBatteriesDestroyed(state, targetColony):
    result.attackerSurvived = false
    return result

  # Marines land - shields and spaceports destroyed
  destroyShields(state, targetColony)
  destroySpaceports(state, targetColony)

  var round = 1'i32
  let maxRounds = 20

  # Track cumulative damage to ground forces (placeholder system)
  # TODO: Replace with proper ground unit tracking
  var marinesDamage = 0'i32
  var defenderDamage = 0'i32

  while round <= maxRounds:
    result.rounds = round

    # Calculate current AS (base AS - cumulative damage)
    let baseMarineAS = calculateMarineAS(state, attackerFleets)
    let baseDefenderAS = calculateGroundForceAS(state, targetColony)

    let attackerAS = max(0'i32, baseMarineAS - marinesDamage)
    let defenderAS = max(0'i32, baseDefenderAS - defenderDamage)

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
    let attackerHits = int32(float32(attackerAS) * attackerCER)
    let defenderHits = int32(float32(defenderAS) * defenderCER)

    # Apply damage (simplified - accumulate until proper ground unit tracking)
    marinesDamage += defenderHits
    defenderDamage += attackerHits

    round += 1

  # If attackers won, 50% infrastructure destroyed
  if not result.defenderSurvived and result.attackerSurvived:
    let colonyOpt = state.colony(targetColony)
    if colonyOpt.isSome:
      let colony = colonyOpt.get()
      let infrastructureLoss = int32(float32(colony.infrastructure) * 0.5)
      applyInfrastructureDamage(state, targetColony, infrastructureLoss)

  return result

proc resolveBlitz*(
  state: var GameState,
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
  # This is BOMBARDMENT, not ground combat - fleet bombards from orbit

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

  let totalAttackerAS = planetBreakerAS + regularAS
  let defenderAS = calculateGroundBatteryAS(state, targetColony)

  # DRM: This is orbital bombardment, not ground combat
  let attackerDRM = if hasPlanetBreaker: 4'i32 else: 0'i32
  let defenderDRM = 0'i32 # No bonus - batteries firing at orbiting ships

  # CER: Use Space/Orbital table (bombardment), NOT Ground table
  let attackerCER = rollCER(rng, attackerDRM, CombatTheater.Orbital)
  let defenderCER = rollCER(rng, defenderDRM, CombatTheater.Orbital)

  # Calculate hits (Planet-Breaker bypasses shields)
  let shieldReduction = getShieldReduction(state, targetColony)

  let planetBreakerHits = int32(float32(planetBreakerAS) * attackerCER)
  let regularHits = int32(float32(regularAS) * attackerCER * (1.0 - shieldReduction))
  let attackerHits = planetBreakerHits + regularHits

  let defenderHits = int32(float32(defenderAS) * defenderCER)

  # Apply hits to batteries
  applyHitsToBatteries(state, targetColony, attackerHits)

  # Apply hits to ALL fleet ships (including transports!)
  # Transports are vulnerable - can be destroyed before landing
  var allShips: seq[ShipId] = @[]
  for fleetId in attackerFleets:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isSome:
      let fleet = fleetOpt.get()
      allShips.add(fleet.ships)

  # Apply hits using standard hit application rules
  var remainingHits = defenderHits

  # Phase 1: Cripple undamaged ships
  for shipId in allShips:
    if remainingHits <= 0:
      break

    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue

    var ship = shipOpt.get()
    if ship.state != CombatState.Undamaged:
      continue

    let hitsNeeded = ship.stats.defenseStrength
    if remainingHits >= hitsNeeded:
      if ship.shipClass == ShipClass.Fighter:
        ship.state = CombatState.Destroyed
      else:
        ship.state = CombatState.Crippled
      remainingHits -= hitsNeeded
      state.updateShip(shipId, ship)

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
  var round = 1'i32
  let maxRounds = 20'i32

  # Track cumulative damage (placeholder system)
  # TODO: Replace with proper ground unit tracking
  var marinesDamage = 0'i32
  var defenderDamage = 0'i32
  var batteryDamage = 0'i32

  while round <= maxRounds:
    result.rounds = round

    # Calculate current AS (base AS - cumulative damage)
    let baseMarineAS = calculateMarineAS(state, attackerFleets)
    let baseGroundAS = calculateGroundForceAS(state, targetColony)
    let baseBatteryAS = calculateGroundBatteryAS(state, targetColony)

    let marineAS = max(0'i32, baseMarineAS - marinesDamage)
    let groundAS = max(0'i32, baseGroundAS - defenderDamage)
    let batteryAS = max(0'i32, baseBatteryAS - batteryDamage)
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

    let attackerHits_round = int32(float32(marineAS) * attackerCER_round)
    let defenderHits_round = int32(float32(totalDefenderAS) * defenderCER_round)

    # Apply damage (simplified - accumulate until proper ground unit tracking)
    # Distribute attacker hits proportionally between ground forces and batteries
    if totalDefenderAS > 0:
      let groundPortion = float32(groundAS) / float32(totalDefenderAS)
      let batteryPortion = float32(batteryAS) / float32(totalDefenderAS)

      defenderDamage += int32(float32(attackerHits_round) * groundPortion)
      batteryDamage += int32(float32(attackerHits_round) * batteryPortion)

    marinesDamage += defenderHits_round

    round += 1

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
##
## **Invasion Mechanics:**
## - Requires all batteries destroyed first
## - Marines land → shields destroyed
## - Marines vs Ground Forces
## - Defender gets +2 DRM (prepared defenses), +1 if homeworld
## - 50% infrastructure destroyed if attackers win
##
## **Blitz Mechanics:**
## - One bombardment round (batteries fire at transports!)
## - Marines land immediately under fire
## - Ground combat with batteries + ground forces (defender +3 DRM)
## - 0% infrastructure destroyed if attackers win (captured intact)
## - High risk, high reward
##
## **TODO Items:**
## - Implement proper ground unit tracking
## - Implement marine capacity in ship stats
## - Implement homeworld detection
## - Implement transport targeting in blitz
## - Implement proper hit distribution in ground combat
## - Add circular dependency resolution for hits module
