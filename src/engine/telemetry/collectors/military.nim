## @engine/telemetry/collectors/military.nim
##
## Collect military assets metrics from GameState.
## Covers: ship counts by class, squadron counts, ground unit counts.

import std/tables
import ../../types/[telemetry, core, game_state, event, ship, squadron, ground_unit, colony, fleet]

proc collectMilitaryMetrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect military asset counts from GameState
  result = prevMetrics  # Start with previous metrics

  let house = state.houses.entities.getOrDefault(houseId)

  # ================================================================
  # MILITARY ASSETS - SHIPS (All 18 ship classes)
  # ================================================================
  # NOTE: Starbases are facilities (not ships), tracked in facilities.nim

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
  for systemId, colony in state.colonies.entities.pairs:
    if colony.owner == houseId:
      fighterShips += colony.fighterSquadronIds.len

  # Planet-breakers tracked at house level
  planetBreakerShips = house.planetBreakerCount

  # Count fleet-based ships
  var idleCarrierCount = 0
  var totalCarrierCount = 0

  # Iterate through squadrons to count ships
  for squadronId, squadron in state[].squadrons[].entities.pairs:
    if squadron.houseId == houseId and not squadron.destroyed:
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
        # TODO: Check embarked fighters when squadron type supports it
        # if squadron.embarkedFighters.len == 0:
        #   idleCarrierCount += 1
      of ShipClass.SuperCarrier:
        superCarrierShips += 1
        totalCarrierCount += 1
      of ShipClass.PlanetBreaker: planetBreakerShips += 1
      of ShipClass.ETAC: etacShips += 1
      of ShipClass.TroopTransport: troopTransportShips += 1

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
  for colonyId, colony in state.colonies.entities.pairs:
    if colony.owner == houseId:
      if colony.planetaryShieldLevel > 0:
        planetaryShieldUnits += 1
      groundBatteryUnits += colony.groundBatteryIds.len
      armyUnits += colony.armyIds.len
      marinesAtColonies += colony.marineIds.len

  # Count marines loaded on transports
  for squadronId, squadron in state[].squadrons[].entities.pairs:
    if squadron.houseId == houseId and
       squadron.squadronType == SquadronType.Auxiliary:
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
  # SCOUT MESH TRACKING (Intelligence support)
  # ================================================================

  var scoutCount = 0

  # Count scouts in squadrons
  for squadronId, squadron in state[].squadrons[].entities.pairs:
    if squadron.houseId == houseId and not squadron.destroyed:
      if squadron.flagship.shipClass == ShipClass.Scout:
        scoutCount += 1
      # Count additional scout ships in squadron
      for shipId in squadron.ships:
        if state.ships.entities.contains(shipId):
          let ship = state.ships.entities.getEntity(shipId)
          if ship.shipClass == ShipClass.Scout:
            scoutCount += 1

  result.scoutCount = scoutCount

  # Total fighters (colony-based + fleet-based from earlier count)
  result.totalFighters = fighterShips
