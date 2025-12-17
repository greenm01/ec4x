## Domestikos Collector - Military Commander Domain
##
## Tracks combat performance, military assets (ships, ground units, facilities),
## capacity management, and fleet activity.
##
## REFACTORED: 2025-12-06 - Extracted from diagnostics.nim (lines 631-841)
## NEW: Facility tracking (totalSpaceports, totalShipyards)

import std/[math, strformat, tables, options]
import ./types
import ../../../engine/[gamestate, logger]
import ../../../engine/config/military_config
import ../../../common/types/[core, units]
import ../../common/types

proc collectDomestikosMetrics*(state: GameState, houseId: HouseId,
                               prevMetrics: DiagnosticMetrics): DiagnosticMetrics =
  ## Collect military commander metrics: combat, assets, capacity
  result = initDiagnosticMetrics(state.turn, houseId)

  let house = state.houses.getOrDefault(houseId)

  # ================================================================
  # COMBAT PERFORMANCE (from turn resolution tracking)
  # ================================================================

  # Space combat statistics
  result.spaceCombatWins = house.lastTurnSpaceCombatWins
  result.spaceCombatLosses = house.lastTurnSpaceCombatLosses
  result.spaceCombatTotal = house.lastTurnSpaceCombatTotal

  # Combat performance metrics (tracked during resolution)
  # TODO: Implement these during turn resolution
  result.orbitalFailures = 0
  result.orbitalTotal = 0
  result.raiderAmbushSuccess = 0
  result.raiderAmbushAttempts = 0

  # Detection metrics (tracked from events)
  result.raiderDetectedCount = house.lastTurnRaidersDetected
  result.raiderStealthSuccessCount = house.lastTurnRaidersStealthSuccess
  result.eliDetectionAttempts = house.lastTurnEliDetectionAttempts
  # Calculate averages (avoid division by zero)
  if house.lastTurnEliDetectionAttempts > 0:
    result.avgEliRoll = float(house.lastTurnEliRollsSum) /
      float(house.lastTurnEliDetectionAttempts)
  else:
    result.avgEliRoll = 0.0
  let totalClkRolls = house.lastTurnRaidersDetected +
    house.lastTurnRaidersStealthSuccess
  if totalClkRolls > 0:
    result.avgClkRoll = float(house.lastTurnClkRollsSum) / float(totalClkRolls)
  else:
    result.avgClkRoll = 0.0

  # Scout detection metrics (reconnaissance)
  result.scoutsDetected = house.lastTurnScoutsDetected
  result.scoutsDetectedBy = house.lastTurnScoutsDetectedBy

  result.combatCERAverage = 0
  result.bombardmentRoundsTotal = 0
  result.groundCombatVictories = 0
  result.retreatsExecuted = 0
  result.criticalHitsDealt = 0
  result.criticalHitsReceived = 0
  result.cloakedAmbushSuccess = 0
  result.shieldsActivatedCount = 0

  # Phase 1: Invasion order tracking (populated during order generation)
  result.invasionOrders_generated = 0
  result.invasionOrders_bombard = 0
  result.invasionOrders_invade = 0
  result.invasionOrders_blitz = 0
  result.invasionOrders_canceled = 0

  # ================================================================
  # CAPACITY MANAGEMENT (Fighter & Squadron Limits)
  # ================================================================

  # Fighter Doctrine multiplier (FD tech level)
  let fdMultiplier = case house.techTree.levels.fighterDoctrine
    of 1: 1.0
    of 2: 1.5
    of 3: 2.0
    else: 1.0

  # Calculate fighter capacity and violations
  let fighterIUDivisor =
    globalMilitaryConfig.fighter_mechanics.fighter_capacity_iu_divisor
  var totalFighterCapacity = 0
  var totalFighters = 0
  var totalStarbases = 0
  var capacityViolationCount = 0

  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      let colonyCapacity =
        int(floor(float(colony.industrial.units) / float(fighterIUDivisor)) *
        fdMultiplier)
      totalFighterCapacity += colonyCapacity
      totalFighters += colony.fighterSquadrons.len
      totalStarbases += colony.starbases.len

      if colony.capacityViolation.active:
        capacityViolationCount += 1

  result.fighterCapacityMax = totalFighterCapacity
  result.fighterCapacityUsed = totalFighters
  result.fighterCapacityViolation =
    result.fighterCapacityUsed > result.fighterCapacityMax
  result.capacityViolationsActive = capacityViolationCount

  # Squadron limit calculation
  var totalIU = 0
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      totalIU += colony.industrial.units

  let squadronIUDivisor =
    globalMilitaryConfig.squadron_limits.squadron_limit_iu_divisor
  result.squadronLimitMax = max(8, (totalIU div squadronIUDivisor) * 2)

  # TODO: Count actual capital squadrons (not all squadrons)
  result.squadronLimitUsed = 0
  result.squadronLimitViolation = false

  # Starbase tracking (facilities, not ships)
  result.starbasesActual = totalStarbases

  # ================================================================
  # MILITARY ASSETS - SHIPS (All 18 ship classes)
  # ================================================================
  # NOTE: Starbases are facilities (not ships), tracked separately in starbasesActual

  var fighterShips = 0
  var corvetteShips = 0
  var frigateShips = 0
  var scoutShips = 0
  var raiderShips = 0
  var destroyerShips = 0
  var cruiserShips = 0
  var lightCruiserShips = 0
  var heavyCruiserShips = 0
  var battlecruiserShips = 0
  var battleshipShips = 0
  var dreadnoughtShips = 0
  var superDreadnoughtShips = 0
  var carrierShips = 0
  var superCarrierShips = 0
  var etacShips = 0
  var troopTransportShips = 0
  var planetBreakerShips = 0

  # Count colony-based fighters
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      fighterShips += colony.fighterSquadrons.len

  # Planet-breakers tracked at house level
  planetBreakerShips = house.planetBreakerCount

  # Count fleet-based ships
  var idleCarrierCount = 0
  var totalCarrierCount = 0

  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      # Count squadron ships (military)
      for squadron in fleet.squadrons:
        case squadron.flagship.shipClass:
        of ShipClass.Fighter: fighterShips += 1
        of ShipClass.Corvette: corvetteShips += 1
        of ShipClass.Frigate: frigateShips += 1
        of ShipClass.Scout: scoutShips += 1
        of ShipClass.Raider: raiderShips += 1
        of ShipClass.Destroyer: destroyerShips += 1
        of ShipClass.Cruiser: cruiserShips += 1
        of ShipClass.LightCruiser: lightCruiserShips += 1
        of ShipClass.HeavyCruiser: heavyCruiserShips += 1
        of ShipClass.Battlecruiser: battlecruiserShips += 1
        of ShipClass.Battleship: battleshipShips += 1
        of ShipClass.Dreadnought: dreadnoughtShips += 1
        of ShipClass.SuperDreadnought: superDreadnoughtShips += 1
        of ShipClass.Carrier:
          carrierShips += 1
          totalCarrierCount += 1
          if squadron.embarkedFighters.len == 0:
            idleCarrierCount += 1
        of ShipClass.SuperCarrier:
          superCarrierShips += 1
          totalCarrierCount += 1
          if squadron.embarkedFighters.len == 0:
            idleCarrierCount += 1
        of ShipClass.PlanetBreaker: planetBreakerShips += 1
        of ShipClass.ETAC: etacShips += 1  # ETACs now in Expansion squadrons
        of ShipClass.TroopTransport:
          troopTransportShips += 1  # TroopTransports now in Auxiliary squadrons

  # Assign ship counts
  result.fighterShips = fighterShips
  result.corvetteShips = corvetteShips
  result.frigateShips = frigateShips
  result.scoutShips = scoutShips
  result.raiderShips = raiderShips
  result.destroyerShips = destroyerShips
  result.cruiserShips = cruiserShips
  result.lightCruiserShips = lightCruiserShips
  result.heavyCruiserShips = heavyCruiserShips
  result.battlecruiserShips = battlecruiserShips
  result.battleshipShips = battleshipShips
  result.dreadnoughtShips = dreadnoughtShips
  result.superDreadnoughtShips = superDreadnoughtShips
  result.carrierShips = carrierShips
  result.superCarrierShips = superCarrierShips
  result.etacShips = etacShips
  result.troopTransportShips = troopTransportShips
  result.planetBreakerShips = planetBreakerShips

  # Calculate total ships (18 ship classes, starbases are facilities)
  result.totalShips = fighterShips + corvetteShips + frigateShips +
                      scoutShips + raiderShips + destroyerShips +
                      cruiserShips + lightCruiserShips + heavyCruiserShips +
                      battlecruiserShips + battleshipShips +
                      dreadnoughtShips + superDreadnoughtShips +
                      carrierShips + superCarrierShips +
                      etacShips + troopTransportShips + planetBreakerShips

  # Logistics
  result.totalFighters = totalFighters
  result.totalCarriers = totalCarrierCount
  result.idleCarriers = idleCarrierCount
  result.totalTransports = etacShips + troopTransportShips

  # ================================================================
  # MILITARY ASSETS - GROUND UNITS (All 4 ground unit types)
  # ================================================================

  var planetaryShieldUnits = 0
  var groundBatteryUnits = 0
  var armyUnits = 0
  var marinesAtColonies = 0
  var marinesOnTransports = 0

  # Count ground units at colonies
  for colonyId, colony in state.colonies:
    if colony.owner == houseId:
      if colony.planetaryShieldLevel > 0:
        planetaryShieldUnits += 1  # Colony has shield (level 1-6)
      groundBatteryUnits += colony.groundBatteries
      armyUnits += colony.armies
      marinesAtColonies += colony.marines

  # Count marines loaded on transports (auto-loaded after commissioning)
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        if squadron.squadronType == SquadronType.Auxiliary:
          if squadron.flagship.cargo.isSome:
            let cargo = squadron.flagship.cargo.get()
            if cargo.cargoType == CargoType.Marines:
              marinesOnTransports += cargo.quantity

  result.planetaryShieldUnits = planetaryShieldUnits
  result.groundBatteryUnits = groundBatteryUnits
  result.armyUnits = armyUnits
  result.marinesAtColonies = marinesAtColonies
  result.marinesOnTransports = marinesOnTransports
  result.marineDivisionUnits = marinesAtColonies + marinesOnTransports

  # ================================================================
  # MILITARY ASSETS - FACILITIES (NEW - Gap #10 fix)
  # ================================================================

  var totalSpaceports = 0
  var totalShipyards = 0
  var totalDrydocks = 0

  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      totalSpaceports += colony.spaceports.len
      totalShipyards += colony.shipyards.len
      totalDrydocks += colony.drydocks.len

  result.totalSpaceports = totalSpaceports
  result.totalShipyards = totalShipyards
  result.totalDrydocks = totalDrydocks

  # ================================================================
  # SCOUT MESH TRACKING (Intelligence support)
  # ================================================================

  var scoutCount = 0

  # Count scouts in fleets
  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        if squadron.flagship.shipClass == ShipClass.Scout:
          scoutCount += 1
        for ship in squadron.ships:
          if ship.shipClass == ShipClass.Scout:
            scoutCount += 1

  # Count unassigned scouts at colonies
  for systemId, colony in state.colonies:
    if colony.owner == houseId:
      for squadron in colony.unassignedSquadrons:
        if squadron.flagship.shipClass == ShipClass.Scout:
          scoutCount += 1
        for ship in squadron.ships:
          if ship.shipClass == ShipClass.Scout:
            scoutCount += 1

  result.scoutCount = scoutCount

  # ================================================================
  # FLEET ACTIVITY & ETAC TRACKING
  # ================================================================

  # TODO: Implement fleet movement tracking
  # These fields are defined in DiagnosticMetrics but not yet implemented
  result.fleetsMoved = 0
  result.systemsColonized = 0
  result.failedColonizationAttempts = 0
  result.fleetsWithOrders = 0
  result.stuckFleets = 0

  # ETAC specific tracking
  result.totalETACs = etacShips
  result.etacsWithoutOrders = 0  # TODO: Track idle ETACs
  result.etacsInTransit = 0      # TODO: Track moving ETACs

  # ================================================================
  # COMBAT LOGISTICS
  # ================================================================

  # TODO: Track fighters disbanded due to capacity violations
  result.fightersDisbanded = 0
